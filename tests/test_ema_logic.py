"""Tests for EMA overlay alignment, regime direction, and status cache."""

from hab_logic import (
    compute_ema_status,
    ema_overlay_aligned,
    ema_regime_dir,
    ema_regime_pass_for_auto,
)


class TestEMAOverlayAligned:
    def test_full_bull_alignment(self):
        aligned, why = ema_overlay_aligned(1, e20=110, e50=100, e100=90, e200=80)
        assert aligned is True
        assert why == "ema_align_bull"

    def test_full_bear_alignment(self):
        aligned, why = ema_overlay_aligned(-1, e20=80, e50=90, e100=100, e200=110)
        assert aligned is True
        assert why == "ema_align_bear"

    def test_buy_blocked_partial(self):
        # e20 > e50 > e100 but e100 < e200 → blocked
        aligned, why = ema_overlay_aligned(1, e20=110, e50=100, e100=90, e200=95)
        assert aligned is False
        assert "block" in why

    def test_sell_blocked_partial(self):
        aligned, why = ema_overlay_aligned(-1, e20=90, e50=100, e100=110, e200=105)
        assert aligned is False
        assert "block" in why

    def test_direction_zero(self):
        aligned, why = ema_overlay_aligned(0, e20=110, e50=100, e100=90, e200=80)
        assert aligned is False
        assert why == "ema_dir_zero"

    def test_partial_ok_without_full_alignment(self):
        # e20>e50>e100 and e100>e200, but not requiring full alignment
        # With full alignment=False and slow_vs_long=True, still should pass
        aligned, why = ema_overlay_aligned(
            1,
            e20=110,
            e50=100,
            e100=90,
            e200=80,
            require_full_alignment=False,
            require_slow_vs_long=True,
        )
        assert aligned is True

    def test_no_slow_vs_long_requirement(self):
        # e20>e50>e100 but e100 < e200 → pass when slow_vs_long=False
        aligned, why = ema_overlay_aligned(
            1,
            e20=110,
            e50=100,
            e100=90,
            e200=95,
            require_full_alignment=False,
            require_slow_vs_long=False,
        )
        assert aligned is True


class TestEMARegimeDir:
    def test_bull(self):
        d, why = ema_regime_dir(105.0, 100.0)
        assert d == 1
        assert "bull" in why

    def test_bear(self):
        d, why = ema_regime_dir(95.0, 100.0)
        assert d == -1
        assert "bear" in why

    def test_neutral(self):
        d, why = ema_regime_dir(100.0, 100.0)
        assert d == 0
        assert "neutral" in why


class TestEMARegimePassForAuto:
    def test_disabled(self):
        ok, _ = ema_regime_pass_for_auto(1, 100.0, 95.0, use_regime_filter=False)
        assert ok is True

    def test_buy_bull_passes(self):
        ok, why = ema_regime_pass_for_auto(1, 105.0, 100.0)
        assert ok is True
        assert "ok_buy" in why

    def test_sell_bear_passes(self):
        ok, why = ema_regime_pass_for_auto(-1, 95.0, 100.0)
        assert ok is True
        assert "ok_sell" in why

    def test_buy_in_bear_blocked(self):
        ok, why = ema_regime_pass_for_auto(1, 95.0, 100.0)
        assert ok is False
        assert "mismatch" in why

    def test_neutral_blocked(self):
        ok, why = ema_regime_pass_for_auto(1, 100.0, 100.0, allow_neutral=False)
        assert ok is False
        assert "neutral_block" in why

    def test_neutral_allowed(self):
        ok, why = ema_regime_pass_for_auto(1, 100.0, 100.0, allow_neutral=True)
        assert ok is True
        assert "neutral_allowed" in why


class TestComputeEMAStatus:
    def test_full_bull(self):
        b, s = compute_ema_status(e20=110, e50=100, e100=90, e200=80)
        assert b == 2  # GREEN
        assert s == 0  # RED

    def test_full_bear(self):
        b, s = compute_ema_status(e20=80, e50=90, e100=100, e200=110)
        assert b == 0  # RED
        assert s == 2  # GREEN

    def test_partial_bull(self):
        # e50>e100>e200 but e20 NOT > e50
        b, s = compute_ema_status(e20=95, e50=100, e100=90, e200=80)
        assert b == 1  # YELLOW
        assert s == 0  # RED

    def test_partial_bear(self):
        # e50<e100<e200 but e20 NOT < e50
        b, s = compute_ema_status(e20=105, e50=100, e100=110, e200=120)
        assert b == 0
        assert s == 1  # YELLOW

    def test_no_alignment(self):
        b, s = compute_ema_status(e20=100, e50=100, e100=100, e200=100)
        assert b == 0
        assert s == 0
