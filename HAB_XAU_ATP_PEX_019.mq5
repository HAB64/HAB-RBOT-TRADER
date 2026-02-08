//+------------------------------------------------------------------+
//| HAB_XAU_ATP_PEX_HYBRID_v1_018.mq5  |
//| v1.015 - Anchor EMA20/50/100 entry-quality validation (M5 bar-close)                 |
//| Changes v1.379 (Requested):                                      |
//| - Trade 1 (0.02 Lot): SL = 300 Pips.                            |
//| - Trade 2 (0.05 Lot): SL = 200 Pips.                            |
//| - Trade 3 & 4 (0.10 Lot): SL = 100 Pips.                        |
//| - Hard Cap: Max 4 total active trades (Manual + EA).            |
//| - اعمال قوانین SL/TP روی معاملات دستی                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.019"

#include <Trade\Trade.mqh>

//============================= Inputs ==============================//
input ulong           Inp_MagicNumber                = 777777;
input int             Inp_DeviationPoints            = 30;
input int             Inp_CooldownSeconds            = 15;

//============================= Symbol Scope (HARD SAFETY) ==============================//
// This EA must never modify or manage positions/orders on any symbol other than the intended one.
// If you accidentally attach it to BTC/indices/etc, it will STILL only touch Inp_ManagedSymbol.
input string          Inp_ManagedSymbol              = "XAUUSD";

//============================= Internal Symbol Resolver ==============================//
string ManagedSymbol()
{
  if(Inp_ManagedSymbol!="") return Inp_ManagedSymbol;
  return _Symbol;
}

// CAPS (separated)
// v1.379: Total cap includes Manual + EA
input int             Inp_MaxPositions               = 4;     // CAP on ALL OPEN POSITIONS on this symbol
input int             Inp_MaxEAPendings              = 4;     // CAP on EA pendings (all types) on this symbol
input bool            Inp_DeleteEAPendingsWhenCapHit = true;  // delete EA pendings if MaxPositions hit

// Account mode handling
input bool            Inp_AllowNetting               = false; // default FAIL-CLOSED on netting accounts

// Anchor detection (manual OR pending-filled)
input double          Inp_AnchorLot_Reference        = 0.02;  // anchor trigger volume
input double          Inp_AnchorLot_Tolerance        = 0.0005; // |vol-ref| <= tol => treat as anchor
input bool            Inp_AnchorMagic0Only           = false; // true => anchor must be magic=0 only

// Anchor TP management switch (structural TP)
input bool            Inp_SetAnchorTP                = true;

// Volume ladder for EA orders (level-based) - Reference only, logic uses EnforceSequenceLot
input double          Inp_Lot_S1R1                   = 0.05;
input double          Inp_Lot_S2R2                   = 0.10;
input double          Inp_Lot_S3R3Plus               = 0.10;

// SL (ATR or fixed) - Inputs kept but Logic overridden by v1.379 sequence rules
input bool            Inp_UseATR_SLTP                = false; 
input ENUM_TIMEFRAMES Inp_ATR_TF                     = PERIOD_M5;
input int             Inp_ATRPeriod                  = 14;
input double          Inp_SL_ATR_Mult                = 1.5;
input int             Inp_FixedSL_Points             = 500;

// Pendings & level guards (ladder)
input int             Inp_MaxPendingsPerSide         = 3;
input int             Inp_MinDist_Points             = 100;   // do not place if too close to market
input double          Inp_MaxLevelDist_ATR           = 2.2;   // anti-stale: ignore if too far from market (ATR multiple)
input int             Inp_LevelShift_TolPts          = 15;    // if level moved more than this -> resync

// Spread gate
input int             Inp_MaxSpreadPoints            = 80;    // spread gate (points)

// Dynamic Spread Gate (for high-frequency scalping). If enabled, MaxSpread becomes:
 // max(SpreadFloorPoints, SpreadATR14Ratio * ATR14_points)
input bool            Inp_UseDynamicSpreadGate       = true;
input int             Inp_SpreadFloorPoints          = 40;    // absolute floor (points)
input double          Inp_SpreadATR14Ratio           = 0.12;  // ATR14_points * ratio

// Burst Control (trade frequency limiter). Counts filled ENTRY deals (manual + EA) on this symbol.
input bool            Inp_EnableBurstControl         = true;
input int             Inp_MaxEntriesPer5Min          = 25;
input int             Inp_MaxEntriesPer15Min         = 60;
input int             Inp_BurstPauseSeconds          = 300;   // pause duration after burst hit

// Loss-Cluster Governor (halts new entries during adverse micro-regimes)
input bool            Inp_EnableLossClusterPause     = true;
input int             Inp_PauseAfterConsecLosses     = 3;
input int             Inp_LossClusterPauseSeconds    = 600;
input int             Inp_RollingWindowTrades        = 20;
input double          Inp_MinRollingProfitFactor     = 1.10;
input int             Inp_LowPFPauseSeconds          = 600;


//================== Trend-Permission (M5, Bar-Close Only) ==================//
// Final decision is strictly one of: ALLOW_BUY / ALLOW_SELL / NO_TRADE
input ENUM_TIMEFRAMES Inp_ExecTF                     = PERIOD_M5;   // fixed by spec; keep as input for safety
input int             Inp_EMAPeriod                  = 200;         // EMA200
input int             Inp_Slope_L_Bars               = 20;          // L
input double          Inp_k_band                     = 0.15;        // ATR band multiplier
input double          Inp_k_slope                    = 0.04;        // normalized slope threshold
input double          Inp_ATR_Min_Points             = 80;          // ATR14 minimum (points) -> sleep gate
input double          Inp_ShockRatio                 = 1.8;         // ATR14/ATR100 shock gate
//================== EMA Overlay (No removal of existing controls) ==================//
// EMA overlay is used ONLY to improve automatic first-trade (EA Anchor / AutoAnchor).
// Manual Anchor is NEVER blocked (warn-only), unless user explicitly changes inputs.
input bool            Inp_UseEMAOverlay              = true;
input ENUM_TIMEFRAMES Inp_EMAOverlayTF               = PERIOD_M5;
input int             Inp_EMA_Fast_Period            = 20;
input int             Inp_EMA_Mid_Period             = 50;
input int             Inp_EMA_Slow_Period            = 100;
input int             Inp_EMA_Long_Period            = 200;  // overlay reference (kept separate from core EMA200)
input bool            Inp_EMAOverlayRequireFullAlignment = true; // 20>50>100>200 for BUY; reverse for SELL
input bool            Inp_EMAOverlayRequireSlowVsLong = true;     // require EMA100>EMA200 (BUY) / EMA100<EMA200 (SELL)
input bool            Inp_EMAOverlayBlockAutoEntries  = true;     // blocks EA auto-open + AutoAnchor if alignment mismatch
input bool            Inp_EMAOverlayWarnManualAnchor  = true;     // warn-only on manual anchor mismatch (never blocks)
// Anchor entry-quality filter (uses EMA20/50/100 as a STRUCTURAL VALIDATOR for Anchor timing)
input bool            Inp_EMAOverlayRequireCloseVsEMA50 = true; // BUY: Close(1) > EMA50, SELL: Close(1) < EMA50
input bool            Inp_EMAOverlayAllowReclaim        = true; // allow pullback->reclaim entry-quality pattern
input bool            Inp_EMAOverlayReclaimUseEMA20     = true; // reclaim level: EMA20 if true else EMA50

//================== EMA Regime Filter (H1, Auto-Entry Gate Only) ==================//
// Regime filter is a higher-timeframe sanity check: it gates ONLY EA auto actions
// (EA Anchor open + AutoAnchor pending). Manual Anchor is never blocked (warn-only).
input bool            Inp_UseEMARegimeFilter         = true;
input ENUM_TIMEFRAMES Inp_EMARegimeTF                = PERIOD_H1;
input int             Inp_EMARegime_Slow_Period      = 100; // regime EMA100
input int             Inp_EMARegime_Long_Period      = 200; // regime EMA200
input bool            Inp_EMARegimeAllowNeutral      = false; // if false => neutral blocks auto entries
input bool            Inp_EMARegimeBlockAutoEntries  = true;  // blocks EA auto-open + AutoAnchor if regime mismatch
input bool            Inp_EMARegimeWarnManualAnchor  = true;  // warn-only on manual anchor mismatch
input bool            Inp_EMAOverlayAllowYellow      = true;  // allow partial alignment (YELLOW) for auto entries



//================== Anchor + Pending Policy ==================//
input bool            Inp_EnableEAAnchorOpen         = true;        // EA may open the 0.02 Anchor when permission allows
input double          Inp_EAAnchorLot                = 0.02;        // Anchor lot (must match manual anchor reference)
input int             Inp_MaxTotalPendingsAfterAnchor= 3;           // HARD CAP: TOTAL pendings on symbol (manual + EA)


// ATR shock gate
input bool            Inp_EnableATRShock             = true;
input int             Inp_ATRShockLookback           = 20;
input double          Inp_ATRShockFactor             = 1.8;
input bool            Inp_ATRShockFailClosed         = true;  // baseline missing => NO TRADE
input bool            Inp_DeletePendingsOnShock      = true;

// AutoAnchor STOP
input bool            Inp_EnableAutoAnchor           = true;
input ENUM_TIMEFRAMES Inp_TrendTF                    = PERIOD_H1;
input int             Inp_TrendMAPeriod              = 200;
input int             Inp_TrendSlopeBars             = 2;
input int             Inp_AutoAnchorExpiryMin        = 60;
input double          Inp_AutoAnchorLot              = 0.02;
input int             Inp_AutoAnchorSL_Pips          = 300;   // fixed SL for AutoAnchor (thermometer)
input double          Inp_AutoAnchorMaxRiskPct        = 1.0;   // safety cap: if fixed lot risks more than this, downsize/block
input bool            Inp_AutoAnchorDownsizeToMaxRisk = true;  // if true, reduce lot to fit max risk; else block trade

input bool            Inp_AutoAnchorUseMagic0Only    = false; 

// AutoAnchor: NO SL (TP only) 
// v1.379: Set to false implicitly by logic for Trade 1
input bool            Inp_AutoAnchor_NoSL            = false;

// AutoAnchor must be inside Pivot(P) Zone (FIXED $)
input bool            Inp_AutoAnchorRequirePZone     = true;  // market must be inside zone else no AutoAnchor
input double          Inp_PZone_HalfWidth_Dollars    = 2.0;   // EXACT: ±$2 around P (total $4 corridor)

// Structural TP (EDGE-based)
input bool            Inp_UseStructuralTP            = true;
input int             Inp_TP_LevelBufferPoints       = 25;    // edge buffer (points)
input int             Inp_TP_MinProfitPoints         = 50;    // minimum profit distance from entry (points)

// Ladder Mode (mode-driven PivotLadder execution)
enum HAB_LADDER_MODE { LADDER_CONSERVATIVE=0, LADDER_BALANCED=1, LADDER_AGGRESSIVE=2 };
input HAB_LADDER_MODE Inp_LadderMode                = LADDER_BALANCED; // Conservative: 1 level, Balanced: 2, Aggressive: 3

// Protected-NoSL (professional risk envelope; replaces raw "NO_SL")
input bool            Inp_ProtectedNoSL             = false; // if true: do NOT use tight SL; use catastrophic stop + equity kill switch
input double          Inp_MaxEquityDD_Percent       = 15.0;  // kill-switch: max equity drawdown from peak since EA start (percent)
input bool            Inp_CloseAllOnKill            = true;  // close all positions on this symbol when kill-switch triggers
input int             Inp_TimeStopMinutes           = 0;     // 0 disables; close positions on this symbol after N minutes open
input double          Inp_CatastrophicSL_ATRMult    = 6.0;   // catastrophic stop distance = ATR * mult (if ATR available)
input int             Inp_CatastrophicSL_Points     = 0;     // optional hard minimum catastrophic SL (points); 0 disables

// مدیریت معاملات دستی
input bool            Inp_ApplyRulesToManualTrades   = true;  // اعمال قوانین SL/TP روی معاملات دستی
input bool            Inp_SetManualSL                = true;  // تنظیم SL برای معاملات دستی
input bool            Inp_SetManualTP                = true;  // تنظیم TP برای معاملات دستی
input bool            Inp_IncludeManualInSequence    = true;  // شمارش معاملات دستی در سکانس

// LOCK + Logger
input bool            Inp_EnableLock                 = true;
input int             Inp_LockTTLSeconds             = 90;
input bool            Inp_LoggerA                    = true;
input bool            Inp_LogTradeTransactions       = true;

input bool           Inp_ShowManualNumbering = true;   // show numbering of manual open+pending trades in chart Comment()
// UI: Manual Refresh Button (top-right, purple)
input bool           Inp_EnableRefreshButton  = true;
input int            Inp_RefreshBtn_XDistance = 10;
input int            Inp_RefreshBtn_YDistance = 10;
input int            Inp_RefreshBtn_Width     = 120;
input int            Inp_RefreshBtn_Height    = 26;
input string         Inp_RefreshBtn_Text      = "REFRESH";
input bool           Inp_EnableRefreshPanel  = true;  // rectangle panel behind refresh button
input int            Inp_RefreshPanel_Padding = 6;    // pixels around button


//============================= Levels (HAB PEX 61) =============================//
// Exact level computation & drawing logic adapted from HAB PEX 61 (PivotLadder7).
// Objects are drawn with PREFIX "HAB_PEX_L7_" and tags S3,S2,S1,P,R1,R2,R3 (+ *_LBL).
input bool            Inp_LV_Enable                   = true;
input ENUM_TIMEFRAMES Inp_LV_ContextTF                = PERIOD_H1;   // Builder TF
input ENUM_TIMEFRAMES Inp_LV_FilterTF                 = PERIOD_M5;   // Scalp TF
input int             Inp_LV_ATRPeriod                = 14;

// Candidate sources (institutional)
input bool            Inp_LV_UsePrevDayHL             = true;        // D1[1] High/Low/Close
input bool            Inp_LV_UsePrevWeekHL            = true;        // W1[1] High/Low/Close
input bool            Inp_LV_UseQuarterHL             = true;        // ~90 D1 bars High/Low
input bool            Inp_LV_UseRound50               = true;        // Round 50 levels near price
input bool            Inp_LV_UseH4Swings              = true;        // H4 swing highs/lows
input int             Inp_LV_SwingLen                 = 3;
input int             Inp_LV_SwingLookbackH4Bars      = 300;

// Micro rounds (scalp usability, near price only)
input bool            Inp_LV_EnableMicroRounds        = true;
input int             Inp_LV_MicroRoundStep1_USD      = 10;          // 10 USD grid
input int             Inp_LV_MicroRoundStep2_USD      = 5;           // 5 USD grid
input int             Inp_LV_MicroRoundCountEachSide  = 2;           // +/- steps
input double          Inp_LV_MicroRoundMaxDist_ATR_M5  = 1.8;         // only include if within this * ATR(M5)

// H1 scoring (reaction quality)
input int             Inp_LV_LookbackH1Bars           = 600;
input double          Inp_LV_TouchBand_ATR_H1         = 0.12;
input int             Inp_LV_TouchBand_MinPoints      = 10;
input double          Inp_LV_MinReaction_ATR_H1       = 0.60;
input int             Inp_LV_MaxReactionBars_H1       = 3;
input double          Inp_LV_BodyMin_ATR_H1           = 0.30;
input int             Inp_LV_MinScore                = 65;           // scalp-friendly threshold

// Scalp filters (M5)
input double          Inp_LV_ScalpMaxDistancePct      = 0.008;        // 0.80% of price (7 levels)
input double          Inp_LV_ScalpMaxDistanceATR_M5   = 2.2;          // 2.2*ATR(M5)
input double          Inp_LV_ScalpMergePct            = 0.0015;       // 0.15% of price
input double          Inp_LV_ScalpMergeATR_M5         = 0.8;          // 0.8*ATR(M5)

// Visuals (minimal rectangles)
input bool            Inp_LV_DrawRectangles           = true;
input int             Inp_LV_RectAlpha                = 110;          // 0..255
input int             Inp_LV_LineWidth                = 2;
input double          Inp_LV_DrawWidth_ATR_M5          = 0.12;         // half-width = max(x*ATR(M5), min points)
input int             Inp_LV_DrawWidth_MinPoints      = 5;
input bool            Inp_LV_ShowLabels               = true;

// Pivot ladder behavior
input bool            Inp_LV_UsePivotLadder7          = true;         // enforce S3,S2,S1,P,R1,R2,R3
input color           Inp_LV_PivotColor               = clrGold;

// Diagnostics
input bool            Inp_LV_DebugPrint               = false;

//============================= Globals =============================//
string PREFIX      = "HAB_PEX_L7_";
string g_lockKey   = "";
string g_lockTsKey = "";

CTrade   trade;

int      g_atrHandle     = INVALID_HANDLE;
int      g_trendMAHandle = INVALID_HANDLE;
double   g_atrNow        = 0.0;
datetime g_lastAction    = 0;



double   g_startEquity = 0.0;
double   g_peakEquity  = 0.0;
bool     g_killSwitch  = false;
datetime g_killTime    = 0;
// ---- High-frequency governance (burst + loss cluster) ----
datetime g_pauseUntil = 0;           // master pause timestamp (blocks NEW entries only)
datetime g_burstPauseUntil = 0;      // burst-specific pause

// Store recent entry times (DEAL_ENTRY_IN). Fixed ring buffer.
datetime g_entryTimes[3000];
int      g_entryTimesCount = 0;

// Rolling performance window on closed trades (DEAL_ENTRY_OUT)
double   g_rollProfits[200];   // net profit per closed trade
int      g_rollCount = 0;
int      g_rollIdx   = 0;
int      g_consecLosses = 0;

// Cached TrendPermission decision (computed only on closed bar)
int      g_permDir        = 0;      // +1 ALLOW_BUY, -1 ALLOW_SELL, 0 NO_TRADE
datetime g_lastPermBarTime= 0;      // last processed closed bar time (ExecTF)

// Anchor state
bool   g_anchorActive = false;
ulong  g_anchorTicket = 0;
int    g_anchorDir    = 0; // 1 buy, -1 sell
double g_anchorLot    = 0.0;
double g_anchorEntry  = 0.0;

//============================= Trend/EMA Handles (Core + Overlay) =============================//
// Core TrendPermission handles (EMA200 + ATR14/ATR100 on M5)
int      g_emaHandle      = INVALID_HANDLE;
int      g_atr14Handle    = INVALID_HANDLE;
int      g_atr100Handle   = INVALID_HANDLE;

// EMA overlay (same TF as Exec by default; informational + optional gate for EA auto actions)
bool     g_emaOverlayReady = false;
int      g_ema20OHandle    = INVALID_HANDLE;
int      g_ema50OHandle    = INVALID_HANDLE;
int      g_ema100OHandle   = INVALID_HANDLE;
int      g_ema200OHandle   = INVALID_HANDLE;

// Cached overlay status for UI/comment
int      g_emaBullStatus   = 0; // 0=RED, 1=YELLOW(partial), 2=GREEN(full)
int      g_emaBearStatus   = 0; // 0=RED, 1=YELLOW(partial), 2=GREEN(full)
string   g_emaStatusText   = "";

// EMA regime (higher TF) filter for EA auto actions
bool     g_emaRegimeReady  = false;
int      g_emaReg100Handle = INVALID_HANDLE;
int      g_emaReg200Handle = INVALID_HANDLE;
int      g_regimeDir       = 0; // +1 bull, -1 bear, 0 neutral

//============================= Logger ==============================//
enum REASON_CODE
{
  RC_NONE=0,
  RC_LOCK_BUSY=1,
  RC_ENV_BLOCK=10,
  RC_NETTING_BLOCK=11,
  RC_SPREAD_BLOCK=20,
  RC_COOLDOWN_BLOCK=21,
  RC_ATR_SHOCK_BLOCK=30,
  RC_POSCAP_BLOCK=40,
  RC_PENDCAP_BLOCK=41,
  RC_LEVEL_TOO_FAR=50,
  RC_MINDIST_BLOCK=60,
  RC_STOPS_BLOCK=61,
  RC_INVALID_INPUT=62,
  RC_RISK_BLOCK=63,
  RC_RISK_DOWNSIZE=64,
  RC_RISK_HALTED=65,
  RC_LEVEL_MISSING=70,
  RC_MAX_PER_SIDE=80,
  RC_TP_LEVEL_FAIL=90,
  RC_PENDING_PLACED=100,
  RC_PENDING_FAILED=101,
  RC_PENDING_EXISTS=102,
  RC_PENDING_DELETED=103,
  RC_ANCHOR_DETECTED=200,
  RC_ANCHOR_RESET=201,
  RC_ANCHOR_TP_SET=210,
  RC_ANCHOR_TP_SKIP=211,
  RC_AUTO_NO_TREND=300,
  RC_AUTO_EXISTS=301,
  RC_AUTO_EXPIRED=302,
  RC_AUTO_TREND_FLIP=303,
  RC_AUTO_PZONE_BLOCK=304,
  RC_MANUAL_MODIFIED=400,
  RC_MANUAL_SKIP=401,
  RC_EMA_ALIGN_BLOCK=500,
  RC_EMA_ALIGN_WARN=501,
  RC_EMA_REGIME_BLOCK=502,
  RC_EMA_REGIME_WARN=503,
  RC_EMA_YELLOW_PASS=504,
  // --- Hybrid v1.014 additions ---
  RC_POS_CLOSED=610,
  RC_POS_CLOSE_FAIL=611
};

