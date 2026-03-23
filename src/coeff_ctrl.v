// =============================================================================
// coeff_ctrl.v  —  UART Coefficient Loader FSM
//
// UART Protocol (9600 8N1):
//   Send exactly 5 bytes in order:
//       Byte 0 : 0xA5          (magic header, identifies a config packet)
//       Byte 1 : coeff0        (signed 8-bit, Q7 format)
//       Byte 2 : coeff1
//       Byte 3 : coeff2
//       Byte 4 : coeff3
//
// On receiving a valid 5-byte frame, coeff_we is pulsed and coeff[0:3]
// are updated atomically.
//
// Any byte that is not 0xA5 in the HEADER state resets the FSM, so you
// can send multiple frames back-to-back safely.
// =============================================================================
`default_nettype none

module coeff_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // From UART RX
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // Coefficient outputs (registered, stable between writes)
    output reg  signed [7:0] coeff0,
    output reg  signed [7:0] coeff1,
    output reg  signed [7:0] coeff2,
    output reg  signed [7:0] coeff3,

    // Write-enable strobe (1 clk pulse when new coefficients are loaded)
    output reg         coeff_we
);

localparam MAGIC = 8'hA5;

// FSM states
localparam S_HEADER = 3'd0;
localparam S_C0     = 3'd1;
localparam S_C1     = 3'd2;
localparam S_C2     = 3'd3;
localparam S_C3     = 3'd4;

reg [2:0] state;
// Staging registers — hold partial packet until fully received
reg signed [7:0] c0_buf, c1_buf, c2_buf;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state    <= S_HEADER;
        coeff_we <= 1'b0;
        coeff0   <= 8'sh40;  // default: low-pass box, all 0.5
        coeff1   <= 8'sh40;
        coeff2   <= 8'sh40;
        coeff3   <= 8'sh40;
        c0_buf   <= 8'h0;
        c1_buf   <= 8'h0;
        c2_buf   <= 8'h0;
    end else begin
        coeff_we <= 1'b0;   // default deassert

        if (rx_valid) begin
            case (state)
                S_HEADER: begin
                    if (rx_data == MAGIC)
                        state <= S_C0;
                    // else: ignore, wait for magic
                end

                S_C0: begin
                    c0_buf <= rx_data;
                    state  <= S_C1;
                end

                S_C1: begin
                    c1_buf <= rx_data;
                    state  <= S_C2;
                end

                S_C2: begin
                    c2_buf <= rx_data;
                    state  <= S_C3;
                end

                S_C3: begin
                    // Full packet received — commit atomically
                    coeff0   <= c0_buf;
                    coeff1   <= c1_buf;
                    coeff2   <= c2_buf;
                    coeff3   <= rx_data;
                    coeff_we <= 1'b1;
                    state    <= S_HEADER;
                end

                default: state <= S_HEADER;
            endcase
        end
    end
end

endmodule
`default_nettype wire
