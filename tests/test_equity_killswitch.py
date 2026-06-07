"""Tests for equity kill-switch and trading-halted logic."""

from hab_logic import EquityKillSwitch


class TestEquityKillSwitch:
    def test_disabled(self):
        ks = EquityKillSwitch(protected_nosl=False)
        triggered = ks.update(5000.0)
        assert triggered is False
        assert ks.halted() is False

    def test_no_drawdown(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=15.0)
        ks.update(10000.0)
        ks.update(10500.0)
        assert ks.halted() is False
        assert ks.peak_equity == 10500.0

    def test_triggers_at_threshold(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=15.0)
        ks.update(10000.0)
        # drawdown = (10000 - 8500) / 10000 * 100 = 15.0%
        triggered = ks.update(8500.0)
        assert triggered is True
        assert ks.halted() is True

    def test_does_not_trigger_just_below(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=15.0)
        ks.update(10000.0)
        # drawdown = 14.99% < 15%
        triggered = ks.update(8501.0)
        assert triggered is False
        assert ks.halted() is False

    def test_halted_stays_halted(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=10.0)
        ks.update(10000.0)
        ks.update(9000.0)  # triggers
        assert ks.halted() is True
        # equity recovers, but kill-switch stays on
        ks.update(15000.0)
        assert ks.halted() is True

    def test_peak_tracks_highest(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=50.0)
        ks.update(10000.0)
        ks.update(12000.0)
        ks.update(11000.0)
        assert ks.peak_equity == 12000.0

    def test_zero_equity(self):
        ks = EquityKillSwitch(protected_nosl=True)
        triggered = ks.update(0.0)
        assert triggered is False

    def test_zero_dd_threshold(self):
        ks = EquityKillSwitch(protected_nosl=True, max_equity_dd_pct=0.0)
        ks.update(10000.0)
        triggered = ks.update(5000.0)
        assert triggered is False  # 0% threshold → never triggers