void LogA(const string stage, int dir, REASON_CODE code, const string msg, double v=0.0)
{
  if(!Inp_LoggerA) return;
  string sdir = (dir==1 ? "BUY" : (dir==-1 ? "SELL" : "NA"));
  PrintFormat("[HAB_L7][%s][%s][%d] %s | v=%.5f", stage, sdir, (int)code, msg, v);
}

//============================= Utils ===============================//
int DigitsSym() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }
double NPrice(const double p) { return NormalizeDouble(p, DigitsSym()); }

double Mid()
{
  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0) return 0.0;
  return (bid+ask)*0.5;
}

bool IsNettingAccount()
{
  long mm = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
  return (mm==ACCOUNT_MARGIN_MODE_RETAIL_NETTING || mm==ACCOUNT_MARGIN_MODE_EXCHANGE);
}

bool IsTradeEnvironmentOK()
{
  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
  { LogA("ENV", 0, RC_ENV_BLOCK, "TERMINAL_TRADE_ALLOWED=false"); return false; }

  if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
  { LogA("ENV", 0, RC_ENV_BLOCK, "ACCOUNT_TRADE_ALLOWED=false"); return false; }

  UpdateEquityKillSwitch();
  if(TradingHalted())
  { LogA("ENV", 0, RC_ENV_BLOCK, "Trading halted by equity kill-switch (Protected-NoSL)"); return false; }

  long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
  if(mode == SYMBOL_TRADE_MODE_DISABLED)
  { LogA("ENV", 0, RC_ENV_BLOCK, "SYMBOL_TRADE_MODE_DISABLED"); return false; }

  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0 || ask<=bid)
  { LogA("ENV", 0, RC_ENV_BLOCK, "Invalid bid/ask"); return false; }

  if(IsNettingAccount() && !Inp_AllowNetting)
  { LogA("ENV", 0, RC_NETTING_BLOCK, "Netting account detected => FAIL-CLOSED (Inp_AllowNetting=false)"); return false; }

  return true;
}

//==================== Risk Envelope (Protected-NoSL) ====================//
void UpdateEquityKillSwitch()
{
  if(!Inp_ProtectedNoSL) return;
  if(g_killSwitch) return;

  const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
  if(eq <= 0.0) return;

  if(g_startEquity <= 0.0) g_startEquity = eq;
  if(g_peakEquity  <= 0.0) g_peakEquity  = eq;

  if(eq > g_peakEquity) g_peakEquity = eq;

  if(Inp_MaxEquityDD_Percent <= 0.0) return;

  const double ddPct = (g_peakEquity - eq) / g_peakEquity * 100.0;
  if(ddPct >= Inp_MaxEquityDD_Percent)
  {
    g_killSwitch = true;
    g_killTime   = TimeCurrent();

    LogA("KILL", 0, RC_ENV_BLOCK,
         StringFormat("Equity kill-switch TRIGGERED: peak=%.2f eq=%.2f DD=%.2f%% >= %.2f%%",
                      g_peakEquity, eq, ddPct, Inp_MaxEquityDD_Percent),
         eq);

    // Fail-closed: stop all new actions and clean EA pendings
    if(Inp_DeleteEAPendingsWhenCapHit){ DeleteAllEAPendings_LadderOnly("KILL", 0, RC_PENDING_DELETED); DeleteAutoAnchorPending("kill-switch", RC_PENDING_DELETED); }

    if(Inp_CloseAllOnKill)
    {
      // Close all positions on this symbol (manual + EA). If any close fails, trading remains halted.
      for(int i=PositionsTotal()-1; i>=0; --i)
      {
        const ulong _ptk = PositionGetTicket(i);
        if(_ptk==0) continue;
        if(!PositionSelectByTicket(_ptk)) continue;
        const string sym = PositionGetString(POSITION_SYMBOL);
        if(sym != _Symbol) continue;

        const ulong  pt  = (ulong)PositionGetInteger(POSITION_TICKET);
        const int    typ = (int)PositionGetInteger(POSITION_TYPE);

        trade.SetExpertMagicNumber(Inp_MagicNumber);
        trade.SetDeviationInPoints(Inp_DeviationPoints);

        bool ok=false;
        if(typ==POSITION_TYPE_BUY)  ok = trade.PositionClose(pt);
        if(typ==POSITION_TYPE_SELL) ok = trade.PositionClose(pt);

        LogA("KILL", (typ==POSITION_TYPE_BUY?1:-1),
             ok?RC_POS_CLOSED:RC_POS_CLOSE_FAIL,
             StringFormat("Close on kill ticket=%I64u ret=%d (%s)",
                           pt, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()),
             (double)pt);
      }
    }
  }
}

bool TradingHalted()
{
  if(!Inp_ProtectedNoSL) return false;
  if(!g_killSwitch) return false;
  return true;
}

void EnforceTimeStop()
{
  if(Inp_TimeStopMinutes <= 0) return;

  const datetime now = TimeCurrent();

  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    const ulong _ptk = PositionGetTicket(i);
        if(_ptk==0) continue;
        if(!PositionSelectByTicket(_ptk)) continue;
    const string sym = PositionGetString(POSITION_SYMBOL);
    if(sym != _Symbol) continue;

    const datetime opent = (datetime)PositionGetInteger(POSITION_TIME);
    if(opent <= 0) continue;

    const int ageMin = (int)((now - opent) / 60);
    if(ageMin < Inp_TimeStopMinutes) continue;

    const ulong  pt  = (ulong)PositionGetInteger(POSITION_TICKET);
    const int    typ = (int)PositionGetInteger(POSITION_TYPE);

    trade.SetExpertMagicNumber(Inp_MagicNumber);
    trade.SetDeviationInPoints(Inp_DeviationPoints);

    bool ok=false;
    if(typ==POSITION_TYPE_BUY)  ok = trade.PositionClose(pt);
    if(typ==POSITION_TYPE_SELL) ok = trade.PositionClose(pt);

    LogA("TSTOP", (typ==POSITION_TYPE_BUY?1:-1),
         ok?RC_POS_CLOSED:RC_POS_CLOSE_FAIL,
         StringFormat("TimeStop close ticket=%I64u age=%dmin >= %dmin ret=%d (%s)",
                      pt, ageMin, Inp_TimeStopMinutes, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()),
         (double)pt);
  }
}


//==================== High-frequency Governance Helpers ====================//
double ATR14PointsLatest()
{
  // Uses existing ATR14 handle (M5). Returns 0 on failure.
  if(g_atr14Handle==INVALID_HANDLE) return 0.0;
  double a[1];
  if(CopyBuffer(g_atr14Handle, 0, 0, 1, a) != 1) return 0.0;
  if(a[0] <= 0.0 || _Point<=0.0) return 0.0;
  return (a[0] / _Point);
}

int DynamicMaxSpreadPoints()
{
  if(!Inp_UseDynamicSpreadGate) return Inp_MaxSpreadPoints;

  // Fail-safe: if ATR not available, fall back to static
  const double atrPts = ATR14PointsLatest();
  int dyn = Inp_MaxSpreadPoints;

  if(atrPts > 0.0)
  {
    const int byAtr = (int)MathFloor(Inp_SpreadATR14Ratio * atrPts + 0.5);
    dyn = MathMax(Inp_SpreadFloorPoints, byAtr);
  }
  else
  {
    dyn = MathMax(Inp_SpreadFloorPoints, Inp_MaxSpreadPoints);
  }

  // sanity
  if(dyn < 1) dyn = 1;
  if(dyn > 2000) dyn = 2000;
  return dyn;
}

void AddEntryTime(const datetime t)
{
  if(t<=0) return;
  const int cap = (int)ArraySize(g_entryTimes);
  if(cap<=0) return;

  if(g_entryTimesCount < cap)
  {
    g_entryTimes[g_entryTimesCount++] = t;
    return;
  }

  // shift left by 1 (cap is small enough and only used for governance)
  for(int i=1;i<cap;i++) g_entryTimes[i-1] = g_entryTimes[i];
  g_entryTimes[cap-1] = t;
  g_entryTimesCount = cap;
}

int CountEntriesSince(const int secondsLookback)
{
  if(secondsLookback<=0) return 0;
  const datetime now = TimeCurrent();
  const datetime t0  = now - secondsLookback;

  int cnt=0;
  for(int i=g_entryTimesCount-1; i>=0; i--)
  {
    if(g_entryTimes[i] < t0) break;
    cnt++;
  }
  return cnt;
}

double RollingProfitFactor()
{
  if(g_rollCount < 5) return 999.0; // not enough data => don't block
  double wins=0.0, losses=0.0;
  for(int i=0;i<g_rollCount;i++)
  {
    const double p = g_rollProfits[i];
    if(p>0.0) wins += p;
    else      losses += p;
  }
  if(losses >= 0.0) return 999.0;
  return (wins / MathAbs(losses));
}

void AddClosedTradeNetProfit(const double netp)
{
  const int cap = (int)ArraySize(g_rollProfits);
  if(cap<=0) return;

  if(g_rollCount < cap)
  {
    g_rollProfits[g_rollCount++] = netp;
  }
  else
  {
    g_rollProfits[g_rollIdx] = netp;
    g_rollIdx++;
    if(g_rollIdx >= cap) g_rollIdx = 0;
  }

  if(netp < 0.0) g_consecLosses++;
  else           g_consecLosses = 0;

  // Apply pause rules
  const datetime now = TimeCurrent();
  if(Inp_EnableLossClusterPause)
  {
    if(g_consecLosses >= Inp_PauseAfterConsecLosses)
    {
      g_pauseUntil = MathMax(g_pauseUntil, now + Inp_LossClusterPauseSeconds);
      LogA("RISK", 0, RC_RISK_HALTED, StringFormat("Loss-cluster pause: consecLoss=%d >= %d", g_consecLosses, Inp_PauseAfterConsecLosses), (double)g_consecLosses);
    }

    const double pf = RollingProfitFactor();
    if(pf < Inp_MinRollingProfitFactor)
    {
      g_pauseUntil = MathMax(g_pauseUntil, now + Inp_LowPFPauseSeconds);
      LogA("RISK", 0, RC_RISK_HALTED, StringFormat("Rolling PF pause: PF=%.2f < %.2f (N=%d)", pf, Inp_MinRollingProfitFactor, g_rollCount), pf);
    }
  }
}

bool EntryGovernanceOK()
{
  const datetime now = TimeCurrent();

  // Master pauses (loss cluster + burst)
  if(now < g_pauseUntil)
  { LogA("GATE", 0, RC_COOLDOWN_BLOCK, StringFormat("Paused by risk governor until %s", TimeToString(g_pauseUntil, TIME_SECONDS))); return false; }

  if(now < g_burstPauseUntil)
  { LogA("GATE", 0, RC_COOLDOWN_BLOCK, StringFormat("Paused by burst control until %s", TimeToString(g_burstPauseUntil, TIME_SECONDS))); return false; }

  if(!Inp_EnableBurstControl) return true;

  const int c5  = CountEntriesSince(5*60);
  const int c15 = CountEntriesSince(15*60);

  if(c5 >= Inp_MaxEntriesPer5Min || c15 >= Inp_MaxEntriesPer15Min)
  {
    g_burstPauseUntil = now + Inp_BurstPauseSeconds;
    LogA("GATE", 0, RC_COOLDOWN_BLOCK, StringFormat("Burst hit: c5=%d/%d c15=%d/%d => pause %ds",
         c5, Inp_MaxEntriesPer5Min, c15, Inp_MaxEntriesPer15Min, Inp_BurstPauseSeconds));
    return false;
  }

  return true;
}


bool SpreadOK()
{
  const long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  if(sp<=0) return false;
  const int maxSp = DynamicMaxSpreadPoints();
  const bool ok = (sp <= maxSp);
  if(!ok) LogA("GATE", 0, RC_SPREAD_BLOCK, StringFormat("Spread=%d > Max=%d", (int)sp, maxSp), (double)sp);
  return ok;
}

bool CooldownOK()
{
  const long dt = (long)(TimeCurrent() - g_lastAction);
  const bool ok = (dt >= Inp_CooldownSeconds);
  if(!ok) LogA("GATE", 0, RC_COOLDOWN_BLOCK, "Cooldown active", (double)dt);
  return ok;
}

void StampActionTime() { g_lastAction = TimeCurrent(); }


//---------------- Lot normalize ----------------//
double NormalizeLot(double lot)
{
  const double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  const double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if(step <= 0.0) step = 0.01;

  lot = MathMax(lot, minLot);
  lot = MathMin(lot, maxLot);

  lot = MathFloor((lot/step) + 0.5) * step;
  lot = NormalizeDouble(lot, 8);

  if(lot < minLot) lot = minLot;
  if(lot > maxLot) lot = maxLot;
  return lot;
}

//==================== Pip/Point conversion (fail-closed) ====================//
// MT5 symbols differ by DIGITS. For common FX-style quoting (5/3 digits), 1 pip = 10 points.
// For 2/4 digits (or metals with 2 digits), 1 pip is typically 1 point.
// We keep this conservative and transparent: if result is non-positive, caller must NO TRADE.
int PipsToPointsSafe(const int pips)
{
  if(pips<=0) return 0;

  const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  int mul = 1;

  // Common convention: 5-digit or 3-digit symbols have fractional pip -> 10 points per pip.
  if(digits==5 || digits==3) mul = 10;
  else                      mul = 1;

  long pts = (long)pips * (long)mul;
  if(pts<=0) return 0;
  if(pts>2000000) return 0; // sanity cap
  return (int)pts;
}

//==================== Monetary risk per lot (for SL distance) ====================//
double ValuePerPointPerLot()
{
  const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
  const double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

  if(tickValue<=0.0 || tickSize<=0.0 || _Point<=0.0) return 0.0;

  // value per 1 point (price step=_Point) for 1.0 lot
  return tickValue * (_Point / tickSize);
}

double CalcLotForRisk(const double riskPct, const int slPoints)
{
  if(riskPct<=0.0 || slPoints<=0) return 0.0;

  const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
  if(eq<=0.0) return 0.0;

  const double vpp = ValuePerPointPerLot();
  if(vpp<=0.0) return 0.0;

  const double riskMoney = eq * (riskPct/100.0);
  const double denom = (double)slPoints * vpp;
  if(denom<=0.0) return 0.0;

  double lot = riskMoney / denom;
  return NormalizeLot(lot);
}

double CalcRiskPctForLot(const double lot, const int slPoints)
{
  if(lot<=0.0 || slPoints<=0) return 0.0;

  const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
  if(eq<=0.0) return 0.0;

  const double vpp = ValuePerPointPerLot();
  if(vpp<=0.0) return 0.0;

  const double riskMoney = lot * (double)slPoints * vpp;
  return 100.0 * riskMoney / eq;
}

double LotForTag(const string tag)
{
  if(tag=="S1" || tag=="R1") return NormalizeLot(Inp_Lot_S1R1);
  if(tag=="S2" || tag=="R2") return NormalizeLot(Inp_Lot_S2R2);
  return NormalizeLot(Inp_Lot_S3R3Plus);
}

//==================== Volume Sequencing (Updated v1.379) ====================//
bool IsPendingOrderType(const ENUM_ORDER_TYPE t)
{
  return (t==ORDER_TYPE_BUY_LIMIT  || t==ORDER_TYPE_SELL_LIMIT  ||
          t==ORDER_TYPE_BUY_STOP   || t==ORDER_TYPE_SELL_STOP   ||
          t==ORDER_TYPE_BUY_STOP_LIMIT || t==ORDER_TYPE_SELL_STOP_LIMIT);
}

int CountAllOpenPositionsSymbol()
{
  int n=0;
  for(int i=PositionsTotal()-1; i>=0; --i)
  {
    const ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(PositionGetString(POSITION_SYMBOL)==ManagedSymbol()) n++;
  }
  return n;
}

int CountAllPendingsSymbol()
{
  int n=0;
  for(int i=OrdersTotal()-1; i>=0; --i)
  {
    const ulong ticket = OrderGetTicket(i);
    if(ticket==0) continue;
    if(OrderGetString(ORDER_SYMBOL)!=ManagedSymbol()) continue;
    const ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(IsPendingOrderType(t)) n++;
  }
  return n;
}

int CountAllActiveTradesSymbol()
{
  return (CountAllOpenPositionsSymbol() + CountAllPendingsSymbol());
}

//=================== شماره سکانس برای معاملات دستی ===================//
int GetSequenceNumberForTicket(ulong targetTicket)
{
  struct TradeItem
  {
    ulong ticket;
    datetime time;
    bool isPending;
    long magic;
  };
  
  TradeItem items[];
  ArrayResize(items, 0);
  
  // جمع آوری معاملات باز
  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
    
    long magic = PositionGetInteger(POSITION_MAGIC);
    
    // اگر پارامتر IncludeManualInSequence خاموش باشد و magic=0 باشد، رد کن
    if(!Inp_IncludeManualInSequence && magic == 0) continue;
    
    int n = ArraySize(items);
    ArrayResize(items, n + 1);
    items[n].ticket = ticket;
    items[n].time = (datetime)PositionGetInteger(POSITION_TIME);
    items[n].isPending = false;
    items[n].magic = magic;
  }
  
  // جمع آوری پندینگ‌ها
  for(int i = OrdersTotal() - 1; i >= 0; i--)
  {
    ulong ticket = OrderGetTicket(i);
    if(ticket == 0) continue;
    if(!OrderSelect(ticket)) continue;
    if(OrderGetString(ORDER_SYMBOL) != ManagedSymbol()) continue;
    
    // فقط پندینگ‌های فعال
    ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(!IsPendingOrderType(ot)) continue;
    
    long magic = OrderGetInteger(ORDER_MAGIC);
    
    // اگر پارامتر IncludeManualInSequence خاموش باشد و magic=0 باشد، رد کن
    if(!Inp_IncludeManualInSequence && magic == 0) continue;
    
    int n = ArraySize(items);
    ArrayResize(items, n + 1);
    items[n].ticket = ticket;
    items[n].time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
    items[n].isPending = true;
    items[n].magic = magic;
  }
  
  // مرتب‌سازی بر اساس زمان (قدیمی‌ترین اول)
  for(int i = 0; i < ArraySize(items) - 1; i++)
  {
    for(int j = i + 1; j < ArraySize(items); j++)
    {
      if(items[j].time < items[i].time)
      {
        TradeItem tmp = items[i];
        items[i] = items[j];
        items[j] = tmp;
      }
    }
  }
  
  // پیدا کردن شماره سکانس
  for(int i = 0; i < ArraySize(items); i++)
  {
    if(items[i].ticket == targetTicket)
      return i + 1; // شماره سکانس از 1 شروع می‌شود
  }
  
  return 0; // پیدا نشد
}

//=================== محاسبه لات بر اساس سکانس ===================//
double EnforceSequenceLot(const double baseLot)
{
  if(!Inp_IncludeManualInSequence)
  {
    // فقط معاملات EA را بشمار
    int eaActive = CountEAOpenPositionsSymbol() + CountEAPendingsSymbol_AllTypes();
    int nextEaIndex = eaActive + 1;
    
    if(nextEaIndex > 4) return 0.0;
    
    double lot = 0.0;
    if(nextEaIndex == 1) lot = 0.02;
    else if(nextEaIndex == 2) lot = 0.05;
    else if(nextEaIndex == 3 || nextEaIndex == 4) lot = 0.10;
    
    return NormalizeLot(lot);
  }
  else
  {
    // محاسبه قبلی (شامل همه معاملات)
    const int totalActive = CountAllActiveTradesSymbol();
    const int nextIndex   = totalActive + 1;
    
    if(totalActive >= 4) return 0.0;
    
    double lot = 0.0;
    if(nextIndex == 1) lot = 0.02;
    else if(nextIndex == 2) lot = 0.05;
    else if(nextIndex == 3 || nextIndex == 4) lot = 0.10;
    
    return NormalizeLot(lot);
  }
}

//---------------- Stops/Frozen distance guards ----------------//
int StopLevelPoints()   { return (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); }
int FreezeLevelPoints() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL); }

