// =============================================================================
// tb_fir_filter.v  —  Testbench for the complete FIR Filter TT design
//
// Tests performed:
//   1. Default coefficient verification (box filter: all 0.5)
//   2. UART coefficient loading (load a low-pass [0.25 0.25 0.25 0.25])
//   3. Impulse response check
//   4. Step response + saturation check
//   5. High-pass coefficient test
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_fir_filter;

// --------------------------------------------------------------------------
// DUT port connections
// --------------------------------------------------------------------------
reg  [7:0] ui_in;
wire [7:0] uo_out;
reg  [7:0] uio_in;
wire [7:0] uio_out;
wire [7:0] uio_oe;
reg        ena, clk, rst_n;

tt_um_fir_filter dut (
    .ui_in   (ui_in),
    .uo_out  (uo_out),
    .uio_in  (uio_in),
    .uio_out (uio_out),
    .uio_oe  (uio_oe),
    .ena     (ena),
    .clk     (clk),
    .rst_n   (rst_n)
);

// --------------------------------------------------------------------------
// Clock: 25 MHz  →  period = 40 ns
// --------------------------------------------------------------------------
localparam CLK_PERIOD = 40;              // ns
localparam BAUD_PERIOD = 104_167;        // ns  (9600 baud)

always #(CLK_PERIOD/2) clk = ~clk;

// --------------------------------------------------------------------------
// UART TX task  —  sends one byte at 9600 baud on uio_in[0]
// --------------------------------------------------------------------------
task uart_send_byte;
    input [7:0] b;
    integer i;
    begin
        // Start bit
        uio_in[0] = 0;
        #(BAUD_PERIOD);
        // 8 data bits (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            uio_in[0] = b[i];
            #(BAUD_PERIOD);
        end
        // Stop bit
        uio_in[0] = 1;
        #(BAUD_PERIOD);
    end
endtask

// --------------------------------------------------------------------------
// Send a complete 5-byte coefficient packet
// coefficients are in Q7 signed format
// --------------------------------------------------------------------------
task send_coefficients;
    input signed [7:0] c0, c1, c2, c3;
    begin
        uart_send_byte(8'hA5);     // magic header
        uart_send_byte(c0);
        uart_send_byte(c1);
        uart_send_byte(c2);
        uart_send_byte(c3);
        // Wait for FSM to latch
        #(CLK_PERIOD * 10);
    end
endtask

// --------------------------------------------------------------------------
// Push one sample through the filter and wait for result
// --------------------------------------------------------------------------
task push_sample;
    input signed [7:0] sample;
    begin
        ui_in       = sample;
        uio_in[2]   = 1'b1;    // assert sample_valid
        @(posedge clk);
        #1;
        uio_in[2]   = 1'b0;    // deassert
        // Wait 3 clocks for 2-stage pipeline + margin
        repeat(3) @(posedge clk);
    end
endtask

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------
integer pass_count = 0;
integer fail_count = 0;

task check;
    input [7:0]  actual;
    input [7:0]  expected;
    input [127:0] test_name;
    begin
        if (actual === expected) begin
            $display("PASS [%s]  got=%0d (0x%02H)", test_name, $signed(actual), actual);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%s]  got=%0d (0x%02H)  expected=%0d (0x%02H)",
                     test_name, $signed(actual), actual, $signed(expected), expected);
            fail_count = fail_count + 1;
        end
    end
endtask

