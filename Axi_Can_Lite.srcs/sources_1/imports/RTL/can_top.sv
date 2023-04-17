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
    parameter logic [10:0] LOCAL_ID      = 11'h456,//本地ID 11位短ID
    
    // recieve ID filter parameters
    parameter logic [10:0] RX_ID_SHORT_FILTER = 11'h122,//接收 ID 短过滤器参数，位宽为 11
    parameter logic [10:0] RX_ID_SHORT_MASK   = 11'h17e,//接收 ID 短掩码参数
    parameter logic [28:0] RX_ID_LONG_FILTER  = 29'h12345678,//接收 ID 短掩码参数
    parameter logic [28:0] RX_ID_LONG_MASK    = 29'h1fffffff,//接收 ID 长掩码参数
    
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
    input  wire        tx_valid,  // when tx_valid=1 and tx_ready=1, push a data to tx fifo用户 TX 缓冲写入接口，当 tx_valid=1 且 tx_ready=1 时，将一个数据写入 TX fifo 中
    output wire        tx_ready,  // whether the tx fifo is available用户 TX 缓冲就绪接口，输出，表示 TX fifo 是否可用
    input  wire [31:0] tx_data,   // the data to push to tx fifo
    
    // user rx data interface (byte per cycle, unbuffered)
    output reg         rx_valid,  // whether data byte is valid
    output reg         rx_last,   // indicate the last data byte of a packet用户 RX 缓冲数据最后一个字节标识接口
    output reg  [ 7:0] rx_data,   // a data byte in the packet用户 RX 缓冲数据接口
    output reg  [28:0] rx_id,     // the ID of a packet用户 RX 缓冲 ID 接口
    output reg         rx_ide     // whether the ID is LONG or SHORT用户 TX 缓冲就绪接口，输出，表示 TX fifo 是否可用
);

initial {rx_valid, rx_last, rx_data, rx_id, rx_ide} = '0;    // 初始化 rx_valid, rx_last, rx_data, rx_id, rx_ide

reg         buff_valid = '0;      // buffer 的有效位
reg         buff_ready = '0;      // buffer 的就绪位
wire [31:0] buff_data;           // TXbuffer 的数据

//包数据
reg         pkt_txing = '0;       // 是否正在发送一个包
reg  [31:0] pkt_tx_data = '0;     // 发送包的数据
wire        pkt_tx_done;          // 发送包是否完成
wire        pkt_tx_acked;         // 包是否被确认接收
wire        pkt_rx_valid;         // 是否接收到了一个包
wire [28:0] pkt_rx_id;            // 接收到的包的 ID
wire        pkt_rx_ide;           // 接收到的包的 ID 是否是长 ID
wire        pkt_rx_rtr;           // 接收到的包是否是远程帧
wire [ 3:0] pkt_rx_len;           // 接收到的包的数据长度
wire [63:0] pkt_rx_data;          // 接收到的包的数据
reg         pkt_rx_ack = '0;      // 包是否被确认接收

reg         t_rtr_req = '0;       // 发送远程帧请求的标志位
reg         r_rtr_req = '0;       // 接收到远程帧请求的标志位
reg  [ 3:0] r_cnt = '0;           // 已经接收到的字节数
reg  [ 3:0] r_len = '0;           // 接收到的包的数据长度
reg  [63:0] r_data = '0;          // 接收到的数据
reg  [ 1:0] t_retry_cnt = '0;     // 重试次数计数器




// ---------------------------------------------------------------------------------------------------------------------------------------
//  TX buffer
//可存储 1024 个 32 位数据的缓冲区，用于存储 CAN 总线接收到的数据
// ---------------------------------------------------------------------------------------------------------------------------------------
localparam DSIZE = 32;  // 定义数据位数为32位
localparam ASIZE = 10;  // 定义地址位数为10位

reg [DSIZE-1:0] buffer [1<<ASIZE];  // 定义深度为2^10=1024，数据位数为32位的存储数组，可能会自动合成为BRAM

reg [ASIZE:0] wptr = '0, rptr = '0;  // 定义读写指针，初始化为0

wire full = wptr == {~rptr[ASIZE], rptr[ASIZE-1:0]};  // 判断缓存是否已满
wire empty = wptr == rptr;  // 判断缓存是否为空

assign tx_ready = ~full;  // 如果缓存未满，则准备好写入新数据

always @ (posedge clk or negedge rstn)  // 这个always块用于在时钟上升沿或复位时操作
    if (~rstn) begin
        wptr <= '0;  // 复位写指针为0
    end else begin
        if (tx_valid & ~full)  // 如果收到新数据且缓存未满
            wptr <= wptr + (1+ASIZE)'(1);  // 写指针加1，新数据被存储在写指针指向的位置
    end

always @ (posedge clk)  // 这个always块用于在时钟上升沿时操作
    if (tx_valid & ~full)  // 如果收到新数据且缓存未满
        buffer[wptr[ASIZE-1:0]] <= tx_data;  // 将新数据写入缓存的对应位置

wire rdready = ~buff_valid | buff_ready;  // 判断是否可读
reg rdack = '0;  // 读应答信号，初始化为0
reg [DSIZE-1:0] rddata;  // 读出的数据 
reg [DSIZE-1:0] keepdata = '0;  // 保留数据，初始化为0
assign buff_data = rdack ? rddata : keepdata;  // 如果可读，返回读出的数据，否则返回保留的数据


