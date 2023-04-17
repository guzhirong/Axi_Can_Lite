`timescale 1ns/1ps
//--------------------------------------------------------------------------------------------------------
// Module  : can_level_packet
// Type    : synthesizable, IP's sub module
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: CAN bus packet level controller,
//           instantiated by can_top
//--------------------------------------------------------------------------------------------------------

module can_level_packet #(
parameter logic TX_RTR = 1'b0, // 发送数据的类型，是远程传输请求还是数据帧
parameter logic [10:0] TX_ID = 11'h456, // 发送数据的ID号
parameter logic [15:0] default_c_PTS = 16'd34, // 默认的时间段分配
parameter logic [15:0] default_c_PBS1 = 16'd5, // 默认的位间隔宽度
parameter logic [15:0] default_c_PBS2 = 16'd10 // 默认的同步跳转宽度
) (
    input  wire        rstn,  // set to 1 while working启动信号
    input  wire        clk,   // system clock时钟信号
    
// CAN TX and RX
input  wire        can_rx, // CAN总线接收端口
output wire        can_tx, // CAN总线发送端口

// user tx packet interface
input  wire        tx_start, // 发送数据启动信号
input  wire [31:0] tx_data,  // 发送的数据
output reg         tx_done,  // 发送完成标志
output reg         tx_acked, // 发送确认标志

// user rx packet interface
output reg         rx_valid, // 接收到有效数据标志
output reg  [28:0] rx_id,    // 接收到的数据的ID
output reg         rx_ide,   // 是否为扩展帧标志
output reg         rx_rtr,   // 接收到的数据的类型，是远程传输请求还是数据帧
output reg  [ 3:0] rx_len,   // 接收到的数据长度
output reg  [63:0] rx_data,  // 接收到的数据
input  wire        rx_ack    // 接收到数据确认信号

);
// 初始化输出端口值
initial {tx_done, tx_acked} = 1'b0;
initial {rx_valid,rx_id,rx_ide,rx_rtr,rx_len,rx_data} = '0;

// CRC 15位异或函数
function automatic logic [14:0] crc15(input logic [14:0] crc_val, input logic in_bit);
    return {crc_val[13:0], 1'b0} ^ (crc_val[14] ^ in_bit ? 15'h4599 : 15'h0);
endfunction
// 连接 CAN 位级控制器
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


//定义一个长度为8的寄存器 rx_history 并赋初值 '0'
reg [7:0] rx_history = '0;
//定义一个长度为4的寄存器 tx_history 并赋初值 '1'
reg [3:0] tx_history = '1;
//定义一个 wire 类型变量 rx_end，它的值等于 rx_history 的值是否等于 1
wire rx_end = rx_history == '1;
//定义一个 wire 类型变量 rx_err，它的值等于 rx_history 的低6位是否都为 0
wire rx_err = rx_history[5:0] == '0;
//定义一个 wire 类型变量 rx_ben，它的值等于 rx_history 的低5位是否既不等于 0 也不等于 1
wire rx_ben = rx_history[4:0] != '0 && rx_history[4:0] != '1;
//定义一个 wire 类型变量 tx_ben，它的值等于 {tx_history, bit_tx} 是否既不等于 0 也不等于 1
wire tx_ben = {tx_history, bit_tx} != '0 && {tx_history, bit_tx} != '1;

//对 rx_history 和 tx_history 进行赋值
always @ (posedge clk or negedge rstn)
if(~rstn) begin
    //当复位信号为低电平时，将 rx_history 和 tx_history 赋值为 0 和 1
    rx_history <= '0;
    tx_history <= '1;
end else begin
    //当 bit_req 信号为高电平时，将 bit_rx 存入 rx_history 的低7位，将 bit_tx 存入 tx_history 的低3位
    if(bit_req) begin
        rx_history <= {rx_history[6:0], bit_rx};
        tx_history <= {tx_history[2:0], bit_tx};
    end
end



//定义一个长度为1的 reg 类型变量 tx_arbitrary 并赋初值 '0'
reg tx_arbitrary = '0;
//定义一个长度为15的 reg 类型变量 rx_crc 并赋初值 '0'
reg [14:0] rx_crc = '0;
//定义一个长度为15的 wire 类型变量 rx_crc_next，它的值等于将 rx_crc 左移一位后加上一个高位为 0 的数，
//然后对其与一个 15 位的十六进制数 15'h4599 或 15'h0 进行按位异或运算
wire [14:0] rx_crc_next = {rx_crc[13:0], 1'b0} ^ (rx_crc[14] ^ bit_rx ? 15'h4599 : 15'h0);
//定义一个长度为50的 reg 类型变量 tx_shift 并赋初值 '1'
reg [49:0] tx_shift = '1;
//定义一个长度为15的 reg 类型变量 tx_crc 并赋初值 '0' 
reg [14:0] tx_crc = '0;
wire[14:0] tx_crc_next = {tx_crc[13:0], 1'b0} ^ (tx_crc[14] ^ tx_shift[49] ? 15'h4599 : 15'h0);//进行按位异或运算（XOR）
//(tx_crc[14] ^ tx_shift[49] ：表示将 tx_crc 的最高位和 tx_shift 的最高位进行异或运算
//如果tx_crc[14] ^ tx_shift[49]=1 则计算结果为一个15位的十六进制数 15'h4599，否则计算结果为一个15位的十六进制数 15'h0。
//15'h4599:15'b0100010110011001
wire[ 3:0] rx_len_next = {rx_len[2:0], bit_rx};  // 计算下一个接收长度，将bit_rx插入到rx_len的低3位中
wire[ 7:0] rx_cnt = rx_len[3] ? 8'd63 : {1'd0, rx_len, 3'd0} - 8'd1; // 根据接收长度计算接收字节数，如果长度位的最高位为1，接收的字节数为63，否则，接收的字节数为长度位的低四位+1

localparam [3:0] INIT         = 4'd0, // 定义状态机状态名称对应的值
                 IDLE         = 4'd1, // 空闲状态，等待开始发送或接收
                 TX_ID_MSB    = 4'd2, // 开始发送ID位的最高位
                 TRX_ID_BASE  = 4'd3, // 发送或接收ID的其余位
                 TX_PAYLOAD   = 4'd4, // 发送数据
                 TX_ACK_DEL   = 4'd5, // 发送ACK应答前的延时状态
                 TX_ACK       = 4'd6, // 发送ACK应答
                 TX_EOF       = 4'd7, // 发送结束位
                 RX_IDE_BIT   = 4'd8, // 接收IDE位
                 RX_ID_EXTEND = 4'd9, // 接收ID的扩展位
                 RX_RESV1_BIT = 4'd10, // 接收保留位
                 RX_CTRL      = 4'd11, // 接收控制位
                 RX_DATA      = 4'd12, // 接收数据
                 RX_CRC       = 4'd13, // 接收CRC
                 RX_ACK       = 4'd14, // 接收ACK应答
                 RX_EOF       = 4'd15; // 接收结束位

reg [ 7:0] cnt = '0; // 发送或接收状态计数器
reg [ 3:0] stat = INIT; // 状态机状态变量

reg rx_valid_pre = '0; // 前一帧接收是否有效
reg rx_valid_latch = '0; // 当前帧接收是否有效
reg rx_ack_latch = '0; // 当前帧接收ACK应答是否有效

always @ (posedge clk or negedge rstn) // 组合逻辑块，处理前一帧接收是否有效，以及当前帧接收是否有效和ACK应答是否有效的更新
    if(~rstn) begin
        rx_valid <= 1'b0;
        rx_valid_latch <= 1'b0;
        rx_ack_latch <= 1'b0;
    end else begin
        rx_valid <= rx_valid_pre & (rx_crc==15'd0); // 当前帧接收是否有效的判断，rx_crc==15'd0表示接收到的CRC校验码正确
        rx_valid_latch <= rx_valid;
        if(rx_valid_latch)
            rx_ack_latch <= rx_ack; // 更新ACK应答是否有效
    end

          always @ (posedge clk or negedge rstn) // 按时钟或复位信号变化时执行
                if(~rstn) begin // 复位
                        {tx_done, tx_acked} <= 1'b0; // 传输完成标志位和应答标志位复位
                        rx_valid_pre <= 1'b0; // 接收数据有效前导位复位
                        {rx_id,rx_ide,rx_rtr,rx_len,rx_data,rx_crc} <= '0; // 接收数据相关变量复位
                        bit_tx <= 1'b1; // 发送数据位复位
                        tx_arbitrary <= 1'b0; // 发送任意位复位
                        tx_crc <= '0; // 发送数据 CRC 校验码复位
                        tx_shift <= '1; // 发送数据移位寄存器复位
                        cnt <= 8'd0; // 计数器复位
                        stat <= INIT; // 状态机状态复位
        end else begin // 正常工作状态
                        {tx_done, tx_acked} <= 1'b0; // 传输完成标志位和应答标志位复位
                        rx_valid_pre <= 1'b0; // 接收数据有效前导位复位
                 if(bit_req) begin // 根据请求信号执行相应操作
                        bit_tx <= 1'b1; // 发送数据位复位
        
        case(stat) // 根据状态机状态执行相应操作
            INIT : begin // 初始状态
                if(rx_end) // 如果接收到结束位，则进入空闲状态
                    stat <= IDLE;
            end
            
            IDLE : begin // 空闲状态
                tx_arbitrary <= 1'b0; // 发送任意位复位
                {rx_id,rx_ide,rx_rtr,rx_len,rx_data,rx_crc} <= '0; // 接收数据相关变量复位
                tx_crc <= '0; // 发送数据 CRC 校验码复位
                //把数送进来
                tx_shift <= {TX_ID, TX_RTR, 1'b0, 1'b0, 4'd4, tx_data}; // 将发送数据按格式存入发送数据移位寄存器
                if(bit_rx == 1'b0) begin // 如果接收数据位为低电平
                    cnt <= 8'd0; // 计数器复位
                    stat <= TRX_ID_BASE; // 进入交换标识符基础位状态
                end else if(cnt<8'd20) begin // 如果计数器小于 20
                    cnt <= cnt + 8'd1; // 计数器加 1
                    
                    //开始发送数据
                end else if(tx_start) begin // 如果可以开始发送
                    bit_tx <= 1'b0; // 发送数据位设为低电平
                    cnt <= 8'd0; // 计数器复位
                    stat <= TX_ID_MSB; // 进入发送标识符 MSB 状态
                end
            end
            
            TX_ID_MSB : begin // 发送标识符 MSB 状态
 // 如果bit_rx是高电平
        if(bit_rx) begin
            // 进入TX_EOF状态
            stat <= TX_EOF;
        end else begin
            // 将tx_shift左移一位，并加入bit_tx
       //bit_tx的值会在每个时钟周期中根据发送数据的移位寄存器和当前数据位的值进行更新
            {bit_tx, tx_shift} <= {tx_shift, 1'b1};
            // 更新CRC
            tx_crc <= tx_crc_next;
            // TX任意位标记位设为高电平
            tx_arbitrary <= 1'b1;
            // 进入TRX_ID_BASE状态
            stat <= TRX_ID_BASE;
        end
                end
                
                TRX_ID_BASE : begin
                 // 如果TX任意位标记位是高电平，并且bit_rx等于bit_tx
                    if(tx_arbitrary && bit_rx==bit_tx) begin
                     // 如果tx_ben为高电平
                        if(tx_ben) begin
                         // 将tx_shift左移一位，并加入bit_tx
                            {bit_tx, tx_shift} <= {tx_shift, 1'b1};
                              // 更新CRC
                            tx_crc <= tx_crc_next;
                             // 如果tx_ben为低电平
                        end else begin
                          // bit_tx取反
                            bit_tx <= ~tx_history[0];
                        end
                         // 如果TX任意位标记位为低电平或bit_rx不等于bit_tx
                    end else begin
                      // TX任意位标记位设为低电平
                        tx_arbitrary <= 1'b0;
                    end
                     // 如果rx_end为高电平
                    if(rx_end) begin
                      // 进入IDLE状态
                        stat <= IDLE;
                        // 如果rx_err为高电平
                    end else if(rx_err) begin
                       // 进入RX_EOF状态
                        stat <= RX_EOF;
               // 如果rx_ben为高电平
        end else if(rx_ben) begin
            // 更新rx_crc
            rx_crc <= rx_crc_next;
            // 计数器加一
            cnt <= cnt + 8'd1;
            // 如果计数器小于11
            if(cnt<8'd11) begin
                // 将bit_rx加入rx_id
                rx_id <= {rx_id[27:0], bit_rx};
            // 如果计数器大于等于11
            end else begin
                // 将bit_rx赋值给rx_rtr
                rx_rtr <= bit_rx;
                // 如果TX任意位标记位为低电平或bit_rx不等于bit_tx
                if( !(tx_arbitrary && bit_rx==bit_tx) ) begin              // TX arbitrary failed
                    // 计数器清零
                    cnt <= 8'd0;
                    // 进入RX_IDE_BIT状态
                    stat <= RX_IDE_BIT;
                // 如果TX任意位标记位为高电平，并且tx_ben为高电平
                end else if(tx_ben) begin
                    // 计数器清零
                    cnt <= 8'd0;
                    // 进入TX_PAYLOAD状态
                    stat <= TX_PAYLOAD;
                end
            end
        // 如果计数器大于11
        end else if(cnt>8'd11) begin
            // 计数器清零
            cnt <= 8'd0;
            // 进入TX_PAYLOAD状态
            stat <= TX_PAYLOAD;
        end
                end

//                TX_PAYLOAD: 发送数据部分的状态。如果接收到的数据与发送的数据不一致，则跳转到TX_EOF状态。
//                如果数据传输允许（tx_ben），则左移1位并将下一个数据位存入tx_shift。
//                还需要将校验和的下一位tx_crc_next存入tx_crc。如果计数器cnt等于36，则将校验和的值存储到tx_shift的49-35位。
//                如果计数器小于52，则增加计数器的值，否则将计数器的值重置为0并跳转到TX_ACK_DEL状态。
            TX_PAYLOAD : begin                               // 发送数据帧的Payload阶段
                if(bit_rx != bit_tx) begin        // 检查接收数据线是否与发送数据线相同，如果不同则跳到TX_EOF状态
                    stat <= TX_EOF;
                end else if(tx_ben) begin         // 检查是否开启了总线接口
                    {bit_tx, tx_shift} <= {tx_shift, 1'b1}; // 将 tx_shift 向左移一位，并将最低位设置为 bit_tx 的值
                    tx_crc <= tx_crc_next;          // 更新校验和
                    if(cnt==8'd36) tx_shift[49:35] <= tx_crc_next; // 在第36位处写入校验和
                    if(cnt<8'd52) begin             // 继续发送数据，直到52位
                        cnt <= cnt + 8'd1;
                    end else begin
                        cnt <= 8'd0;                // 发送完毕，跳到TX_ACK_DEL状态
                        stat <= TX_ACK_DEL;
                    end
                end else begin                     // 如果总线接口未开启，则在发送数据线上输出反转的历史值
                    bit_tx <= ~tx_history[0];
                end
            end

                //如果接收到的位与发送的位相同，则跳转到TX_ACK状态，否则跳转到TX_EOF状态。
                TX_ACK_DEL : begin
                    stat <= bit_rx ? TX_ACK : TX_EOF;
                end
                //传输完成的状态，设置tx_done = 1，存储~bit_rx到tx_acked中，然后跳转到TX_EOF状态。
                TX_ACK : begin
                    tx_done <= 1'b1;
                    tx_acked <= ~bit_rx;
                    stat <= TX_EOF;
                end
                //用于发送完最后8位数据之后的状态。如果计数器cnt小于8，则增加计数器的值。否则将计数器的值重置为0并跳转到RX_EOF状态。
                    TX_EOF : begin
                if(cnt<8'd8) begin // 如果发送的数据位数小于8位，继续计数
                    cnt <= cnt + 8'd1;
                 end else begin // 否则将计数器清零，并将状态机状态设置为RX_EOF
                        cnt <= 8'd0;
                        stat <= RX_EOF;
                    end
                   end
                
RX_IDE_BIT : begin
if(rx_end) begin // 如果帧结束，则将状态机状态设置为IDLE
stat <= IDLE;
end else if(rx_err) begin //如果出现错误，则将状态机状态设置为RX_EOF
stat <= RX_EOF;
end else if(rx_ben) begin // 如果正确接收到比特，则更新CRC并将状态机状态转移
rx_crc <= rx_crc_next;
rx_ide <= bit_rx;
stat <= bit_rx ? RX_ID_EXTEND : RX_CTRL;
end
end
                
                
//     在 RX_IDE_BIT 状态位为 1 时切换到此状态，处理标识符扩展位。如果数据接收已经完成，则状态机切换到 IDLE 状态，
//    如果出错了则切换到 RX_EOF 状态。在远程帧标识符后有两位的 RTR 位，所以状态机会在这里把 RTR 位保存到 rx_rtr 变量中，
//     并等待下一个状态处理。标识符扩展位有 18 位，状态机会将这些位从高位到低位依次存储在 rx_id 中，同时 cnt 变量记录已经处理的位数，
//     初始值为 0，每次进入此状态 cnt 自增 1。当 cnt 大于等于 18 时，状态机切换到 RX_RESV1_BIT 状态。
RX_ID_EXTEND : begin                     // RX_ID_EXTEND状态用于接收拓展标识符
                    if(rx_end) begin           // 如果接收结束了，进入IDLE状态
                        stat <= IDLE;
                    end else if(rx_err) begin  // 如果接收出现错误，进入RX_EOF状态
                        stat <= RX_EOF;
                    end else if(rx_ben) begin  // 如果接收使能位是高电平
                        rx_crc <= rx_crc_next;  // 更新CRC
                        if(cnt<8'd18) begin     // 如果计数器小于18，说明正在接收标识符的扩展部分，把接收到的比特加到标识符中
                            rx_id <= {rx_id[27:0], bit_rx};
                            cnt <= cnt + 8'd1;
                        end else begin          // 如果计数器等于18，说明已经接收完了标识符的扩展部分
                            rx_rtr <= bit_rx;   // 把比特添加到rtr字段
                            cnt <= 8'd0;        // 重置计数器
                            stat <= RX_RESV1_BIT; // 进入RX_RESV1_BIT状态，接收保留位R1
                        end
                    end
                end

//                如果当前接收到数据，且不是结束位，则根据接收到的数据位设置状态为 RX_EOF 或 RX_CTRL。
//                如果接收到数据为 1，则将状态设置为 RX_EOF，否则将状态设置为 RX_CTRL。
          RX_RESV1_BIT : begin                    // 接收到扩展帧的保留位1
    if(rx_end) begin                    // 帧接收完毕
        stat <= IDLE;                   // 返回IDLE状态
    end else if(rx_err) begin           // 帧接收出错
        stat <= RX_EOF;                 // 返回RX_EOF状态
    end else if(rx_ben) begin           // 帧接收正常
        rx_crc <= rx_crc_next;          // 更新接收CRC校验码
        stat <= bit_rx ? RX_EOF : RX_CTRL; // 如果接收到的是1，则返回RX_EOF状态，否则返回RX_CTRL状态
    end
end

              //  开始解析CAN协议帧的控制位，若符合协议规定则进入RX_DATA或RX_CRC状态。
          RX_CTRL : begin                                    // 接收到控制帧标志符，等待数据长度字段
                    if(rx_end) begin                   // 如果接收到了消息的结束符
                        stat <= IDLE;                   // 切换到空闲状态
                    end else if(rx_err) begin           // 如果接收到了错误标志位
                        stat <= RX_EOF;                 // 切换到接收错误状态
                    end else if(rx_ben) begin           // 如果接收到了有效的CAN总线数据
                        rx_crc <= rx_crc_next;           // 计算CRC校验值
                        rx_len <= rx_len_next;           // 保存数据长度
                        if(cnt<8'd4) begin               // 继续接收
                            cnt <= cnt + 8'd1;           // 计数器加1
                        end else begin                    // 接收完成
                            cnt <= 8'd0;                 // 计数器清零
                            stat <= (rx_len_next!='0 && rx_rtr==1'b0) ? RX_DATA : RX_CRC;  // 跳转到数据接收或CRC校验状态
                        end
                    end
                end

                //开始接收数据帧的数据部分。
                RX_DATA : begin
  if(rx_end) begin // 如果接收完成
    stat <= IDLE; // 状态机状态置为IDLE
        end else if(rx_err) begin // 如果出错
    stat <= RX_EOF; // 状态机状态置为RX_EOF
        end else if(rx_ben) begin // 如果接收使能信号有效
    rx_crc <= rx_crc_next; // 接收校验码更新为下一状态的校验码
    rx_data <= {rx_data[62:0], bit_rx}; // 将接收到的数据按位存储
  if(cnt<rx_cnt) begin // 如果数据位数未接收完
    cnt <= cnt + 8'd1; // 接收计数器加1
        end else begin // 如果数据位数已经接收完
    cnt <= 8'd0; // 接收计数器清零
    stat <= RX_CRC; // 状态机状态置为RX_CRC
                        end
                    end
                end
                //检查接收到的CRC是否正确，如果正确，则解析接收到的数据，否则返回RX_EOF状态，意味着接收错误。
            RX_CRC : begin                              // 接收CRC
                    if(rx_end) begin          // 如果接收到结束位
                        stat <= IDLE;          // 切换到IDLE状态
                    end else if(rx_err) begin // 如果接收到错误
                        stat <= RX_EOF;        // 切换到RX_EOF状态
                    end else if(rx_ben) begin // 如果接收到有效数据
                        rx_crc <= rx_crc_next; // 将接收到的数据存入CRC寄存器
                        if(cnt<8'd14) begin     // 如果计数器小于14
                            cnt <= cnt + 8'd1;  // 计数器加1
                        end else begin          // 如果计数器等于14
                            cnt <= 8'd0;         // 计数器清零
                            stat <= RX_ACK;      // 切换到RX_ACK状态
                            rx_valid_pre <= 1'b1;// 将rx_valid_pre置为1
                        end
                    end
                end

                
RX_ACK : begin
if(rx_end) begin // 若接收结束
stat <= IDLE; // 切换到空闲状态
end else if(rx_err) begin // 若出现接收错误
stat <= RX_EOF; // 切换到接收结束状态
end else if(rx_ben) begin // 若数据包在总线上传输到该节点
if(bit_rx && rx_crc==15'd0 && rx_ack_latch) // 如果 DEL=1，无 CRC 错误且用户允许发送 ACK=0 位
bit_tx <= 1'b0; // 发送 ACK
stat <= RX_EOF; // 切换到接收结束状态
end
end
                
                           RX_EOF : begin
                if(rx_end)                   // 若接收结束
                    stat <= IDLE;             // 切换到空闲状态
            end


            endcase
        end
    end



endmodule
