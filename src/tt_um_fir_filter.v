// =============================================================================
// tt_um_fir_filter.v  —  TinyTapeout Top-Level Wrapper
//
// Pin Map:
//   ui_in[7:0]   — 8-bit signed input sample (parallel, applied with strobe)
//   uo_out[7:0]  — 8-bit signed filtered output
//
//   uio[0]  IN   — UART RX (9600 8N1) — coefficient programming
//   uio[1]  OUT  — UART TX (future echo / status, tied to 1 for now)
//   uio[2]  IN   — sample_valid  : rising edge → process sample on ui_in
//   uio[3]  OUT  — out_valid     : pulses HIGH when uo_out holds new result
//   uio[4]  OUT  — coeff_we      : pulses HIGH when coefficients updated
//   uio[7:5] OUT — tied LOW (reserved)
//
// Clock: 25 MHz (TinyTapeout default configurable clock)
// UART:  9600 baud  (divisor = 2604)
// =============================================================================
`default_nettype none

module tt_um_fir_filter (
    input  wire [7:0] ui_in,    // 8-bit input sample
    output wire [7:0] uo_out,   // 8-bit filtered output
    input  wire [7:0] uio_in,   // bidir IOs — input path
    output wire [7:0] uio_out,  // bidir IOs — output path
    output wire [7:0] uio_oe,   // bidir IOs — output enable (1 = output)
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

// --------------------------------------------------------------------------
// Bidir direction control
// uio[0] = UART RX    → INPUT
// uio[1] = UART TX    → OUTPUT
// uio[2] = sample_valid → INPUT
// uio[3] = out_valid  → OUTPUT
// uio[4] = coeff_we   → OUTPUT
// uio[7:5]            → OUTPUT (tied 0)
// --------------------------------------------------------------------------
assign uio_oe  = 8'b1111_1010;   // 0=in: bits 0,2; 1=out: bits 1,3,4,5,6,7

// --------------------------------------------------------------------------
// Internal signals
// --------------------------------------------------------------------------
wire        uart_rx_line  = uio_in[0];
wire        sample_valid  = uio_in[2];
wire signed [7:0] sample_in_s = $signed(ui_in); // explicit signed wire for fir port

wire [7:0]  uart_data;
wire        uart_valid;

wire signed [7:0] coeff0, coeff1, coeff2, coeff3;
wire        coeff_we;

wire        out_valid;
wire [7:0]  filtered_out;         // matches fir_filter output reg [7:0] (unsigned bits)

// --------------------------------------------------------------------------
// UART Receiver
// --------------------------------------------------------------------------
uart_rx #(
    .CLK_FREQ  (25_000_000),
    .BAUD_RATE (9_600)
) u_uart_rx (
    .clk   (clk),
    .rst_n (rst_n),
    .rx    (uart_rx_line),
    .data  (uart_data),
    .valid (uart_valid)
);

// --------------------------------------------------------------------------
// Coefficient Controller
// --------------------------------------------------------------------------
coeff_ctrl u_coeff_ctrl (
    .clk      (clk),
    .rst_n    (rst_n),
    .rx_data  (uart_data),
    .rx_valid (uart_valid),
    .coeff0   (coeff0),
    .coeff1   (coeff1),
    .coeff2   (coeff2),
    .coeff3   (coeff3),
    .coeff_we (coeff_we)
);

// --------------------------------------------------------------------------
// FIR Filter Core
// --------------------------------------------------------------------------
fir_filter u_fir (
    .clk          (clk),
    .rst_n        (rst_n),
    .coeff0       (coeff0),
    .coeff1       (coeff1),
    .coeff2       (coeff2),
    .coeff3       (coeff3),
    .sample_valid (sample_valid),
    .sample_in    (sample_in_s),
    .out_valid    (out_valid),
    .filtered_out (filtered_out)
);

// --------------------------------------------------------------------------
// Output assignments
// --------------------------------------------------------------------------
assign uo_out  = filtered_out;

assign uio_out = {3'b000, coeff_we, out_valid, 1'b1, 1'b0, 1'b0};
//                [7:5]=0  [4]=coeff_we [3]=out_valid [2]=1(TX idle) [1]=0 [0]=0

// Prevent unused input warnings (ena always 1 in TT; uio_in[7:3,1] not used)
wire _unused = &{ena, uio_in[7:3], uio_in[1]};

endmodule
`default_nettype wire