bool ValidateStopsDistances(const ENUM_ORDER_TYPE pendingType, const double price, const double sl, const double tp)
{
  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0) return false;

  const int st = StopLevelPoints();
  const int fr = FreezeLevelPoints();
  const int minPts = MathMax(st, fr);

  if(minPts > 0)
  {
    if(sl > 0.0)
    {
      const double dpts = MathAbs(price - sl) / _Point;
      if(dpts < (double)minPts) return false;
    }
    if(tp > 0.0)
    {
      const double dpts = MathAbs(price - tp) / _Point;
      if(dpts < (double)minPts) return false;
    }

    if(pendingType == ORDER_TYPE_BUY_LIMIT)  if((bid - price)/_Point < (double)minPts) return false;
    if(pendingType == ORDER_TYPE_SELL_LIMIT) if((price - ask)/_Point < (double)minPts) return false;
    if(pendingType == ORDER_TYPE_BUY_STOP)   if((price - ask)/_Point < (double)minPts) return false;
    if(pendingType == ORDER_TYPE_SELL_STOP)  if((bid - price)/_Point < (double)minPts) return false;
  }
  return true;
}

//============================= ATR ================================//
bool EnsureATRHandle()
{
  if(!(Inp_UseATR_SLTP || Inp_EnableATRShock || Inp_EnableAutoAnchor || Inp_UseStructuralTP)) return true;
  if(g_atrHandle != INVALID_HANDLE) return true;

  g_atrHandle = iATR(_Symbol, Inp_ATR_TF, Inp_ATRPeriod);
  if(g_atrHandle == INVALID_HANDLE)
  { LogA("ATR", 0, RC_ENV_BLOCK, "Failed to create ATR handle"); return false; }
  return true;
}

bool UpdateATRNow()
{
  g_atrNow = 0.0;

  if(!(Inp_UseATR_SLTP || Inp_EnableATRShock || Inp_EnableAutoAnchor || Inp_UseStructuralTP))
    return true;

  if(g_atrHandle == INVALID_HANDLE) return false;

  double b[];
  ArrayResize(b, 1);
  ArraySetAsSeries(b, true);

  if(CopyBuffer(g_atrHandle, 0, 1, 1, b) != 1) return false;
  if(b[0] <= 0.0) return false;

  g_atrNow = b[0];
  return true;
}

double ATRMedian(const int lookback, bool &ok)
{
  ok=false;
  if(g_atrHandle == INVALID_HANDLE) return 0.0;
  if(lookback < 3) { ok=(g_atrNow>0.0); return g_atrNow; }

  double b[];
  ArrayResize(b, lookback);
  ArraySetAsSeries(b, true);

  const int got = CopyBuffer(g_atrHandle, 0, 1, lookback, b);
  if(got < 3) return 0.0;

  // copy to temp (non-series) then sort ascending
  double t[];
  ArrayResize(t, got);
  for(int i=0;i<got;i++) t[i]=b[i];
  ArraySort(t);

  const int mid = got/2;
  double med = 0.0;
  if((got % 2)==1) med = t[mid];
  else             med = 0.5*(t[mid-1]+t[mid]);

  ok = (med>0.0);
  return med;
}

bool ATRShockActive()
{
  if(!Inp_EnableATRShock) return false;
  if(g_atrNow<=0.0) return false;

  bool ok=false;
  const double baseline = ATRMedian(Inp_ATRShockLookback, ok);
  if(!ok || baseline<=0.0)
  {
    if(Inp_ATRShockFailClosed)
    {
      LogA("GATE", 0, RC_ATR_SHOCK_BLOCK,
           StringFormat("ATR shock baseline unavailable (lookback=%d) => FAIL-CLOSED", Inp_ATRShockLookback),
           g_atrNow);
      return true; // block trading until baseline exists
    }
    return false;
  }

  const bool shock = (g_atrNow > baseline * Inp_ATRShockFactor);
  if(shock) LogA("GATE", 0, RC_ATR_SHOCK_BLOCK,
                 StringFormat("ATR shock: now=%.5f median=%.5f factor=%.2f", g_atrNow, baseline, Inp_ATRShockFactor),
                 g_atrNow);
  return shock;
}

bool LevelTooFarFromMarket(const double level)
{
  if(g_atrNow<=0.0) return false;
  const double m = Mid();
  if(m<=0.0) return false;

  const bool far = (MathAbs(level - m) > Inp_MaxLevelDist_ATR * g_atrNow);
  if(far) LogA("GATE", 0, RC_LEVEL_TOO_FAR, "Level too far from market (anti-stale)", level);
  return far;
}

//==================== Positions / Orders Count =====================//
int CountOpenPositionsSymbol()
{
  int c=0;
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
    ulong ticket=PositionGetTicket(i);
    if(ticket>0 && PositionSelectByTicket(ticket))
      if(PositionGetString(POSITION_SYMBOL)==ManagedSymbol()) c++;
  }
  return c;
}

int CountEAOpenPositionsSymbol()
{
  int c=0;
  for(int i=PositionsTotal()-1;i>=0;i--)
  {
    ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;
    if(PositionGetString(POSITION_SYMBOL)!=ManagedSymbol()) continue;

    const long mg = PositionGetInteger(POSITION_MAGIC);
    if((ulong)mg==Inp_MagicNumber) c++;
  }
  return c;
}

int CountEAPendingsSymbol_AllTypes()
{
  int c=0;
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)==ManagedSymbol() && (ulong)OrderGetInteger(ORDER_MAGIC)==Inp_MagicNumber)
    {
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_SELL_LIMIT ||
         ot==ORDER_TYPE_BUY_STOP  || ot==ORDER_TYPE_SELL_STOP)
        c++;
    }
  }
  return c;
}

bool PositionsCapOK()
{
  // v1.379: Total Cap includes Manual + EA
  const int openPos = CountAllActiveTradesSymbol();
  const bool ok = (openPos < 4);
  if(!ok) LogA("CAP", 0, RC_POSCAP_BLOCK, StringFormat("Total Cap Hit (Manual+EA)=%d max=4", openPos), (double)openPos);
  return ok;
}

bool PendingCapOKForNew()
{
  const int eaPend = CountEAPendingsSymbol_AllTypes();
  const bool ok = (eaPend < Inp_MaxEAPendings);
  if(!ok) LogA("CAP", 0, RC_PENDCAP_BLOCK, StringFormat("EA pending cap hit pend=%d cap=%d", eaPend, Inp_MaxEAPendings), (double)eaPend);
  return ok;
}

//==================== Read levels/zonelines from objects ============//
bool GetObjDouble(const long chartId, const string name, const ENUM_OBJECT_PROPERTY_DOUBLE prop, const int index, double &out)
{
  if(ObjectFind(chartId, name) < 0) return false;
  return ObjectGetDouble(chartId, name, prop, index, out);
}

bool ReadLevelMid(const string tag, double &outPrice)
{
  const string name = PREFIX + tag;
  const long chartId = 0;

  if(ObjectFind(chartId,name) < 0) return false;

  long type=0; if(!ObjectGetInteger(chartId,name,OBJPROP_TYPE,0,type)) return false;

  if(type == OBJ_RECTANGLE)
  {
    double p1=0.0,p2=0.0;
    if(!GetObjDouble(chartId, name, OBJPROP_PRICE, 0, p1)) return false;
    if(!GetObjDouble(chartId, name, OBJPROP_PRICE, 1, p2)) return false;
    if(p1<=0 || p2<=0) return false;
    outPrice = NPrice((p1+p2)*0.5);
    return true;
  }

  if(type == OBJ_HLINE)
  {
    double p=0.0;
    if(!GetObjDouble(chartId, name, OBJPROP_PRICE, 0, p)) return false;
    if(p<=0) return false;
    outPrice = NPrice(p);
    return true;
  }

  double p=0.0;
  if(GetObjDouble(chartId, name, OBJPROP_PRICE, 0, p) && p>0.0)
  {
    outPrice=NPrice(p);
    return true;
  }

  return false;
}

bool ReadLevelMidWithFB(const string tag, const string fbTag, double &outPrice)
{
  if(ReadLevelMid(tag, outPrice)) return true;
  if(fbTag!="" && ReadLevelMid(fbTag, outPrice)) return true;
  return false;
}

// EDGE-AWARE: returns zone low/high (rectangle), or line treated as low=high
bool ReadZoneOrLine(const string tag, double &zLow, double &zHigh, bool &isZone)
{
  isZone=false;
  zLow=0.0; zHigh=0.0;

  const string name = PREFIX + tag;
  const long chartId = 0;

  if(ObjectFind(chartId,name) < 0) return false;

  long type=0; if(!ObjectGetInteger(chartId,name,OBJPROP_TYPE,0,type)) return false;

  if(type == OBJ_RECTANGLE)
  {
    double p1=0.0,p2=0.0;
    if(!GetObjDouble(chartId, name, OBJPROP_PRICE, 0, p1)) return false;
    if(!GetObjDouble(chartId, name, OBJPROP_PRICE, 1, p2)) return false;
    if(p1<=0 || p2<=0) return false;

    zLow  = NPrice(MathMin(p1,p2));
    zHigh = NPrice(MathMax(p1,p2));
    isZone=true;
    return true;
  }

  double p=0.0;
  if(GetObjDouble(chartId, name, OBJPROP_PRICE, 0, p) && p>0.0)
  {
    zLow=NPrice(p);
    zHigh=NPrice(p);
    isZone=false;
    return true;
  }

  return false;
}

bool ReadZoneOrLineWithFB(const string tag, const string fbTag, double &zLow, double &zHigh, bool &isZone)
{
  if(ReadZoneOrLine(tag, zLow, zHigh, isZone)) return true;
  if(fbTag!="" && ReadZoneOrLine(fbTag, zLow, zHigh, isZone)) return true;
  return false;
}

//==================== Pivot(P) Zone helpers (FIXED $) ===============//
bool ReadPivotP(double &Pcenter)
{
  double zl=0.0, zh=0.0; bool isZ=false;
  if(ReadZoneOrLineWithFB("P","P_FB",zl,zh,isZ))
  {
    Pcenter = NPrice((zl+zh)*0.5);
    return true;
  }
  return false;
}

double PZoneHalfWidthPrice()
{
  double w = Inp_PZone_HalfWidth_Dollars;
  if(w < 0.0) w = 0.0;
  return w;
}

bool IsInsidePZone(const double price, const double P)
{
  const double w = PZoneHalfWidthPrice();
  return (price >= (P - w) && price <= (P + w));
}

double ClampToPZone(const double price, const double P)
{
  const double w = PZoneHalfWidthPrice();
  const double lo = P - w;
  const double hi = P + w;
  if(price < lo) return lo;
  if(price > hi) return hi;
  return price;
}

//==================== Structural TP (EDGE-based, ALL trades) ========//
bool ComputeStructuralTP_EdgeBased(const int dir, const double entry, double &tpOut, double &edgeRefOut, string &tagOut)
{
  tpOut=0.0; edgeRefOut=0.0; tagOut="";
  if(dir!=1 && dir!=-1) return false;

  string tags[] = {"P","R1","R2","R3","S1","S2","S3"};
  string fbs[]  = {"P_FB","R1_FB","R2_FB","R3_FB","S1_FB","S2_FB","S3_FB"};

  double bestRef=0.0;
  double bestLow=0.0, bestHigh=0.0;
  bool   found=false;
  string bestTag="";

  for(int i=0;i<ArraySize(tags);i++)
  {
    double zl=0.0, zh=0.0; bool isZ=false;
    if(!ReadZoneOrLineWithFB(tags[i], fbs[i], zl, zh, isZ)) continue;

    double ref = (dir==1 ? zl : zh);

    if(dir==1)
    {
      if(ref <= entry) continue;
      if(!found || ref < bestRef)
      {
        found=true; bestRef=ref;
        bestLow=zl; bestHigh=zh;
        bestTag=tags[i];
      }
    }
    else
    {
      if(ref >= entry) continue;
      if(!found || ref > bestRef)
      {
        found=true; bestRef=ref;
        bestLow=zl; bestHigh=zh;
        bestTag=tags[i];
      }
    }
  }

  if(!found) return false;

  const double buf  = (double)MathMax(0, Inp_TP_LevelBufferPoints) * _Point;
  const double minp = (double)MathMax(0, Inp_TP_MinProfitPoints) * _Point;

  double tp=0.0;
  if(dir==1)
  {
    tp = bestLow - buf;
    if(tp <= entry + minp) return false;
    edgeRefOut = bestLow;
  }
  else
  {
    tp = bestHigh + buf;
    if(tp >= entry - minp) return false;
    edgeRefOut = bestHigh;
  }

  tpOut = NPrice(tp);
  tagOut = bestTag;
  return true;
}

//====================== SL computation + TP selection (v1.379) ===============//
void ComputeSL_AndTP(const int dir, const double entry, double &sl, double &tp, double &edgeRef, string &tpTag)
{
  sl=0.0; tp=0.0; edgeRef=0.0; tpTag="";

  // --- v1.379: Sequence-based SL Logic ---
  const int totalActive = CountAllActiveTradesSymbol();
  const int nextIndex   = totalActive + 1; 

  double slDistPts = 0.0; // In Pips (Standard 10 points for 5 digit broker)

  if(nextIndex == 1) slDistPts = 300.0;      // Trade 1: 300 Pips
  else if(nextIndex == 2) slDistPts = 200.0; // Trade 2: 200 Pips
  else slDistPts = 100.0;                    // Trade 3 & 4: 100 Pips

  double slVal = slDistPts * 10.0 * _Point; // Convert Pips to Price

  if(dir==1) sl = entry - slVal;
  else      sl = entry + slVal;
  
  sl = NPrice(sl);

  // Protected-NoSL: replace tight SL with catastrophic stop (risk envelope). TP logic remains structural/edge-based.
  if(Inp_ProtectedNoSL)
  {
    double cat=0.0;

    // hard minimum catastrophic SL
    if(Inp_CatastrophicSL_Points>0) cat = Inp_CatastrophicSL_Points * _Point;

    // ATR-based catastrophic SL (preferred)
    double atr=0.0;
    if(g_atrHandle!=INVALID_HANDLE)
    {
      double a[1];
      if(CopyBuffer(g_atrHandle, 0, 0, 1, a)==1 && a[0]>0.0) atr=a[0];
    }
    if(atr>0.0 && Inp_CatastrophicSL_ATRMult>0.0)
    {
      const double byAtr = atr * Inp_CatastrophicSL_ATRMult;
      if(byAtr>cat) cat=byAtr;
    }

    if(cat>0.0)
    {
      if(dir==1) sl = entry - cat;
      else      sl = entry + cat;
      sl = NPrice(sl);
    }
    else
    {
      // If no catastrophic distance can be computed, fail-closed: keep original SL (do not disable protection silently)
      LogA("PNOSL", dir, RC_ENV_BLOCK, "ProtectedNoSL enabled but catastrophic SL distance is zero -> keeping computed SL", entry);
    }
  }

  if(!Inp_UseStructuralTP) return;

  double t=0.0, edge=0.0; string ttag="";
  if(ComputeStructuralTP_EdgeBased(dir, entry, t, edge, ttag))
  {
    tp=t; edgeRef=edge; tpTag=ttag;
    return;
  }
  // fail-closed: TP stays 0.0
}

// ✅ AutoAnchor SLTP: TP + SL (SL overridden for Trade 1)
void ComputeAutoAnchor_SLTP(const int dir, const double entry, double &sl, double &tp, double &edgeRef, string &tpTag)
{
  sl=0.0; tp=0.0; edgeRef=0.0; tpTag="";

  // Structural TP is optional in this EA, but if Inp_UseStructuralTP is enabled we fail-closed on missing edge.
  if(Inp_UseStructuralTP)
  {
    double t=0.0, edge=0.0; string ttag="";
    if(!ComputeStructuralTP_EdgeBased(dir, entry, t, edge, ttag))
      return;
    tp=t; edgeRef=edge; tpTag=ttag;
  }

  // AutoAnchor is a MARKET THERMOMETER: SL is FIXED in pips (user-defined, default 300).
  const int slPts = PipsToPointsSafe(Inp_AutoAnchorSL_Pips);
  if(slPts<=0)
  {
    LogA("AUTO", dir, RC_INVALID_INPUT, "Invalid SL pips conversion => no AutoAnchor", entry);
    return;
  }

  const double slVal = (double)slPts * _Point;
  if(dir==+1) sl = entry - slVal;
  else        sl = entry + slVal;

  sl = NPrice(sl);
}

//=================== SLTP modify by POSITION TICKET =================//
bool ModifyPositionSLTP_ByTicket(const ulong posTicket, const double sl, const double tp)
{
  if(posTicket==0) return false;

  const string sym = (Inp_ManagedSymbol!="" ? Inp_ManagedSymbol : _Symbol);
  // HARD SAFETY: never touch positions from other symbols.
  if(!PositionSelectByTicket(posTicket)) return false;
  if(PositionGetString(POSITION_SYMBOL)!=sym) return false;

  MqlTradeRequest req; ZeroMemory(req);
  MqlTradeResult  res; ZeroMemory(res);

  req.action   = TRADE_ACTION_SLTP;
  req.position = posTicket;
  req.symbol   = sym;
  req.sl       = sl;
  req.tp       = tp;

  const bool ok = OrderSend(req,res);
  if(!ok)
  { LogA("SLTP", 0, RC_ENV_BLOCK, StringFormat("OrderSend SLTP failed ret=%d", (int)res.retcode)); return false; }

  return (res.retcode==10009 || res.retcode==10008);
}

//=================== Order / Pending Management ====================//
bool DeleteOrderByTicket(const ulong ticket)
{
  if(ticket==0) return false;

  // HARD SAFETY: ensure selected order belongs to managed symbol before removal.
  const string sym = ManagedSymbol();
  if(OrderSelect(ticket))
  {
    if(OrderGetString(ORDER_SYMBOL)!=sym) return false;
  }

  MqlTradeRequest req; ZeroMemory(req);
  MqlTradeResult  res; ZeroMemory(res);

  req.action = TRADE_ACTION_REMOVE;
  req.order  = ticket;
  req.symbol = sym;

  const bool ok = OrderSend(req,res);
  if(!ok) LogA("DEL", 0, RC_PENDING_FAILED, StringFormat("Delete FAIL ticket=%I64u ret=%d", ticket, (int)res.retcode), (double)ticket);
  return ok;
}

void DeleteAllEAPendings_LadderOnly(const string stage, int dir, REASON_CODE code)
{
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)==ManagedSymbol() && (ulong)OrderGetInteger(ORDER_MAGIC)==Inp_MagicNumber)
    {
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==ORDER_TYPE_BUY_LIMIT || ot==ORDER_TYPE_SELL_LIMIT)
      {
        if(DeleteOrderByTicket(ticket))
          LogA(stage, dir, code, StringFormat("Deleted ladder pending ticket=%I64u", ticket), 0.0);
      }
    }
  }
}


// HARD RULE: delete ALL pending orders on symbol (EA + manual, any magic) when Anchor closes
void DeleteAllPendings_Symbol_AllOwners(const string stage, int dir, REASON_CODE code)
{
  for(int i=OrdersTotal()-1; i>=0; --i)
  {
    const ulong ticket = OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)!=ManagedSymbol()) continue;

    const ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(!IsPendingOrderType(ot)) continue;

    if(DeleteOrderByTicket(ticket))
      LogA(stage, dir, code, StringFormat("Deleted PENDING (all owners) ticket=%I64u type=%d magic=%I64u",
                                          ticket, (int)ot, (ulong)OrderGetInteger(ORDER_MAGIC)),
           0.0);
  }
}

void DeleteAutoAnchorPending(const string why, REASON_CODE code)
{
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)!=ManagedSymbol()) continue;

    ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(!(ot==ORDER_TYPE_BUY_STOP || ot==ORDER_TYPE_SELL_STOP)) continue;

    if((ulong)OrderGetInteger(ORDER_MAGIC)!=Inp_MagicNumber) continue;

    string cmt=OrderGetString(ORDER_COMMENT);
    if(StringFind(cmt,"HAB_AUTO_ANCHOR")!=0) continue;

    if(DeleteOrderByTicket(ticket))
      LogA("AUTO", 0, code, StringFormat("AutoAnchor deleted (%s) ticket=%I64u", why, ticket), 0.0);
  }
}

int CountPendings(const ENUM_ORDER_TYPE t)
{
  int c=0;
  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)==ManagedSymbol() && (ulong)OrderGetInteger(ORDER_MAGIC)==Inp_MagicNumber)
    {
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot==t) c++;
    }
  }
  return c;
}

bool FindPendingByTag(const string tag, ulong &orderTicket, double &orderPrice, ENUM_ORDER_TYPE &ot, double &orderVol)
{
  const string want = "HAB_PEX_L7@" + tag;

  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    const ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)==ManagedSymbol() && (ulong)OrderGetInteger(ORDER_MAGIC)==Inp_MagicNumber)
    {
      const string cmt = OrderGetString(ORDER_COMMENT);
      if(cmt == want)
      {
        ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        orderTicket = ticket;
        orderPrice  = OrderGetDouble(ORDER_PRICE_OPEN);
        orderVol    = OrderGetDouble(ORDER_VOLUME_CURRENT);
        return true;
      }
    }
  }
  return false;
}

