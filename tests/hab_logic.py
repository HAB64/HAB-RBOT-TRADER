"""
Python port of pure-logic functions from HAB_XAU_ATP_PEX_019.mq5.

Only computational / decision functions are ported — anything that calls
the MetaTrader API (SymbolInfoDouble, CopyBuffer, PositionGetTicket …)
is replaced by parameter injection so unit tests can exercise the logic
without a live broker connection.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def normalize_double(value: float, digits: int) -> float:
    """MQL5 NormalizeDouble equivalent."""
    return round(value, digits)


def normalize_lot(
    lot: float,
    min_lot: float = 0.01,
    max_lot: float = 100.0,
    step: float = 0.01,
) -> float:
    """Port of NormalizeLot()."""
    if step <= 0.0:
        step = 0.01
    lot = max(lot, min_lot)
    lot = min(lot, max_lot)
    lot = math.floor(lot / step + 0.5) * step
    lot = round(lot, 8)
    if lot < min_lot:
        lot = min_lot
    if lot > max_lot:
        lot = max_lot
    return lot


def pips_to_points_safe(pips: int, digits: int) -> int:
    """Port of PipsToPointsSafe()."""
    if pips <= 0:
        return 0
    mul = 10 if digits in (5, 3) else 1
    pts = pips * mul
    if pts <= 0:
        return 0
    if pts > 2_000_000:
        return 0
    return pts


def value_per_point_per_lot(
    tick_value: float,
    tick_size: float,
    point: float,
) -> float:
    """Port of ValuePerPointPerLot()."""
    if tick_value <= 0.0 or tick_size <= 0.0 or point <= 0.0:
        return 0.0
    return tick_value * (point / tick_size)


def calc_lot_for_risk(
    risk_pct: float,
    sl_points: int,
    equity: float,
    tick_value: float,
    tick_size: float,
    point: float,
    min_lot: float = 0.01,
    max_lot: float = 100.0,
    step: float = 0.01,
) -> float:
    """Port of CalcLotForRisk()."""
    if risk_pct <= 0.0 or sl_points <= 0:
        return 0.0
    if equity <= 0.0:
        return 0.0
    vpp = value_per_point_per_lot(tick_value, tick_size, point)
    if vpp <= 0.0:
        return 0.0
    risk_money = equity * (risk_pct / 100.0)
    denom = sl_points * vpp
    if denom <= 0.0:
        return 0.0
    lot = risk_money / denom
    return normalize_lot(lot, min_lot, max_lot, step)


def calc_risk_pct_for_lot(
    lot: float,
    sl_points: int,
    equity: float,
    tick_value: float,
    tick_size: float,
    point: float,
) -> float:
    """Port of CalcRiskPctForLot()."""
    if lot <= 0.0 or sl_points <= 0:
        return 0.0
    if equity <= 0.0:
        return 0.0
    vpp = value_per_point_per_lot(tick_value, tick_size, point)
    if vpp <= 0.0:
        return 0.0
    risk_money = lot * sl_points * vpp
    return 100.0 * risk_money / equity


def lot_for_tag(
    tag: str,
    lot_s1r1: float = 0.05,
    lot_s2r2: float = 0.10,
    lot_s3r3plus: float = 0.10,
    min_lot: float = 0.01,
    max_lot: float = 100.0,
    step: float = 0.01,
) -> float:
    """Port of LotForTag()."""
    if tag in ("S1", "R1"):
        return normalize_lot(lot_s1r1, min_lot, max_lot, step)
    if tag in ("S2", "R2"):
        return normalize_lot(lot_s2r2, min_lot, max_lot, step)
    return normalize_lot(lot_s3r3plus, min_lot, max_lot, step)


def is_anchor_volume(
    vol: float,
    anchor_lot_reference: float = 0.02,
    anchor_lot_tolerance: float = 0.0005,
) -> bool:
    """Port of IsAnchorVolume()."""
    if anchor_lot_reference <= 0.0:
        return False
    return abs(vol - anchor_lot_reference) <= anchor_lot_tolerance


# ---------------------------------------------------------------------------
# Spread gate
# ---------------------------------------------------------------------------


def dynamic_max_spread_points(
    use_dynamic: bool,
    max_spread_points: int,
    spread_floor_points: int,
    spread_atr14_ratio: float,
    atr14_points: float,
) -> int:
    """Port of DynamicMaxSpreadPoints()."""
    if not use_dynamic:
        return max_spread_points

    dyn = max_spread_points
    if atr14_points > 0.0:
        by_atr = int(math.floor(spread_atr14_ratio * atr14_points + 0.5))
        dyn = max(spread_floor_points, by_atr)
    else:
        dyn = max(spread_floor_points, max_spread_points)

    if dyn < 1:
        dyn = 1
    if dyn > 2000:
        dyn = 2000
    return dyn


# ---------------------------------------------------------------------------
# P-Zone logic
# ---------------------------------------------------------------------------


def pzone_half_width_price(half_width_dollars: float = 2.0) -> float:
    """Port of PZoneHalfWidthPrice()."""
    return max(half_width_dollars, 0.0)


def is_inside_pzone(
    price: float,
    p: float,
    half_width_dollars: float = 2.0,
) -> bool:
    """Port of IsInsidePZone()."""
    w = pzone_half_width_price(half_width_dollars)
    return (p - w) <= price <= (p + w)


def clamp_to_pzone(
    price: float,
    p: float,
    half_width_dollars: float = 2.0,
) -> float:
    """Port of ClampToPZone()."""
    w = pzone_half_width_price(half_width_dollars)
    lo = p - w
    hi = p + w
    if price < lo:
        return lo
    if price > hi:
        return hi
    return price


# ---------------------------------------------------------------------------
# Rolling Profit Factor
# ---------------------------------------------------------------------------


def rolling_profit_factor(profits: list[float]) -> float:
    """Port of RollingProfitFactor()."""
    if len(profits) < 5:
        return 999.0
    wins = sum(p for p in profits if p > 0.0)
    losses = sum(p for p in profits if p <= 0.0)
    if losses >= 0.0:
        return 999.0
    return wins / abs(losses)


# ---------------------------------------------------------------------------
# Entry time ring buffer + burst counting
# ---------------------------------------------------------------------------


@dataclass
class EntryTimeBuffer:
    """Port of g_entryTimes ring buffer + AddEntryTime / CountEntriesSince."""

    capacity: int = 3000
    _times: list[int] = field(default_factory=list)

    def add(self, t: int) -> None:
        """Port of AddEntryTime()."""
        if t <= 0:
            return
        if self.capacity <= 0:
            return
        if len(self._times) < self.capacity:
            self._times.append(t)
            return
        # shift left
        self._times = self._times[1:] + [t]

    def count_since(self, now: int, seconds_lookback: int) -> int:
        """Port of CountEntriesSince()."""
        if seconds_lookback <= 0:
            return 0
        t0 = now - seconds_lookback
        cnt = 0
        for i in range(len(self._times) - 1, -1, -1):
            if self._times[i] < t0:
                break
            cnt += 1
        return cnt


# ---------------------------------------------------------------------------
# Closed-trade ring buffer + consecutive loss tracking
# ---------------------------------------------------------------------------


@dataclass
class ClosedTradeBuffer:
    """Port of g_rollProfits ring buffer + AddClosedTradeNetProfit."""

    capacity: int = 200
    _profits: list[float] = field(default_factory=list)
    _idx: int = 0
    consec_losses: int = 0

    def add(self, netp: float) -> None:
        """Port of AddClosedTradeNetProfit() — data part only."""
        if self.capacity <= 0:
            return
        if len(self._profits) < self.capacity:
            self._profits.append(netp)
        else:
            self._profits[self._idx] = netp
            self._idx += 1
            if self._idx >= self.capacity:
                self._idx = 0
        if netp < 0.0:
            self.consec_losses += 1
        else:
            self.consec_losses = 0

    def profit_factor(self) -> float:
        return rolling_profit_factor(self._profits)

    @property
    def count(self) -> int:
        return len(self._profits)


# ---------------------------------------------------------------------------
# Equity kill-switch
# ---------------------------------------------------------------------------


@dataclass
class EquityKillSwitch:
    """Port of UpdateEquityKillSwitch + TradingHalted."""

    protected_nosl: bool = False
    max_equity_dd_pct: float = 15.0
    start_equity: float = 0.0
    peak_equity: float = 0.0
    kill_switch: bool = False

    def update(self, equity: float) -> bool:
        """Returns True if kill-switch was triggered on this call."""
        if not self.protected_nosl:
            return False
        if self.kill_switch:
            return False
        if equity <= 0.0:
            return False
        if self.start_equity <= 0.0:
            self.start_equity = equity
        if self.peak_equity <= 0.0:
            self.peak_equity = equity
        if equity > self.peak_equity:
            self.peak_equity = equity
        if self.max_equity_dd_pct <= 0.0:
            return False
        dd_pct = (self.peak_equity - equity) / self.peak_equity * 100.0
        if dd_pct >= self.max_equity_dd_pct:
            self.kill_switch = True
            return True
        return False

    def halted(self) -> bool:
        if not self.protected_nosl:
            return False
        return self.kill_switch


# ---------------------------------------------------------------------------
# Pending-order type check
# ---------------------------------------------------------------------------

# MT5 order type enum values
ORDER_TYPE_BUY = 0
ORDER_TYPE_SELL = 1
ORDER_TYPE_BUY_LIMIT = 2
ORDER_TYPE_SELL_LIMIT = 3
ORDER_TYPE_BUY_STOP = 4
ORDER_TYPE_SELL_STOP = 5
ORDER_TYPE_BUY_STOP_LIMIT = 6
ORDER_TYPE_SELL_STOP_LIMIT = 7


def is_pending_order_type(t: int) -> bool:
    """Port of IsPendingOrderType()."""
    return t in (
        ORDER_TYPE_BUY_LIMIT,
        ORDER_TYPE_SELL_LIMIT,
        ORDER_TYPE_BUY_STOP,
        ORDER_TYPE_SELL_STOP,
        ORDER_TYPE_BUY_STOP_LIMIT,
        ORDER_TYPE_SELL_STOP_LIMIT,
    )


# ---------------------------------------------------------------------------
# SL/TP computation
# ---------------------------------------------------------------------------


def compute_sl(
    direction: int,
    entry: float,
    total_active_trades: int,
    point: float,
    digits: int,
    protected_nosl: bool = False,
    catastrophic_sl_points: int = 0,
    catastrophic_sl_atr_mult: float = 6.0,
    atr_value: float = 0.0,
) -> float:
    """Port of the SL portion of ComputeSL_AndTP()."""
    next_index = total_active_trades + 1
    if next_index == 1:
        sl_dist_pips = 300.0
    elif next_index == 2:
        sl_dist_pips = 200.0
    else:
        sl_dist_pips = 100.0

    sl_val = sl_dist_pips * 10.0 * point

    if direction == 1:
        sl = entry - sl_val
    else:
        sl = entry + sl_val

    sl = normalize_double(sl, digits)

    if protected_nosl:
        cat = 0.0
        if catastrophic_sl_points > 0:
            cat = catastrophic_sl_points * point
        if atr_value > 0.0 and catastrophic_sl_atr_mult > 0.0:
            by_atr = atr_value * catastrophic_sl_atr_mult
            if by_atr > cat:
                cat = by_atr
        if cat > 0.0:
            if direction == 1:
                sl = entry - cat
            else:
                sl = entry + cat
            sl = normalize_double(sl, digits)

    return sl


# ---------------------------------------------------------------------------
# Structural TP (edge-based)
# ---------------------------------------------------------------------------


def compute_structural_tp_edge_based(
    direction: int,
    entry: float,
    levels: dict[str, tuple[float, float]],
    tp_level_buffer_points: int = 25,
    tp_min_profit_points: int = 50,
    point: float = 0.01,
    digits: int = 2,
) -> tuple[float, float, str] | None:
    """
    Port of ComputeStructuralTP_EdgeBased().

    levels: dict mapping tag -> (zone_low, zone_high).
    Returns (tp, edge_ref, tag) or None if no valid TP found.
    """
    if direction not in (1, -1):
        return None

    best_ref = 0.0
    best_low = 0.0
    best_high = 0.0
    best_tag = ""
    found = False

    for tag, (zl, zh) in levels.items():
        ref = zl if direction == 1 else zh

        if direction == 1:
            if ref <= entry:
                continue
            if not found or ref < best_ref:
                found = True
                best_ref = ref
                best_low = zl
                best_high = zh
                best_tag = tag
        else:
            if ref >= entry:
                continue
            if not found or ref > best_ref:
                found = True
                best_ref = ref
                best_low = zl
                best_high = zh
                best_tag = tag

    if not found:
        return None

    buf = max(0, tp_level_buffer_points) * point
    minp = max(0, tp_min_profit_points) * point

    if direction == 1:
        tp = best_low - buf
        if tp <= entry + minp:
            return None
        edge_ref = best_low
    else:
        tp = best_high + buf
        if tp >= entry - minp:
            return None
        edge_ref = best_high

    tp = normalize_double(tp, digits)
    return tp, edge_ref, best_tag


# ---------------------------------------------------------------------------
# EMA alignment & regime
# ---------------------------------------------------------------------------


def ema_overlay_aligned(
    direction: int,
    e20: float,
    e50: float,
    e100: float,
    e200: float,
    require_full_alignment: bool = True,
    require_slow_vs_long: bool = True,
) -> tuple[bool, str]:
    """
    Port of EMAOverlayAligned() — pure decision logic.

    Returns (aligned: bool, reason: str).
    """
    bull = (e20 > e50) and (e50 > e100)
    bear = (e20 < e50) and (e50 < e100)

    if require_slow_vs_long:
        bull = bull and (e100 > e200)
        bear = bear and (e100 < e200)

    if require_full_alignment:
        bull = bull and (e20 > e50) and (e50 > e100) and (e100 > e200)
        bear = bear and (e20 < e50) and (e50 < e100) and (e100 < e200)

    if direction == 1:
        if bull:
            return True, "ema_align_bull"
        return False, "ema_align_block_buy"
    if direction == -1:
        if bear:
            return True, "ema_align_bear"
        return False, "ema_align_block_sell"

    return False, "ema_dir_zero"


def ema_regime_dir(e100: float, e200: float) -> tuple[int, str]:
    """Port of EMARegimeDir() — pure decision."""
    if e100 > e200:
        return 1, "regime_bull"
    if e100 < e200:
        return -1, "regime_bear"
    return 0, "regime_neutral"


def ema_regime_pass_for_auto(
    direction: int,
    e100: float,
    e200: float,
    use_regime_filter: bool = True,
    block_auto_entries: bool = True,
    allow_neutral: bool = False,
) -> tuple[bool, str]:
    """Port of EMARegimePassForAuto() — pure decision."""
    if not use_regime_filter or not block_auto_entries:
        return True, "disabled"

    rd, _rwhy = ema_regime_dir(e100, e200)

    if rd == 0 and allow_neutral:
        return True, "regime_neutral_allowed"
    if direction == 1 and rd == 1:
        return True, "regime_ok_buy"
    if direction == -1 and rd == -1:
        return True, "regime_ok_sell"

    if rd == 0:
        return False, "regime_neutral_block"
    return False, "regime_mismatch"


def compute_ema_status(
    e20: float,
    e50: float,
    e100: float,
    e200: float,
) -> tuple[int, int]:
    """
    Port of the status part of UpdateEMAStatusCache().

    Returns (bull_status, bear_status): 0=RED, 1=YELLOW, 2=GREEN.
    """
    bull_full = (e20 > e50) and (e50 > e100) and (e100 > e200)
    bear_full = (e20 < e50) and (e50 < e100) and (e100 < e200)
    bull_partial = (e50 > e100) and (e100 > e200)
    bear_partial = (e50 < e100) and (e100 < e200)

    bull_status = 2 if bull_full else (1 if bull_partial else 0)
    bear_status = 2 if bear_full else (1 if bear_partial else 0)
    return bull_status, bear_status


# ---------------------------------------------------------------------------
# Level distance
# ---------------------------------------------------------------------------


def level_too_far_from_market(
    level: float,
    mid: float,
    atr_now: float,
    max_level_dist_atr: float = 2.2,
) -> bool:
    """Port of LevelTooFarFromMarket()."""
    if atr_now <= 0.0:
        return False
    if mid <= 0.0:
        return False
    return abs(level - mid) > max_level_dist_atr * atr_now


# ---------------------------------------------------------------------------
# Ladder mode
# ---------------------------------------------------------------------------

LADDER_CONSERVATIVE = 0
LADDER_BALANCED = 1
LADDER_AGGRESSIVE = 2


def ladder_levels_count(mode: int) -> int:
    """How many pending levels to manage based on ladder mode."""
    if mode == LADDER_CONSERVATIVE:
        return 1
    if mode == LADDER_BALANCED:
        return 2
    if mode == LADDER_AGGRESSIVE:
        return 3
    return 2  # default balanced


# ---------------------------------------------------------------------------
# Sequence-based lot enforcement (v1.379)
# ---------------------------------------------------------------------------


def enforce_sequence_lot(
    base_lot: float,
    total_active_trades: int,
    min_lot: float = 0.01,
    max_lot: float = 100.0,
    step: float = 0.01,
    lot_s1r1: float = 0.05,
    lot_s2r2: float = 0.10,
    lot_s3r3plus: float = 0.10,
) -> float:
    """
    Port of EnforceSequenceLot() — assigns lot size based on sequence
    position rather than raw base_lot.
    """
    next_index = total_active_trades + 1
    if next_index <= 1:
        return normalize_lot(base_lot, min_lot, max_lot, step)
    if next_index == 2:
        return normalize_lot(lot_s1r1, min_lot, max_lot, step)
    if next_index == 3:
        return normalize_lot(lot_s2r2, min_lot, max_lot, step)
    return normalize_lot(lot_s3r3plus, min_lot, max_lot, step)


# ---------------------------------------------------------------------------
# Managed symbol resolver
# ---------------------------------------------------------------------------


def managed_symbol(inp_managed: str, current_symbol: str) -> str:
    """Port of ManagedSymbol()."""
    if inp_managed != "":
        return inp_managed
    return current_symbol


# ---------------------------------------------------------------------------
# AutoAnchor SL computation
# ---------------------------------------------------------------------------


def compute_auto_anchor_sl(
    direction: int,
    entry: float,
    sl_pips: int,
    digits: int,
    point: float,
) -> float | None:
    """
    Port of the SL portion of ComputeAutoAnchor_SLTP().
    Returns the SL price, or None if invalid.
    """
    sl_pts = pips_to_points_safe(sl_pips, digits)
    if sl_pts <= 0:
        return None
    sl_dist = sl_pts * point
    if direction == 1:
        sl = entry - sl_dist
    else:
        sl = entry + sl_dist
    return normalize_double(sl, digits)
