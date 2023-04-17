`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : can_level_packet
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: CAN bus packet level controller,
//           instantiated by can_top
//--------------------------------------------------------------------------------------------------------

module can_level_packet #(
parameter logic TX_RTR = 1'b0, // �������ݵ����ͣ���Զ�̴�������������֡
parameter logic [10:0] TX_ID = 11'h456, // �������ݵ�ID��
parameter logic [15:0] default_c_PTS = 16'd34, // Ĭ�ϵ�ʱ��η���
parameter logic [15:0] default_c_PBS1 = 16'd5, // Ĭ�ϵ�λ������
parameter logic [15:0] default_c_PBS2 = 16'd10 // Ĭ�ϵ�ͬ����ת���
) (
    input  wire        rstn,  // set to 1 while working�����ź�
    input  wire        clk,   // system clockʱ���ź�
    
// CAN TX and RX
input  wire        can_rx, // CAN���߽��ն˿�
output wire        can_tx, // CAN���߷��Ͷ˿�

// user tx packet interface
input  wire        tx_start, // �������������ź�
input  wire [31:0] tx_data,  // ���͵�����
output reg         tx_done,  // ������ɱ�־
output reg         tx_acked, // ����ȷ�ϱ�־

// user rx packet interface
output reg         rx_valid, // ���յ���Ч���ݱ�־
output reg  [28:0] rx_id,    // ���յ������ݵ�ID
output reg         rx_ide,   // �Ƿ�Ϊ��չ֡��־
output reg         rx_rtr,   // ���յ������ݵ����ͣ���Զ�̴�������������֡
output reg  [ 3:0] rx_len,   // ���յ������ݳ���
output reg  [63:0] rx_data,  // ���յ�������
input  wire        rx_ack    // ���յ�����ȷ���ź�

);
// ��ʼ������˿�ֵ
initial {tx_done, tx_acked} = 1'b0;
initial {rx_valid,rx_id,rx_ide,rx_rtr,rx_len,rx_data} = '0;

// CRC 15λ�����
function automatic logic [14:0] crc15(input logic [14:0] crc_val, input logic in_bit);
    return {crc_val[13:0], 1'b0} ^ (crc_val[14] ^ in_bit ? 15'h4599 : 15'h0);
endfunction
// ���� CAN λ��������
wire bit_req;
wire bit_rx;
reg  bit_tx = 1'b1;

can_level_bit #(
    .default_c_PTS   ( default_c_PTS    ),
    .default_c_PBS1  ( default_c_PBS1   ),
    .default_c_PBS2  ( default_c_PBS2   )
) can_level_bit_i (
    .rstn            ( rstn             ),
    .clk             ( clk              ),
    .can_rx          ( can_rx           ),
    .can_tx          ( can_tx           ),
    .req             ( bit_req          ),
    .rbit            ( bit_rx           ),
    .tbit            ( bit_tx           )
);


//����һ������Ϊ8�ļĴ��� rx_history ������ֵ '0'
reg [7:0] rx_history = '0;
//����һ������Ϊ4�ļĴ��� tx_history ������ֵ '1'
reg [3:0] tx_history = '1;
//����һ�� wire ���ͱ��� rx_end������ֵ���� rx_history ��ֵ�Ƿ���� 1
wire rx_end = rx_history == '1;
//����һ�� wire ���ͱ��� rx_err������ֵ���� rx_history �ĵ�6λ�Ƿ�Ϊ 0
wire rx_err = rx_history[5:0] == '0;
//����һ�� wire ���ͱ��� rx_ben������ֵ���� rx_history �ĵ�5λ�Ƿ�Ȳ����� 0 Ҳ������ 1
wire rx_ben = rx_history[4:0] != '0 && rx_history[4:0] != '1;
//����һ�� wire ���ͱ��� tx_ben������ֵ���� {tx_history, bit_tx} �Ƿ�Ȳ����� 0 Ҳ������ 1
wire tx_ben = {tx_history, bit_tx} != '0 && {tx_history, bit_tx} != '1;

//�� rx_history �� tx_history ���и�ֵ
always @ (posedge clk or negedge rstn)
if(~rstn) begin
    //����λ�ź�Ϊ�͵�ƽʱ���� rx_history �� tx_history ��ֵΪ 0 �� 1
    rx_history <= '0;
    tx_history <= '1;
end else begin
    //�� bit_req �ź�Ϊ�ߵ�ƽʱ���� bit_rx ���� rx_history �ĵ�7λ���� bit_tx ���� tx_history �ĵ�3λ
    if(bit_req) begin
        rx_history <= {rx_history[6:0], bit_rx};
        tx_history <= {tx_history[2:0], bit_tx};
    end
end



//����һ������Ϊ1�� reg ���ͱ��� tx_arbitrary ������ֵ '0'
reg tx_arbitrary = '0;
//����һ������Ϊ15�� reg ���ͱ��� rx_crc ������ֵ '0'
reg [14:0] rx_crc = '0;
//����һ������Ϊ15�� wire ���ͱ��� rx_crc_next������ֵ���ڽ� rx_crc ����һλ�����һ����λΪ 0 ������
//Ȼ�������һ�� 15 λ��ʮ�������� 15'h4599 �� 15'h0 ���а�λ�������
wire [14:0] rx_crc_next = {rx_crc[13:0], 1'b0} ^ (rx_crc[14] ^ bit_rx ? 15'h4599 : 15'h0);
//����һ������Ϊ50�� reg ���ͱ��� tx_shift ������ֵ '1'
reg [49:0] tx_shift = '1;
//����һ������Ϊ15�� reg ���ͱ��� tx_crc ������ֵ '0' 
reg [14:0] tx_crc = '0;
wire[14:0] tx_crc_next = {tx_crc[13:0], 1'b0} ^ (tx_crc[14] ^ tx_shift[49] ? 15'h4599 : 15'h0);//���а�λ������㣨XOR��
//(tx_crc[14] ^ tx_shift[49] ����ʾ�� tx_crc �����λ�� tx_shift �����λ�����������
//���tx_crc[14] ^ tx_shift[49]=1 �������Ϊһ��15λ��ʮ�������� 15'h4599�����������Ϊһ��15λ��ʮ�������� 15'h0��
//15'h4599:15'b0100010110011001
wire[ 3:0] rx_len_next = {rx_len[2:0], bit_rx};  // ������һ�����ճ��ȣ���bit_rx���뵽rx_len�ĵ�3λ��
wire[ 7:0] rx_cnt = rx_len[3] ? 8'd63 : {1'd0, rx_len, 3'd0} - 8'd1; // ���ݽ��ճ��ȼ�������ֽ������������λ�����λΪ1�����յ��ֽ���Ϊ63�����򣬽��յ��ֽ���Ϊ����λ�ĵ���λ+1

localparam [3:0] INIT         = 4'd0, // ����״̬��״̬���ƶ�Ӧ��ֵ
                 IDLE         = 4'd1, // ����״̬���ȴ���ʼ���ͻ����
                 TX_ID_MSB    = 4'd2, // ��ʼ����IDλ�����λ
                 TRX_ID_BASE  = 4'd3, // ���ͻ����ID������λ
                 TX_PAYLOAD   = 4'd4, // ��������
                 TX_ACK_DEL   = 4'd5, // ����ACKӦ��ǰ����ʱ״̬
                 TX_ACK       = 4'd6, // ����ACKӦ��
                 TX_EOF       = 4'd7, // ���ͽ���λ
                 RX_IDE_BIT   = 4'd8, // ����IDEλ
                 RX_ID_EXTEND = 4'd9, // ����ID����չλ
                 RX_RESV1_BIT = 4'd10, // ���ձ���λ
                 RX_CTRL      = 4'd11, // ���տ���λ
                 RX_DATA      = 4'd12, // ��������
                 RX_CRC       = 4'd13, // ����CRC
                 RX_ACK       = 4'd14, // ����ACKӦ��
                 RX_EOF       = 4'd15; // ���ս���λ

reg [ 7:0] cnt = '0; // ���ͻ����״̬������
reg [ 3:0] stat = INIT; // ״̬��״̬����

reg rx_valid_pre = '0; // ǰһ֡�����Ƿ���Ч
reg rx_valid_latch = '0; // ��ǰ֡�����Ƿ���Ч
reg rx_ack_latch = '0; // ��ǰ֡����ACKӦ���Ƿ���Ч

always @ (posedge clk or negedge rstn) // ����߼��飬����ǰһ֡�����Ƿ���Ч���Լ���ǰ֡�����Ƿ���Ч��ACKӦ���Ƿ���Ч�ĸ���
    if(~rstn) begin
        rx_valid <= 1'b0;
        rx_valid_latch <= 1'b0;
        rx_ack_latch <= 1'b0;
    end else begin
        rx_valid <= rx_valid_pre & (rx_crc==15'd0); // ��ǰ֡�����Ƿ���Ч���жϣ�rx_crc==15'd0��ʾ���յ���CRCУ������ȷ
        rx_valid_latch <= rx_valid;
        if(rx_valid_latch)
            rx_ack_latch <= rx_ack; // ����ACKӦ���Ƿ���Ч
    end

          always @ (posedge clk or negedge rstn) // ��ʱ�ӻ�λ�źű仯ʱִ��
                if(~rstn) begin // ��λ
                        {tx_done, tx_acked} <= 1'b0; // ������ɱ�־λ��Ӧ���־λ��λ
                        rx_valid_pre <= 1'b0; // ����������Чǰ��λ��λ
                        {rx_id,rx_ide,rx_rtr,rx_len,rx_data,rx_crc} <= '0; // ����������ر�����λ
                        bit_tx <= 1'b1; // ��������λ��λ
                        tx_arbitrary <= 1'b0; // ��������λ��λ
                        tx_crc <= '0; // �������� CRC У���븴λ
                        tx_shift <= '1; // ����������λ�Ĵ�����λ
                        cnt <= 8'd0; // ��������λ
                        stat <= INIT; // ״̬��״̬��λ
        end else begin // ��������״̬
                        {tx_done, tx_acked} <= 1'b0; // ������ɱ�־λ��Ӧ���־λ��λ
                        rx_valid_pre <= 1'b0; // ����������Чǰ��λ��λ
                 if(bit_req) begin // ���������ź�ִ����Ӧ����
                        bit_tx <= 1'b1; // ��������λ��λ
        
        case(stat) // ����״̬��״ִ̬����Ӧ����
            INIT : begin // ��ʼ״̬
                if(rx_end) // ������յ�����λ����������״̬
                    stat <= IDLE;
            end
            
            IDLE : begin // ����״̬
                tx_arbitrary <= 1'b0; // ��������λ��λ
                {rx_id,rx_ide,rx_rtr,rx_len,rx_data,rx_crc} <= '0; // ����������ر�����λ
                tx_crc <= '0; // �������� CRC У���븴λ
                //�����ͽ���
                tx_shift <= {TX_ID, TX_RTR, 1'b0, 1'b0, 4'd4, tx_data}; // ���������ݰ���ʽ���뷢��������λ�Ĵ���
                if(bit_rx == 1'b0) begin // �����������λΪ�͵�ƽ
                    cnt <= 8'd0; // ��������λ
                    stat <= TRX_ID_BASE; // ���뽻����ʶ������λ״̬
                end else if(cnt<8'd20) begin // ���������С�� 20
                    cnt <= cnt + 8'd1; // �������� 1
                    
                    //��ʼ��������
                end else if(tx_start) begin // ������Կ�ʼ����
                    bit_tx <= 1'b0; // ��������λ��Ϊ�͵�ƽ
                    cnt <= 8'd0; // ��������λ
                    stat <= TX_ID_MSB; // ���뷢�ͱ�ʶ�� MSB ״̬
                end
            end
            
            TX_ID_MSB : begin // ���ͱ�ʶ�� MSB ״̬
 // ���bit_rx�Ǹߵ�ƽ
        if(bit_rx) begin
            // ����TX_EOF״̬
            stat <= TX_EOF;
        end else begin
            // ��tx_shift����һλ��������bit_tx
       //bit_tx��ֵ����ÿ��ʱ�������и��ݷ������ݵ���λ�Ĵ����͵�ǰ����λ��ֵ���и���
            {bit_tx, tx_shift} <= {tx_shift, 1'b1};
            // ����CRC
            tx_crc <= tx_crc_next;
            // TX����λ���λ��Ϊ�ߵ�ƽ
            tx_arbitrary <= 1'b1;
            // ����TRX_ID_BASE״̬
            stat <= TRX_ID_BASE;
        end
                end
                
                TRX_ID_BASE : begin
                 // ���TX����λ���λ�Ǹߵ�ƽ������bit_rx����bit_tx
                    if(tx_arbitrary && bit_rx==bit_tx) begin
                     // ���tx_benΪ�ߵ�ƽ
                        if(tx_ben) begin
                         // ��tx_shift����һλ��������bit_tx
                            {bit_tx, tx_shift} <= {tx_shift, 1'b1};
                              // ����CRC
                            tx_crc <= tx_crc_next;
                             // ���tx_benΪ�͵�ƽ
                        end else begin
                          // bit_txȡ��
                            bit_tx <= ~tx_history[0];
                        end
                         // ���TX����λ���λΪ�͵�ƽ��bit_rx������bit_tx
                    end else begin
                      // TX����λ���λ��Ϊ�͵�ƽ
                        tx_arbitrary <= 1'b0;
                    end
                     // ���rx_endΪ�ߵ�ƽ
                    if(rx_end) begin
                      // ����IDLE״̬
                        stat <= IDLE;
                        // ���rx_errΪ�ߵ�ƽ
                    end else if(rx_err) begin
                       // ����RX_EOF״̬
                        stat <= RX_EOF;
               // ���rx_benΪ�ߵ�ƽ
        end else if(rx_ben) begin
            // ����rx_crc
            rx_crc <= rx_crc_next;
            // ��������һ
            cnt <= cnt + 8'd1;
            // ���������С��11
            if(cnt<8'd11) begin
                // ��bit_rx����rx_id
                rx_id <= {rx_id[27:0], bit_rx};
            // ������������ڵ���11
            end else begin
                // ��bit_rx��ֵ��rx_rtr
                rx_rtr <= bit_rx;
                // ���TX����λ���λΪ�͵�ƽ��bit_rx������bit_tx
                if( !(tx_arbitrary && bit_rx==bit_tx) ) begin              // TX arbitrary failed
                    // ����������
                    cnt <= 8'd0;
                    // ����RX_IDE_BIT״̬
                    stat <= RX_IDE_BIT;
                // ���TX����λ���λΪ�ߵ�ƽ������tx_benΪ�ߵ�ƽ
                end else if(tx_ben) begin
                    // ����������
                    cnt <= 8'd0;
                    // ����TX_PAYLOAD״̬
                    stat <= TX_PAYLOAD;
                end
            end
        // �������������11
        end else if(cnt>8'd11) begin
            // ����������
            cnt <= 8'd0;
            // ����TX_PAYLOAD״̬
            stat <= TX_PAYLOAD;
        end
                end

//                TX_PAYLOAD: �������ݲ��ֵ�״̬��������յ��������뷢�͵����ݲ�һ�£�����ת��TX_EOF״̬��
//                ������ݴ�������tx_ben����������1λ������һ������λ����tx_shift��
//                ����Ҫ��У��͵���һλtx_crc_next����tx_crc�����������cnt����36����У��͵�ֵ�洢��tx_shift��49-35λ��
//                ���������С��52�������Ӽ�������ֵ�����򽫼�������ֵ����Ϊ0����ת��TX_ACK_DEL״̬��
            TX_PAYLOAD : begin                               // ��������֡��Payload�׶�
                if(bit_rx != bit_tx) begin        // �������������Ƿ��뷢����������ͬ�������ͬ������TX_EOF״̬
                    stat <= TX_EOF;
                end else if(tx_ben) begin         // ����Ƿ��������߽ӿ�
                    {bit_tx, tx_shift} <= {tx_shift, 1'b1}; // �� tx_shift ������һλ���������λ����Ϊ bit_tx ��ֵ
                    tx_crc <= tx_crc_next;          // ����У���
                    if(cnt==8'd36) tx_shift[49:35] <= tx_crc_next; // �ڵ�36λ��д��У���
                    if(cnt<8'd52) begin             // �����������ݣ�ֱ��52λ
                        cnt <= cnt + 8'd1;
                    end else begin
                        cnt <= 8'd0;                // ������ϣ�����TX_ACK_DEL״̬
                        stat <= TX_ACK_DEL;
                    end
                end else begin                     // ������߽ӿ�δ���������ڷ����������������ת����ʷֵ
                    bit_tx <= ~tx_history[0];
                end
            end

                //������յ���λ�뷢�͵�λ��ͬ������ת��TX_ACK״̬��������ת��TX_EOF״̬��
                TX_ACK_DEL : begin
                    stat <= bit_rx ? TX_ACK : TX_EOF;
                end
                //������ɵ�״̬������tx_done = 1���洢~bit_rx��tx_acked�У�Ȼ����ת��TX_EOF״̬��
                TX_ACK : begin
                    tx_done <= 1'b1;
                    tx_acked <= ~bit_rx;
                    stat <= TX_EOF;
                end
                //���ڷ��������8λ����֮���״̬�����������cntС��8�������Ӽ�������ֵ�����򽫼�������ֵ����Ϊ0����ת��RX_EOF״̬��
                    TX_EOF : begin
                if(cnt<8'd8) begin // ������͵�����λ��С��8λ����������
                    cnt <= cnt + 8'd1;
                 end else begin // ���򽫼��������㣬����״̬��״̬����ΪRX_EOF
                        cnt <= 8'd0;
                        stat <= RX_EOF;
                    end
                   end
                
RX_IDE_BIT : begin
if(rx_end) begin // ���֡��������״̬��״̬����ΪIDLE
stat <= IDLE;
end else if(rx_err) begin //������ִ�����״̬��״̬����ΪRX_EOF
stat <= RX_EOF;
end else if(rx_ben) begin // �����ȷ���յ����أ������CRC����״̬��״̬ת��
rx_crc <= rx_crc_next;
rx_ide <= bit_rx;
stat <= bit_rx ? RX_ID_EXTEND : RX_CTRL;
end
end
                
                
//     �� RX_IDE_BIT ״̬λΪ 1 ʱ�л�����״̬�������ʶ����չλ��������ݽ����Ѿ���ɣ���״̬���л��� IDLE ״̬��
//    ������������л��� RX_EOF ״̬����Զ��֡��ʶ��������λ�� RTR λ������״̬����������� RTR λ���浽 rx_rtr �����У�
//     ���ȴ���һ��״̬������ʶ����չλ�� 18 λ��״̬���Ὣ��Щλ�Ӹ�λ����λ���δ洢�� rx_id �У�ͬʱ cnt ������¼�Ѿ������λ����
//     ��ʼֵΪ 0��ÿ�ν����״̬ cnt ���� 1���� cnt ���ڵ��� 18 ʱ��״̬���л��� RX_RESV1_BIT ״̬��
RX_ID_EXTEND : begin                     // RX_ID_EXTEND״̬���ڽ�����չ��ʶ��
                    if(rx_end) begin           // ������ս����ˣ�����IDLE״̬
                        stat <= IDLE;
                    end else if(rx_err) begin  // ������ճ��ִ��󣬽���RX_EOF״̬
                        stat <= RX_EOF;
                    end else if(rx_ben) begin  // �������ʹ��λ�Ǹߵ�ƽ
                        rx_crc <= rx_crc_next;  // ����CRC
                        if(cnt<8'd18) begin     // ���������С��18��˵�����ڽ��ձ�ʶ������չ���֣��ѽ��յ��ı��ؼӵ���ʶ����
                            rx_id <= {rx_id[27:0], bit_rx};
                            cnt <= cnt + 8'd1;
                        end else begin          // �������������18��˵���Ѿ��������˱�ʶ������չ����
                            rx_rtr <= bit_rx;   // �ѱ�����ӵ�rtr�ֶ�
                            cnt <= 8'd0;        // ���ü�����
                            stat <= RX_RESV1_BIT; // ����RX_RESV1_BIT״̬�����ձ���λR1
                        end
                    end
                end

//                �����ǰ���յ����ݣ��Ҳ��ǽ���λ������ݽ��յ�������λ����״̬Ϊ RX_EOF �� RX_CTRL��
//                ������յ�����Ϊ 1����״̬����Ϊ RX_EOF������״̬����Ϊ RX_CTRL��
          RX_RESV1_BIT : begin                    // ���յ���չ֡�ı���λ1
    if(rx_end) begin                    // ֡�������
        stat <= IDLE;                   // ����IDLE״̬
    end else if(rx_err) begin           // ֡���ճ���
        stat <= RX_EOF;                 // ����RX_EOF״̬
    end else if(rx_ben) begin           // ֡��������
        rx_crc <= rx_crc_next;          // ���½���CRCУ����
        stat <= bit_rx ? RX_EOF : RX_CTRL; // ������յ�����1���򷵻�RX_EOF״̬�����򷵻�RX_CTRL״̬
    end
end

              //  ��ʼ����CANЭ��֡�Ŀ���λ��������Э��涨�����RX_DATA��RX_CRC״̬��
          RX_CTRL : begin                                    // ���յ�����֡��־�����ȴ����ݳ����ֶ�
                    if(rx_end) begin                   // ������յ�����Ϣ�Ľ�����
                        stat <= IDLE;                   // �л�������״̬
                    end else if(rx_err) begin           // ������յ��˴����־λ
                        stat <= RX_EOF;                 // �л������մ���״̬
                    end else if(rx_ben) begin           // ������յ�����Ч��CAN��������
                        rx_crc <= rx_crc_next;           // ����CRCУ��ֵ
                        rx_len <= rx_len_next;           // �������ݳ���
                        if(cnt<8'd4) begin               // ��������
                            cnt <= cnt + 8'd1;           // ��������1
                        end else begin                    // �������
                            cnt <= 8'd0;                 // ����������
                            stat <= (rx_len_next!='0 && rx_rtr==1'b0) ? RX_DATA : RX_CRC;  // ��ת�����ݽ��ջ�CRCУ��״̬
                        end
                    end
                end

                //��ʼ��������֡�����ݲ��֡�
                RX_DATA : begin
  if(rx_end) begin // ����������
    stat <= IDLE; // ״̬��״̬��ΪIDLE
        end else if(rx_err) begin // �������
    stat <= RX_EOF; // ״̬��״̬��ΪRX_EOF
        end else if(rx_ben) begin // �������ʹ���ź���Ч
    rx_crc <= rx_crc_next; // ����У�������Ϊ��һ״̬��У����
    rx_data <= {rx_data[62:0], bit_rx}; // �����յ������ݰ�λ�洢
  if(cnt<rx_cnt) begin // �������λ��δ������
    cnt <= cnt + 8'd1; // ���ռ�������1
        end else begin // �������λ���Ѿ�������
    cnt <= 8'd0; // ���ռ���������
    stat <= RX_CRC; // ״̬��״̬��ΪRX_CRC
                        end
                    end
                end
                //�����յ���CRC�Ƿ���ȷ�������ȷ����������յ������ݣ����򷵻�RX_EOF״̬����ζ�Ž��մ���
            RX_CRC : begin                              // ����CRC
                    if(rx_end) begin          // ������յ�����λ
                        stat <= IDLE;          // �л���IDLE״̬
                    end else if(rx_err) begin // ������յ�����
                        stat <= RX_EOF;        // �л���RX_EOF״̬
                    end else if(rx_ben) begin // ������յ���Ч����
                        rx_crc <= rx_crc_next; // �����յ������ݴ���CRC�Ĵ���
                        if(cnt<8'd14) begin     // ���������С��14
                            cnt <= cnt + 8'd1;  // ��������1
                        end else begin          // �������������14
                            cnt <= 8'd0;         // ����������
                            stat <= RX_ACK;      // �л���RX_ACK״̬
                            rx_valid_pre <= 1'b1;// ��rx_valid_pre��Ϊ1
                        end
                    end
                end

                
RX_ACK : begin
if(rx_end) begin // �����ս���
stat <= IDLE; // �л�������״̬
end else if(rx_err) begin // �����ֽ��մ���
stat <= RX_EOF; // �л������ս���״̬
end else if(rx_ben) begin // �����ݰ��������ϴ��䵽�ýڵ�
if(bit_rx && rx_crc==15'd0 && rx_ack_latch) // ��� DEL=1���� CRC �������û������� ACK=0 λ
bit_tx <= 1'b0; // ���� ACK
stat <= RX_EOF; // �л������ս���״̬
end
end
                
                           RX_EOF : begin
                if(rx_end)                   // �����ս���
                    stat <= IDLE;             // �л�������״̬
            end


            endcase
        end
    end



endmodule
