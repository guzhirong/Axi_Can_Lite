
//--------------------------------------------------------------------------------------------------------
// Module  : fpga_top
// Type    : synthesizable, FPGA's top, IP's example design
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: an example of can_top
//--------------------------------------------------------------------------------------------------------

module fpga_top (
        // clock ，连接到 FPGA 板上晶振，频率必须为 50MHz 
    input  wire           clk_50mhz,
    // UART (TX only), 连接到电脑串口（比如通过 USB 转 UART 模块），不方便接 UART 可以不接
    output wire           uart_tx,
    // CAN bus, 连接到 CAN PHY 芯片，然后 CAN PHY 连接到 CAN 总线
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
//发送接口
reg [31:0] can_tx_cnt;
reg        can_tx_valid;
reg [31:0] can_tx_data;
//接收接口
wire       can_rx_valid;
wire [7:0] can_rx_data;


// --------------------------------------------------------------------------------------------------------------
//  Periodically send incremental data to the CAN tx-buffer
// --------------------------------------------------------------------------------------------------------------
//发送数据至发送缓存器
//can_top.sv 的 tx_valid, tx_ready, tx_data 构成了流式输入接口，它们都与 clk 的上升沿对齐，用于向发送缓存中写入一个数据。
//tx_valid 和 tx_ready 是一对握手信号，只有当 tx_valid 和 tx_ready 都为1时，tx_data 才被写入缓存。
//tx_ready=0 说明缓存已满，此时即使 tx_valid=1 ，也无法写入缓存。
always @ (posedge clk or negedge rstn)
if(~rstn) begin
can_tx_cnt <= 0; //重置CAN发送计数器
can_tx_valid <= 1'b0; //置位CAN发送数据无效
can_tx_data <= 0; //清空CAN发送数据
end else begin
if(can_tx_cnt<50000000-1) begin //如果CAN发送计数器未达到阈值
can_tx_cnt <= can_tx_cnt + 1; //CAN发送计数器递增
can_tx_valid <= 1'b0; //置位CAN发送数据无效
end else begin //如果CAN发送计数器已达到阈值
can_tx_cnt <= 0; //重置CAN发送计数器
can_tx_valid <= 1'b1; //置位CAN发送数据有效
can_tx_data <= can_tx_data + 1; //CAN发送数据递增
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
//发送缓存器中的数据会逐个被CAN控制器发送到CAN总线上
can_top #(
//配置本地ID
    .LOCAL_ID          ( 11'h456            ),
    //配置ID过滤器
    //短ID过滤器
    .RX_ID_SHORT_FILTER( 11'h123            ),
    .RX_ID_SHORT_MASK  ( 11'h7ff            ),
    //长ID过滤器
    .RX_ID_LONG_FILTER ( 29'h12345678       ),
    .RX_ID_LONG_MASK   ( 29'h1fffffff       ),
    //配置时序参数(分频系数)
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