bool HasAutoAnchorPending(ulong &ticketOut, int &dirOut, datetime &setupOut)
{
  ticketOut=0; dirOut=0; setupOut=0;

  for(int i=OrdersTotal()-1;i>=0;i--)
  {
    ulong ticket=OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    if(OrderGetString(ORDER_SYMBOL)!=ManagedSymbol()) continue;
    if((ulong)OrderGetInteger(ORDER_MAGIC)!=Inp_MagicNumber) continue;

    string cmt=OrderGetString(ORDER_COMMENT);
    if(StringFind(cmt,"HAB_AUTO_ANCHOR")!=0) continue;

    ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
    if(ot==ORDER_TYPE_BUY_STOP){ dirOut=+1; }
    else if(ot==ORDER_TYPE_SELL_STOP){ dirOut=-1; }
    else continue;

    ticketOut=ticket;
    setupOut=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
    return true;
  }
  return false;
}

bool EntryFarEnoughForStop(const int dir, const double entry)
{
  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0) return false;

  double distPts = 0.0;
  if(dir==+1) distPts = (entry - ask) / _Point;
  else        distPts = (bid - entry) / _Point;

  if(distPts < (double)Inp_MinDist_Points)
  { LogA("AUTO", dir, RC_MINDIST_BLOCK, "AutoAnchor entry too close to market", distPts); return false; }

  return true;
}

bool PlaceAutoAnchorStop(const int dir, const double entry, const double sl, const double tp, const double tpEdgeRef, const string tpTag)
{
  if(!IsTradeEnvironmentOK()) return false;
  if(!PositionsCapOK()) return false;
  if(!PendingCapOKForNew()) return false;
  if(!SpreadOK()) return false;
  if(!CooldownOK()) return false;
  if(!EntryFarEnoughForStop(dir, entry)) return false;

  trade.SetExpertMagicNumber(Inp_MagicNumber);
  trade.SetDeviationInPoints(Inp_DeviationPoints);

  const ENUM_ORDER_TYPE ot = (dir==+1)? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
  if(!ValidateStopsDistances(ot, entry, sl, tp))
  { LogA("AUTO", dir, RC_STOPS_BLOCK, "Stops/Freeze blocked", entry); return false; }

  // AutoAnchor SL is fixed. Enforce monetary risk safety.
  const int slPts = (int)MathRound(MathAbs(entry - sl) / _Point);
  if(slPts<=0)
  { LogA("AUTO", dir, RC_INVALID_INPUT, "Invalid SL distance => no AutoAnchor", entry); return false; }

  double lot = NormalizeLot(Inp_AutoAnchorLot);
  lot = EnforceSequenceLot(lot);
  if(lot<=0.0)
  { LogA("AUTO", dir, RC_POSCAP_BLOCK, "Total active trades cap (manual+EA) reached or invalid lot by sequence", entry); return false; }

  const double riskNow = CalcRiskPctForLot(lot, slPts);
  if(Inp_AutoAnchorMaxRiskPct>0.0 && riskNow>Inp_AutoAnchorMaxRiskPct+1e-9)
  {
    if(Inp_AutoAnchorDownsizeToMaxRisk)
    {
      double adj = CalcLotForRisk(Inp_AutoAnchorMaxRiskPct, slPts);
      if(adj<=0.0)
      { LogA("AUTO", dir, RC_RISK_BLOCK, "Risk cap hit and cannot downsize => no AutoAnchor", entry); return false; }

      // Ensure not increasing size by rounding
      if(adj>lot) adj=lot;

      LogA("AUTO", dir, RC_RISK_DOWNSIZE,
           StringFormat("AutoAnchor lot downsized %.3f -> %.3f to respect maxRisk=%.2f%% (SLpts=%d)",
                        lot, adj, Inp_AutoAnchorMaxRiskPct, slPts),
           entry);
      lot=adj;

      // final check
      const double r2 = CalcRiskPctForLot(lot, slPts);
      if(r2>Inp_AutoAnchorMaxRiskPct+1e-9)
      { LogA("AUTO", dir, RC_RISK_BLOCK, "Downsized lot still exceeds maxRisk => no AutoAnchor", entry); return false; }
    }
    else
    {
      LogA("AUTO", dir, RC_RISK_BLOCK,
           StringFormat("AutoAnchor risk %.2f%% > maxRisk %.2f%% => blocked", riskNow, Inp_AutoAnchorMaxRiskPct),
           entry);
      return false;
    }
  }

  bool ok=false;

  if(dir==+1)
    ok = trade.BuyStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "HAB_AUTO_ANCHOR|EXP23");
  else
    ok = trade.SellStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "HAB_AUTO_ANCHOR|EXP23");

  if(ok)
  {
    g_lastAction = TimeCurrent();
    LogA("AUTO", dir, RC_PENDING_PLACED,
         StringFormat("AutoAnchor STOP placed entry=%.2f SL=%s TP=%.2f (TPedge=%.2f tag=%s)",
                      entry,
                      (sl>0.0 ? DoubleToString(sl,2) : "NONE"),
                      tp, tpEdgeRef, tpTag),
         entry);
  }
  else
  {
    LogA("AUTO", dir, RC_PENDING_FAILED,
         StringFormat("FAILED ret=%d (%s)", (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()),
         entry);
  }
  return ok;
}

