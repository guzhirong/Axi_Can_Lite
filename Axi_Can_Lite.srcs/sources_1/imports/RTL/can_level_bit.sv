`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : can_level_bit
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: CAN bus bit level controller,
//           instantiated by can_level_packet
//--------------------------------------------------------------------------------------------------------

module can_level_bit #(
    parameter logic [15:0] default_c_PTS  = 16'd34,   // 默认的时间段1长度
    parameter logic [15:0] default_c_PBS1 = 16'd5,    // 默认的时间段2长度
    parameter logic [15:0] default_c_PBS2 = 16'd10    // 默认的时间段3长度
) (
    input  wire        rstn,  // 复位信号，低电平有效
    input  wire        clk,   // 时钟信号
    
    // CAN TX and RX
    input  wire        can_rx, // CAN总线接收数据信号
    output reg         can_tx, // CAN总线发送数据信号
    
    // user interface
    output reg         req,   // 控制信息，用于指示当前数据帧的边界
    output reg         rbit,  // 上一位接收到的数据位，只有在req=1时才有效
    input  wire        tbit   // 下一位要发送的数据位，必须在req=1后的周期设置
);

initial can_tx = 1'b1;   // 初始值，CAN总线发送数据信号为高电
initial req = 1'b0;      // 初始值，控制信息为0
initial rbit = 1'b1;     // 初始值，上一位接收到的数据位为1

reg        rx_buf = 1'b1;   // 输入缓冲区，初始值为1
reg        rx_fall = 1'b0;  // 上升沿检测，初始值为0
always @ (posedge clk or negedge rstn)  // 时钟上升沿或复位信号下降沿时执行
    if(~rstn) begin   // 复位
        rx_buf  <= 1'b1;  // 重置缓冲区为1
        rx_fall <= 1'b0;  // 重置上升沿检测为0
    end else begin     // 时钟上升沿
        rx_buf  <= can_rx;               // 存储接收到的数据
        rx_fall <= rx_buf & ~can_rx;     // 检测上升沿
    end

localparam [16:0] default_c_PTS_e  = {1'b0, default_c_PTS};    // 计算默认的时间段1长度
localparam [16:0] default_c_PBS1_e = {1'b0, default_c_PBS1};   // 计算默认的时间段2长度
localparam [16:0] default_c_PBS2_e = {1'b0, default_c_PBS2};   // 计算默认的时间段3长度

reg  [16:0] adjust_c_PBS1 = '0;  // 调整时间段2长度的变量，初始值为0

reg  [ 2:0] cnt_high = '0;  //定义一个3位寄存器，用于计算高位字节的数量，初始值为0
reg  [16:0] cnt = 17'd1;   //定义一个17位寄存器，用于计数器，初始值为1
enum logic [1:0] {STAT_PTS, STAT_PBS1, STAT_PBS2} stat = STAT_PTS;  //定义一个状态枚举变量，用于控制状态转移，初始状态为STAT_PTS
reg        inframe = 1'b0;  //定义一个1位寄存器，用于标识是否处于发送帧中，初始值为0

// state machine
// 状态机模块，根据状态转移进行数据帧的发送和接收
always @ (posedge clk or negedge rstn)  //always块，当时钟上升沿或复位下降沿发生时执行以下操作
//复位操作s
    if(~rstn) begin  //如果复位为0，则执行以下操作
        can_tx <= 1'b1;  //将发送端口置为1
        req <= 1'b0;     //将请求置为0
        rbit <= 1'b1;    //将接收端口置为1
        adjust_c_PBS1 <= 8'd0;  //将调整计数器初始化为0
        cnt_high <= 3'd0;      //将高位字节数量计数器初始化为0
        cnt <= 17'd1;          //将计数器初始化为1
        stat <= STAT_PTS;      //将状态枚举变量初始化为STAT_PTS
        inframe <= 1'b0;       //将是否处于发送帧中的标识初始化为0
        //正常操作
    end else begin   //否则，即复位不为0，则执行以下操作
        req <= 1'b0;    //将请求置为0
        //发送帧inframe=1 控制信息req=1
        if(~inframe & rx_fall) begin  //如果不在发送帧中并且接收到下降沿，则执行以下操作
        
            adjust_c_PBS1 <= default_c_PBS1_e;  //将调整计数器设置为默认值
            cnt <= 17'd1;  //将计数器初始化为1
            stat <= STAT_PTS;  //将状态枚举变量置为STAT_PTS
            inframe <= 1'b1;   //将是否处于发送帧中的标识设置为1
        end 
        
        else begin  //否则，即在发送帧中或未接收到下降沿，则执行以下操作

            case(stat)  //根据状态枚举变量的值进行状态转移
                STAT_PTS: begin  //时间段1，如果状态为STAT_PTS，则执行以下操作
                    if( (rx_fall & tbit) && cnt>17'd2 )  //如果接收到下降沿和传输位为1且计数器大于2，则执行以下操作
                        adjust_c_PBS1 <= default_c_PBS1_e + cnt;  //将调整计数器设置为默认值加上计数器的值
                    if(cnt>=default_c_PTS_e) begin  //如果计数器大于等于默认值，则执行以下操作
                        cnt <= 17'd1; // 计数器复位为1
                        stat <= STAT_PBS1;// 状态转移为时间段2
                        //如果不走第二个状态机，就只是给计数器加1
                    end else
                        cnt <= cnt + 17'd1;// 计数器加1
                end
              // 时间段2
                STAT_PBS1: begin
                    if(cnt==17'd1) begin // 如果计数器 cnt 等于1
                        req <= 1'b1; // 则请求数据发送
                        rbit <= rx_buf;   // sampling bit // 将接收到的数据赋值给 rbit
                        cnt_high <= rx_buf ? cnt_high<3'd7 ? cnt_high+3'd1 : cnt_high : 3'd0;// 如果接收到的数据为1，则计数器 cnt_high 加 1；否则将其置为0
                    end
                    if(cnt>=adjust_c_PBS1) begin// 如果计数器 cnt 大于等于调整计数器 adjust_c_PBS1，则转移到状态 STAT_PBS2，并将计数器 cnt 复位为0
                        cnt <= 17'd0;
                        stat <= STAT_PBS2;
                    end else
                        cnt <= cnt + 17'd1;// 否则计数器 cnt 加 1
                end
                STAT_PBS2: begin
                // 如果接收到下降沿并且传输位为1，或者计数器 cnt 大于等于默认时间段3的长度，则将发送端口置为传输位 tbit，调整计数器为默认时间段2的长度，将计数器复位为1，
                //将状态机转移到状态 STAT_PTS，如果计数器 cnt_high 等于7，则将是否处于发送帧中的标识 inframe 置为0
                    if( (rx_fall & tbit) || (cnt>=default_c_PBS2_e) ) begin
                        can_tx <= tbit;
                        adjust_c_PBS1 <= default_c_PBS1_e;
                        cnt <= 17'd1;
                        stat <= STAT_PTS;
                        if(cnt_high==3'd7) inframe <= 1'b0;
                    end else begin
                    // 否则计数器 cnt 加 1，如果计数器 cnt 等于默认时间段3的长度减1，则将发送端口置为传输位 tbit
                        cnt <= cnt + 17'd1;
                        if(cnt==default_c_PBS2_e-17'd1)
                            can_tx <= tbit;
                    end
                end
                default : begin
                // 默认情况下，将状态机转移到状态 STAT_PTS
                    stat <= STAT_PTS;
                end
            endcase
        end
    end

endmodule
