`default_nettype none
`timescale 1ns/1ps

module tb ();

  // DUT pin connections
  reg        clk;
  reg        rst_n;
  reg        ena;
  reg  [7:0] ui_in;
  reg  [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef USE_POWER_PINS
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // DUT instantiation
  tt_um_fir_filter dut (
`ifdef USE_POWER_PINS
    .VPWR   (VPWR),
    .VGND   (VGND),
`endif
    .ui_in  (ui_in),
    .uo_out (uo_out),
    .uio_in (uio_in),
    .uio_out(uio_out),
    .uio_oe (uio_oe),
    .ena    (ena),
    .clk    (clk),
    .rst_n  (rst_n)
  );

  // Dump waveform
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // 25 MHz clock
  initial clk = 0;
  always #20 clk = ~clk;   // 20 ns half-period → 25 MHz

endmodule
`default_nettype wire
