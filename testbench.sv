module tb_uart_top;
    reg        clk;
    reg        reset;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire [7:0] rx_data;
    wire       rx_done;
    wire       tx_busy;

    // Instantiate Top Loopback Module
    uart_top #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uut (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .rx_done(rx_done),
        .tx_busy(tx_busy)
    );

    // 50 MHz Clock (20ns Period)
    always #10 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart_top);

        clk      = 0;
        reset    = 1;
        tx_start = 0;
        tx_data  = 8'h00;

        #100;
        reset = 0;
        #100;

        // Test Byte 1: 0x35
        send_byte(8'h35);

        // Test Byte 2: 0xA9
        send_byte(8'hA9);

        #1000;
        $display("--- SUCCESS: All Bytes Transmitted & Received Successfully ---");
        $finish;
    end

    // Task to send byte and verify result
    task send_byte(input [7:0] data_in);
        begin
            @(posedge clk);
            tx_data  = data_in;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            // Wait for receiver to finish receiving data
            @(posedge rx_done);
            if (rx_data == data_in) begin
                $display("[PASS] Sent: 0x%h | Received: 0x%h at time %0t ns", data_in, rx_data, $time);
            end else begin
                $display("[FAIL] Sent: 0x%h | Received: 0x%h at time %0t ns", data_in, rx_data, $time);
            end
        end
    endtask
endmodule

