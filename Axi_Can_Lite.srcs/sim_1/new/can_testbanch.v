`timescale 1ns/1ns

module can_testbanch;

    reg clk_50mhz;
    wire uart_tx;
    reg can_rx;
    wire can_tx;
    
    can_testbanch dut (
        .clk(clk_50mhz),
        .uart_tx(uart_tx),
        .can_rx(can_rx),
        .can_tx(can_tx)
    );

    initial begin
        clk_50mhz = 1'b0;
        forever #10 clk_50mhz = ~clk_50mhz;
    end
    
    initial begin
        $dumpfile("can_testbanch.vcd");
        $dumpvars(0, can_testbanch);
        #1000;
        can_rx = 1'b1;
        #500000;
        can_rx = 1'b0;
        #500000;
        can_rx = 1'b1;
        #500000;
        can_rx = 1'b0;
        #500000;
        $finish;
    end
    
    integer i;
    integer k;
    integer j;
    
    reg [31:0] can_tx_cnt;
    reg can_tx_valid;
    reg [31:0] can_tx_data;
     reg [31:0] can_rx_data;
    always @(posedge clk_50mhz) begin
        if (can_tx_valid) begin
            k = can_tx_cnt;
            for (i = 0; i < 32; i = i + 8) begin
                can_tx_data[i+:8] = k[31-i+:8];
            end
        end
    end
    
    always @(posedge clk_50mhz) begin
        if (can_tx_valid) begin
            can_tx_cnt <= can_tx_cnt + 1;
        end
        if (can_tx_cnt == 50000000-1) begin
            can_tx_valid <= 1'b0;
        end
        if (!can_tx_valid) begin
            can_tx_cnt <= 0;
            can_tx_valid <= 1'b1;
            can_tx_data <= can_tx_data + 1;
        end
    end
    
    always @(negedge clk_50mhz) begin
        if (can_rx && !can_tx) begin
            j = can_rx_data;
            $display("Received data: %d", j);
        end
    end

endmodule
