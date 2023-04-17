`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : can_top
// Type    : synthesizable, IP's top
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: CAN bus controller,
//           CAN-TX: buffer input data and send them to CAN bus,
//           CAN-RX: get CAN bus data and output to user
//--------------------------------------------------------------------------------------------------------

module can_top #(
    // local ID parameter
    parameter logic [10:0] LOCAL_ID      = 11'h456,//����ID 11λ��ID
    
    // recieve ID filter parameters
    parameter logic [10:0] RX_ID_SHORT_FILTER = 11'h122,//���� ID �̹�����������λ��Ϊ 11
    parameter logic [10:0] RX_ID_SHORT_MASK   = 11'h17e,//���� ID ���������
    parameter logic [28:0] RX_ID_LONG_FILTER  = 29'h12345678,//���� ID ���������
    parameter logic [28:0] RX_ID_LONG_MASK    = 29'h1fffffff,//���� ID ���������
    
    // CAN timing parameters
    parameter logic [15:0] default_c_PTS  = 16'd34,
    parameter logic [15:0] default_c_PBS1 = 16'd5,
    parameter logic [15:0] default_c_PBS2 = 16'd10
) (
    input  wire        rstn,  // set to 1 while working
    input  wire        clk,   // system clock
    
    // CAN TX and RX, connect to external CAN phy (e.g., TJA1050)
    input  wire        can_rx,
    output wire        can_tx,
    
    // user tx-buffer write interface
    input  wire        tx_valid,  // when tx_valid=1 and tx_ready=1, push a data to tx fifo�û� TX ����д��ӿڣ��� tx_valid=1 �� tx_ready=1 ʱ����һ������д�� TX fifo ��
    output wire        tx_ready,  // whether the tx fifo is available�û� TX ��������ӿڣ��������ʾ TX fifo �Ƿ����
    input  wire [31:0] tx_data,   // the data to push to tx fifo
    
    // user rx data interface (byte per cycle, unbuffered)
    output reg         rx_valid,  // whether data byte is valid
    output reg         rx_last,   // indicate the last data byte of a packet�û� RX �����������һ���ֽڱ�ʶ�ӿ�
    output reg  [ 7:0] rx_data,   // a data byte in the packet�û� RX �������ݽӿ�
    output reg  [28:0] rx_id,     // the ID of a packet�û� RX ���� ID �ӿ�
    output reg         rx_ide     // whether the ID is LONG or SHORT�û� TX ��������ӿڣ��������ʾ TX fifo �Ƿ����
);

initial {rx_valid, rx_last, rx_data, rx_id, rx_ide} = '0;    // ��ʼ�� rx_valid, rx_last, rx_data, rx_id, rx_ide

reg         buff_valid = '0;      // buffer ����Чλ
reg         buff_ready = '0;      // buffer �ľ���λ
wire [31:0] buff_data;           // TXbuffer ������

//������
reg         pkt_txing = '0;       // �Ƿ����ڷ���һ����
reg  [31:0] pkt_tx_data = '0;     // ���Ͱ�������
wire        pkt_tx_done;          // ���Ͱ��Ƿ����
wire        pkt_tx_acked;         // ���Ƿ�ȷ�Ͻ���
wire        pkt_rx_valid;         // �Ƿ���յ���һ����
wire [28:0] pkt_rx_id;            // ���յ��İ��� ID
wire        pkt_rx_ide;           // ���յ��İ��� ID �Ƿ��ǳ� ID
wire        pkt_rx_rtr;           // ���յ��İ��Ƿ���Զ��֡
wire [ 3:0] pkt_rx_len;           // ���յ��İ������ݳ���
wire [63:0] pkt_rx_data;          // ���յ��İ�������
reg         pkt_rx_ack = '0;      // ���Ƿ�ȷ�Ͻ���

reg         t_rtr_req = '0;       // ����Զ��֡����ı�־λ
reg         r_rtr_req = '0;       // ���յ�Զ��֡����ı�־λ
reg  [ 3:0] r_cnt = '0;           // �Ѿ����յ����ֽ���
reg  [ 3:0] r_len = '0;           // ���յ��İ������ݳ���
reg  [63:0] r_data = '0;          // ���յ�������
reg  [ 1:0] t_retry_cnt = '0;     // ���Դ���������




// ---------------------------------------------------------------------------------------------------------------------------------------
//  TX buffer
//�ɴ洢 1024 �� 32 λ���ݵĻ����������ڴ洢 CAN ���߽��յ�������
// ---------------------------------------------------------------------------------------------------------------------------------------
localparam DSIZE = 32;  // ��������λ��Ϊ32λ
localparam ASIZE = 10;  // �����ַλ��Ϊ10λ

reg [DSIZE-1:0] buffer [1<<ASIZE];  // �������Ϊ2^10=1024������λ��Ϊ32λ�Ĵ洢���飬���ܻ��Զ��ϳ�ΪBRAM

reg [ASIZE:0] wptr = '0, rptr = '0;  // �����дָ�룬��ʼ��Ϊ0

wire full = wptr == {~rptr[ASIZE], rptr[ASIZE-1:0]};  // �жϻ����Ƿ�����
wire empty = wptr == rptr;  // �жϻ����Ƿ�Ϊ��

assign tx_ready = ~full;  // �������δ������׼����д��������

always @ (posedge clk or negedge rstn)  // ���always��������ʱ�������ػ�λʱ����
    if (~rstn) begin
        wptr <= '0;  // ��λдָ��Ϊ0
    end else begin
        if (tx_valid & ~full)  // ����յ��������һ���δ��
            wptr <= wptr + (1+ASIZE)'(1);  // дָ���1�������ݱ��洢��дָ��ָ���λ��
    end

always @ (posedge clk)  // ���always��������ʱ��������ʱ����
    if (tx_valid & ~full)  // ����յ��������һ���δ��
        buffer[wptr[ASIZE-1:0]] <= tx_data;  // ��������д�뻺��Ķ�Ӧλ��

wire rdready = ~buff_valid | buff_ready;  // �ж��Ƿ�ɶ�
reg rdack = '0;  // ��Ӧ���źţ���ʼ��Ϊ0
reg [DSIZE-1:0] rddata;  // ���������� 
reg [DSIZE-1:0] keepdata = '0;  // �������ݣ���ʼ��Ϊ0
assign buff_data = rdack ? rddata : keepdata;  // ����ɶ������ض��������ݣ����򷵻ر���������


always @ (posedge clk or negedge rstn) // ͬ����ʱ�������ػ�λ�½���
    if(~rstn) begin // �����λ�ź�Ϊ�͵�ƽ
        buff_valid <= 1'b0; // ��������Ч
        rdack <= 1'b0; // ��ȡȷ���ź���Ч
        rptr <= '0; // ��ָ������
        keepdata <= '0; // ��������������
    end else begin
        buff_valid <= ~empty | ~rdready; // ��������Ч����δ�ջ��ȡ׼����
        rdack <= ~empty & rdready; // ��ȡȷ���ź���Ч����δ���Ҷ�ȡ׼����
        if(~empty & rdready) // ��δ���Ҷ�ȡ׼����
            rptr <= rptr + (1+ASIZE)'(1); // ��ָ���1
        if(rdack) // ����ȡȷ���ź���Ч
            keepdata <= rddata; // ����������������
    end

always @ (posedge clk)
    rddata <= buffer[rptr[ASIZE-1:0]]; // �ӻ������ж�ȡ���ݣ�����ֵ��rddata����




// ---------------------------------------------------------------------------------------------------------------------------------------
//  CAN packet level controllerʵ����
// ---------------------------------------------------------------------------------------------------------------------------------------
can_level_packet #(
    .TX_ID           ( LOCAL_ID         ),
    .default_c_PTS   ( default_c_PTS    ),
    .default_c_PBS1  ( default_c_PBS1   ),
    .default_c_PBS2  ( default_c_PBS2   )
) can_level_packet_i (
    .rstn            ( rstn             ),
    .clk             ( clk              ),
    
    .can_rx          ( can_rx           ),
    .can_tx          ( can_tx           ),
    
    .tx_start        ( pkt_txing        ),
    .tx_data         ( pkt_tx_data      ),
    .tx_done         ( pkt_tx_done      ),
    .tx_acked        ( pkt_tx_acked     ),
    
    .rx_valid        ( pkt_rx_valid     ),
    .rx_id           ( pkt_rx_id        ),
    .rx_ide          ( pkt_rx_ide       ),
    .rx_rtr          ( pkt_rx_rtr       ),
    .rx_len          ( pkt_rx_len       ),
    .rx_data         ( pkt_rx_data      ),
    .rx_ack          ( pkt_rx_ack       )
);



// ---------------------------------------------------------------------------------------------------------------------------------------
//  RX action
// ---------------------------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        pkt_rx_ack <= 1'b0;
        r_rtr_req <= 1'b0;
        r_cnt <= 4'd0;
        r_len <= 4'd0;
        r_data <= '0;
        {rx_valid, rx_last, rx_data, rx_id, rx_ide} <= '0;  // ��ʼ��Ϊ0
    end else begin
        {rx_valid, rx_last, rx_data} <= '0;
        
        pkt_rx_ack <= 1'b0;          // ��ʼ��Ϊ0
        r_rtr_req <= 1'b0;           // ��ʼ��Ϊ0
        
        if(r_cnt>4'd0) begin         // ���������ֽ�

            rx_valid <= (r_cnt<=r_len);
            rx_last  <= (r_cnt<=r_len) && (r_cnt==4'd1);
            {rx_data, r_data} <= {r_data, 8'd0};  // ����һ�ֽڣ������ֽ��ƺ���0
            r_cnt <= r_cnt - 4'd1;                // ������-1
            
        end else if(pkt_rx_valid) begin  // �����°�
        
            r_len <= pkt_rx_len;             // latchס���յ������ݰ�����
            r_data <= pkt_rx_data;           // latchס���յ������ݰ�����
            
            if(pkt_rx_rtr) begin
                if(~pkt_rx_ide && pkt_rx_id[10:0]==LOCAL_ID) begin           // ��һ����ID��Զ�����ݰ�����IDƥ��LOCAL_ID
                    pkt_rx_ack <= 1'b1;                                     // ����ACK�ź�
                    r_rtr_req <= 1'b1;                                      // ����Զ������
                end
            end else if(~pkt_rx_ide) begin                                   // ��һ����ID�����ݰ�
                if( (pkt_rx_id[10:0] & RX_ID_SHORT_MASK) == (RX_ID_SHORT_FILTER & RX_ID_SHORT_MASK) ) begin  // IDƥ��
                    pkt_rx_ack <= 1'b1;                                     // ����ACK�ź�
                    r_cnt <= 4'd8;                                          // ��ʼ��������Ϊ8��������8�ֽ����ݣ�
                    rx_id <= pkt_rx_id;                                      // latchס���յ������ݰ�ID
                    rx_ide <= pkt_rx_ide;                                    // latchס���յ������ݰ����ͣ���ID/��ID��
                end
            end else begin                                                   // ��һ����ID�����ݰ�
                if( (pkt_rx_id & RX_ID_LONG_MASK) == (RX_ID_LONG_FILTER & RX_ID_LONG_MASK) ) begin           // IDƥ��
                    pkt_rx_ack <= 1'b1;                                     // ����ACK�ź�
                    r_cnt <= 4'd8;                                          // ��ʼ��������Ϊ8��������8�ֽ����ݣ�
                    rx_id <= pkt_rx_id;                                      // latchס���յ������ݰ�ID
                    rx_ide <= pkt_rx_ide;                                    // latchס���յ������ݰ����ͣ���ID/��ID��
                end
            end
        end
    end
// ---------------------------------------------------------------------------------------------------------------------------------------
//  RX action Finish
// --------------------------------------------------------



// ---------------------------------------------------------------------------------------------------------------------------------------
//  TX action
// ---------------------------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        buff_ready <= 1'b0;         // ��λʱ�� buff_ready ��Ϊ 0
        pkt_tx_data <= '0;          // ��λʱ�� pkt_tx_data ��Ϊ 0
        t_rtr_req <= 1'b0;          // ��λʱ�� t_rtr_req ��Ϊ 0
        pkt_txing <= 1'b0;          // ��λʱ�� pkt_txing ��Ϊ 0
        t_retry_cnt <= 2'd0;        // ��λʱ�� t_retry_cnt ��Ϊ 0
    end else begin
        buff_ready <= 1'b0;         // �� buff_ready ��Ϊ 0
        
        if(r_rtr_req)
            t_rtr_req <= 1'b1;                   // ����յ���Զ������֡���� t_rtr_req ��Ϊ 1
        
        if(~pkt_txing) begin                      // �����ǰû�����ڷ��͵�֡
            t_retry_cnt <= 2'd0;                  // ���ش������� t_retry_cnt ��Ϊ 0
            if(t_rtr_req | buff_valid) begin      // ����յ���Զ������֡�����߷��ͻ�����������
                buff_ready <= buff_valid;         // ���Խ����ͻ������е����ݵ�����������ͻ�����������
                t_rtr_req <= 1'b0;                // �� t_rtr_req ��Ϊ 0
                if(buff_valid)                    // ������ͻ����������ݣ������ pkt_tx_data
                    pkt_tx_data <= buff_data;
                pkt_txing <= 1'b1;                // �� pkt_txing ��Ϊ 1����ʾ���ڷ���֡
            end
        end else if(pkt_tx_done) begin            // �����ǰ���ڷ���֡�ҷ������
            if(pkt_tx_acked || t_retry_cnt==2'd3) begin   // ���֡���ͳɹ������ش��������Ѿ����� 3
                pkt_txing <= 1'b0;                       // �� pkt_txing ��Ϊ 0����ʾ֡�����Ѿ�����
            end else begin
                t_retry_cnt <= t_retry_cnt + 2'd1;        // �����ش��������� 1
            end
        end
    end



endmodule