bool PlaceLimit(const int dir, const double level, const string tag, double lot)
{
  if(!IsTradeEnvironmentOK()) return false;
  if(!PositionsCapOK()) return false;
  if(!PendingCapOKForNew()) return false;
  if(!SpreadOK()) return false;
  if(!CooldownOK()) return false;

  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0) return false;

  const double cur = (dir==1)? bid : ask;
  const double distPts = MathAbs(level - cur) / _Point;
  if(distPts < Inp_MinDist_Points)
  { LogA("PEND", dir, RC_MINDIST_BLOCK, StringFormat("Too close: %.0f pts < %d", distPts, Inp_MinDist_Points), distPts); return false; }

  lot = NormalizeLot(lot);
  lot = EnforceSequenceLot(lot);
  if(lot<=0.0)
  {
    LogA("PEND", dir, RC_POSCAP_BLOCK, "Total active trades cap (manual+EA) reached or invalid lot by sequence", level);
    return false;
  }
  double sl=0.0,tp=0.0,tpEdge=0.0; string tpTag="";
  ComputeSL_AndTP(dir, level, sl, tp, tpEdge, tpTag);

  if(Inp_UseStructuralTP && tp<=0.0)
  { LogA("PEND", dir, RC_TP_LEVEL_FAIL, StringFormat("TP missing (edge-based) for tag=%s => fail-closed", tag), level); return false; }

  const ENUM_ORDER_TYPE pendingType = (dir==1)? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
  if(!ValidateStopsDistances(pendingType, level, sl, tp))
  { LogA("PEND", dir, RC_STOPS_BLOCK, "Stops/Freeze blocked", level); return false; }

  trade.SetExpertMagicNumber(Inp_MagicNumber);
  trade.SetDeviationInPoints(Inp_DeviationPoints);

  const string cmt="HAB_PEX_L7@" + tag;
  bool ok=false;

  if(dir==1)
    ok = trade.BuyLimit(lot, level, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
  else
    ok = trade.SellLimit(lot, level, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);

  if(ok)
  {
    g_lastAction = TimeCurrent();
    LogA("PEND", dir, RC_PENDING_PLACED,
         StringFormat("Placed %s lot=%.2f @ %.2f SL=%.2f TP=%.2f (TPedge=%.2f TPtag=%s)",
                      tag, lot, level, sl, tp, tpEdge, tpTag),
         level);
  }
  else
  {
    LogA("PEND", dir, RC_PENDING_FAILED,
         StringFormat("FAILED ret=%d (%s)", (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()),
         level);
  }
  return ok;
}

//======================== Pending Sync (ladder) =====================//
void SyncPendingToLevel(const string tag, const double level, const ENUM_ORDER_TYPE expectedType, double expectedLot)
{
  ulong ticket=0;
  double op=0, ov=0;
  ENUM_ORDER_TYPE ot=expectedType;

  if(FindPendingByTag(tag, ticket, op, ot, ov))
  {
    if(ot != expectedType)
    {
      DeleteOrderByTicket(ticket);
      g_lastAction = TimeCurrent();
      LogA("SYNC", 0, RC_PENDING_DELETED, "Wrong type -> deleted", op);
      return;
    }

    const double shiftPts = MathAbs(op - level) / _Point;
    const bool levelMoved = (shiftPts >= Inp_LevelShift_TolPts);

    expectedLot = NormalizeLot(expectedLot);
    ov = NormalizeLot(ov);
    const bool volMismatch = (MathAbs(ov - expectedLot) > 1e-10);

    if(levelMoved || volMismatch)
    {
      DeleteOrderByTicket(ticket);
      g_lastAction = TimeCurrent();
      LogA("SYNC", 0, RC_PENDING_DELETED,
           StringFormat("Resync delete: moved=%s(%.0fpts) volMismatch=%s",
                        (levelMoved?"Y":"N"), shiftPts, (volMismatch?"Y":"N")),
           op);
    }
  }
}

void EnsurePending(const int dir, const string tag, const string fbTag)
{
  if(!PendingCapOKForNew()) return;

  double lvl=0.0;
  bool ok = ReadLevelMidWithFB(tag, fbTag, lvl);
  if(!ok)
  { LogA("LEVEL", dir, RC_LEVEL_MISSING, StringFormat("Missing level tag=%s fb=%s", tag, fbTag), 0); return; }

  if(LevelTooFarFromMarket(lvl)) return;

  const ENUM_ORDER_TYPE expected = (dir==1) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
  const double lot = LotForTag(tag);

  SyncPendingToLevel(tag, lvl, expected, lot);

  ulong t=0; double op=0, ov=0; ENUM_ORDER_TYPE ot=expected;
  if(FindPendingByTag(tag, t, op, ot, ov))
  { LogA("PEND", dir, RC_PENDING_EXISTS, StringFormat("Exists tag=%s ticket=%I64u", tag, t), op); return; }

  const int sideCount = (dir==1)? CountPendings(ORDER_TYPE_BUY_LIMIT) : CountPendings(ORDER_TYPE_SELL_LIMIT);
  if(sideCount >= Inp_MaxPendingsPerSide)
  { LogA("PEND", dir, RC_MAX_PER_SIDE, StringFormat("MaxPerSide hit count=%d max=%d", sideCount, Inp_MaxPendingsPerSide), (double)sideCount); return; }

  // HARD CAP: total pendings on symbol (manual + EA) after Anchor
  const int totalPend = CountAllPendingsSymbol();
  if(Inp_MaxTotalPendingsAfterAnchor>0 && totalPend >= Inp_MaxTotalPendingsAfterAnchor)
  { LogA("PEND", dir, RC_PENDCAP_BLOCK, StringFormat("Total pending cap hit total=%d cap=%d", totalPend, Inp_MaxTotalPendingsAfterAnchor), (double)totalPend); return; }

  if(!CooldownOK())
  { LogA("PEND", dir, RC_COOLDOWN_BLOCK, "Cooldown active => pending blocked"); return; }

  if(PlaceLimit(dir, lvl, tag, lot)) StampActionTime();
}

//==================== Anchor detection =============================//
bool IsAnchorVolume(const double vol)
{
  if(Inp_AnchorLot_Reference<=0.0) return false;
  return (MathAbs(vol - Inp_AnchorLot_Reference) <= Inp_AnchorLot_Tolerance);
}

bool FindAnchor(ulong &ticketOut, int &dirOut, double &lotOut, double &entryOut)
{
  const string sym = (Inp_ManagedSymbol!="" ? Inp_ManagedSymbol : _Symbol);
  datetime bestT=0;
  ulong bestTicket=0;
  int bestDir=0;
  double bestLot=0.0;
  double bestEntry=0.0;

  for(int i=PositionsTotal()-1;i>=0;i--)
  {
    const ulong ticket=PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;

    if(PositionGetString(POSITION_SYMBOL)!=sym) continue;

    const long type=PositionGetInteger(POSITION_TYPE);
    int d=0;
    if(type==POSITION_TYPE_BUY) d=1;
    else if(type==POSITION_TYPE_SELL) d=-1;
    else continue;

    const double vol=PositionGetDouble(POSITION_VOLUME);
    if(!IsAnchorVolume(vol)) continue;

    const long magic=(long)PositionGetInteger(POSITION_MAGIC);
    if(Inp_AnchorMagic0Only && magic!=0) continue;

    const datetime tOpen=(datetime)PositionGetInteger(POSITION_TIME);
    if(tOpen>=bestT)
    {
      bestT=tOpen;
      bestTicket=ticket;
      bestDir=d;
      bestLot=vol;
      bestEntry=PositionGetDouble(POSITION_PRICE_OPEN);
    }
  }

  if(bestTicket==0) return false;

  ticketOut=bestTicket;
  dirOut=bestDir;
  lotOut=bestLot;
  entryOut=bestEntry;
  return true;
}

void ResetCycle()
{
  g_anchorActive=false;
  g_anchorTicket=0;
  g_anchorDir=0;
  g_anchorLot=0.0;
  g_anchorEntry=0.0;
}

//==================== Manual SL/TP one-shot tracker ===================//
// Purpose: Apply EA-style SL/TP to MANUAL positions once at detection time,
// then NEVER enforce again (trader may move SL/TP freely afterwards).
string ManualSLTPKey(const ulong ticket)
{
  const string sym = (Inp_ManagedSymbol!="" ? Inp_ManagedSymbol : _Symbol);
  return StringFormat("HAB_MANUAL_SLTP_%s_%I64u_%I64u", sym, (long)Inp_MagicNumber, ticket);
}
bool ManualSLTP_IsInitialized(const ulong ticket)
{
  string key = ManualSLTPKey(ticket);
  if(!GlobalVariableCheck(key)) return false;
  return (GlobalVariableGet(key) > 0.5);
}
void ManualSLTP_MarkInitialized(const ulong ticket)
{
  GlobalVariableSet(ManualSLTPKey(ticket), 1.0);
}

//==================== Anchor SLTP rule (EDGE-based) ===================//
void EnsureAnchorSLTP()
{
  if(!g_anchorActive) return;
  if(!PositionSelectByTicket(g_anchorTicket)) return;

  const string sym = (Inp_ManagedSymbol!="" ? Inp_ManagedSymbol : _Symbol);
  if(PositionGetString(POSITION_SYMBOL)!=sym) return;

  
  // Manual anchor: apply SL/TP ONCE, then allow trader to move freely
  const long magic = PositionGetInteger(POSITION_MAGIC);
  const bool isManual = (magic == 0);
  if(isManual)
  {
    if(!Inp_ApplyRulesToManualTrades) return;
    if(ManualSLTP_IsInitialized(g_anchorTicket)) return;
  }

  int seqNum = GetSequenceNumberForTicket(g_anchorTicket);
  if(seqNum <= 0 || seqNum > 4) 
  {
    LogA("ANCHOR_SLTP", g_anchorDir, RC_ANCHOR_TP_SKIP, 
         "Anchor sequence number out of range", (double)seqNum);
    return;
  }
  
  // NOTE (v1.017 fix): Anchor SL must be set even if TP is disabled or TP computation fails.
  // Inp_SetAnchorTP now controls ONLY TP setting, not SL.

  const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
  const double currentSL = PositionGetDouble(POSITION_SL);
  const double currentTP = PositionGetDouble(POSITION_TP);

  // محاسبه SL جدید بر اساس سکانس
  double slDistPts = 0.0;
  if(seqNum == 1) slDistPts = 300.0;
  else if(seqNum == 2) slDistPts = 200.0;
  else slDistPts = 100.0;
  
  double slVal = slDistPts * 10.0 * _Point;
  double newSL = (g_anchorDir == 1) ? entry - slVal : entry + slVal;
  newSL = NPrice(newSL);
  
  // TP is optional (controlled by Inp_SetAnchorTP). SL is always applied.
  double newTP = 0.0, edge = 0.0; 
  string ttag = "";
  bool   wantTP = (Inp_SetAnchorTP && Inp_UseStructuralTP);
  double targetTP = currentTP;
  if(wantTP)
  {
    if(ComputeStructuralTP_EdgeBased(g_anchorDir, entry, newTP, edge, ttag))
      targetTP = newTP;
    else
    {
      // Fail-closed for TP only: keep TP unchanged, but still apply SL.
      wantTP = false;
      LogA("ANCHOR_TP", g_anchorDir, RC_TP_LEVEL_FAIL, "Structural TP compute failed => TP unchanged (SL still applied)");
    }
  }

  // بررسی نیاز به اصلاح
  bool needModifySL = (MathAbs(currentSL - newSL) > 0.5 * _Point);
  bool needModifyTP = (wantTP && (MathAbs(currentTP - targetTP) > 0.5 * _Point));
  
  if(!needModifySL && !needModifyTP)
  { LogA("ANCHOR_SLTP", g_anchorDir, RC_ANCHOR_TP_SKIP, "SL/TP already at target values", currentTP); return; }

  if(!IsTradeEnvironmentOK()) return;

  UpdateEMAStatusCache();

  const bool ok = ModifyPositionSLTP_ByTicket(g_anchorTicket, 
                needModifySL ? newSL : currentSL, 
                needModifyTP ? targetTP : currentTP);
  if(ok)
  {
    if(isManual) ManualSLTP_MarkInitialized(g_anchorTicket);
    LogA("ANCHOR_SLTP", g_anchorDir, RC_ANCHOR_TP_SET,
         StringFormat("Anchor SLTP set ticket=%I64u seq=%d SL=%.2f TP=%.2f (edge=%.2f tag=%s)", 
                     g_anchorTicket, seqNum, newSL, (needModifyTP?targetTP:currentTP), edge, ttag),
         (needModifyTP?targetTP:currentTP));
  }
  else
    LogA("ANCHOR_SLTP", g_anchorDir, RC_ANCHOR_TP_SKIP, "SLTP modify failed", 0);
}

//=================== مدیریت معاملات دستی ===================//
// Requirement: For ALL MANUAL positions, set SL/TP exactly like EA (sequence-based SL + structural TP)
// BUT ONLY ONCE at first detection. After that, the trader can move SL/TP freely.
void CheckAndModifyManualTrades()
{
  if(!Inp_ApplyRulesToManualTrades) return;

  const string sym = (Inp_ManagedSymbol!="" ? Inp_ManagedSymbol : _Symbol);

  for(int i = PositionsTotal() - 1; i >= 0; i--)
  {
    ulong ticket = PositionGetTicket(i);
    if(ticket == 0) continue;
    if(!PositionSelectByTicket(ticket)) continue;

    if(PositionGetString(POSITION_SYMBOL) != sym) continue;

    const long magic = PositionGetInteger(POSITION_MAGIC);
    if(magic != 0) continue; // manual only

    // Anchor handled by EnsureAnchorSLTP()
    if(g_anchorActive && ticket == g_anchorTicket) continue;

    // One-shot: if already initialized, NEVER touch again
    if(ManualSLTP_IsInitialized(ticket)) continue;

    const int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
    const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
    const double currentSL = PositionGetDouble(POSITION_SL);
    const double currentTP = PositionGetDouble(POSITION_TP);

    // Determine sequence number (manual positions can be included/excluded via Inp_IncludeManualInSequence)
    const int seqNum = GetSequenceNumberForTicket(ticket);
    if(seqNum <= 0 || seqNum > 4)
    {
      LogA("MANUAL_SLTP", dir, RC_MANUAL_SKIP,
           StringFormat("Manual trade seq out of range: %d (ticket=%I64u)", seqNum, ticket), entry);
      continue;
    }

    // SL distance by sequence (v1.379 rule)
    double slDistPts = 0.0;
    if(seqNum == 1) slDistPts = 300.0;
    else if(seqNum == 2) slDistPts = 200.0;
    else slDistPts = 100.0;

    const double slVal = slDistPts * 10.0 * _Point;
    double newSL = (dir == 1) ? (entry - slVal) : (entry + slVal);
    newSL = NPrice(newSL);

    // TP: structural edge-based (same as EA)
    double newTP = 0.0, edgeRef = 0.0;
    string tpTag = "";

    if(Inp_SetManualTP && Inp_UseStructuralTP)
    {
      if(!ComputeStructuralTP_EdgeBased(dir, entry, newTP, edgeRef, tpTag))
      {
        LogA("MANUAL_TP", dir, RC_TP_LEVEL_FAIL,
             StringFormat("Structural TP failed for manual ticket=%I64u seq=%d", ticket, seqNum), entry);
        // Fail-closed for TP: DO NOT remove an existing TP. Keep TP unchanged.
        newTP = currentTP;
      }
    }

    // Decide which legs to set
    const bool wantSL = Inp_SetManualSL;
    const bool wantTP = Inp_SetManualTP;

    // If user already set SL/TP manually at open, we STILL normalize ONCE per requirement.
    // After this one-time normalization, trader can move freely.
    double targetSL = wantSL ? newSL : currentSL;
    double targetTP = wantTP ? newTP : currentTP;

    // HARD SAFETY: never zero-out stops accidentally.
    if(wantSL && targetSL<=0.0)
    {
      LogA("MANUAL_SL", dir, RC_INVALID_INPUT,
           StringFormat("Computed SL invalid (<=0) => keep existing SL (ticket=%I64u)", ticket), entry);
      targetSL = currentSL;
    }
    if(wantTP && targetTP<=0.0 && currentTP>0.0)
    {
      // If we already had a TP, never remove it by setting 0.
      LogA("MANUAL_TP", dir, RC_INVALID_INPUT,
           StringFormat("Computed TP invalid (<=0) => keep existing TP (ticket=%I64u)", ticket), entry);
      targetTP = currentTP;
    }

    if(!IsTradeEnvironmentOK()) continue;

    const bool ok = ModifyPositionSLTP_ByTicket(ticket, targetSL, targetTP);
    if(ok)
    {
      ManualSLTP_MarkInitialized(ticket);
      LogA("MANUAL_SLTP", dir, RC_MANUAL_MODIFIED,
           StringFormat("Manual SLTP initialized ticket=%I64u seq=%d SL=%.2f TP=%.2f (edge=%.2f tag=%s)",
                       ticket, seqNum, targetSL, targetTP, edgeRef, tpTag),
           entry);
    }
    else
    {
      LogA("MANUAL_SLTP", dir, RC_MANUAL_SKIP,
           StringFormat("Failed to initialize manual SLTP ticket=%I64u", ticket),
           entry);
    }
  }
}


//========================== LOCK (SAFE OWNER) =======================//
long OwnerIdSafe()
{
  long id = (long)(ChartID() % 2147483647);
  if(id<=0) id = (long)(MathRand()+1);
  return id;
}

bool AcquireLock()
{
  if(!Inp_EnableLock) return true;

  g_lockKey   = StringFormat("HAB_L7_LOCK_%s_%I64u", _Symbol, Inp_MagicNumber);
  g_lockTsKey = g_lockKey + "_TS";

  const long   myOwner = OwnerIdSafe();
  const double now     = (double)TimeCurrent();
  const double ttl     = (double)MathMax(10, Inp_LockTTLSeconds);

  if(GlobalVariableCheck(g_lockKey))
  {
    const long owner = (long)GlobalVariableGet(g_lockKey);

    if(owner == myOwner)
    {
      GlobalVariableSet(g_lockTsKey, now);
      LogA("LOCK", 0, RC_NONE, "Lock re-acquired (same owner)");
      return true;
    }

    if(GlobalVariableCheck(g_lockTsKey))
    {
      const double ts = GlobalVariableGet(g_lockTsKey);
      if(ts > 0.0 && (now - ts) > ttl)
      {
        GlobalVariableDel(g_lockKey);
        GlobalVariableDel(g_lockTsKey);
        LogA("LOCK", 0, RC_NONE, "Stale lock expired");
      }
      else
      {
        LogA("LOCK", 0, RC_LOCK_BUSY, StringFormat("Lock busy owner=%ld", owner));
        return false;
      }
    }
    else
    {
      LogA("LOCK", 0, RC_LOCK_BUSY, "Lock busy (no TS key)");
      return false;
    }
  }

  GlobalVariableSet(g_lockKey, (double)myOwner);
  GlobalVariableSet(g_lockTsKey, now);
  LogA("LOCK", 0, RC_NONE, "Lock acquired");
  return true;
}

void TouchLock()
{
  if(!Inp_EnableLock) return;
  if(g_lockTsKey=="") return;
  GlobalVariableSet(g_lockTsKey, (double)TimeCurrent());
}

void ReleaseLock()
{
  if(!Inp_EnableLock) return;
  if(g_lockKey=="") return;

  const long myOwner = OwnerIdSafe();
  if(GlobalVariableCheck(g_lockKey))
  {
    const long owner = (long)GlobalVariableGet(g_lockKey);
    if(owner == myOwner)
    {
      GlobalVariableDel(g_lockKey);
      GlobalVariableDel(g_lockTsKey);
    }
  }
}

//==================== TrendPermission Engine (Bar-Close Only) ====================//
bool EnsureTrendPermissionHandles()
{
  if(Inp_ExecTF!=PERIOD_M5)
  {
    // Spec fixed to M5; fail-closed to avoid silent misconfig.
    LogA("PERM", 0, RC_INVALID_INPUT, "Inp_ExecTF must be M5 (PERIOD_M5) => fail-closed");
    return false;
  }

  if(g_emaHandle==INVALID_HANDLE)
  {
    g_emaHandle = iMA(_Symbol, Inp_ExecTF, Inp_EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(g_emaHandle==INVALID_HANDLE)
    { LogA("PERM", 0, RC_ENV_BLOCK, "Failed to create EMA handle"); return false; }
  }
  if(g_atr14Handle==INVALID_HANDLE)
  {
    g_atr14Handle = iATR(_Symbol, Inp_ExecTF, 14);
    if(g_atr14Handle==INVALID_HANDLE)
    { LogA("PERM", 0, RC_ENV_BLOCK, "Failed to create ATR14 handle"); return false; }
  }
  if(g_atr100Handle==INVALID_HANDLE)
  {
    g_atr100Handle = iATR(_Symbol, Inp_ExecTF, 100);
    if(g_atr100Handle==INVALID_HANDLE)
    { LogA("PERM", 0, RC_ENV_BLOCK, "Failed to create ATR100 handle"); return false; }
  }
  return true;
}

//==================== EMA Overlay helpers ====================//
bool EnsureEMAOverlayHandles()
{
  if(!Inp_UseEMAOverlay) { g_emaOverlayReady=false; return true; }

  // create handles lazily
  if(g_ema20OHandle==INVALID_HANDLE)
    g_ema20OHandle = iMA(_Symbol, Inp_EMAOverlayTF, Inp_EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
  if(g_ema50OHandle==INVALID_HANDLE)
    g_ema50OHandle = iMA(_Symbol, Inp_EMAOverlayTF, Inp_EMA_Mid_Period, 0, MODE_EMA, PRICE_CLOSE);
  if(g_ema100OHandle==INVALID_HANDLE)
    g_ema100OHandle = iMA(_Symbol, Inp_EMAOverlayTF, Inp_EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
  if(g_ema200OHandle==INVALID_HANDLE)
    g_ema200OHandle = iMA(_Symbol, Inp_EMAOverlayTF, Inp_EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE);

  if(g_ema20OHandle==INVALID_HANDLE || g_ema50OHandle==INVALID_HANDLE ||
     g_ema100OHandle==INVALID_HANDLE || g_ema200OHandle==INVALID_HANDLE)
  {
    g_emaOverlayReady=false;
    LogA("EMA_OVL", 0, RC_ENV_BLOCK, "Failed to create EMA overlay handles => fail-closed for auto entries");
    return false;
  }

  g_emaOverlayReady=true;
  return true;
}

void ReleaseEMAOverlayHandles()
{
  if(g_ema20OHandle!=INVALID_HANDLE)  { IndicatorRelease(g_ema20OHandle);  g_ema20OHandle=INVALID_HANDLE; }
  if(g_ema50OHandle!=INVALID_HANDLE)  { IndicatorRelease(g_ema50OHandle);  g_ema50OHandle=INVALID_HANDLE; }
  if(g_ema100OHandle!=INVALID_HANDLE) { IndicatorRelease(g_ema100OHandle); g_ema100OHandle=INVALID_HANDLE; }
  if(g_ema200OHandle!=INVALID_HANDLE) { IndicatorRelease(g_ema200OHandle); g_ema200OHandle=INVALID_HANDLE; }
  g_emaOverlayReady=false;
}

//==================== EMA Regime (H1) helpers ====================//
bool EnsureEMARegimeHandles()
{
  if(!Inp_UseEMARegimeFilter) { g_emaRegimeReady=false; return true; }

  if(g_emaReg100Handle==INVALID_HANDLE)
    g_emaReg100Handle = iMA(_Symbol, Inp_EMARegimeTF, Inp_EMARegime_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
  if(g_emaReg200Handle==INVALID_HANDLE)
    g_emaReg200Handle = iMA(_Symbol, Inp_EMARegimeTF, Inp_EMARegime_Long_Period, 0, MODE_EMA, PRICE_CLOSE);

  if(g_emaReg100Handle==INVALID_HANDLE || g_emaReg200Handle==INVALID_HANDLE)
  {
    g_emaRegimeReady=false;
    LogA("EMA_REG", 0, RC_ENV_BLOCK, "Failed to create EMA regime handles => fail-closed for auto entries");
    return false;
  }
  g_emaRegimeReady=true;
  return true;
}

void ReleaseEMARegimeHandles()
{
  if(g_emaReg100Handle!=INVALID_HANDLE) { IndicatorRelease(g_emaReg100Handle); g_emaReg100Handle=INVALID_HANDLE; }
  if(g_emaReg200Handle!=INVALID_HANDLE) { IndicatorRelease(g_emaReg200Handle); g_emaReg200Handle=INVALID_HANDLE; }
  g_emaRegimeReady=false;
}

bool GetEMARegimeValues(const int shift, double &e100, double &e200, string &why)
{
  why=""; e100=e200=0.0;
  if(!EnsureEMARegimeHandles()) { why="ema_regime_handle_fail"; return false; }
  if(!g_emaRegimeReady) { why="ema_regime_not_ready"; return false; }

  double a100[], a200[];
  ArrayResize(a100,1); ArrayResize(a200,1);
  ArraySetAsSeries(a100,true); ArraySetAsSeries(a200,true);

  if(CopyBuffer(g_emaReg100Handle,0,shift,1,a100)!=1) { why="emaReg100_copy_fail"; return false; }
  if(CopyBuffer(g_emaReg200Handle,0,shift,1,a200)!=1) { why="emaReg200_copy_fail"; return false; }

  e100=a100[0]; e200=a200[0];
  return true;
}

// regimeDir: +1 bullish (EMA100>EMA200), -1 bearish (EMA100<EMA200), 0 neutral
int EMARegimeDir(const int shift, string &why, double &e100, double &e200)
{
  if(!GetEMARegimeValues(shift, e100, e200, why)) return 0;
  if(e100 > e200) { why="regime_bull"; return +1; }
  if(e100 < e200) { why="regime_bear"; return -1; }
  why="regime_neutral";
  return 0;
}

// For auto actions: require regime match; neutral treated per Inp_EMARegimeAllowNeutral
bool EMARegimePassForAuto(const int dir, string &why, double &e100, double &e200)
{
  why=""; e100=e200=0.0;
  if(!Inp_UseEMARegimeFilter || !Inp_EMARegimeBlockAutoEntries) return true;

  string rwhy=""; 
  const int rd = EMARegimeDir(1, rwhy, e100, e200); // bar-close only (shift=1)
  g_regimeDir = rd;

  if(rd==0 && Inp_EMARegimeAllowNeutral)
  { why="regime_neutral_allowed"; return true; }

  if(dir==+1 && rd==+1) { why="regime_ok_buy"; return true; }
  if(dir==-1 && rd==-1) { why="regime_ok_sell"; return true; }

  if(rd==0) why="regime_neutral_block";
  else      why="regime_mismatch";
  return false;
}

void UpdateEMAStatusCache()
{
  // called frequently; must be cheap and fail-closed
  g_emaStatusText = "";
  if(Inp_UseEMAOverlay)
  {
    string why=""; double e20=0,e50=0,e100=0,e200=0;
    if(GetEMAOverlayValues(1, e20, e50, e100, e200, why))
    {
      const bool bull_full    = (e20 > e50) && (e50 > e100) && (e100 > e200);
      const bool bear_full    = (e20 < e50) && (e50 < e100) && (e100 < e200);
      const bool bull_partial = (e50 > e100) && (e100 > e200);
      const bool bear_partial = (e50 < e100) && (e100 < e200);

      g_emaBullStatus = (bull_full ? 2 : (bull_partial ? 1 : 0));
      g_emaBearStatus = (bear_full ? 2 : (bear_partial ? 1 : 0));

      string bull = (g_emaBullStatus==2?"GREEN":(g_emaBullStatus==1?"YELLOW":"RED"));
      string bear = (g_emaBearStatus==2?"GREEN":(g_emaBearStatus==1?"YELLOW":"RED"));

      g_emaStatusText = StringFormat("EMA(M5) Bull=%s Bear=%s | 20=%.2f 50=%.2f 100=%.2f 200=%.2f",
                                     bull, bear, e20, e50, e100, e200);
    }
    else
    {
      g_emaStatusText = "EMA(M5) n/a";
    }
  }

  if(Inp_UseEMARegimeFilter)
  {
    string rwhy=""; double r100=0,r200=0;
    g_regimeDir = EMARegimeDir(1, rwhy, r100, r200);
  }
}



bool GetEMAOverlayValues(const int shift, double &e20, double &e50, double &e100, double &e200, string &why)
{
  why="";
  e20=e50=e100=e200=0.0;

  if(!EnsureEMAOverlayHandles())
  { why="ema_overlay_handle_fail"; return false; }
  if(!g_emaOverlayReady)
  { why="ema_overlay_not_ready"; return false; }

  double a20[], a50[], a100[], a200[];
  ArrayResize(a20,1); ArrayResize(a50,1); ArrayResize(a100,1); ArrayResize(a200,1);
  ArraySetAsSeries(a20,true); ArraySetAsSeries(a50,true); ArraySetAsSeries(a100,true); ArraySetAsSeries(a200,true);

  if(CopyBuffer(g_ema20OHandle, 0, shift, 1, a20)!=1)  { why="ema20_copy_fail"; return false; }
  if(CopyBuffer(g_ema50OHandle, 0, shift, 1, a50)!=1)  { why="ema50_copy_fail"; return false; }
  if(CopyBuffer(g_ema100OHandle,0, shift, 1, a100)!=1) { why="ema100_copy_fail"; return false; }
  if(CopyBuffer(g_ema200OHandle,0, shift, 1, a200)!=1) { why="ema200_copy_fail"; return false; }

  e20=a20[0]; e50=a50[0]; e100=a100[0]; e200=a200[0];
  return true;
}

bool EMAOverlayAligned(const int dir, string &why, double &e20, double &e50, double &e100, double &e200)
{
  // IMPORTANT: bar-close only => shift=1 (previous closed bar) to avoid flicker
  if(!GetEMAOverlayValues(1, e20, e50, e100, e200, why)) return false;

  bool bull = (e20 > e50) && (e50 > e100);
  bool bear = (e20 < e50) && (e50 < e100);

  if(Inp_EMAOverlayRequireSlowVsLong)
  {
    bull = bull && (e100 > e200);
    bear = bear && (e100 < e200);
  }

  if(Inp_EMAOverlayRequireFullAlignment)
  {
    bull = bull && (e20 > e50) && (e50 > e100) && (e100 > e200);
    bear = bear && (e20 < e50) && (e50 < e100) && (e100 < e200);
  }

  // For dashboards/telemetry: keep a simple GREEN/RED status (no YELLOW in v1.0.7 logic)
  g_emaBullStatus = (bull ? 2 : 0);
  g_emaBearStatus = (bear ? 2 : 0);

  if(dir==+1) { if(bull) { why="ema_align_bull"; return true; } why="ema_align_block_buy"; return false; }
  if(dir==-1) { if(bear) { why="ema_align_bear"; return true; } why="ema_align_block_sell"; return false; }

  why="ema_dir_zero";
  return false;
}

// EMA Anchor Entry-Quality (M5 bar-close only)
// - Does NOT change core Trend-Permission (EMA200+Slope+ATR gates)
// - Adds a timing validator for AUTO actions (EA Anchor open, AutoAnchor pending)
//   using EMA20/50/100 micro-structure and close-vs-EMA50 / reclaim pattern.
bool EMAOverlayAnchorValid(const int dir, string &why, double &e20, double &e50, double &e100, double &e200)
{
  why=""; e20=e50=e100=e200=0.0;

  // shift=1 => previous closed bar (bar-close only)
  if(!GetEMAOverlayValues(1, e20, e50, e100, e200, why)) return false;

  // Rates on overlay TF, bar-close only
  MqlRates r1[1];
  if(CopyRates(_Symbol, Inp_EMAOverlayTF, 1, 1, r1)!=1)
  { why="ema_overlay_rates1_fail"; return false; }

  const double c1 = r1[0].close;
  const double o1 = r1[0].open;

  // Base alignment (reuse the same alignment options)
  bool bull = (e20 > e50) && (e50 > e100);
  bool bear = (e20 < e50) && (e50 < e100);

  if(Inp_EMAOverlayRequireSlowVsLong)
  {
    bull = bull && (e100 > e200);
    bear = bear && (e100 < e200);
  }

  if(Inp_EMAOverlayRequireFullAlignment)
  {
    bull = bull && (e20 > e50) && (e50 > e100) && (e100 > e200);
    bear = bear && (e20 < e50) && (e50 < e100) && (e100 < e200);
  }

  // Close vs EMA50 (timing quality)
  bool closeOK=true;
  if(Inp_EMAOverlayRequireCloseVsEMA50)
  {
    if(dir==+1) closeOK = (c1 > e50);
    else if(dir==-1) closeOK = (c1 < e50);
    else closeOK=false;
  }

  if(dir==+1 && bull && closeOK) { why="ema_anchor_align_close_ok_buy"; return true; }
  if(dir==-1 && bear && closeOK) { why="ema_anchor_align_close_ok_sell"; return true; }

  // Optional reclaim pattern:
  // BUY example: previous bar closed below EMA50 (pullback), now closed back above EMA20/EMA50 with bullish candle.
  // SELL example: previous bar closed above EMA50, now closed back below EMA20/EMA50 with bearish candle.
  if(!Inp_EMAOverlayAllowReclaim)
  {
    if(dir==+1) { why = (bull? "ema_anchor_close_block_buy":"ema_anchor_align_block_buy"); return false; }
    if(dir==-1) { why = (bear? "ema_anchor_close_block_sell":"ema_anchor_align_block_sell"); return false; }
    why="ema_dir_zero"; return false;
  }

  double p20=0,p50=0,p100=0,p200=0; string why2="";
  if(!GetEMAOverlayValues(2, p20, p50, p100, p200, why2))
  { why = "ema_reclaim_prev_ema_fail"; return false; }

  MqlRates r2[1];
  if(CopyRates(_Symbol, Inp_EMAOverlayTF, 2, 1, r2)!=1)
  { why="ema_overlay_rates2_fail"; return false; }

  const double c2 = r2[0].close;

  // Maintain higher-level bias for reclaim (keep it conservative):
  // require at least EMA100 vs EMA200 alignment if configured
  bool biasOK=true;
  if(Inp_EMAOverlayRequireSlowVsLong)
  {
    if(dir==+1) biasOK = (e100 > e200);
    if(dir==-1) biasOK = (e100 < e200);
  }

  const double reclaimLevel = (Inp_EMAOverlayReclaimUseEMA20 ? e20 : e50);

  if(dir==+1)
  {
    const bool pullback = (c2 < p50);                 // previous close below EMA50
    const bool reclaim  = (c1 > reclaimLevel);        // current close above EMA20/50
    const bool candle   = (c1 > o1);                  // bullish body
    const bool microOK  = (Inp_EMAOverlayAllowYellow ? (e20 > e50) : bull); // yellow => require at least 20>50
    if(pullback && reclaim && candle && biasOK && microOK)
    { why="ema_anchor_reclaim_ok_buy"; return true; }

    why="ema_anchor_reclaim_block_buy";
    return false;
  }

  if(dir==-1)
  {
    const bool pullback = (c2 > p50);                 // previous close above EMA50
    const bool reclaim  = (c1 < reclaimLevel);        // current close below EMA20/50
    const bool candle   = (c1 < o1);                  // bearish body
    const bool microOK  = (Inp_EMAOverlayAllowYellow ? (e20 < e50) : bear);
    if(pullback && reclaim && candle && biasOK && microOK)
    { why="ema_anchor_reclaim_ok_sell"; return true; }

    why="ema_anchor_reclaim_block_sell";
    return false;
  }

  why="ema_dir_zero";
  return false;
}


bool IsNewClosedBar_M5(datetime &barTimeOut)
{
  MqlRates r[2];
  if(CopyRates(_Symbol, Inp_ExecTF, 1, 1, r)!=1) return false;
  barTimeOut = r[0].time;
  return (barTimeOut!=0 && barTimeOut!=g_lastPermBarTime);
}

int TrendPermission_OnBarClose(string &why, double &vClose, double &vEMA, double &vATR14, double &vATR100, double &vSlopeNorm, double &vBand)
{
  why=""; vClose=0; vEMA=0; vATR14=0; vATR100=0; vSlopeNorm=0; vBand=0;

  if(!EnsureTrendPermissionHandles())
  { why="handle_fail"; return 0; }

  // Need EMA at bar 1 and bar (1+L)
  const int L = (Inp_Slope_L_Bars<1?1:Inp_Slope_L_Bars);
  const int needEMA = L + 2; // indexes: 1..(1+L)
  double ema[];
  ArrayResize(ema, needEMA);
  if(CopyBuffer(g_emaHandle, 0, 1, needEMA, ema) != needEMA)
  { why="ema_copy_fail"; return 0; }

  double atr14[1], atr100[1];
  if(CopyBuffer(g_atr14Handle, 0, 1, 1, atr14)!=1) { why="atr14_copy_fail"; return 0; }
  if(CopyBuffer(g_atr100Handle,0, 1, 1, atr100)!=1){ why="atr100_copy_fail"; return 0; }

  MqlRates rr[1];
  if(CopyRates(_Symbol, Inp_ExecTF, 1, 1, rr)!=1) { why="rates_copy_fail"; return 0; }

  vClose = rr[0].close;
  vEMA   = ema[0];
  vATR14 = atr14[0];
  vATR100= atr100[0];

  // Execution gates that depend on ATR:
  const double atrMinPrice = Inp_ATR_Min_Points * _Point;
  if(atrMinPrice>0.0 && vATR14 < atrMinPrice)
  { why="atr_sleep"; return 0; }

  if(vATR100>0.0 && Inp_ShockRatio>0.0 && (vATR14 / vATR100) > Inp_ShockRatio + 1e-9)
  { why="atr_shock"; return 0; }

  // slope_norm = ((EMA_now - EMA_L)/L) / ATR14
  const double slope = (ema[0] - ema[L]) / (double)L;
  if(vATR14<=0.0) { why="atr14_zero"; return 0; }
  vSlopeNorm = slope / vATR14;

  vBand = Inp_k_band * vATR14;

  if(vClose > (vEMA + vBand) && vSlopeNorm > +Inp_k_slope)
  { why="allow_buy"; return +1; }

  if(vClose < (vEMA - vBand) && vSlopeNorm < -Inp_k_slope)
  { why="allow_sell"; return -1; }

  why="no_trade";
  return 0;
}


// Override v24 TrendDir(): use TrendPermission output
int TrendDir()
{
  // Use last computed permission on bar close
  return g_permDir;
}

void UpdateTrendPermissionIfNewBar()
{
  datetime bt=0;
  if(!IsNewClosedBar_M5(bt)) return;

  string why; double c,e,a14,a100,sn,b;
  const int d = TrendPermission_OnBarClose(why,c,e,a14,a100,sn,b);
  g_permDir = d;
  g_lastPermBarTime = bt;

  LogA("PERM", d, RC_NONE,
       StringFormat("BarClose perm=%s close=%.2f ema=%.2f band=%.2f slopeN=%.5f atr14=%.5f atr100=%.5f why=%s",
                    (d==1?"ALLOW_BUY":(d==-1?"ALLOW_SELL":"NO_TRADE")),
                    c,e,b,sn,a14,a100,why),
       (double)d);
}


//==================== Trend MA (cached handle) ======================//
bool EnsureTrendMAHandle()
{
  if(!Inp_EnableAutoAnchor) return true;
  if(g_trendMAHandle != INVALID_HANDLE) return true;

  g_trendMAHandle = iMA(_Symbol, Inp_TrendTF, Inp_TrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
  if(g_trendMAHandle == INVALID_HANDLE)
  { LogA("AUTO", 0, RC_ENV_BLOCK, "Failed to create Trend MA handle"); return false; }
  return true;
}

int TrendDir_OBSOLETE()
{
  if(!EnsureTrendMAHandle()) return 0;
  if(g_trendMAHandle==INVALID_HANDLE) return 0;

  const int need = Inp_TrendSlopeBars+2;

  double ma[];
  ArrayResize(ma, need);
  ArraySetAsSeries(ma,true);

  if(CopyBuffer(g_trendMAHandle,0,1,need,ma)!=need) return 0;

  MqlRates r[];
  ArrayResize(r,2);
  ArraySetAsSeries(r,true);
  if(CopyRates(_Symbol, Inp_TrendTF, 1, 2, r)!=2) return 0;

  bool slopeUp   = (ma[0] > ma[Inp_TrendSlopeBars]);
  bool slopeDown = (ma[0] < ma[Inp_TrendSlopeBars]);

  bool up   = (r[0].close > ma[0]) && slopeUp;
  bool down = (r[0].close < ma[0]) && slopeDown;

  if(up && !down) return +1;
  if(down && !up) return -1;
  return 0;
}

//==================== AutoAnchor engine (P ± $2) ====================//
void ManageAutoAnchorPending()
{
  ulong tk=0; int dir=0; datetime ts=0;
  if(!HasAutoAnchorPending(tk, dir, ts)) return;

  if(ts>0 && Inp_AutoAnchorExpiryMin>0)
  {
    long ageSec = (long)(TimeCurrent() - ts);
    if(ageSec > (long)Inp_AutoAnchorExpiryMin*60)
    {
      DeleteAutoAnchorPending("expired", RC_AUTO_EXPIRED);
      return;
    }
  }

  int td = TrendDir();
  if(td!=0 && td!=dir)
  {
    DeleteAutoAnchorPending("trend flip", RC_AUTO_TREND_FLIP);
    return;
  }

  LogA("AUTO", dir, RC_AUTO_EXISTS, StringFormat("AutoAnchor pending alive ticket=%I64u", tk), 0.0);
}

void AutoAnchorEngine_PivotZoneStop()
{
  if(!Inp_EnableAutoAnchor) return;

  ulong tk=0; int pdir=0; datetime ts=0;
  if(HasAutoAnchorPending(tk, pdir, ts))
  {
    ManageAutoAnchorPending();
    return;
  }

  int dir = TrendDir();
  if(dir==0)
  { LogA("AUTO", 0, RC_AUTO_NO_TREND, "No clear trend => no AutoAnchor"); return; }

  // EMA Regime gate (H1): blocks ONLY auto actions
  if(Inp_UseEMARegimeFilter && Inp_EMARegimeBlockAutoEntries)
  {
    string rwhy=""; double r100=0,r200=0;
    if(!EMARegimePassForAuto(dir, rwhy, r100, r200))
    {
      LogA("AUTO", dir, RC_EMA_REGIME_BLOCK,
           StringFormat("EMA regime blocked AutoAnchor (%s) e100=%.2f e200=%.2f", rwhy, r100, r200),
           r100);
      return;
    }
  }

  if(Inp_UseEMAOverlay && Inp_EMAOverlayBlockAutoEntries)
  {
    string ewhy=""; double e20=0,e50=0,e100=0,e200=0;
    if(!EMAOverlayAnchorValid(dir, ewhy, e20, e50, e100, e200))
    {
      LogA("AUTO", dir, RC_EMA_ALIGN_BLOCK,
           StringFormat("EMA overlay blocked AutoAnchor (%s) e20=%.2f e50=%.2f e100=%.2f e200=%.2f", ewhy, e20, e50, e100, e200),
           e20);
      return;
    }
  }

  double P=0.0;
  if(!ReadPivotP(P))
  { LogA("AUTO", dir, RC_LEVEL_MISSING, "Pivot P missing => no AutoAnchor"); return; }

  const double m = Mid();
  if(m<=0.0) return;

  if(Inp_AutoAnchorRequirePZone && !IsInsidePZone(m, P))
  { LogA("AUTO", dir, RC_AUTO_PZONE_BLOCK, "Market not in P-Zone(±$2) => no AutoAnchor", m); return; }

  const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  if(bid<=0 || ask<=0) return;

  const int minPtsBroker = MathMax(StopLevelPoints(), FreezeLevelPoints());
  const int minPts = MathMax(Inp_MinDist_Points, minPtsBroker);
  const double pad = (double)minPts * _Point;

  double entry=0.0;
  if(dir==+1) entry = MathMax(P, ask + pad);
  else        entry = MathMin(P, bid - pad);

  entry = ClampToPZone(entry, P);
  entry = NPrice(entry);

  if(!EntryFarEnoughForStop(dir, entry))
  { LogA("AUTO", dir, RC_MINDIST_BLOCK, "Entry after PZone clamp too close => no AutoAnchor", entry); return; }

  double sl=0.0,tp=0.0,tpEdge=0.0; string tpTag="";
  ComputeAutoAnchor_SLTP(dir, entry, sl, tp, tpEdge, tpTag);

  if(Inp_UseStructuralTP && tp<=0.0)
  { LogA("AUTO", dir, RC_TP_LEVEL_FAIL, "Structural TP (edge) missing => no AutoAnchor (fail-closed)", entry); return; }

  PlaceAutoAnchorStop(dir, entry, sl, tp, tpEdge, tpTag);
}

//===================== Manual Trades Numbering (Dashboard) =====================//
struct SManualItem
{
  datetime t;
  bool     is_position;
  ulong    ticket;
  string   kind;     // "POS" or "ORD"
  string   side;     // BUY/SELL/BUYLIMIT/...
  double   volume;
  double   price;
  int      seqNum;   // شماره سکانس
};

int  ManualCollect(SManualItem &items[])
{
  ArrayResize(items,0);

  // Positions (manual => magic==0)
  const int pt = PositionsTotal();
  for(int i=0;i<pt;i++)
  {
    const ulong ticket = PositionGetTicket(i);
    if(ticket==0) continue;
    if(!PositionSelectByTicket(ticket)) continue;

    const string sym = PositionGetString(POSITION_SYMBOL);
    if(sym != _Symbol) continue;

    const long magic = PositionGetInteger(POSITION_MAGIC);
    if(magic != 0) continue; // manual only

    SManualItem it;
    it.is_position = true;
    it.ticket      = ticket;
    it.t           = (datetime)PositionGetInteger(POSITION_TIME);
    const long ptype = PositionGetInteger(POSITION_TYPE);
    it.side        = (ptype==POSITION_TYPE_BUY ? "BUY" : "SELL");
    it.volume      = PositionGetDouble(POSITION_VOLUME);
    it.price       = PositionGetDouble(POSITION_PRICE_OPEN);
    it.kind        = "POS";
    it.seqNum      = GetSequenceNumberForTicket(ticket);

    const int n = ArraySize(items);
    ArrayResize(items, n+1);
    items[n]=it;
  }

  // Pending orders (manual => magic==0)
  const int ot = OrdersTotal();
  for(int i=0;i<ot;i++)
  {
    const ulong ticket = OrderGetTicket(i);
    if(ticket==0) continue;
    if(!OrderSelect(ticket)) continue;

    const string sym = OrderGetString(ORDER_SYMBOL);
    if(sym != _Symbol) continue;

    const long magic = OrderGetInteger(ORDER_MAGIC);
    if(magic != 0) continue; // manual only

    const long otype = OrderGetInteger(ORDER_TYPE);
    // We only want pendings (not market orders)
    if(otype==ORDER_TYPE_BUY || otype==ORDER_TYPE_SELL) continue;

    SManualItem it;
    it.is_position = false;
    it.ticket      = ticket;
    it.t           = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
    it.volume      = OrderGetDouble(ORDER_VOLUME_CURRENT);
    it.price       = OrderGetDouble(ORDER_PRICE_OPEN);
    it.kind        = "ORD";
    it.seqNum      = GetSequenceNumberForTicket(ticket);

    switch((ENUM_ORDER_TYPE)otype)
    {
      case ORDER_TYPE_BUY_LIMIT:   it.side="BUYLIMIT";  break;
      case ORDER_TYPE_SELL_LIMIT:  it.side="SELLLIMIT"; break;
      case ORDER_TYPE_BUY_STOP:    it.side="BUYSTOP";   break;
      case ORDER_TYPE_SELL_STOP:   it.side="SELLSTOP";  break;
      case ORDER_TYPE_BUY_STOP_LIMIT:  it.side="BUYSTOPLIMIT";  break;
      case ORDER_TYPE_SELL_STOP_LIMIT: it.side="SELLSTOPLIMIT"; break;
      default: it.side="PENDING"; break;
    }

    const int n = ArraySize(items);
    ArrayResize(items, n+1);
    items[n]=it;
  }

  return ArraySize(items);
}

void ManualSortByTimeAsc(SManualItem &items[])
{
  const int n = ArraySize(items);
  for(int i=0;i<n-1;i++)
  {
    int best=i;
    for(int j=i+1;j<n;j++)
      if(items[j].t < items[best].t) best=j;

    if(best!=i)
    {
      SManualItem tmp=items[i];
      items[i]=items[best];
      items[best]=tmp;
    }
  }
}

void UpdateManualNumberingComment()
{
  if(!Inp_ShowManualNumbering)
  { Comment(""); return; }

  SManualItem items[];
  const int n = ManualCollect(items);
  if(n<=0)
  { string s0="Manual trades: 0"; if(g_emaStatusText!="") s0+="\n"+g_emaStatusText; if(Inp_UseEMARegimeFilter){ s0+=StringFormat("\nRegime(H1): %s", (g_regimeDir==1?"BULL":(g_regimeDir==-1?"BEAR":"NEUTRAL"))); } Comment(s0); return; }

  ManualSortByTimeAsc(items);

  string s;
  s = StringFormat("Manual trades (open+pending): %d\n", n);
  s += "Seq# | Type  | Side      | Volume | Price   | Time\n";
  s += "-----|-------|-----------|--------|---------|-------------------\n";

  for(int i=0;i<n;i++)
  {
    const string ts = TimeToString(items[i].t, TIME_MINUTES|TIME_SECONDS);
    s += StringFormat("%-4d | %-5s | %-9s | %6.2f | %7.2f | %s\n",
                      items[i].seqNum,
                      items[i].kind,
                      items[i].side,
                      items[i].volume,
                      items[i].price,
                      ts);
  }

  if(g_emaStatusText!="") s += "\n" + g_emaStatusText; if(Inp_UseEMARegimeFilter){ s += StringFormat("\nRegime(H1): %s", (g_regimeDir==1?"BULL":(g_regimeDir==-1?"BEAR":"NEUTRAL"))); }
  Comment(s);
}

//============================== Core ================================//
void Process()
{
  TouchLock();
  if(!IsTradeEnvironmentOK()) return;

  //================ SAFETY: Manual SL/TP initialization ================//
  // Runs BEFORE auto-entry gates (spread/shock/caps).
  // When you open a MANUAL trade (including 0.02 manual Anchor), EA sets SL/TP ONCE
  // using the SAME calculations as EA trades, then never enforces again.
  ulong _at=0; int _ad=0; double _al=0.0; double _ae=0.0;
  const bool _hasAnchorNow = FindAnchor(_at, _ad, _al, _ae);
  if(_hasAnchorNow)
  {
    if(!g_anchorActive || g_anchorTicket!=_at)
    {
      g_anchorActive=true;
      g_anchorTicket=_at;
      g_anchorDir=_ad;
      g_anchorLot=_al;
      g_anchorEntry=_ae;
    }
    EnsureAnchorSLTP();
  }
  if(Inp_ApplyRulesToManualTrades)
    CheckAndModifyManualTrades();


  if(!EnsureATRHandle()) return;
  if(!EnsureTrendPermissionHandles()) return;
  UpdateTrendPermissionIfNewBar();

  if((Inp_UseATR_SLTP || Inp_EnableATRShock || Inp_UseStructuralTP))
    if(!UpdateATRNow())
    { LogA("ATR", 0, RC_ENV_BLOCK, "ATR read failed => fail-closed"); return; }

  // v1.379: Total Cap (Manual + EA) = 4
  const int openPosNow = CountAllActiveTradesSymbol();
  if(openPosNow >= 4)
  {
    if(Inp_DeleteEAPendingsWhenCapHit)
    {
      DeleteAllEAPendings_LadderOnly("CAP", 0, RC_PENDING_DELETED);
      DeleteAutoAnchorPending("cap hit", RC_PENDING_DELETED);
      LogA("CAP", 0, RC_POSCAP_BLOCK, StringFormat("CAP HIT Total=%d max=4", openPosNow));
    }
    return;
  }

  if(ATRShockActive())
  {
    if(Inp_DeletePendingsOnShock)
    {
      DeleteAllEAPendings_LadderOnly("SHOCK", 0, RC_PENDING_DELETED);
      DeleteAutoAnchorPending("ATR shock", RC_PENDING_DELETED);
      LogA("GATE", 0, RC_ATR_SHOCK_BLOCK, "ATR SHOCK => delete pendings + block");
    }
    return;
  }

  if(!SpreadOK()) return;

  ulong t=0; int d=0; double lot=0.0; double entry=0.0;
  const bool nowAnchor = FindAnchor(t,d,lot,entry);

  if(!nowAnchor)
  {
    if(g_anchorActive)
    {
      DeleteAllPendings_Symbol_AllOwners("CYCLE_END", g_anchorDir, RC_PENDING_DELETED);
      ResetCycle();
      LogA("ANCHOR", 0, RC_ANCHOR_RESET, "Anchor missing => reset + delete ALL pendings");
    }

    const bool canEnter = EntryGovernanceOK();
    // If governance blocks entries, we still allow manual trade management below.
    if(!canEnter)
    {
      // Skip auto-entry engines
    }

    // EA Anchor open (optional): if no anchor exists and permission allows
    if(canEnter && Inp_EnableEAAnchorOpen)
    {
      // Only attempt if no open positions and no pendings on symbol (fail-safe)
      if(CountAllOpenPositionsSymbol()==0 && CountAllPendingsSymbol()==0)
      {
        const int perm = g_permDir;
        if(perm!=0 && CooldownOK())
        {
          bool blocked=false;

          // EMA Regime gate (H1): blocks ONLY auto actions (EA Anchor open attempt)
          if(Inp_UseEMARegimeFilter && Inp_EMARegimeBlockAutoEntries)
          {
            string rwhy=""; double r100=0,r200=0;
            if(!EMARegimePassForAuto(perm, rwhy, r100, r200))
            {
              LogA("ANCHOR", perm, RC_EMA_REGIME_BLOCK,
                   StringFormat("EMA regime blocked EA Anchor open (%s) e100=%.2f e200=%.2f", rwhy, r100, r200),
                   r100);
              blocked=true;
            }
          }

if(Inp_UseEMAOverlay && Inp_EMAOverlayBlockAutoEntries)
          {
            string ewhy=""; double e20=0,e50=0,e100=0,e200=0;
            if(!EMAOverlayAnchorValid(perm, ewhy, e20, e50, e100, e200))
            {
              LogA("ANCHOR", perm, RC_EMA_ALIGN_BLOCK,
                   StringFormat("EMA overlay blocked EA Anchor open (%s) e20=%.2f e50=%.2f e100=%.2f e200=%.2f", ewhy, e20, e50, e100, e200));
              blocked=true;
            }
          }

          if(!blocked)
          {
            const double lotA = NormalizeLot(Inp_EAAnchorLot);
            if(lotA>0.0)
            {
              trade.SetDeviationInPoints(Inp_DeviationPoints);
              bool ok=false;
              if(perm==+1) ok = trade.Buy(lotA, _Symbol);
              else         ok = trade.Sell(lotA, _Symbol);

              if(ok)
              {
                StampActionTime();
                LogA("ANCHOR", perm, RC_NONE, StringFormat("EA opened Anchor MARKET lot=%.2f perm=%s", lotA, (perm==1?"BUY":"SELL")));
              }
              else
              {
                LogA("ANCHOR", perm, RC_ENV_BLOCK, StringFormat("EA Anchor open failed ret=%d", (int)trade.ResultRetcode()));
              }
            }
          }
        }
      }
    }

    if(canEnter) AutoAnchorEngine_PivotZoneStop();
    
    // بررسی و اصلاح معاملات دستی
    if(Inp_ApplyRulesToManualTrades)
    {
      CheckAndModifyManualTrades();
    }
    return;
  }

  DeleteAutoAnchorPending("anchor present", RC_PENDING_DELETED);

  if(!g_anchorActive || g_anchorTicket!=t)
  {
    g_anchorActive=true;
    g_anchorTicket=t;
    g_anchorDir=d;
    g_anchorLot=lot;
    g_anchorEntry=entry;

    DeleteAllEAPendings_LadderOnly("CYCLE_NEW", d, RC_PENDING_DELETED);
    LogA("ANCHOR", d, RC_ANCHOR_DETECTED,
         StringFormat("NEW ANCHOR ticket=%I64u dir=%s lot=%.2f entry=%.2f",
                      g_anchorTicket, (g_anchorDir==1?"BUY":"SELL"), g_anchorLot, g_anchorEntry),
         g_anchorLot);
    // EMA overlay: warn-only for MANUAL anchor (never blocks)
    if(Inp_UseEMAOverlay && Inp_EMAOverlayWarnManualAnchor)
    {
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      if(mg==0)
      {
        string ewhy=""; double e20=0,e50=0,e100=0,e200=0;
        if(!EMAOverlayAnchorValid(d, ewhy, e20, e50, e100, e200))
        {
          LogA("EMA_OVL", d, RC_EMA_ALIGN_WARN,
               StringFormat("Manual Anchor vs EMA alignment mismatch (%s) e20=%.2f e50=%.2f e100=%.2f e200=%.2f", ewhy, e20, e50, e100, e200),
               e20);
        }
      }
    }

  // EMA regime: warn-only for MANUAL anchor (never blocks)
  if(Inp_UseEMARegimeFilter && Inp_EMARegimeWarnManualAnchor)
  {
    long mg2 = (long)PositionGetInteger(POSITION_MAGIC);
    if(mg2==0)
    {
      string rwhy=""; double r100=0,r200=0;
      const int rd = EMARegimeDir(1, rwhy, r100, r200);
      // warn if regime is opposite direction; neutral warns only if auto would have been blocked
      bool mismatch=false;
      if(d==+1 && rd==-1) mismatch=true;
      if(d==-1 && rd==+1) mismatch=true;
      if(rd==0 && !Inp_EMARegimeAllowNeutral) mismatch=true;

      if(mismatch)
      {
        LogA("EMA_REG", d, RC_EMA_REGIME_WARN,
             StringFormat("Manual Anchor vs EMA regime mismatch (%s) e100=%.2f e200=%.2f", rwhy, r100, r200),
             r100);
      }
    }
  }

  EnsureAnchorSLTP();

  // بررسی و اصلاح معاملات دستی
  if(Inp_ApplyRulesToManualTrades)
  {
    CheckAndModifyManualTrades();
  }

  // Mode-driven ladder (strength from HAB EXP 24, but risk-governed)
  int nLevels = 2;
  if(Inp_LadderMode==LADDER_CONSERVATIVE) nLevels = 1;
  if(Inp_LadderMode==LADDER_BALANCED)     nLevels = 2;
  if(Inp_LadderMode==LADDER_AGGRESSIVE)   nLevels = 3;

  if(g_anchorDir==1)
  {
    if(nLevels>=1) EnsurePending( 1, "S1", "S1_FB");
    if(nLevels>=2) EnsurePending( 1, "S2", "S2_FB");
    if(nLevels>=3) EnsurePending( 1, "S3", "S3_FB");
  }
  else if(g_anchorDir==-1)
  {
    if(nLevels>=1) EnsurePending(-1, "R1", "R1_FB");
    if(nLevels>=2) EnsurePending(-1, "R2", "R2_FB");
    if(nLevels>=3) EnsurePending(-1, "R3", "R3_FB");
  }
}
}

//============================ UI: Refresh Button =========================//
string g_refreshBtnName   = "HAB_BTN_REFRESH";
string g_refreshPanelName = "HAB_UI_REFRESH_PANEL";

bool CreateRefreshPanel()
{
  if(!Inp_EnableRefreshButton) return true;
  if(!Inp_EnableRefreshPanel)  return true;

  if(ObjectFind(0, g_refreshPanelName) >= 0) return true;

  if(!ObjectCreate(0, g_refreshPanelName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
  {
    Print("Failed to create refresh panel. err=", GetLastError());
    return false;
  }

  const int pad = (Inp_RefreshPanel_Padding<0?0:Inp_RefreshPanel_Padding);
  const int xd  = (Inp_RefreshBtn_XDistance>pad? Inp_RefreshBtn_XDistance-pad : 0);
  const int yd  = (Inp_RefreshBtn_YDistance>pad? Inp_RefreshBtn_YDistance-pad : 0);

  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_XDISTANCE, xd);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_YDISTANCE, yd);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_XSIZE, Inp_RefreshBtn_Width + 2*pad);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_YSIZE, Inp_RefreshBtn_Height + 2*pad);

  // Semi-transparent dark panel with purple border
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_BGCOLOR, ColorToARGB(clrBlack, 60));
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_BORDER_COLOR, clrPurple);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_COLOR, clrPurple);

  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_SELECTABLE, false);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_HIDDEN, true);
  ObjectSetInteger(0, g_refreshPanelName, OBJPROP_BACK, true);

  return true;
}

