"""Tests for SL/TP computation: sequence-based SL, structural TP edge-based."""

import pytest
from hab_logic import (
    compute_auto_anchor_sl,
    compute_sl,
    compute_structural_tp_edge_based,
)

POINT = 0.01
DIGITS = 2


class TestComputeSL:
    """Sequence-based SL per v1.379 rules:
    Trade 1 (next=1): 300 pips → 300*10*0.01 = 30.0
    Trade 2 (next=2): 200 pips → 200*10*0.01 = 20.0
    Trade 3+ (next=3): 100 pips → 100*10*0.01 = 10.0
    """

    def test_trade1_buy(self):
        sl = compute_sl(direction=1, entry=2000.0, total_active_trades=0, point=POINT, digits=DIGITS)
        assert sl == pytest.approx(1970.0, abs=0.01)

    def test_trade1_sell(self):
        sl = compute_sl(direction=-1, entry=2000.0, total_active_trades=0, point=POINT, digits=DIGITS)
        assert sl == pytest.approx(2030.0, abs=0.01)

    def test_trade2_buy(self):
        sl = compute_sl(direction=1, entry=2000.0, total_active_trades=1, point=POINT, digits=DIGITS)
        assert sl == pytest.approx(1980.0, abs=0.01)

    def test_trade3_buy(self):
        sl = compute_sl(direction=1, entry=2000.0, total_active_trades=2, point=POINT, digits=DIGITS)
        assert sl == pytest.approx(1990.0, abs=0.01)

    def test_trade4_buy(self):
        sl = compute_sl(direction=1, entry=2000.0, total_active_trades=3, point=POINT, digits=DIGITS)
        assert sl == pytest.approx(1990.0, abs=0.01)

    def test_protected_nosl_atr(self):
        sl = compute_sl(
            direction=1,
            entry=2000.0,
            total_active_trades=0,
            point=POINT,
            digits=DIGITS,
            protected_nosl=True,
            catastrophic_sl_atr_mult=6.0,
            atr_value=10.0,  # 10 * 6 = 60
        )
        assert sl == pytest.approx(1940.0, abs=0.01)

    def test_protected_nosl_fixed_points(self):
        sl = compute_sl(
            direction=-1,
            entry=2000.0,
            total_active_trades=0,
            point=POINT,
            digits=DIGITS,
            protected_nosl=True,
            catastrophic_sl_points=5000,
            catastrophic_sl_atr_mult=0.0,
        )
        # 5000 * 0.01 = 50
        assert sl == pytest.approx(2050.0, abs=0.01)

    def test_protected_nosl_atr_wins(self):
        # ATR*mult > fixed points → use ATR
        sl = compute_sl(
            direction=1,
            entry=2000.0,
            total_active_trades=0,
            point=POINT,
            digits=DIGITS,
            protected_nosl=True,
            catastrophic_sl_points=1000,  # 10.0
            catastrophic_sl_atr_mult=6.0,
            atr_value=10.0,  # 60.0
        )
        assert sl == pytest.approx(1940.0, abs=0.01)


class TestComputeStructuralTP:
    def test_buy_nearest_level(self):
        levels = {
            "R1": (2010.0, 2012.0),
            "R2": (2025.0, 2027.0),
        }
        result = compute_structural_tp_edge_based(
            direction=1,
            entry=2000.0,
            levels=levels,
            tp_level_buffer_points=25,
            tp_min_profit_points=50,
            point=POINT,
            digits=DIGITS,
        )
        assert result is not None
        tp, edge, tag = result
        assert tag == "R1"
        assert edge == pytest.approx(2010.0)
        # tp = 2010.0 - 25*0.01 = 2009.75
        assert tp == pytest.approx(2009.75, abs=0.01)

    def test_sell_nearest_level(self):
        levels = {
            "S1": (1988.0, 1990.0),
            "S2": (1975.0, 1977.0),
        }
        result = compute_structural_tp_edge_based(
            direction=-1,
            entry=2000.0,
            levels=levels,
            tp_level_buffer_points=25,
            tp_min_profit_points=50,
            point=POINT,
            digits=DIGITS,
        )
        assert result is not None
        tp, edge, tag = result
        assert tag == "S1"
        assert edge == pytest.approx(1990.0)
        # tp = 1990.0 + 25*0.01 = 1990.25
        assert tp == pytest.approx(1990.25, abs=0.01)

    def test_no_level_ahead(self):
        levels = {"S1": (1990.0, 1992.0)}  # below entry for buy
        result = compute_structural_tp_edge_based(
            direction=1,
            entry=2000.0,
            levels=levels,
            point=POINT,
            digits=DIGITS,
        )
        assert result is None

    def test_level_too_close(self):
        # Level exists but TP < entry + min_profit
        levels = {"R1": (2000.3, 2000.5)}
        result = compute_structural_tp_edge_based(
            direction=1,
            entry=2000.0,
            levels=levels,
            tp_level_buffer_points=25,
            tp_min_profit_points=50,
            point=POINT,
            digits=DIGITS,
        )
        assert result is None

    def test_invalid_direction(self):
        levels = {"R1": (2010.0, 2012.0)}
        result = compute_structural_tp_edge_based(
            direction=0,
            entry=2000.0,
            levels=levels,
            point=POINT,
            digits=DIGITS,
        )
        assert result is None


class TestComputeAutoAnchorSL:
    def test_buy_300_pips_gold(self):
        sl = compute_auto_anchor_sl(direction=1, entry=2000.0, sl_pips=300, digits=2, point=0.01)
        # 300 pips * 1 (2-digit) * 0.01 = 3.0
        assert sl == pytest.approx(1997.0, abs=0.01)

    def test_sell_300_pips_gold(self):
        sl = compute_auto_anchor_sl(direction=-1, entry=2000.0, sl_pips=300, digits=2, point=0.01)
        assert sl == pytest.approx(2003.0, abs=0.01)

    def test_fx_5digit_50_pips(self):
        sl = compute_auto_anchor_sl(direction=1, entry=1.10000, sl_pips=50, digits=5, point=0.00001)
        # 50 pips * 10 * 0.00001 = 0.00500
        assert sl == pytest.approx(1.09500, abs=0.00001)

    def test_zero_pips(self):
        assert compute_auto_anchor_sl(direction=1, entry=2000.0, sl_pips=0, digits=2, point=0.01) is None

    def test_negative_pips(self):
        assert compute_auto_anchor_sl(direction=1, entry=2000.0, sl_pips=-10, digits=2, point=0.01) is None
