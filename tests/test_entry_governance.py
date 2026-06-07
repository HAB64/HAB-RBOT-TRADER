"""Tests for entry governance: rolling PF, burst control, loss-cluster, entry-time buffer."""

import pytest
from hab_logic import (
    ClosedTradeBuffer,
    EntryTimeBuffer,
    rolling_profit_factor,
)


class TestRollingProfitFactor:
    def test_insufficient_data(self):
        assert rolling_profit_factor([1.0, 2.0]) == 999.0

    def test_no_losses(self):
        assert rolling_profit_factor([1.0, 2.0, 3.0, 4.0, 5.0]) == 999.0

    def test_balanced(self):
        profits = [10.0, -5.0, 8.0, -3.0, 6.0]
        # wins=24, losses=-8 → PF = 24/8 = 3.0
        assert rolling_profit_factor(profits) == pytest.approx(3.0)

    def test_all_losses(self):
        profits = [-1.0, -2.0, -3.0, -4.0, -5.0]
        # wins=0, losses=-15 → PF = 0/15 = 0.0
        assert rolling_profit_factor(profits) == pytest.approx(0.0)

    def test_exactly_five(self):
        profits = [5.0, 5.0, -5.0, -5.0, 10.0]
        # wins=20, losses=-10 → PF = 2.0
        assert rolling_profit_factor(profits) == pytest.approx(2.0)

    def test_empty(self):
        assert rolling_profit_factor([]) == 999.0

    def test_one_win_four_losses(self):
        profits = [100.0, -10.0, -20.0, -30.0, -40.0]
        # wins=100, losses=-100 → PF = 1.0
        assert rolling_profit_factor(profits) == pytest.approx(1.0)


class TestEntryTimeBuffer:
    def test_add_and_count(self):
        buf = EntryTimeBuffer(capacity=10)
        buf.add(1000)
        buf.add(1050)
        buf.add(1100)
        assert buf.count_since(now=1100, seconds_lookback=60) == 2
        assert buf.count_since(now=1100, seconds_lookback=200) == 3

    def test_count_zero_lookback(self):
        buf = EntryTimeBuffer(capacity=10)
        buf.add(1000)
        assert buf.count_since(now=1000, seconds_lookback=0) == 0

    def test_add_ignores_zero(self):
        buf = EntryTimeBuffer(capacity=10)
        buf.add(0)
        assert buf.count_since(now=1000, seconds_lookback=2000) == 0

    def test_add_ignores_negative(self):
        buf = EntryTimeBuffer(capacity=10)
        buf.add(-5)
        assert buf.count_since(now=1000, seconds_lookback=2000) == 0

    def test_overflow_shift(self):
        buf = EntryTimeBuffer(capacity=3)
        buf.add(100)
        buf.add(200)
        buf.add(300)
        buf.add(400)  # should push out 100
        assert buf.count_since(now=400, seconds_lookback=500) == 3
        # 100 should be gone
        assert buf.count_since(now=400, seconds_lookback=150) == 2

    def test_all_too_old(self):
        buf = EntryTimeBuffer(capacity=10)
        buf.add(100)
        buf.add(200)
        assert buf.count_since(now=10000, seconds_lookback=5) == 0


class TestClosedTradeBuffer:
    def test_basic_tracking(self):
        buf = ClosedTradeBuffer(capacity=10)
        buf.add(10.0)
        buf.add(-5.0)
        buf.add(8.0)
        assert buf.count == 3
        assert buf.consec_losses == 0

    def test_consecutive_losses(self):
        buf = ClosedTradeBuffer(capacity=10)
        buf.add(-1.0)
        buf.add(-2.0)
        buf.add(-3.0)
        assert buf.consec_losses == 3
        buf.add(5.0)
        assert buf.consec_losses == 0

    def test_profit_factor_insufficient(self):
        buf = ClosedTradeBuffer(capacity=10)
        buf.add(1.0)
        buf.add(-1.0)
        assert buf.profit_factor() == 999.0  # < 5 trades

    def test_profit_factor_with_data(self):
        buf = ClosedTradeBuffer(capacity=10)
        for p in [10.0, -5.0, 8.0, -3.0, 6.0]:
            buf.add(p)
        # wins=24, losses=-8 → PF=3.0
        assert buf.profit_factor() == pytest.approx(3.0)

    def test_ring_buffer_wrap(self):
        buf = ClosedTradeBuffer(capacity=3)
        buf.add(1.0)
        buf.add(2.0)
        buf.add(3.0)
        # At capacity, now wrap
        buf.add(-10.0)  # replaces idx=0 (was 1.0)
        buf.add(-20.0)  # replaces idx=1 (was 2.0)
        assert buf.count == 3  # capacity limit
        assert buf.consec_losses == 2
        # Profits are now [-10.0, -20.0, 3.0]
        # insufficient data (5 required, only 3) → 999.0
        assert buf.profit_factor() == 999.0
