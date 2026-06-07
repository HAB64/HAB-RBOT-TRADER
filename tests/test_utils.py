"""Tests for utility functions: anchor detection, order types, ladder, managed symbol, level distance, sequence lot."""

from hab_logic import (
    LADDER_AGGRESSIVE,
    LADDER_BALANCED,
    LADDER_CONSERVATIVE,
    enforce_sequence_lot,
    is_anchor_volume,
    is_pending_order_type,
    ladder_levels_count,
    level_too_far_from_market,
    lot_for_tag,
    managed_symbol,
    normalize_lot,
)


class TestIsAnchorVolume:
    def test_exact_match(self):
        assert is_anchor_volume(0.02) is True

    def test_within_tolerance(self):
        assert is_anchor_volume(0.0204, anchor_lot_tolerance=0.0005) is True

    def test_outside_tolerance(self):
        assert is_anchor_volume(0.03) is False

    def test_zero_reference(self):
        assert is_anchor_volume(0.02, anchor_lot_reference=0.0) is False

    def test_negative_volume(self):
        assert is_anchor_volume(-0.02) is False

    def test_custom_reference(self):
        assert is_anchor_volume(0.10, anchor_lot_reference=0.10) is True


class TestIsPendingOrderType:
    def test_buy_limit(self):
        assert is_pending_order_type(2) is True  # ORDER_TYPE_BUY_LIMIT

    def test_sell_limit(self):
        assert is_pending_order_type(3) is True

    def test_buy_stop(self):
        assert is_pending_order_type(4) is True

    def test_sell_stop(self):
        assert is_pending_order_type(5) is True

    def test_buy_stop_limit(self):
        assert is_pending_order_type(6) is True

    def test_sell_stop_limit(self):
        assert is_pending_order_type(7) is True

    def test_market_buy(self):
        assert is_pending_order_type(0) is False

    def test_market_sell(self):
        assert is_pending_order_type(1) is False

    def test_unknown(self):
        assert is_pending_order_type(99) is False


class TestLadderLevelsCount:
    def test_conservative(self):
        assert ladder_levels_count(LADDER_CONSERVATIVE) == 1

    def test_balanced(self):
        assert ladder_levels_count(LADDER_BALANCED) == 2

    def test_aggressive(self):
        assert ladder_levels_count(LADDER_AGGRESSIVE) == 3

    def test_unknown(self):
        assert ladder_levels_count(99) == 2  # default balanced


class TestLotForTag:
    def test_s1(self):
        assert lot_for_tag("S1") == normalize_lot(0.05)

    def test_r1(self):
        assert lot_for_tag("R1") == normalize_lot(0.05)

    def test_s2(self):
        assert lot_for_tag("S2") == normalize_lot(0.10)

    def test_r2(self):
        assert lot_for_tag("R2") == normalize_lot(0.10)

    def test_s3(self):
        assert lot_for_tag("S3") == normalize_lot(0.10)

    def test_other(self):
        assert lot_for_tag("P") == normalize_lot(0.10)


class TestManagedSymbol:
    def test_explicit(self):
        assert managed_symbol("XAUUSD", "EURUSD") == "XAUUSD"

    def test_empty_falls_back(self):
        assert managed_symbol("", "EURUSD") == "EURUSD"


class TestLevelTooFarFromMarket:
    def test_within_range(self):
        assert level_too_far_from_market(2005.0, mid=2000.0, atr_now=10.0) is False

    def test_too_far(self):
        assert level_too_far_from_market(2030.0, mid=2000.0, atr_now=10.0) is True

    def test_at_boundary(self):
        # 2.2 * 10 = 22; |2022 - 2000| = 22 → not > 22 → False
        assert level_too_far_from_market(2022.0, mid=2000.0, atr_now=10.0) is False

    def test_just_past_boundary(self):
        assert level_too_far_from_market(2022.01, mid=2000.0, atr_now=10.0) is True

    def test_zero_atr(self):
        assert level_too_far_from_market(9999.0, mid=2000.0, atr_now=0.0) is False

    def test_zero_mid(self):
        assert level_too_far_from_market(2010.0, mid=0.0, atr_now=10.0) is False


class TestEnforceSequenceLot:
    def test_first_trade_uses_base(self):
        lot = enforce_sequence_lot(0.02, total_active_trades=0)
        assert lot == normalize_lot(0.02)

    def test_second_trade_s1r1(self):
        lot = enforce_sequence_lot(0.02, total_active_trades=1, lot_s1r1=0.05)
        assert lot == normalize_lot(0.05)

    def test_third_trade_s2r2(self):
        lot = enforce_sequence_lot(0.02, total_active_trades=2, lot_s2r2=0.10)
        assert lot == normalize_lot(0.10)

    def test_fourth_trade_s3r3plus(self):
        lot = enforce_sequence_lot(0.02, total_active_trades=3, lot_s3r3plus=0.10)
        assert lot == normalize_lot(0.10)

    def test_fifth_trade_still_s3r3(self):
        lot = enforce_sequence_lot(0.02, total_active_trades=10, lot_s3r3plus=0.10)
        assert lot == normalize_lot(0.10)
