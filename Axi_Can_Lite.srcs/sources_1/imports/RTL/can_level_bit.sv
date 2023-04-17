`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : can_level_bit
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: CAN bus bit level controller,
//           instantiated by can_level_packet
//--------------------------------------------------------------------------------------------------------

module can_level_bit #(
    parameter logic [15:0] default_c_PTS  = 16'd34,   // Ĭ�ϵ�ʱ���1����
    parameter logic [15:0] default_c_PBS1 = 16'd5,    // Ĭ�ϵ�ʱ���2����
    parameter logic [15:0] default_c_PBS2 = 16'd10    // Ĭ�ϵ�ʱ���3����
) (
    input  wire        rstn,  // ��λ�źţ��͵�ƽ��Ч
    input  wire        clk,   // ʱ���ź�
    
    // CAN TX and RX
    input  wire        can_rx, // CAN���߽��������ź�
    output reg         can_tx, // CAN���߷��������ź�
    
    // user interface
    output reg         req,   // ������Ϣ������ָʾ��ǰ����֡�ı߽�
    output reg         rbit,  // ��һλ���յ�������λ��ֻ����req=1ʱ����Ч
    input  wire        tbit   // ��һλҪ���͵�����λ��������req=1�����������
);

initial can_tx = 1'b1;   // ��ʼֵ��CAN���߷��������ź�Ϊ�ߵ�
initial req = 1'b0;      // ��ʼֵ��������ϢΪ0
initial rbit = 1'b1;     // ��ʼֵ����һλ���յ�������λΪ1

reg        rx_buf = 1'b1;   // ���뻺��������ʼֵΪ1
reg        rx_fall = 1'b0;  // �����ؼ�⣬��ʼֵΪ0
always @ (posedge clk or negedge rstn)  // ʱ�������ػ�λ�ź��½���ʱִ��
    if(~rstn) begin   // ��λ
        rx_buf  <= 1'b1;  // ���û�����Ϊ1
        rx_fall <= 1'b0;  // ���������ؼ��Ϊ0
    end else begin     // ʱ��������
        rx_buf  <= can_rx;               // �洢���յ�������
        rx_fall <= rx_buf & ~can_rx;     // ���������
    end

localparam [16:0] default_c_PTS_e  = {1'b0, default_c_PTS};    // ����Ĭ�ϵ�ʱ���1����
localparam [16:0] default_c_PBS1_e = {1'b0, default_c_PBS1};   // ����Ĭ�ϵ�ʱ���2����
localparam [16:0] default_c_PBS2_e = {1'b0, default_c_PBS2};   // ����Ĭ�ϵ�ʱ���3����

reg  [16:0] adjust_c_PBS1 = '0;  // ����ʱ���2���ȵı�������ʼֵΪ0

reg  [ 2:0] cnt_high = '0;  //����һ��3λ�Ĵ��������ڼ����λ�ֽڵ���������ʼֵΪ0
reg  [16:0] cnt = 17'd1;   //����һ��17λ�Ĵ��������ڼ���������ʼֵΪ1
enum logic [1:0] {STAT_PTS, STAT_PBS1, STAT_PBS2} stat = STAT_PTS;  //����һ��״̬ö�ٱ��������ڿ���״̬ת�ƣ���ʼ״̬ΪSTAT_PTS
reg        inframe = 1'b0;  //����һ��1λ�Ĵ��������ڱ�ʶ�Ƿ��ڷ���֡�У���ʼֵΪ0

// state machine
// ״̬��ģ�飬����״̬ת�ƽ�������֡�ķ��ͺͽ���
always @ (posedge clk or negedge rstn)  //always�飬��ʱ�������ػ�λ�½��ط���ʱִ�����²���
//��λ����s
    if(~rstn) begin  //�����λΪ0����ִ�����²���
        can_tx <= 1'b1;  //�����Ͷ˿���Ϊ1
        req <= 1'b0;     //��������Ϊ0
        rbit <= 1'b1;    //�����ն˿���Ϊ1
        adjust_c_PBS1 <= 8'd0;  //��������������ʼ��Ϊ0
        cnt_high <= 3'd0;      //����λ�ֽ�������������ʼ��Ϊ0
        cnt <= 17'd1;          //����������ʼ��Ϊ1
        stat <= STAT_PTS;      //��״̬ö�ٱ�����ʼ��ΪSTAT_PTS
        inframe <= 1'b0;       //���Ƿ��ڷ���֡�еı�ʶ��ʼ��Ϊ0
        //��������
    end else begin   //���򣬼���λ��Ϊ0����ִ�����²���
        req <= 1'b0;    //��������Ϊ0
        //����֡inframe=1 ������Ϣreq=1
        if(~inframe & rx_fall) begin  //������ڷ���֡�в��ҽ��յ��½��أ���ִ�����²���
        
            adjust_c_PBS1 <= default_c_PBS1_e;  //����������������ΪĬ��ֵ
            cnt <= 17'd1;  //����������ʼ��Ϊ1
            stat <= STAT_PTS;  //��״̬ö�ٱ�����ΪSTAT_PTS
            inframe <= 1'b1;   //���Ƿ��ڷ���֡�еı�ʶ����Ϊ1
        end 
        
        else begin  //���򣬼��ڷ���֡�л�δ���յ��½��أ���ִ�����²���

            case(stat)  //����״̬ö�ٱ�����ֵ����״̬ת��
                STAT_PTS: begin  //ʱ���1�����״̬ΪSTAT_PTS����ִ�����²���
                    if( (rx_fall & tbit) && cnt>17'd2 )  //������յ��½��غʹ���λΪ1�Ҽ���������2����ִ�����²���
                        adjust_c_PBS1 <= default_c_PBS1_e + cnt;  //����������������ΪĬ��ֵ���ϼ�������ֵ
                    if(cnt>=default_c_PTS_e) begin  //������������ڵ���Ĭ��ֵ����ִ�����²���
                        cnt <= 17'd1; // ��������λΪ1
                        stat <= STAT_PBS1;// ״̬ת��Ϊʱ���2
                        //������ߵڶ���״̬������ֻ�Ǹ���������1
                    end else
                        cnt <= cnt + 17'd1;// ��������1
                end
              // ʱ���2
                STAT_PBS1: begin
                    if(cnt==17'd1) begin // ��������� cnt ����1
                        req <= 1'b1; // ���������ݷ���
                        rbit <= rx_buf;   // sampling bit // �����յ������ݸ�ֵ�� rbit
                        cnt_high <= rx_buf ? cnt_high<3'd7 ? cnt_high+3'd1 : cnt_high : 3'd0;// ������յ�������Ϊ1��������� cnt_high �� 1����������Ϊ0
                    end
                    if(cnt>=adjust_c_PBS1) begin// ��������� cnt ���ڵ��ڵ��������� adjust_c_PBS1����ת�Ƶ�״̬ STAT_PBS2������������ cnt ��λΪ0
                        cnt <= 17'd0;
                        stat <= STAT_PBS2;
                    end else
                        cnt <= cnt + 17'd1;// ��������� cnt �� 1
                end
                STAT_PBS2: begin
                // ������յ��½��ز��Ҵ���λΪ1�����߼����� cnt ���ڵ���Ĭ��ʱ���3�ĳ��ȣ��򽫷��Ͷ˿���Ϊ����λ tbit������������ΪĬ��ʱ���2�ĳ��ȣ�����������λΪ1��
                //��״̬��ת�Ƶ�״̬ STAT_PTS����������� cnt_high ����7�����Ƿ��ڷ���֡�еı�ʶ inframe ��Ϊ0
                    if( (rx_fall & tbit) || (cnt>=default_c_PBS2_e) ) begin
                        can_tx <= tbit;
                        adjust_c_PBS1 <= default_c_PBS1_e;
                        cnt <= 17'd1;
                        stat <= STAT_PTS;
                        if(cnt_high==3'd7) inframe <= 1'b0;
                    end else begin
                    // ��������� cnt �� 1����������� cnt ����Ĭ��ʱ���3�ĳ��ȼ�1���򽫷��Ͷ˿���Ϊ����λ tbit
                        cnt <= cnt + 17'd1;
                        if(cnt==default_c_PBS2_e-17'd1)
                            can_tx <= tbit;
                    end
                end
                default : begin
                // Ĭ������£���״̬��ת�Ƶ�״̬ STAT_PTS
                    stat <= STAT_PTS;
                end
            endcase
        end
    end

endmodule
