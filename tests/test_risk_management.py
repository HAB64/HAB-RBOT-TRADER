"""Tests for risk management: lot sizing, risk %, pip conversion, value-per-point."""

import pytest
from hab_logic import (
    calc_lot_for_risk,
    calc_risk_pct_for_lot,
    normalize_lot,
    pips_to_points_safe,
    value_per_point_per_lot,
)

# ── XAUUSD-like constants ──
TICK_VALUE = 1.0  # USD per tick for 1 lot
TICK_SIZE = 0.01  # tick size
POINT = 0.01  # _Point for 2-digit gold


class TestNormalizeLot:
    def test_exact_step(self):
        assert normalize_lot(0.05) == 0.05

    def test_below_min(self):
        assert normalize_lot(0.001) == 0.01

    def test_above_max(self):
        assert normalize_lot(200.0, max_lot=100.0) == 100.0

    def test_rounds_to_step(self):
        assert normalize_lot(0.037, step=0.01) == 0.04

    def test_custom_step(self):
        assert normalize_lot(0.123, step=0.05) == 0.10

    def test_zero_step_defaults(self):
        assert normalize_lot(0.05, step=0.0) == 0.05

    def test_negative_lot(self):
        assert normalize_lot(-5.0) == 0.01

    def test_micro_lot_step(self):
        assert normalize_lot(0.015, step=0.001) == 0.015


class TestPipsToPointsSafe:
    def test_gold_2digit(self):
        assert pips_to_points_safe(300, 2) == 300

    def test_fx_5digit(self):
        assert pips_to_points_safe(50, 5) == 500

    def test_fx_3digit(self):
        assert pips_to_points_safe(50, 3) == 500

    def test_fx_4digit(self):
        assert pips_to_points_safe(50, 4) == 50

    def test_zero_pips(self):
        assert pips_to_points_safe(0, 5) == 0

    def test_negative_pips(self):
        assert pips_to_points_safe(-10, 5) == 0

    def test_insane_large(self):
        # pips * 10 > 2_000_000 → 0
        assert pips_to_points_safe(300_000, 5) == 0


class TestValuePerPointPerLot:
    def test_gold_standard(self):
        v = value_per_point_per_lot(1.0, 0.01, 0.01)
        assert v == pytest.approx(1.0)

    def test_zero_tick_value(self):
        assert value_per_point_per_lot(0.0, 0.01, 0.01) == 0.0

    def test_zero_tick_size(self):
        assert value_per_point_per_lot(1.0, 0.0, 0.01) == 0.0

    def test_zero_point(self):
        assert value_per_point_per_lot(1.0, 0.01, 0.0) == 0.0

    def test_fx_eurusd(self):
        # typical EURUSD 5-digit: tick_value=10, tick_size=0.00001, point=0.00001
        v = value_per_point_per_lot(10.0, 0.00001, 0.00001)
        assert v == pytest.approx(10.0)


class TestCalcLotForRisk:
    def test_basic(self):
        # 1% risk, 300pt SL, $10k equity, XAUUSD-like
        lot = calc_lot_for_risk(1.0, 300, 10_000.0, TICK_VALUE, TICK_SIZE, POINT)
        expected = 10_000.0 * 0.01 / (300 * 1.0)
        assert lot == pytest.approx(normalize_lot(expected), rel=1e-6)

    def test_zero_risk(self):
        assert calc_lot_for_risk(0.0, 300, 10_000.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_zero_sl(self):
        assert calc_lot_for_risk(1.0, 0, 10_000.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_zero_equity(self):
        assert calc_lot_for_risk(1.0, 300, 0.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_clamps_to_min(self):
        # tiny risk → lot below minLot → clamp
        lot = calc_lot_for_risk(0.001, 3000, 100.0, TICK_VALUE, TICK_SIZE, POINT)
        assert lot >= 0.01


class TestCalcRiskPctForLot:
    def test_roundtrip(self):
        lot = 0.10
        sl = 300
        eq = 10_000.0
        pct = calc_risk_pct_for_lot(lot, sl, eq, TICK_VALUE, TICK_SIZE, POINT)
        assert pct == pytest.approx(100.0 * (lot * sl * 1.0) / eq)

    def test_zero_lot(self):
        assert calc_risk_pct_for_lot(0.0, 300, 10_000.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_zero_sl(self):
        assert calc_risk_pct_for_lot(0.10, 0, 10_000.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_zero_equity(self):
        assert calc_risk_pct_for_lot(0.10, 300, 0.0, TICK_VALUE, TICK_SIZE, POINT) == 0.0

    def test_large_lot(self):
        pct = calc_risk_pct_for_lot(1.0, 300, 10_000.0, TICK_VALUE, TICK_SIZE, POINT)
        assert pct == pytest.approx(3.0)