bool CreateRefreshButton()
{
  if(!Inp_EnableRefreshButton) return true;

  // Ensure panel exists first (so it sits behind the button)
  if(!CreateRefreshPanel()) return false;

  if(ObjectFind(0, g_refreshBtnName) >= 0) return true;

  if(!ObjectCreate(0, g_refreshBtnName, OBJ_BUTTON, 0, 0, 0))
  {
    Print("Failed to create refresh button. err=", GetLastError());
    return false;
  }

  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_XDISTANCE, Inp_RefreshBtn_XDistance);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_YDISTANCE, Inp_RefreshBtn_YDistance);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_XSIZE, Inp_RefreshBtn_Width);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_YSIZE, Inp_RefreshBtn_Height);

  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_BGCOLOR, clrPurple);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_COLOR, clrWhite);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_BORDER_COLOR, clrPurple);

  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_SELECTABLE, false);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_HIDDEN, true);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_BACK, false);

  ObjectSetString(0, g_refreshBtnName, OBJPROP_TEXT, Inp_RefreshBtn_Text);
  ObjectSetInteger(0, g_refreshBtnName, OBJPROP_FONTSIZE, 9);

  return true;
}

void DeleteRefreshButton()
{
  if(ObjectFind(0, g_refreshBtnName) >= 0)
    ObjectDelete(0, g_refreshBtnName);
  if(ObjectFind(0, g_refreshPanelName) >= 0)
    ObjectDelete(0, g_refreshPanelName);
}