// --------------------------------------------------------------------------
// Test stimulus
// --------------------------------------------------------------------------
initial begin
    $dumpfile("tb_fir_filter.vcd");
    $dumpvars(0, tb_fir_filter);

    // Initialise
    clk     = 0;
    rst_n   = 0;
    ena     = 1;
    ui_in   = 8'h00;
    uio_in  = 8'hFF;   // UART RX idle (HIGH), others 0
    uio_in[0] = 1'b1;  // UART RX idle

    // Assert reset for 10 cycles
    repeat(10) @(posedge clk);
    rst_n = 1;
    #100;

    $display("\n===== TEST 1: Default Box Filter (all coeff=0x40=0.5 Q7) =====");
    // Default coefficients (set in coeff_ctrl reset)
    // Input 64 → expected output approx: (0.5*64 + 0.5*0 + 0.5*0 + 0.5*0)>>0 = 32
    // Actually: (0x40*64 + ...) >> 7 = (64*64)/128 = 32
    push_sample(8'sd64);
    check(uo_out, 8'sd32, "box_filt_step1");

    push_sample(8'sd64);
    check(uo_out, 8'sd64, "box_filt_step2");  // 2 taps filled: (0.5*64 + 0.5*64 + 0.5*0 + 0.5*0) = 64

    push_sample(8'sd64);
    check(uo_out, 8'sd96, "box_filt_step3");  // 3 taps filled: (0.5*64 + 0.5*64 + 0.5*64 + 0.5*0) = 96

    $display("\n===== TEST 2: Load Low-Pass [0.25 0.25 0.25 0.25] via UART =====");
    // 0.25 in Q7 = 0x20 = 32
    send_coefficients(8'sh20, 8'sh20, 8'sh20, 8'sh20);
    // flush delay line
    push_sample(8'sd0);
    push_sample(8'sd0);
    push_sample(8'sd0);
    push_sample(8'sd0);

    // Impulse: send 100, then zeros
    push_sample(8'sd100);
    check(uo_out, 8'sd25, "lp_impulse_n0");   // 0.25*100 = 25

    push_sample(8'sd0);
    check(uo_out, 8'sd25, "lp_impulse_n1");

    push_sample(8'sd0);
    check(uo_out, 8'sd25, "lp_impulse_n2");

    push_sample(8'sd0);
    check(uo_out, 8'sd25, "lp_impulse_n3");

    push_sample(8'sd0);
    check(uo_out, 8'sd0,  "lp_impulse_n4");   // impulse response done

    $display("\n===== TEST 3: High-Pass [0.5 -0.5 0 0] via UART =====");
    // c0=+64 (0.5), c1=-64 (-0.5), c2=0, c3=0
    send_coefficients(8'sh40, 8'shC0, 8'sh00, 8'sh00);
    push_sample(8'sd0);
    push_sample(8'sd0);
    push_sample(8'sd0);
    push_sample(8'sd0);

    push_sample(8'sd64);
    check(uo_out, 8'sd32, "hp_step_n0");   // 0.5*64 - 0.5*0 = 32

    push_sample(8'sd64);
    check(uo_out, 8'sd0,  "hp_step_n1");   // 0.5*64 - 0.5*64 = 0

    push_sample(8'sd64);
    check(uo_out, 8'sd0,  "hp_step_n2");

    $display("\n===== TEST 4: Saturation Check =====");
    // All coefficients = 0x7F ≈ 1, input = 127 → raw ≈ 4*127*127>>7 = 507 → saturate to 127
    send_coefficients(8'sh7F, 8'sh7F, 8'sh7F, 8'sh7F);
    push_sample(8'sd0); push_sample(8'sd0);
    push_sample(8'sd0); push_sample(8'sd0);
    push_sample(8'sd127);
    push_sample(8'sd127);
    push_sample(8'sd127);
    push_sample(8'sd127);
    check(uo_out, 8'sd127, "saturation_pos");

    // Negative saturation: input = -128
    push_sample(8'sd0); push_sample(8'sd0);
    push_sample(8'sd0); push_sample(8'sd0);
    push_sample(-8'sd128);
    push_sample(-8'sd128);
    push_sample(-8'sd128);
    push_sample(-8'sd128);
    check(uo_out, -8'sd128, "saturation_neg");

    // ------------ Summary ------------
    #100;
    $display("\n==============================");
    $display("  PASSED: %0d / %0d", pass_count, pass_count+fail_count);
    $display("  FAILED: %0d / %0d", fail_count, pass_count+fail_count);
    $display("==============================\n");

    if (fail_count == 0)
        $display("ALL TESTS PASSED ✓");
    else
        $display("SOME TESTS FAILED ✗");

    $finish;
end

endmodule
`default_nettype wire