always @ (posedge clk or negedge rstn) // 同步到时钟上升沿或复位下降沿
    if(~rstn) begin // 如果复位信号为低电平
        buff_valid <= 1'b0; // 缓冲区无效
        rdack <= 1'b0; // 读取确认信号无效
        rptr <= '0; // 读指针清零
        keepdata <= '0; // 缓冲区数据清零
    end else begin
        buff_valid <= ~empty | ~rdready; // 缓冲区有效，若未空或读取准备好
        rdack <= ~empty & rdready; // 读取确认信号有效，若未空且读取准备好
        if(~empty & rdready) // 若未空且读取准备好
            rptr <= rptr + (1+ASIZE)'(1); // 读指针加1
        if(rdack) // 若读取确认信号有效
            keepdata <= rddata; // 保留缓冲区的数据
    end

always @ (posedge clk)
    rddata <= buffer[rptr[ASIZE-1:0]]; // 从缓冲区中读取数据，并赋值给rddata变量




// ---------------------------------------------------------------------------------------------------------------------------------------
//  CAN packet level controller实例化
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
        {rx_valid, rx_last, rx_data, rx_id, rx_ide} <= '0;  // 初始化为0
    end else begin
        {rx_valid, rx_last, rx_data} <= '0;
        
        pkt_rx_ack <= 1'b0;          // 初始化为0
        r_rtr_req <= 1'b0;           // 初始化为0
        
        if(r_cnt>4'd0) begin         // 发送数据字节

            rx_valid <= (r_cnt<=r_len);
            rx_last  <= (r_cnt<=r_len) && (r_cnt==4'd1);
            {rx_data, r_data} <= {r_data, 8'd0};  // 发送一字节，其他字节推后，填0
            r_cnt <= r_cnt - 4'd1;                // 计数器-1
            
        end else if(pkt_rx_valid) begin  // 接收新包
        
            r_len <= pkt_rx_len;             // latch住接收到的数据包长度
            r_data <= pkt_rx_data;           // latch住接收到的数据包内容
            
            if(pkt_rx_rtr) begin
                if(~pkt_rx_ide && pkt_rx_id[10:0]==LOCAL_ID) begin           // 是一个短ID的远程数据包，且ID匹配LOCAL_ID
                    pkt_rx_ack <= 1'b1;                                     // 发送ACK信号
                    r_rtr_req <= 1'b1;                                      // 触发远程请求
                end
            end else if(~pkt_rx_ide) begin                                   // 是一个短ID的数据包
                if( (pkt_rx_id[10:0] & RX_ID_SHORT_MASK) == (RX_ID_SHORT_FILTER & RX_ID_SHORT_MASK) ) begin  // ID匹配
                    pkt_rx_ack <= 1'b1;                                     // 发送ACK信号
                    r_cnt <= 4'd8;                                          // 初始化计数器为8（即发送8字节数据）
                    rx_id <= pkt_rx_id;                                      // latch住接收到的数据包ID
                    rx_ide <= pkt_rx_ide;                                    // latch住接收到的数据包类型（短ID/长ID）
                end
            end else begin                                                   // 是一个长ID的数据包
                if( (pkt_rx_id & RX_ID_LONG_MASK) == (RX_ID_LONG_FILTER & RX_ID_LONG_MASK) ) begin           // ID匹配
                    pkt_rx_ack <= 1'b1;                                     // 发送ACK信号
                    r_cnt <= 4'd8;                                          // 初始化计数器为8（即发送8字节数据）
                    rx_id <= pkt_rx_id;                                      // latch住接收到的数据包ID
                    rx_ide <= pkt_rx_ide;                                    // latch住接收到的数据包类型（短ID/长ID）
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
        buff_ready <= 1'b0;         // 复位时将 buff_ready 设为 0
        pkt_tx_data <= '0;          // 复位时将 pkt_tx_data 设为 0
        t_rtr_req <= 1'b0;          // 复位时将 t_rtr_req 设为 0
        pkt_txing <= 1'b0;          // 复位时将 pkt_txing 设为 0
        t_retry_cnt <= 2'd0;        // 复位时将 t_retry_cnt 设为 0
    end else begin
        buff_ready <= 1'b0;         // 将 buff_ready 设为 0
        
        if(r_rtr_req)
            t_rtr_req <= 1'b1;                   // 如果收到了远程请求帧，则将 t_rtr_req 设为 1
        
        if(~pkt_txing) begin                      // 如果当前没有正在发送的帧
            t_retry_cnt <= 2'd0;                  // 将重传计数器 t_retry_cnt 设为 0
            if(t_rtr_req | buff_valid) begin      // 如果收到了远程请求帧，或者发送缓冲区有数据
                buff_ready <= buff_valid;         // 尝试将发送缓冲区中的数据弹出，如果发送缓冲区有数据
                t_rtr_req <= 1'b0;                // 将 t_rtr_req 设为 0
                if(buff_valid)                    // 如果发送缓冲区有数据，则更新 pkt_tx_data
                    pkt_tx_data <= buff_data;
                pkt_txing <= 1'b1;                // 将 pkt_txing 设为 1，表示正在发送帧
            end
        end else if(pkt_tx_done) begin            // 如果当前正在发送帧且发送完成
            if(pkt_tx_acked || t_retry_cnt==2'd3) begin   // 如果帧发送成功或者重传计数器已经等于 3
                pkt_txing <= 1'b0;                       // 将 pkt_txing 设为 0，表示帧发送已经结束
            end else begin
                t_retry_cnt <= t_retry_cnt + 2'd1;        // 否则将重传计数器加 1
            end
        end
    end



endmodule
