// fir_filter.v -- 4-Tap FIR Filter (Time-Multiplexed Single Multiplier)
//
// Uses ONE shared 8x8 multiplier over 4 MAC cycles.
// Coefficient format: 8-bit signed Q7 (0x40 = +0.5, 0x7F ~ +1.0)
// Sample/output: 8-bit signed Q0 (-128..+127), saturated
//
// Timeline (N = cycle sample_valid is asserted):
//   N   : latch sample, reset accumulator, tap=0
//   N+1 : acc += c0 * x[n]
//   N+2 : acc += c1 * x[n-1]
//   N+3 : acc += c2 * x[n-2]
//   N+4 : acc += c3 * x[n-3], right-shift >>7, saturate, out_valid pulses
//   N+5 : delay line shifts, ready for next sample

`default_nettype none

module fir_filter (
    input  wire        clk,
    input  wire        rst_n,

    input  wire signed [7:0] coeff0,
    input  wire signed [7:0] coeff1,
    input  wire signed [7:0] coeff2,
    input  wire signed [7:0] coeff3,

    input  wire        sample_valid,
    input  wire signed [7:0] sample_in,

    output reg         out_valid,
    output reg  signed [7:0] filtered_out
);

// Delay line (shifted AFTER computation)
reg signed [7:0] d1, d2, d3;
reg signed [7:0] cur_sample;

// Tap FSM
reg [1:0]        tap;
reg              active;
reg signed [17:0] acc;   // 18-bit: holds 4 x (127 x 127) = 64516 < 2^17

// Coefficient/data mux (combinational)
reg signed [7:0] mux_coeff;
reg signed [7:0] mux_data;

always @(*) begin
    case (tap)
        2'd0: begin mux_coeff = coeff0; mux_data = cur_sample; end
        2'd1: begin mux_coeff = coeff1; mux_data = d1;         end
        2'd2: begin mux_coeff = coeff2; mux_data = d2;         end
        default: begin mux_coeff = coeff3; mux_data = d3;      end
    endcase
end

// Single shared multiplier
wire signed [15:0] product = mux_coeff * mux_data;
// Sign-extend to 18 bits
wire signed [17:0] product_ext = {{2{product[15]}}, product};

// Saturation after Q7 right-shift
// final_val = (acc + product_ext) >>> 7
// Clamp to [-128, +127]
wire signed [17:0] raw_sum = acc + product_ext;
wire signed [17:0] shifted = $signed(raw_sum) >>> 7;
wire signed [7:0]  clamped = (shifted > 18'sd127)  ? 8'h7F :
                              (shifted < -18'sd128) ? 8'h80 :
                                                      shifted[7:0];

// Main FSM
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        d1           <= 8'h0;
        d2           <= 8'h0;
        d3           <= 8'h0;
        cur_sample   <= 8'h0;
        acc          <= 18'h0;
        tap          <= 2'd0;
        active       <= 1'b0;
        out_valid    <= 1'b0;
        filtered_out <= 8'h0;
    end else begin
        out_valid <= 1'b0;

        if (!active) begin
            if (sample_valid) begin
                cur_sample <= sample_in;
                acc        <= 18'h0;
                tap        <= 2'd0;
                active     <= 1'b1;
            end
        end else begin
            acc <= acc + product_ext;

            if (tap == 2'd3) begin
                // Final tap: compute output, shift delay line, return to idle
                filtered_out <= clamped;
                out_valid    <= 1'b1;
                active       <= 1'b0;
                tap          <= 2'd0;
                // Shift delay line AFTER all taps computed
                d1 <= cur_sample;
                d2 <= d1;
                d3 <= d2;
            end else begin
                tap <= tap + 2'd1;
            end
        end
    end
end

endmodule
`default_nettype wire
