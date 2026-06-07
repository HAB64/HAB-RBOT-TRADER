"""Tests for P-Zone logic: half-width, inside check, clamping."""

import pytest
from hab_logic import clamp_to_pzone, is_inside_pzone, pzone_half_width_price


class TestPZoneHalfWidth:
    def test_default(self):
        assert pzone_half_width_price(2.0) == 2.0

    def test_negative_clamps(self):
        assert pzone_half_width_price(-5.0) == 0.0

    def test_zero(self):
        assert pzone_half_width_price(0.0) == 0.0

    def test_custom(self):
        assert pzone_half_width_price(3.5) == 3.5


class TestIsInsidePZone:
    def test_at_center(self):
        assert is_inside_pzone(2000.0, 2000.0) is True

    def test_at_lower_edge(self):
        assert is_inside_pzone(1998.0, 2000.0) is True

    def test_at_upper_edge(self):
        assert is_inside_pzone(2002.0, 2000.0) is True

    def test_below(self):
        assert is_inside_pzone(1997.99, 2000.0) is False

    def test_above(self):
        assert is_inside_pzone(2002.01, 2000.0) is False

    def test_zero_width(self):
        assert is_inside_pzone(2000.0, 2000.0, half_width_dollars=0.0) is True
        assert is_inside_pzone(2000.01, 2000.0, half_width_dollars=0.0) is False

    def test_large_zone(self):
        assert is_inside_pzone(1990.0, 2000.0, half_width_dollars=10.0) is True
        assert is_inside_pzone(2010.0, 2000.0, half_width_dollars=10.0) is True
        assert is_inside_pzone(2010.01, 2000.0, half_width_dollars=10.0) is False


class TestClampToPZone:
    def test_inside_no_change(self):
        assert clamp_to_pzone(2001.0, 2000.0) == 2001.0

    def test_below_clamps_up(self):
        assert clamp_to_pzone(1997.0, 2000.0) == pytest.approx(1998.0)

    def test_above_clamps_down(self):
        assert clamp_to_pzone(2003.0, 2000.0) == pytest.approx(2002.0)

    def test_at_boundary(self):
        assert clamp_to_pzone(1998.0, 2000.0) == pytest.approx(1998.0)
        assert clamp_to_pzone(2002.0, 2000.0) == pytest.approx(2002.0)

    def test_zero_width(self):
        # zone is just P itself
        assert clamp_to_pzone(1999.0, 2000.0, half_width_dollars=0.0) == 2000.0
        assert clamp_to_pzone(2001.0, 2000.0, half_width_dollars=0.0) == 2000.0
        assert clamp_to_pzone(2000.0, 2000.0, half_width_dollars=0.0) == 2000.0