//====================== UI Refresh: Object + Levels ======================//
bool _IsCoreLevelName(const string name)
{
  return (name=="P" || name=="S1" || name=="S2" || name=="S3" || name=="S4" || name=="S5" ||
          name=="R1" || name=="R2" || name=="R3" || name=="R4" || name=="R5");
}

bool _ShouldRefreshObject(const string name)
{
  if(name=="" || name==g_refreshBtnName || name==g_refreshPanelName) return false;

  // Core levels used by the system (read by EA)
  if(_IsCoreLevelName(name)) return true;

  // Common fallback / fib / auxiliary tags (indicator objects)
  if(StringFind(name, "FB_") == 0) return true;

  // HAB/PEX object namespaces (if present on chart)
  if(StringFind(name, "HAB") == 0) return true;
  if(StringFind(name, "PEX") == 0) return true;

  // Optional: refresh zones/edges by common keywords (conservative)
  if(StringFind(name, "ZONE") >= 0) return true;
  if(StringFind(name, "EDGE") >= 0) return true;

  return false;
}

// Touch an object: re-apply its own anchor points and key properties (forces redraw / refresh)
void _TouchObject(const long chartId, const string name)
{
  if(ObjectFind(chartId, name) < 0) return;

  ResetLastError();

  long ltype=0;
  if(!ObjectGetInteger(chartId, name, OBJPROP_TYPE, 0, ltype))
     return;
  const int type = (int)ltype;

  // Re-set anchor points to themselves (forces internal refresh).
  for(int i=0;i<6;i++)
  {
    long ltime=0;
    if(!ObjectGetInteger(chartId, name, OBJPROP_TIME, i, ltime))
       break;
    datetime t = (datetime)ltime;

    double p = 0.0;
    if(!ObjectGetDouble(chartId, name, OBJPROP_PRICE, i, p))
       break;

    // These setters are safe even if some object types ignore them
    ObjectMove(chartId, name, i, t, p);
  }

  // Re-apply its own integer properties to themselves to force refresh
  long clr=0;
  if(ObjectGetInteger(chartId, name, OBJPROP_COLOR, 0, clr))
     ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr);

  long width=0;
  if(ObjectGetInteger(chartId, name, OBJPROP_WIDTH, 0, width))
     ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);

  long style=0;
  if(ObjectGetInteger(chartId, name, OBJPROP_STYLE, 0, style))
     ObjectSetInteger(chartId, name, OBJPROP_STYLE, style);

  long back=0;
  if(ObjectGetInteger(chartId, name, OBJPROP_BACK, 0, back))
     ObjectSetInteger(chartId, name, OBJPROP_BACK, back);

  long sel=0;
  if(ObjectGetInteger(chartId, name, OBJPROP_SELECTABLE, 0, sel))
     ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, sel);

  if(type < 0) Print("");
}

//--------------------------- Market data refresh (MQL5) ---------------------------//
bool RefreshMarketData(const string sym)
{
  MqlTick t;
  if(!SymbolInfoTick(sym, t)) return false;
  return (t.time > 0);
}

// Refresh all relevant objects (levels + HAB/PEX drawing objects)

//============================= Level Tools =============================//
bool _SetObjBool(const long cid,const string name,const ENUM_OBJECT_PROPERTY_INTEGER prop,const bool v)
{
  if(ObjectFind(cid,name)<0) return false;
  return ObjectSetInteger(cid,name,prop,(long)(v?1:0));
}
bool _SetObjInt(const long cid,const string name,const ENUM_OBJECT_PROPERTY_INTEGER prop,const long v)
{
  if(ObjectFind(cid,name)<0) return false;
  return ObjectSetInteger(cid,name,prop,v);
}

