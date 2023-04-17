`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : fpga_top
// Type    : synthesizable, FPGA's top, IP's example design
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: an example of can_top
//--------------------------------------------------------------------------------------------------------

module fpga_top (
        // clock �����ӵ� FPGA ���Ͼ���Ƶ�ʱ���Ϊ 50MHz 
 input sys_clk_p,//���ʱ�� 200M
    input sys_clk_n,//���ʱ�� 200M
    input rst_n, //����
    // CAN bus, ���ӵ� CAN PHY оƬ��Ȼ�� CAN PHY ���ӵ� CAN ����
    input  wire           can_rx,
    output wire           can_tx
);
  wire sys_clk ;
   reg clk_50mhz;//1Mʱ�� ��ΪCAN�Ĳ��������
   reg  [10:0]timer_cnt; //��Ƶʱ�ӵļ�ʱ��
    IBUFDS IBUFDS_inst (
      .O(sys_clk),   // 1-bit output: Buffer output//ͨ��Դ�ｫ���ʱ��ת���ɵ���ʱ�� 200M
      .I(sys_clk_p),   // 1-bit input: Diff_p buffer input (connect directly to top-level port)
      .IB(sys_clk_n)  // 1-bit input: Diff_n buffer input (connect directly to top-level port)
   );
wire clk = clk_50mhz;  // 50 MHz (maybe you can set a frequency close to but not equal to 50 MHz, like 50.5MHz, for testing the robust of CAN's clock alignment).
wire sys_clk_1=sys_clk;
// ---------------------------------------------------------------------------------------------------------------------------------------
//  CAN bus
// ---------------------------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------
//  power on reset generate
// --------------------------------------------------------------------------------------------------------------
reg        rstn = 1'b0;
reg [ 2:0] rstn_shift = '0;
always @ (posedge clk)
    {rstn, rstn_shift} <= {rstn_shift, 1'b1};

// --------------------------------------------------------------------------------------------------------------
//  signals
// --------------------------------------------------------------------------------------------------------------
//���ͽӿ�
reg [31:0] can_tx_cnt;
reg        can_tx_valid;
reg [31:0] can_tx_data;
//���սӿ�
wire       can_rx_valid;
wire [7:0] can_rx_data;
// --------------------------------------------------------------------------------------------------------------
//  Periodically send incremental data to the CAN tx-buffer
// --------------------------------------------------------------------------------------------------------------
//�������������ͻ�����
//can_top.sv �� tx_valid, tx_ready, tx_data ��������ʽ����ӿڣ����Ƕ��� clk �������ض��룬�������ͻ�����д��һ�����ݡ�
//tx_valid �� tx_ready ��һ�������źţ�ֻ�е� tx_valid �� tx_ready ��Ϊ1ʱ��tx_data �ű�д�뻺�档
//tx_ready=0 ˵��������������ʱ��ʹ tx_valid=1 ��Ҳ�޷�д�뻺�档
//assign can_tx_valid = can_tx_cnt==50000;
always @ (posedge clk or negedge rstn)
if(~rstn) begin
can_tx_cnt <= 0; //����CAN���ͼ�����
can_tx_valid <= 1'b0; //��λCAN����������Ч
can_tx_data <= 0; //���CAN��������
end else begin
if(can_tx_cnt<50000000-1) begin //���CAN���ͼ�����δ�ﵽ��ֵ
can_tx_cnt <= can_tx_cnt + 1; //CAN���ͼ���������
can_tx_valid <= 1'b0; //��λCAN����������Ч
end else begin //���CAN���ͼ������Ѵﵽ��ֵ
can_tx_cnt <= 0; //����CAN���ͼ�����
can_tx_valid <= 1'b1; //��λCAN����������Ч
can_tx_data <= can_tx_data + 1; //CAN�������ݵ���
end
end

// --------------------------------------------------------------------------------------------------------------
//  CAN 1controller
// --------------------------------------------------------------------------------------------------------------
//���ͻ������е����ݻ������CAN���������͵�CAN������
can_top #(
//���ñ���ID
    .LOCAL_ID          ( 11'h456            ),
    //����ID������
    //��ID������
    .RX_ID_SHORT_FILTER( 11'h122            ),
    .RX_ID_SHORT_MASK  ( 11'h17e            ),
    //��ID������
    .RX_ID_LONG_FILTER ( 29'h12345678       ),
    .RX_ID_LONG_MASK   ( 29'h1fffffff       ),
    //����ʱ�����(��Ƶϵ��)
    .default_c_PTS     ( 16'd34             ),
    .default_c_PBS1    ( 16'd5              ),
    .default_c_PBS2    ( 16'd10             )
) 
can0_controller (
    .rstn              ( rstn               ),
    .clk               ( clk                ),
    
    .can_rx            ( can_rx         ),
    .can_tx            ( can_tx         ),
    
    .tx_valid          ( can_tx_valid       ),
    .tx_ready          (                    ),
    .tx_data           ( can_tx_data        ),
    
    .rx_valid          ( can_rx_valid       ),
    .rx_last           (                    ),
    .rx_data           ( can_rx_data        ),
    .rx_id             (                    ),
    .rx_ide            (                    )
);
//����200MHZʱ��  ��Ƶ��50MHZ
 //200M/50M=4
 //4/2=2
 //��ʱ����200M�ߵ�ƽ����CNT+1��CNT=2�����µ�ʱ�ӣ�CNT=4�����µ�ʱ�ӡ�
always@(posedge sys_clk or negedge rst_n)
    begin
         if (!rst_n)
                 begin
                   clk_50mhz <= 0 ;
                      timer_cnt <= 11'd0 ;
                   end
             else  if(timer_cnt == 11'd1)
                         begin
                         clk_50mhz<=~clk_50mhz;
                         timer_cnt <= 0;
                         end
             else 
                          begin
                         timer_cnt <=timer_cnt+1 ;
                          end
        end

endmodule
