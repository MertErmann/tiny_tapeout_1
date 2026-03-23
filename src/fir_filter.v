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

// Delay line
reg signed [7:0] d1, d2, d3;

// Multipliers (4 parallel MACs)
wire signed [15:0] p0 = $signed(coeff0) * $signed(sample_in);
wire signed [15:0] p1 = $signed(coeff1) * $signed(d1);
wire signed [15:0] p2 = $signed(coeff2) * $signed(d2);
wire signed [15:0] p3 = $signed(coeff3) * $signed(d3);

// Accumulator (Sign extended 16->18 bits using $signed)
wire signed [17:0] sum = $signed(p0) + $signed(p1) + $signed(p2) + $signed(p3);

// Q7 Shift
wire signed [17:0] shifted = sum >>> 7;

// Saturation to 8-bit unsigned port (with signed logic)
wire [7:0] sat_out = (shifted >  18'sd127) ? 8'h7F :
                     (shifted < -18'sd128) ? 8'h80 :
                                             shifted[7:0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        d1           <= 8'h0;
        d2           <= 8'h0;
        d3           <= 8'h0;
        out_valid    <= 1'b0;
        filtered_out <= 8'h0;
    end else begin
        out_valid <= sample_valid;

        if (sample_valid) begin
            // Shift delay line
            d1 <= sample_in;
            d2 <= d1;
            d3 <= d2;

            // Output result (combinational -> reg)
            filtered_out <= sat_out;
        end
    end
end

endmodule
`default_nettype wire
