// =============================================================================
// uart_rx.v  —  Simple 8N1 UART Receiver
// CLK_FREQ / BAUD_RATE must be set for your target clock.
// Default: 25 MHz clock, 9600 baud  →  divisor = 2604
// =============================================================================
`default_nettype none

module uart_rx #(
    parameter CLK_FREQ  = 25_000_000,
    parameter BAUD_RATE = 9_600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,          // UART RX line (idle HIGH)
    output reg  [7:0] data,        // received byte
    output reg        valid        // pulses HIGH for 1 clk when byte is ready
);

localparam DIVISOR  = CLK_FREQ / BAUD_RATE;          // clocks per bit (32-bit)
localparam HALF_DIV = DIVISOR / 2;                   // half-bit for start sample

// --------------------------------------------------------------------------
// Double-flop synchroniser on RX line
// --------------------------------------------------------------------------
reg rx_d1, rx_d2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) {rx_d1, rx_d2} <= 2'b11;
    else        {rx_d1, rx_d2} <= {rx, rx_d1};
end

// --------------------------------------------------------------------------
// Main FSM
// --------------------------------------------------------------------------
localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] baud_cnt;     // 16-bit counter saves area (DIVISOR 2604 < 65535)
reg [2:0]  bit_idx;      // which data bit we're receiving
reg [7:0]  shift_reg;    // incoming bits shift in here

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= IDLE;
        baud_cnt  <= 0;
        bit_idx   <= 0;
        shift_reg <= 0;
        data      <= 0;
        valid     <= 0;
    end else begin
        valid <= 0; // default: deassert

        case (state)
            // ----------------------------------------------------------------
            IDLE: begin
                if (!rx_d2) begin           // falling edge = start bit detected
                    baud_cnt <= HALF_DIV;   // wait to sample in middle of start bit
                    state    <= START;
                end
            end
            // ----------------------------------------------------------------
            START: begin
                if (baud_cnt == 0) begin
                    if (!rx_d2) begin       // still low → valid start bit
                        baud_cnt <= DIVISOR;
                        bit_idx  <= 0;
                        state    <= DATA;
                    end else begin
                        state <= IDLE;      // glitch, abort
                    end
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
            // ----------------------------------------------------------------
            DATA: begin
                if (baud_cnt == 0) begin
                    shift_reg <= {rx_d2, shift_reg[7:1]};  // LSB first
                    if (bit_idx == 7) begin
                        baud_cnt <= DIVISOR;
                        state    <= STOP;
                    end else begin
                        bit_idx  <= bit_idx + 1;
                        baud_cnt <= DIVISOR;
                    end
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
            // ----------------------------------------------------------------
            STOP: begin
                if (baud_cnt == 0) begin
                    if (rx_d2) begin        // stop bit must be HIGH
                        data  <= shift_reg;
                        valid <= 1;
                    end
                    state <= IDLE;
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
        endcase
    end
end

endmodule
`default_nettype wire