bool EnsureHLine(const long cid,const string name,const double price,const color clr,const int style,const int width,const bool overwrite)
{
  if(ObjectFind(cid,name)<0)
  {
    if(!ObjectCreate(cid,name,OBJ_HLINE,0,0,price)) return false;
    ObjectSetInteger(cid,name,OBJPROP_COLOR,clr);
    ObjectSetInteger(cid,name,OBJPROP_STYLE,style);
    ObjectSetInteger(cid,name,OBJPROP_WIDTH,width);
    ObjectSetInteger(cid,name,OBJPROP_BACK,false);
    ObjectSetInteger(cid,name,OBJPROP_SELECTABLE,true);
    ObjectSetInteger(cid,name,OBJPROP_HIDDEN,false);
    ObjectSetInteger(cid,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
    return true;
  }
  if(overwrite)
  {
    ObjectSetDouble(cid,name,OBJPROP_PRICE,0,price);
  }
  return true;
}

//============================= Level Engine (HAB PEX 61) =============================//
#define LV_SRC_D1   0x01
#define LV_SRC_W1   0x02
#define LV_SRC_QTR  0x04
#define LV_SRC_R50  0x08
#define LV_SRC_R10  0x10
#define LV_SRC_R5   0x20
#define LV_SRC_H4SW 0x40

struct LV_Level
{
  double price;
  int    score;
  int    reactions;
  int    ageBars;
  int    srcMask;
};

int      g_lv_atrH1      = INVALID_HANDLE;
int      g_lv_atrM5      = INVALID_HANDLE;
datetime g_lv_lastH1     = 0;
datetime g_lv_lastM5     = 0;
LV_Level g_lv_scored[];          // eligible after scoring (may be empty)
bool     g_lv_hasContext = false;

void LV_DBG(const string s){ if(Inp_LV_DebugPrint) Print("[HAB_LV] ", s); }

double LV_GetATR(const int handle)
{
  if(handle==INVALID_HANDLE) return 0.0;
  double b[];
  if(CopyBuffer(handle,0,0,1,b)!=1) return 0.0;
  return b[0];
}

double LV_MidPrice()
{
  double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  return (bid+ask)*0.5;
}

double LV_Pts(const int points){ return points*_Point; }

double LV_NPrice(const double p)
{
  int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
  return NormalizeDouble(p,d);
}

bool LV_NewBar(const ENUM_TIMEFRAMES tf, datetime &last)
{
  datetime t=iTime(_Symbol,tf,0);
  if(t<=0) return false;
  if(t!=last){ last=t; return true; }
  return false;
}

color LV_Alpha(const color c,const int a)
{
  // MQL5 strict: no GetRValue/GetGValue/GetBValue helpers.
  // 'color' uses 0x00BBGGRR (BGR). We compose ARGB as 0xAABBGGRR.
  uint uc = (uint)c;
  // Note: MQL5 does not support C-style integer suffixes (e.g., 0xFFu).
  int r = (int)(uc & (uint)0xFF);
  int g = (int)((uc >> 8) & (uint)0xFF);
  int b = (int)((uc >> 16) & (uint)0xFF);
  int aa = a; if(aa<0) aa=0; if(aa>255) aa=255;
  return (color)( (uint)r | ((uint)g<<8) | ((uint)b<<16) | ((uint)aa<<24) );
}

LV_Level LV_MakeLevel(const double price,const int score,const int srcMask)
{
  LV_Level L;
  L.price=LV_NPrice(price);
  L.score=score;
  L.reactions=0;
  L.ageBars=0;
  L.srcMask=srcMask;
  return L;
}

void LV_Append(LV_Level &arr[], const LV_Level &L)
{
  int n=ArraySize(arr);
  ArrayResize(arr,n+1);
  arr[n]=L;
}

void LV_CopyLevels(LV_Level &dst[], const LV_Level &src[])
{
  int n=ArraySize(src);
  ArrayResize(dst,n);
  for(int i=0;i<n;i++) dst[i]=src[i];
}

double LV_RoundStep(const double price,const double step)
{
  if(step<=0.0) return price;
  return MathRound(price/step)*step;
}

void LV_AddOrMerge(LV_Level &arr[], const double price,const int srcMask)
{
  double p=LV_NPrice(price);
  for(int i=0;i<ArraySize(arr);i++)
  {
    if(MathAbs(arr[i].price-p) <= 0.5*_Point)
    {
      arr[i].srcMask |= srcMask;
      return;
    }
  }
  LV_Level L=LV_MakeLevel(p,0,srcMask);
  LV_Append(arr,L);
}

bool LV_BodyOK(const MqlRates &r,const double bodyMin)
{
  return (MathAbs(r.close-r.open) >= bodyMin);
}

int LV_BarsSinceTouch(const MqlRates &h1[],const int total,const double lvl,const double band)
{
  for(int i=total-1;i>=0;i--)
  {
    if(MathAbs(h1[i].high-lvl)<=band || MathAbs(h1[i].low-lvl)<=band) return (total-1-i);
  }
  return 9999;
}

int LV_TouchesRecent(const MqlRates &h1[],const int total,const double lvl,const double band,const int recentBars)
{
  int c=0;
  int start=MathMax(0,total-recentBars);
  for(int i=start;i<total;i++)
    if(MathAbs(h1[i].high-lvl)<=band || MathAbs(h1[i].low-lvl)<=band) c++;
  return c;
}

int LV_ScoreReacts(const int reactions)
{
  if(reactions<=0) return 0;
  if(reactions==1) return 25;
  if(reactions==2) return 40;
  if(reactions==3) return 55;
  if(reactions>=4) return 65;
  return 0;
}

int LV_ScoreTF(const int srcMask)
{
  int s=0;
  if((srcMask & LV_SRC_D1)!=0)  s+=10;
  if((srcMask & LV_SRC_W1)!=0)  s+=15;
  if((srcMask & LV_SRC_QTR)!=0) s+=18;
  if((srcMask & LV_SRC_H4SW)!=0)s+=10;
  return s;
}

int LV_ScoreInst(const int srcMask)
{
  int s=0;
  if((srcMask & LV_SRC_R50)!=0) s+=10;
  if((srcMask & LV_SRC_R10)!=0) s+=8;
  if((srcMask & LV_SRC_R5)!=0)  s+=6;
  return s;
}

int LV_CountValidReactions(const MqlRates &h1[],const int total,const double lvl,const double band,
                           const double minReact,const int maxBars,const double bodyMin)
{
  int r=0;
  int i=0;
  while(i<total-1-maxBars)
  {
    bool touched=(MathAbs(h1[i].high-lvl)<=band || MathAbs(h1[i].low-lvl)<=band);
    if(!touched){ i++; continue; }

    double maxH=h1[i+1].high;
    double minL=h1[i+1].low;
    bool bull=false,bear=false;

    for(int j=i+1;j<=i+maxBars;j++)
    {
      if(h1[j].high>maxH) maxH=h1[j].high;
      if(h1[j].low <minL) minL=h1[j].low;

      if(LV_BodyOK(h1[j],bodyMin))
      {
        if(h1[j].close>h1[j].open) bull=true;
        if(h1[j].close<h1[j].open) bear=true;
      }
    }

    bool upReact   = ((maxH-lvl)>=minReact) && bull;
    bool downReact = ((lvl-minL)>=minReact) && bear;

    if(upReact || downReact){ r++; i += (maxBars+1); }
    else i++;
  }
  return r;
}

int LV_ScoreAge(const int reactions,const int ageBars,const int recentTouches)
{
  if(reactions<=0) return 0;
  int maxAge=240;
  double x=(double)ageBars/(double)maxAge;
  if(x>1.0) x=1.0;
  double s=25.0*x;
  if(recentTouches>=3) s*=0.5;
  return (int)MathRound(s);
}

bool LV_BuildContext()
{
  g_lv_hasContext=false;
  ArrayResize(g_lv_scored,0);

  if(!Inp_LV_Enable) return false;

  double atrH1=LV_GetATR(g_lv_atrH1);
  if(atrH1<=0.0){ LV_DBG("ATR(Context)=0. History not loaded."); return false; }

  MqlRates h1[];
  int need=MathMax(200,Inp_LV_LookbackH1Bars);
  int got=CopyRates(_Symbol,Inp_LV_ContextTF,0,need,h1);
  if(got<200){ LV_DBG(StringFormat("CopyRates(Context) got=%d (<200).",got)); return false; }
  ArraySetAsSeries(h1,false);

  LV_Level cand[]; ArrayResize(cand,0);
  double mid=LV_MidPrice();

  if(Inp_LV_UsePrevDayHL)
  {
    double dh=iHigh(_Symbol,PERIOD_D1,1);
    double dl=iLow(_Symbol, PERIOD_D1,1);
    double dc=iClose(_Symbol,PERIOD_D1,1);
    if(dh>0 && dl>0){ LV_AddOrMerge(cand,dh,LV_SRC_D1); LV_AddOrMerge(cand,dl,LV_SRC_D1); }
    if(dc>0) LV_AddOrMerge(cand,dc,LV_SRC_D1);
  }

  if(Inp_LV_UsePrevWeekHL)
  {
    double wh=iHigh(_Symbol,PERIOD_W1,1);
    double wl=iLow(_Symbol, PERIOD_W1,1);
    double wc=iClose(_Symbol,PERIOD_W1,1);
    if(wh>0 && wl>0){ LV_AddOrMerge(cand,wh,LV_SRC_W1); LV_AddOrMerge(cand,wl,LV_SRC_W1); }
    if(wc>0) LV_AddOrMerge(cand,wc,LV_SRC_W1);
  }

  if(Inp_LV_UseQuarterHL)
  {
    MqlRates d1[];
    int gd=CopyRates(_Symbol,PERIOD_D1,0,120,d1);
    if(gd>=90)
    {
      ArraySetAsSeries(d1,false);
      double qH=d1[0].high, qL=d1[0].low;
      for(int i=0;i<90;i++){ if(d1[i].high>qH) qH=d1[i].high; if(d1[i].low<qL) qL=d1[i].low; }
      LV_AddOrMerge(cand,qH,LV_SRC_QTR);
      LV_AddOrMerge(cand,qL,LV_SRC_QTR);
    }
  }

  if(Inp_LV_UseRound50)
  {
    double base=LV_RoundStep(mid,50.0);
    for(int k=-3;k<=3;k++) LV_AddOrMerge(cand,base+50.0*k,LV_SRC_R50);
  }

  if(Inp_LV_UseH4Swings)
  {
    MqlRates h4[];
    int gh=CopyRates(_Symbol,PERIOD_H4,0,MathMax(200,Inp_LV_SwingLookbackH4Bars),h4);
    if(gh >= (Inp_LV_SwingLen*2+30))
    {
      ArraySetAsSeries(h4,false);
      int len=Inp_LV_SwingLen;
      for(int i=len;i<gh-len;i++)
      {
        bool sh=true,sl=true;
        double hi=h4[i].high, lo=h4[i].low;
        for(int k=1;k<=len;k++)
        {
          if(h4[i-k].high>=hi || h4[i+k].high>=hi) sh=false;
          if(h4[i-k].low <=lo || h4[i+k].low <=lo) sl=false;
          if(!sh && !sl) break;
        }
        if(sh) LV_AddOrMerge(cand,hi,LV_SRC_H4SW);
        if(sl) LV_AddOrMerge(cand,lo,LV_SRC_H4SW);
      }
    }
  }

  if(Inp_LV_EnableMicroRounds)
  {
    double atrM5=LV_GetATR(g_lv_atrM5);
    if(atrM5>0.0)
    {
      double maxDist=Inp_LV_MicroRoundMaxDist_ATR_M5*atrM5;

      if(Inp_LV_MicroRoundStep1_USD>0)
      {
        double base10=LV_RoundStep(mid,(double)Inp_LV_MicroRoundStep1_USD);
        for(int k=-Inp_LV_MicroRoundCountEachSide;k<=Inp_LV_MicroRoundCountEachSide;k++)
        {
          double p=base10+(double)k*(double)Inp_LV_MicroRoundStep1_USD;
          if(MathAbs(p-mid)<=maxDist) LV_AddOrMerge(cand,p,LV_SRC_R10);
        }
      }
      if(Inp_LV_MicroRoundStep2_USD>0)
      {
        double base5=LV_RoundStep(mid,(double)Inp_LV_MicroRoundStep2_USD);
        for(int k=-Inp_LV_MicroRoundCountEachSide;k<=Inp_LV_MicroRoundCountEachSide;k++)
        {
          double p=base5+(double)k*(double)Inp_LV_MicroRoundStep2_USD;
          if(MathAbs(p-mid)<=maxDist) LV_AddOrMerge(cand,p,LV_SRC_R5);
        }
      }
    }
  }

  if(ArraySize(cand)==0){ LV_DBG("No candidates generated."); return false; }

  double band=MathMax(Inp_LV_TouchBand_ATR_H1*atrH1, LV_Pts(Inp_LV_TouchBand_MinPoints));
  double minReact=Inp_LV_MinReaction_ATR_H1*atrH1;
  double bodyMin=Inp_LV_BodyMin_ATR_H1*atrH1;

  LV_Level eligible[]; ArrayResize(eligible,0);

  for(int i=0;i<ArraySize(cand);i++)
  {
    LV_Level L=cand[i];
    int reactions=LV_CountValidReactions(h1,got,L.price,band,minReact,Inp_LV_MaxReactionBars_H1,bodyMin);
    int ageBars=LV_BarsSinceTouch(h1,got,L.price,band);
    int recent=LV_TouchesRecent(h1,got,L.price,band,24);

    int sA=LV_ScoreReacts(reactions);
    int sB=LV_ScoreTF(L.srcMask);
    int sC=LV_ScoreInst(L.srcMask);
    int sD=LV_ScoreAge(reactions,ageBars,recent);

    L.reactions=reactions;
    L.ageBars=ageBars;
    L.score=sA+sB+sC+sD;

    if(L.score>=Inp_LV_MinScore) LV_Append(eligible,L);
  }

  LV_CopyLevels(g_lv_scored,eligible);
  g_lv_hasContext=true;

  if(ArraySize(g_lv_scored)==0) LV_DBG("Eligible=0 after scoring. Will rely on fallback ladder.");
  else LV_DBG(StringFormat("Context built. candidates=%d eligible=%d",ArraySize(cand),ArraySize(g_lv_scored)));

  return true;
}

void LV_DeleteObjects()
{
  const long cid=0;
  int total=ObjectsTotal(cid,0,-1);
  for(int i=total-1;i>=0;i--)
  {
    string n=ObjectName(cid,i,0,-1);
    if(StringFind(n,PREFIX,0)!=0) continue;
    ObjectDelete(cid,n);
  }
}

void LV_SortByScoreDesc(LV_Level &arr[])
{
  int n=ArraySize(arr);
  for(int i=0;i<n-1;i++)
    for(int j=i+1;j<n;j++)
      if(arr[j].score>arr[i].score){ LV_Level t=arr[i]; arr[i]=arr[j]; arr[j]=t; }
}

void LV_DistanceFilter(LV_Level &arr[], const double ref, const double maxDist)
{
  LV_Level out[]; ArrayResize(out,0);
  for(int i=0;i<ArraySize(arr);i++)
    if(MathAbs(arr[i].price-ref)<=maxDist) LV_Append(out,arr[i]);
  LV_CopyLevels(arr,out);
}

void LV_MergeProximity(LV_Level &arr[], const double thr)
{
  LV_Level out[]; ArrayResize(out,0);
  for(int i=0;i<ArraySize(arr);i++)
  {
    bool merged=false;
    for(int k=0;k<ArraySize(out);k++)
    {
      if(MathAbs(arr[i].price-out[k].price)<thr)
      {
        out[k].srcMask |= arr[i].srcMask;
        merged=true;
        break;
      }
    }
    if(!merged) LV_Append(out,arr[i]);
  }
  LV_CopyLevels(arr,out);
}

// 7-level ladder: S3, S2, S1, P, R1, R2, R3
void LV_SelectPivotLadder7(LV_Level &arr[], const double mid, LV_Level &finalOut[])
{
  ArrayResize(finalOut,0);
  int n=ArraySize(arr);
  if(n==0) return;

  // Find pivot (closest to mid with high score)
  int pIdx=0;
  double bestKey=1e100;
  for(int i=0;i<n;i++)
  {
    double dist=MathAbs(arr[i].price-mid);
    double key=dist - 0.0001*arr[i].score;
    if(key<bestKey){ bestKey=key; pIdx=i; }
  }
  LV_Level P=arr[pIdx];

  LV_Level up[]; LV_Level dn[];
  ArrayResize(up,0); ArrayResize(dn,0);

  // Separate levels above and below pivot
  for(int i=0;i<n;i++)
  {
    if(i==pIdx) continue;
    if(arr[i].price>P.price) LV_Append(up,arr[i]);
    else if(arr[i].price<P.price) LV_Append(dn,arr[i]);
  }

  // Sort levels above by proximity to P
  for(int i=0;i<ArraySize(up)-1;i++)
    for(int j=i+1;j<ArraySize(up);j++)
      if(MathAbs(up[j].price-P.price)<MathAbs(up[i].price-P.price))
      { LV_Level t=up[i]; up[i]=up[j]; up[j]=t; }

  // Sort levels below by proximity to P
  for(int i=0;i<ArraySize(dn)-1;i++)
    for(int j=i+1;j<ArraySize(dn);j++)
      if(MathAbs(dn[j].price-P.price)<MathAbs(dn[i].price-P.price))
      { LV_Level t=dn[i]; dn[i]=dn[j]; dn[j]=t; }

  // Build 7-level ladder
  if(ArraySize(dn)>=3) LV_Append(finalOut,dn[2]); // S3
  if(ArraySize(dn)>=2) LV_Append(finalOut,dn[1]); // S2
  if(ArraySize(dn)>=1) LV_Append(finalOut,dn[0]); // S1
  LV_Append(finalOut,P);                          // P
  if(ArraySize(up)>=1) LV_Append(finalOut,up[0]); // R1
  if(ArraySize(up)>=2) LV_Append(finalOut,up[1]); // R2
  if(ArraySize(up)>=3) LV_Append(finalOut,up[2]); // R3
}

void LV_DrawLevel(const string tag, const LV_Level &L, const double mid, const double halfW)
{
  bool supply=(L.price>mid);
  bool isPivot=(StringFind(tag,"P",0)==0);

  color base = isPivot ? Inp_LV_PivotColor : (supply ? clrRed : clrLime);
  color fill = LV_Alpha(base,Inp_LV_RectAlpha);

  datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 80);
  if(t1<=0) t1 = TimeCurrent();
  datetime t2 = TimeCurrent() + 86400;

  string name = PREFIX + tag;

  if(Inp_LV_DrawRectangles)
  {
    ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,L.price-halfW,t2,L.price+halfW);
    ObjectSetInteger(0,name,OBJPROP_COLOR,fill);
    ObjectSetInteger(0,name,OBJPROP_BACK,true);
    ObjectSetInteger(0,name,OBJPROP_FILL,true);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
  }
  else
  {
    ObjectCreate(0,name,OBJ_HLINE,0,0,L.price);
    ObjectSetInteger(0,name,OBJPROP_COLOR,base);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,Inp_LV_LineWidth);
  }

  ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
  ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);

  if(Inp_LV_ShowLabels)
  {
    string lbl = name+"_LBL";
    ObjectCreate(0,lbl,OBJ_TEXT,0,t2,L.price);
    ObjectSetString(0,lbl,OBJPROP_TEXT, tag+" "+IntegerToString(L.score));
    ObjectSetInteger(0,lbl,OBJPROP_COLOR, base);
    ObjectSetInteger(0,lbl,OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(0,lbl,OBJPROP_ANCHOR, ANCHOR_LEFT);
    ObjectSetInteger(0,lbl,OBJPROP_HIDDEN,false);
    ObjectSetInteger(0,lbl,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
  }
}

void LV_DrawFallbackLadder7(const double mid, const double halfW)
{
  double Pp = LV_NPrice(LV_RoundStep(mid,10.0));

  LV_Level P  = LV_MakeLevel(Pp,       50, LV_SRC_R10);
  LV_Level R1 = LV_MakeLevel(Pp+10.0,  50, LV_SRC_R10);
  LV_Level R2 = LV_MakeLevel(Pp+20.0,  50, LV_SRC_R10);
  LV_Level R3 = LV_MakeLevel(Pp+30.0,  50, LV_SRC_R10);
  LV_Level S1 = LV_MakeLevel(Pp-10.0,  50, LV_SRC_R10);
  LV_Level S2 = LV_MakeLevel(Pp-20.0,  50, LV_SRC_R10);
  LV_Level S3 = LV_MakeLevel(Pp-30.0,  50, LV_SRC_R10);

  LV_DrawLevel("S3_FB", S3, mid, halfW);
  LV_DrawLevel("S2_FB", S2, mid, halfW);
  LV_DrawLevel("S1_FB", S1, mid, halfW);
  LV_DrawLevel("P_FB",  P,  mid, halfW);
  LV_DrawLevel("R1_FB", R1, mid, halfW);
  LV_DrawLevel("R2_FB", R2, mid, halfW);
  LV_DrawLevel("R3_FB", R3, mid, halfW);

  LV_DBG("Fallback Ladder7 drawn.");
}

bool LV_RecomputeAndDraw()
{
  if(!Inp_LV_Enable){ LV_DeleteObjects(); return false; }
  if(!g_lv_hasContext){ LV_DeleteObjects(); return false; }

  double mid=LV_MidPrice();
  double atrM5=LV_GetATR(g_lv_atrM5);
  if(atrM5<=0.0){ LV_DBG("ATR(Filter)=0. History not loaded."); return false; }

  double maxDist = MathMax(Inp_LV_ScalpMaxDistancePct*mid, Inp_LV_ScalpMaxDistanceATR_M5*atrM5);
  double mergeThr= MathMax(Inp_LV_ScalpMergePct*mid,      Inp_LV_ScalpMergeATR_M5*atrM5);
  double halfW   = MathMax(Inp_LV_DrawWidth_ATR_M5*atrM5, LV_Pts(Inp_LV_DrawWidth_MinPoints));

  LV_DeleteObjects();

  if(ArraySize(g_lv_scored)==0)
  {
    LV_DrawFallbackLadder7(mid,halfW);
    return true;
  }

  LV_Level work[]; ArrayResize(work,0);
  LV_CopyLevels(work,g_lv_scored);

  LV_SortByScoreDesc(work);
  LV_DistanceFilter(work,mid,maxDist);
  LV_MergeProximity(work,mergeThr);
  LV_SortByScoreDesc(work);

  if(ArraySize(work)==0)
  {
    LV_DrawFallbackLadder7(mid,halfW);
    return true;
  }

  LV_Level finalLvls[]; ArrayResize(finalLvls,0);
  if(Inp_LV_UsePivotLadder7) LV_SelectPivotLadder7(work,mid,finalLvls);

  if(ArraySize(finalLvls)<7)
  {
    LV_DrawFallbackLadder7(mid,halfW);
    return true;
  }

  LV_DrawLevel("S3", finalLvls[0], mid, halfW);
  LV_DrawLevel("S2", finalLvls[1], mid, halfW);
  LV_DrawLevel("S1", finalLvls[2], mid, halfW);
  LV_DrawLevel("P",  finalLvls[3], mid, halfW);
  LV_DrawLevel("R1", finalLvls[4], mid, halfW);
  LV_DrawLevel("R2", finalLvls[5], mid, halfW);
  LV_DrawLevel("R3", finalLvls[6], mid, halfW);

  LV_DBG(StringFormat("Drawn Ladder7 | maxDist=%.2f merge=%.2f halfW=%.2f",maxDist,mergeThr,halfW));
  return true;
}

bool LV_Init()
{
  if(!Inp_LV_Enable) return true;

  g_lv_atrH1 = iATR(_Symbol, Inp_LV_ContextTF, Inp_LV_ATRPeriod);
  if(g_lv_atrH1==INVALID_HANDLE){ LV_DBG("Failed ATR(Context) handle."); return false; }

  g_lv_atrM5 = iATR(_Symbol, Inp_LV_FilterTF, Inp_LV_ATRPeriod);
  if(g_lv_atrM5==INVALID_HANDLE){ LV_DBG("Failed ATR(Filter) handle."); return false; }

  g_lv_lastH1=0; g_lv_lastM5=0;
  LV_BuildContext();
  LV_RecomputeAndDraw();
  return true;
}

void LV_Deinit()
{
  LV_DeleteObjects();
  if(g_lv_atrH1!=INVALID_HANDLE){ IndicatorRelease(g_lv_atrH1); g_lv_atrH1=INVALID_HANDLE; }
  if(g_lv_atrM5!=INVALID_HANDLE){ IndicatorRelease(g_lv_atrM5); g_lv_atrM5=INVALID_HANDLE; }
  g_lv_hasContext=false;
  ArrayResize(g_lv_scored,0);
}

void LV_OnTimerTick()
{
  if(!Inp_LV_Enable) return;

  bool newH1 = LV_NewBar(Inp_LV_ContextTF, g_lv_lastH1);
  if(newH1) LV_BuildContext();

  bool newM5 = LV_NewBar(Inp_LV_FilterTF, g_lv_lastM5);
  if(newM5 || newH1) LV_RecomputeAndDraw();
}

void LV_FullRebuildNow()
{
  LV_Deinit();
  LV_Init();
}
void RefreshLevelsAndObjects()
{
  const long cid = 0;

  if(!RefreshMarketData(_Symbol)) { LogA("UI_REFRESH", 0, RC_ENV_BLOCK, "RefreshMarketData failed (no tick)"); return; }
  ChartSetSymbolPeriod(cid, _Symbol, _Period);

  // Toggle autoscroll to force internal refresh (no net user-impact)
  long as = ChartGetInteger(cid, CHART_AUTOSCROLL);
  ChartSetInteger(cid, CHART_AUTOSCROLL, (as==0 ? 1 : 0));
  ChartSetInteger(cid, CHART_AUTOSCROLL, as);

  ChartRedraw(cid);

  const int total = ObjectsTotal(cid, 0, -1);
  for(int i=total-1; i>=0; i--)
  {
    string name = ObjectName(cid, i, 0, -1);
    if(_ShouldRefreshObject(name))
      _TouchObject(cid, name);
  }

  ChartRedraw(cid);
}

void FullRefreshNow()
{
  // Recreate indicator handles to force clean state
  if(g_atrHandle!=INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle = INVALID_HANDLE; }
  if(g_emaHandle!=INVALID_HANDLE)   { IndicatorRelease(g_emaHandle);   g_emaHandle   = INVALID_HANDLE; }
  if(g_atr14Handle!=INVALID_HANDLE) { IndicatorRelease(g_atr14Handle); g_atr14Handle = INVALID_HANDLE; }
  if(g_atr100Handle!=INVALID_HANDLE){ IndicatorRelease(g_atr100Handle);g_atr100Handle= INVALID_HANDLE; }
  if(g_trendMAHandle!=INVALID_HANDLE) { IndicatorRelease(g_trendMAHandle); g_trendMAHandle = INVALID_HANDLE; }

  EnsureATRHandle();
  if(Inp_EnableAutoAnchor) EnsureTrendPermissionHandles();

  if(!RefreshMarketData(_Symbol)) { LogA("UI_REFRESH", 0, RC_ENV_BLOCK, "RefreshMarketData failed (no tick)"); return; }
  ChartRedraw(0);

  // Ensure levels exist (auto-draw) then refresh chart objects (levels/zones) before re-running the cycle
  LV_FullRebuildNow();
  RefreshLevelsAndObjects();

  // Re-run core cycle once (same as timer tick)
  Process();
  UpdateManualNumberingComment();

  ChartRedraw(0);
  LogA("UI_REFRESH", 0, RC_NONE, "Manual refresh executed (levels+objects refreshed)");
}

//============================== MT5 Hooks ============================//
int OnInit()
{
  g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  g_peakEquity  = g_startEquity;
  g_killSwitch  = false;
  g_killTime    = 0;

  trade.SetExpertMagicNumber(Inp_MagicNumber);
  trade.SetDeviationInPoints(Inp_DeviationPoints);

  if(!AcquireLock()) return INIT_FAILED;
  if(!EnsureATRHandle()) { ReleaseLock(); return INIT_FAILED; }
  if(Inp_EnableAutoAnchor) if(!EnsureTrendPermissionHandles()) { ReleaseLock(); return INIT_FAILED; }

  if(!LV_Init()) { ReleaseLock(); return INIT_FAILED; }

  EventSetTimer(1);
  CreateRefreshButton();
  if(Inp_UseEMAOverlay) EnsureEMAOverlayHandles();
  LogA("INIT", 0, RC_NONE, "EA INIT OK (HAB_XAU_ATP v1.013)");
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
  EventKillTimer();

  DeleteRefreshButton();

  LV_Deinit();

  if(g_atrHandle!=INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle = INVALID_HANDLE; }
  if(g_emaHandle!=INVALID_HANDLE)   { IndicatorRelease(g_emaHandle);   g_emaHandle   = INVALID_HANDLE; }
  if(g_atr14Handle!=INVALID_HANDLE) { IndicatorRelease(g_atr14Handle); g_atr14Handle = INVALID_HANDLE; }
  if(g_atr100Handle!=INVALID_HANDLE){ IndicatorRelease(g_atr100Handle);g_atr100Handle= INVALID_HANDLE; }
  if(g_trendMAHandle!=INVALID_HANDLE) { IndicatorRelease(g_trendMAHandle); g_trendMAHandle = INVALID_HANDLE; }

  ReleaseEMAOverlayHandles();
  ReleaseEMARegimeHandles();

  ReleaseLock();
  LogA("DEINIT", 0, RC_NONE, StringFormat("EA DEINIT reason=%d", reason));
}

void OnTimer()
{
  UpdateEquityKillSwitch();
  EnforceTimeStop();

  LV_OnTimerTick();
  Process();
  UpdateManualNumberingComment();
}
void OnTick()  { /* intentionally empty (timer-driven) */ }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
  if(!Inp_EnableRefreshButton) return;

  if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_refreshBtnName)
  {
    FullRefreshNow();
  }
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
  const bool doLog = Inp_LogTradeTransactions;
  if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
  if(trans.symbol != _Symbol) return;

  const ulong deal = trans.deal;
  if(deal == 0) return;

  if(!HistoryDealSelect(deal))
  { if(doLog) PrintFormat("[HAB_L7][TTR] deal=%I64u select failed", deal); return; }

  const long   deal_entry  = (long)HistoryDealGetInteger(deal, DEAL_ENTRY);
  const long   deal_reason = (long)HistoryDealGetInteger(deal, DEAL_REASON);
  const long   deal_type   = (long)HistoryDealGetInteger(deal, DEAL_TYPE);

  const double vol         = HistoryDealGetDouble(deal, DEAL_VOLUME);
  const double price       = HistoryDealGetDouble(deal, DEAL_PRICE);
  const double profit      = HistoryDealGetDouble(deal, DEAL_PROFIT);

  const double commission  = HistoryDealGetDouble(deal, DEAL_COMMISSION);
  const double swap        = HistoryDealGetDouble(deal, DEAL_SWAP);
  const double fee         = HistoryDealGetDouble(deal, DEAL_FEE);
  const double netp        = profit + commission + swap + fee;

  const datetime dtime     = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
  if(deal_entry == DEAL_ENTRY_IN)
  {
    AddEntryTime(dtime);
  }
  else if(deal_entry == DEAL_ENTRY_OUT)
  {
    AddClosedTradeNetProfit(netp);
  }

  const ulong  pos_id      = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
  const ulong  order_id    = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);

  const string comment     = HistoryDealGetString(deal, DEAL_COMMENT);

  if(doLog) PrintFormat("[HAB_L7][TTR] deal=%I64u entry=%d reason=%d type=%d vol=%.2f price=%.2f profit=%.2f posId=%I64u order=%I64u cmt=%s",
              deal, (int)deal_entry, (int)deal_reason, (int)deal_type, vol, price, profit, pos_id, order_id, comment);
}