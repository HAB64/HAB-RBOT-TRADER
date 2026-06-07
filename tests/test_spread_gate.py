"""Tests for dynamic spread gate logic."""

from hab_logic import dynamic_max_spread_points


class TestDynamicMaxSpreadPoints:
    def test_disabled_returns_static(self):
        assert (
            dynamic_max_spread_points(
                use_dynamic=False,
                max_spread_points=80,
                spread_floor_points=40,
                spread_atr14_ratio=0.12,
                atr14_points=500.0,
            )
            == 80
        )

    def test_atr_based(self):
        # ATR = 500pts → by_atr = floor(0.12*500 + 0.5) = floor(60.5) = 60
        # max(40, 60) = 60
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=80,
            spread_floor_points=40,
            spread_atr14_ratio=0.12,
            atr14_points=500.0,
        )
        assert result == 60

    def test_floor_wins_over_atr(self):
        # ATR = 100pts → by_atr = floor(0.12*100 + 0.5) = floor(12.5) = 12
        # max(40, 12) = 40
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=80,
            spread_floor_points=40,
            spread_atr14_ratio=0.12,
            atr14_points=100.0,
        )
        assert result == 40

    def test_no_atr_fallback(self):
        # atr = 0 → fallback: max(floor, static)
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=80,
            spread_floor_points=40,
            spread_atr14_ratio=0.12,
            atr14_points=0.0,
        )
        assert result == max(40, 80)

    def test_clamp_minimum(self):
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=0,
            spread_floor_points=0,
            spread_atr14_ratio=0.0,
            atr14_points=0.0,
        )
        assert result >= 1

    def test_clamp_maximum(self):
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=0,
            spread_floor_points=5000,
            spread_atr14_ratio=0.12,
            atr14_points=0.0,
        )
        assert result <= 2000

    def test_negative_atr(self):
        # negative ATR treated as zero (fallback path)
        result = dynamic_max_spread_points(
            use_dynamic=True,
            max_spread_points=80,
            spread_floor_points=40,
            spread_atr14_ratio=0.12,
            atr14_points=-10.0,
        )
        assert result == max(40, 80)
