// fir_filter.v -- 4-Tap FIR Filter (Time-Multiplexed Single Multiplier)
//
// One 8x8 signed multiplier shared across 4 MAC cycles.
// Coefficients: 8-bit signed Q7 (0x40 = +0.5)
// Input/output: 8-bit signed Q0 (-128..+127) with saturation.
//
// Latency: 4 clock cycles after sample_valid.
// Delay line shifts AFTER all taps computed (preserves correct x[n-k] values).

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
    output reg  [7:0]  filtered_out
);

// Delay line (shifted after computation, NOT at sample capture)
reg signed [7:0] d1, d2, d3;
reg signed [7:0] cur_sample;

// MAC state
reg [1:0]         tap;
reg               active;
reg signed [17:0] acc;

// Coefficient / data mux (combinational)
reg signed [7:0] mux_c;
reg signed [7:0] mux_d;

always @(*) begin
    case (tap)
        2'd0: begin mux_c = coeff0; mux_d = cur_sample; end
        2'd1: begin mux_c = coeff1; mux_d = d1;         end
        2'd2: begin mux_c = coeff2; mux_d = d2;         end
        default: begin mux_c = coeff3; mux_d = d3;      end
    endcase
end

// Single 8x8 signed multiplier
wire signed [15:0] product = $signed(mux_c) * $signed(mux_d);

// Sign-extend 16->18 bits using $signed (NOT concat -- concat is always unsigned
// and would cause Yosys assertion: arg->is_signed != sig.is_signed)
wire signed [17:0] product_ext = $signed(product);

// Final-tap combinational result (used when tap==3)
wire signed [17:0] final_sum   = $signed(acc) + $signed(product_ext);
wire signed [17:0] final_shift = $signed(final_sum) >>> 7;

// Saturate to [-128, +127] -- output is plain [7:0] bits (signed interpretation at top)
wire [7:0] sat_out = ($signed(final_shift) >  18'sd127) ? 8'h7F :
                     ($signed(final_shift) < -18'sd128) ? 8'h80 :
                                                          final_shift[7:0];

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
            acc <= $signed(acc) + $signed(product_ext);

            if (tap == 2'd3) begin
                filtered_out <= sat_out;
                out_valid    <= 1'b1;
                active       <= 1'b0;
                tap          <= 2'd0;
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
