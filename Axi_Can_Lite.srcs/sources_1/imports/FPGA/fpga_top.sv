
//--------------------------------------------------------------------------------------------------------
// Module  : fpga_top
// Type    : synthesizable, FPGA's top, IP's example design
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: an example of can_top
//--------------------------------------------------------------------------------------------------------

module fpga_top (
        // clock �����ӵ� FPGA ���Ͼ���Ƶ�ʱ���Ϊ 50MHz 
    input  wire           clk_50mhz,
    // UART (TX only), ���ӵ����Դ��ڣ�����ͨ�� USB ת UART ģ�飩��������� UART ���Բ���
    output wire           uart_tx,
    // CAN bus, ���ӵ� CAN PHY оƬ��Ȼ�� CAN PHY ���ӵ� CAN ����
    input  wire           can_rx,
    output wire           can_tx
);

wire clk = clk_50mhz;  // 50 MHz (maybe you can set a frequency close to but not equal to 50 MHz, like 50.5MHz, for testing the robust of CAN's clock alignment).


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


//always @ (posedge clk or negedge rstn)
//    if(~rstn) begin
//        can_tx_cnt <= 0;
//        can_tx_valid <= 1'b0;
//        can_tx_data <= 0;
//    end else begin
//            can_tx_cnt <= 0;
//            can_tx_valid <= 1'b1;
//            can_tx_data <= can_tx_data + 1;
//    end







// --------------------------------------------------------------------------------------------------------------
//  CAN controller
// --------------------------------------------------------------------------------------------------------------
//���ͻ������е����ݻ������CAN���������͵�CAN������
can_top #(
//���ñ���ID
    .LOCAL_ID          ( 11'h456            ),
    //����ID������
    //��ID������
    .RX_ID_SHORT_FILTER( 11'h123            ),
    .RX_ID_SHORT_MASK  ( 11'h7ff            ),
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


// --------------------------------------------------------------------------------------------------------------
//  send CAN RX data to UART TX
// --------------------------------------------------------------------------------------------------------------
uart_tx #(
    .CLK_DIV           ( 434                ),
    .PARITY            ( "NONE"             ),
    .ASIZE             ( 11                 ),
    .DWIDTH            ( 1                  ),
    .ENDIAN            ( "LITTLE"           ),
    .MODE              ( "RAW"              ),
    .END_OF_DATA       ( ""                 ),
    .END_OF_PACK       ( ""                 )
) uart_tx_i (
    .rstn              ( rstn               ),
    .clk               ( clk                ),
    .tx_data           ( can_rx_data        ),
    .tx_last           ( 1'b0               ),
    .tx_en             ( can_rx_valid       ),
    .tx_rdy            (                    ),
    .o_uart_tx         ( uart_tx        )
);


endmodule
