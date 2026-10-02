module baud_rate_gen #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 9600
)(
    input  wire clk,
    input  wire reset,
    output reg  baud_tick
);
    localparam DIVISOR = CLK_FREQ / (BAUD_RATE * 16);
    reg [15:0] counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter   <= 16'd0;
            baud_tick <= 1'b0;
        end else if (counter == DIVISOR - 1) begin
            counter   <= 16'd0;
            baud_tick <= 1'b1;
        end else begin
            counter   <= counter + 1'b1;
            baud_tick <= 1'b0;
        end
    end
endmodule

// -------------------------------------------------------------
// Module 2: UART Transmitter (TX)
// -------------------------------------------------------------
module uart_tx (
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_start,
    input  wire       baud_tick,
    input  wire [7:0] tx_data,
    output reg        tx_line,
    output reg        tx_busy,
    output reg        tx_done
);
    localparam IDLE  = 2'b00,
               START = 2'b01,
               DATA  = 2'b10,
               STOP  = 2'b11;

    reg [1:0] state;
    reg [3:0] tick_count;
    reg [2:0] bit_index;
    reg [7:0] tx_shift_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            tx_line      <= 1'b1;
            tx_busy      <= 1'b0;
            tx_done      <= 1'b0;
            tick_count   <= 0;
            bit_index    <= 0;
            tx_shift_reg <= 0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx_line <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        state        <= START;
                        tx_busy      <= 1'b1;
                        tx_shift_reg <= tx_data;
                        tick_count   <= 0;
                    end
                end

                START: begin
                    tx_line <= 1'b0;
                    if (baud_tick) begin
                        if (tick_count == 15) begin
                            state      <= DATA;
                            tick_count <= 0;
                            bit_index  <= 0;
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end

                DATA: begin
                    tx_line <= tx_shift_reg[bit_index];
                    if (baud_tick) begin
                        if (tick_count == 15) begin
                            tick_count <= 0;
                            if (bit_index == 7) begin
                                state <= STOP;
                            end else begin
                                bit_index <= bit_index + 1;
                            end
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end

                STOP: begin
                    tx_line <= 1'b1;
                    if (baud_tick) begin
                        if (tick_count == 15) begin
                            tx_done <= 1'b1;
                            tx_busy <= 1'b0;
                            state   <= IDLE;
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule

// -------------------------------------------------------------
// Module 3: UART Receiver (RX)
// -------------------------------------------------------------
module uart_rx (
    input  wire       clk,
    input  wire       reset,
    input  wire       rx_line,
    input  wire       baud_tick,
    output reg  [7:0] rx_data,
    output reg        rx_done
);
    localparam IDLE  = 2'b00,
               START = 2'b01,
               DATA  = 2'b10,
               STOP  = 2'b11;

    reg [1:0] state;
    reg [3:0] tick_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            rx_done      <= 1'b0;
            rx_data      <= 8'd0;
            tick_count   <= 0;
            bit_index    <= 0;
            rx_shift_reg <= 0;
        end else begin
            rx_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (~rx_line) begin // Falling edge detects Start Bit
                        state      <= START;
                        tick_count <= 0;
                    end
                end

                START: begin
                    if (baud_tick) begin
                        if (tick_count == 7) begin // Sample at mid-point
                            state      <= DATA;
                            tick_count <= 0;
                            bit_index  <= 0;
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        if (tick_count == 15) begin // Sample center of bit
                            rx_shift_reg[bit_index] <= rx_line;
                            tick_count <= 0;
                            if (bit_index == 7) begin
                                state <= STOP;
                            end else begin
                                bit_index <= bit_index + 1;
                            end
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        if (tick_count == 15) begin
                            rx_data <= rx_shift_reg;
                            rx_done <= 1'b1;
                            state   <= IDLE;
                        end else begin
                            tick_count <= tick_count + 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule

// -------------------------------------------------------------
// Top Module: Loopback Integration
// -------------------------------------------------------------
module uart_top #(
    parameter CLK_FREQ  = 50000000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire [7:0] rx_data,
    output wire       rx_done,
    output wire       tx_busy
);
    wire baud_tick;
    wire loopback_wire; // Connects TX line directly to RX line

    baud_rate_gen #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) baud_gen (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick)
    );

    uart_tx transmitter (
        .clk(clk),
        .reset(reset),
        .tx_start(tx_start),
        .baud_tick(baud_tick),
        .tx_data(tx_data),
        .tx_line(loopback_wire),
        .tx_busy(tx_busy),
        .tx_done()
    );

    uart_rx receiver (
        .clk(clk),
        .reset(reset),
        .rx_line(loopback_wire),
        .baud_tick(baud_tick),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );
endmodule
