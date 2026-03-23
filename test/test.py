# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# ── Helpers ──────────────────────────────────────────────────────────────────

def signed8(val: int) -> int:
    return val if val < 128 else val - 256

async def push_sample(dut, sample: int) -> int:
    """Drive ui_in + strobe sample_valid; return signed filtered output.
    The time-multiplexed FIR takes 4 MAC cycles + pipeline → wait 6 clocks."""
    dut.ui_in.value  = sample & 0xFF
    dut.uio_in.value = 0x05   # bit0=1 (UART RX idle HIGH), bit2=1 (sample_valid)
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = 0x01   # deassert sample_valid, keep UART idle
    await ClockCycles(dut.clk, 6)
    return signed8(int(dut.uo_out.value))


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 25 MHz clock  →  40 ns period
    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0x01   # UART RX idle HIGH (bit0), everything else 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 5)

    # ── Box filter (default coefficients: all 0x40 = +0.5 Q7) ───────────────
    # y[n] = (0.5*x[n] + 0.5*x[n-1] + 0.5*x[n-2] + 0.5*x[n-3]) (saturated)
    dut._log.info("Test: default box filter")

    out = await push_sample(dut, 64)
    assert out == 32, f"step1: expected 32, got {out}"
    dut._log.info(f"  step1 PASS: got {out}")

    out = await push_sample(dut, 64)
    assert out == 64, f"step2: expected 64, got {out}"
    dut._log.info(f"  step2 PASS: got {out}")

    out = await push_sample(dut, 64)
    assert out == 96, f"step3: expected 96, got {out}"
    dut._log.info(f"  step3 PASS: got {out}")

    # ── Zero input → zero output ─────────────────────────────────────────────
    dut._log.info("Test: zero input")
    for _ in range(4):
        await push_sample(dut, 0)
    out = await push_sample(dut, 0)
    assert out == 0, f"zero: expected 0, got {out}"
    dut._log.info("  zero PASS")

    # ── Negative input ───────────────────────────────────────────────────────
    dut._log.info("Test: negative input (-64)")
    out = await push_sample(dut, -64 & 0xFF)
    assert out == -32, f"neg step1: expected -32, got {out}"
    dut._log.info(f"  neg step1 PASS: got {out}")

    dut._log.info("All tests passed!")
