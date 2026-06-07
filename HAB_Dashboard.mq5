//+------------------------------------------------------------------+
//| HAB MASTER CYBORG - FULL SCREEN DASHBOARD v2.3                    |
//| داشبورد تمام‌صفحه حرفه‌ای + لنگر + سبد (Basket)              |
//| v2.3: SL/TP, KillSwitch, SpreadGate, Confirm, ErrorCheck  |
//| ارتباط با اکسپرت اصلی از طریق GlobalVariable                     |
//+------------------------------------------------------------------+
#property copyright "HAB"
#property version   "2.30"
#property strict

#include <Trade/Trade.mqh>

//=====================================================================
//                         INPUTS
//=====================================================================
input string    Inp_DashSymbol        = "XAUUSD";    // نماد هدف
input ulong     Inp_MagicNumber       = 777777;      // شماره‌ی مجیک اکسپرت اصلی
input int       Inp_MaxPositions      = 5;           // سقف پوزیشن

//--- لات نردبانی (باید با اکسپرت اصلی یکسان باشد)
input double    Inp_Lot1              = 0.01;
input double    Inp_Lot2              = 0.02;
input double    Inp_Lot3              = 0.04;
input double    Inp_Lot4              = 0.06;
input double    Inp_Lot5              = 0.10;

//--- ظاهر
input color     Inp_BgColor           = C'12,30,12';
input color     Inp_PanelBg           = C'20,45,20';
input color     Inp_HeaderBg          = C'10,60,30';
input color     Inp_TextColor         = C'200,220,200';
input color     Inp_LabelColor        = clrGold;
input color     Inp_ValueColor        = clrLime;
input color     Inp_WarningColor      = clrOrange;
input color     Inp_DangerColor       = C'255,50,50';
input color     Inp_BtnBorderColor    = C'60,120,60';
input string    Inp_Font              = "Segoe UI";
input string    Inp_FontMono          = "Consolas";

//--- هشدار
input bool      Inp_AlertSound        = true;
input bool      Inp_AlertPush         = true;

//--- رژیم نوسان (محاسبه‌ی مستقل)
input ENUM_TIMEFRAMES Inp_ATR_TF      = PERIOD_M5;
input int       Inp_ATR_Period        = 14;
input int       Inp_Regime_AvgPeriod  = 50;
input double    Inp_Regime_CalmRatio  = 0.6;
input double    Inp_Regime_HighRatio  = 1.8;

//--- ریسک گارد
input double    Inp_DailyLossLimitPct = 3.0;
input double    Inp_WeeklyLossLimitPct= 6.0;

//--- SL/TP پیش‌فرض برای معاملات داشبورد
input bool      Inp_DashAutoSLTP      = true;     // اضافه کردن SL/TP خودکار به معاملات داشبورد
input double    Inp_DashSL_ATR_Mult   = 2.0;      // ضریب ATR برای SL پیش‌فرض
input double    Inp_DashTP_R_Multiple = 1.5;      // ضریب R برای TP (TP = SL × R)
input int       Inp_MaxSpreadPoints   = 80;       // حداکثر اسپرد مجاز برای ورود
input bool      Inp_UseMagicForDash   = false;    // استفاده از MagicNumber EA برای معاملات داشبورد
input bool      Inp_ConfirmDestructive = true;     // تأییدیه قبل از اقدامات مخرب

//=====================================================================
//                         DEFINES
//=====================================================================
#define GV_PAUSED       "HAB_PEX_PAUSED"
#define GV_NEWS_BLOCK   "HAB_PEX_NEWS_BLOCK"
#define GV_KILLSWITCH   "HAB_PEX_KILLSWITCH"
#define GV_BASKET_TRAIL "HAB_BASKET_TRAIL_USD"
#define PREFIX          "HABDASH_"

#define BTN_BUY         1
#define BTN_SELL        2
#define BTN_CLOSE_ALL   3
#define BTN_CLOSE_WIN   4
#define BTN_CLOSE_LOSE  5
#define BTN_DEL_PEND    6
#define BTN_FLIP_LONG   7
#define BTN_FLIP_SHORT  8
#define BTN_TRAIL_ALL   9
#define BTN_BE_ALL      10
#define BTN_PAUSE       11
#define BTN_RESUME      12
#define BTN_RESET       13
#define BTN_PANIC       14
#define BTN_ANCHOR_BUY  15
#define BTN_ANCHOR_SELL 16

//=====================================================================
//                         GLOBALS
//=====================================================================
CTrade   g_trade;
int      g_atrHandle   = INVALID_HANDLE;
double   g_atrNow      = 0.0;

datetime g_dayAnchor    = 0;
datetime g_weekAnchor   = 0;
double   g_eqDayStart   = 0.0;
double   g_eqWeekStart  = 0.0;
double   g_maxDD        = 0.0;
bool     g_alertedDaily = false;
bool     g_alertedWeekly= false;

int      g_chartW = 0;
int      g_chartH = 0;

// Confirmation state for destructive actions
datetime g_confirmTime  = 0;
int      g_confirmBtnId = 0;
#define CONFIRM_TIMEOUT 3  // ثانیه برای تأیید کلیک دوم

//=====================================================================
//                     DRAWING PRIMITIVES
//=====================================================================
string BtnName(int id)     { return PREFIX + "B" + IntegerToString(id); }
string LblName(string tag) { return PREFIX + "L_" + tag; }
string PnlName(string tag) { return PREFIX + "P_" + tag; }

void MakePanel(string name, int x, int y, int w, int h, color bg, color border)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void MakeLabel(string name, int x, int y, string text, color clr, int fontSize, string font = "")
  {
   if(font == "") font = Inp_Font;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void SetLabel(string name, string text, color clr)
  {
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void MakeButton(string name, int x, int y, int w, int h, string text, color bg, color txt, int fontSize)
  {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, Inp_Font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, Inp_BtnBorderColor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
  }

//=====================================================================
//                    POSITION / ACCOUNT HELPERS
//=====================================================================
int CountPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      cnt++;
     }
   return cnt;
  }

double GetNextLot()
  {
   int n = CountPositions();
   if(n >= Inp_MaxPositions) return 0;
   switch(n)
     {
      case 0: return Inp_Lot1;
      case 1: return Inp_Lot2;
      case 2: return Inp_Lot3;
      case 3: return Inp_Lot4;
      default: return Inp_Lot5;
     }
  }

double CalcExposure(int dir)
  {
   double vol = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      int pdir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(pdir == dir) vol += PositionGetDouble(POSITION_VOLUME);
     }
   return vol;
  }

double CalcFloating()
  {
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return pnl;
  }

double CalcPnLSince(datetime since)
  {
   double pnl = 0;
   if(HistorySelect(since, TimeCurrent()))
     {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         if(HistoryDealGetString(tk, DEAL_SYMBOL) != Inp_DashSymbol) continue;
         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
            pnl += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                   + HistoryDealGetDouble(tk, DEAL_COMMISSION);
        }
     }
   pnl += CalcFloating();
   return pnl;
  }

string RegimeText()
  {
   if(g_atrHandle == INVALID_HANDLE || g_atrNow <= 0) return "N/A";
   double b[];
   int p = Inp_Regime_AvgPeriod;
   ArrayResize(b, p);
   ArraySetAsSeries(b, true);
   int got = CopyBuffer(g_atrHandle, 0, 1, p, b);
   if(got < 5) return "N/A";
   double sum = 0;
   for(int i = 0; i < got; i++) sum += b[i];
   double avg = sum / got;
   if(avg <= 0) return "N/A";
   double ratio = g_atrNow / avg;
   if(ratio < Inp_Regime_CalmRatio)  return "CALM";
   if(ratio > Inp_Regime_HighRatio)  return "HIGH";
   return "NORMAL";
  }

// مدت زمان باز بودن آخرین معامله
string GetLastTradeOpenDuration()
  {
   datetime newest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(openTime > newest) newest = openTime;
     }
   if(newest == 0) return "---";
   int elapsed = (int)(TimeCurrent() - newest);
   if(elapsed < 0) elapsed = 0;
   int hours = elapsed / 3600;
   int mins  = (elapsed % 3600) / 60;
   int secs  = elapsed % 60;
   if(hours > 0)
      return IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
   else
      return IntegerToString(mins) + "m " + IntegerToString(secs) + "s";
  }

// --- بررسی اسپرد قبل از ورود ---
bool SpreadOK()
  {
   long spread = SymbolInfoInteger(Inp_DashSymbol, SYMBOL_SPREAD);
   if(spread > Inp_MaxSpreadPoints)
     {
      Alert(StringFormat("[HAB DASH] Spread %d > %d pts => blocked", (int)spread, Inp_MaxSpreadPoints));
      return false;
     }
   return true;
  }

// --- محاسبه SL/TP پیش‌فرض بر اساس ATR ---
void CalcDashSLTP(int dir, double entry, double &sl, double &tp)
  {
   sl = 0; tp = 0;
   if(!Inp_DashAutoSLTP) return;
   if(g_atrNow <= 0) return;

   double slDist = g_atrNow * Inp_DashSL_ATR_Mult;
   sl = (dir == 1) ? entry - slDist : entry + slDist;

   double tpDist = slDist * Inp_DashTP_R_Multiple;
   tp = (dir == 1) ? entry + tpDist : entry - tpDist;

   int digits = (int)SymbolInfoInteger(Inp_DashSymbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
  }

// --- بررسی نتیجه معامله ---
void CheckTradeResult(string action)
  {
   uint retcode = g_trade.ResultRetcode();
   if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      return;
   string desc = g_trade.ResultRetcodeDescription();
   Alert(StringFormat("[HAB DASH] %s FAILED: retcode=%d (%s)", action, retcode, desc));
  }

// --- تأییدیه دوبار کلیک ---
bool ConfirmAction(int btnId)
  {
   if(!Inp_ConfirmDestructive) return true;
   datetime now = TimeCurrent();
   if(g_confirmBtnId == btnId && (long)(now - g_confirmTime) < CONFIRM_TIMEOUT)
     {
      g_confirmBtnId = 0;
      g_confirmTime = 0;
      return true;
     }
   g_confirmBtnId = btnId;
   g_confirmTime = now;
   Alert("[HAB DASH] دوباره کلیک کنید برای تأیید / Click again to confirm");
   return false;
  }

// --- وضعیت لنگر (Anchor) ---
// شناسایی لنگر: پوزیشن با حجم ≈ 0.01 روی نماد هدف
bool GetAnchorInfo(int &ancDir, double &ancEntry, datetime &ancTime)
  {
   datetime bestT = 0;
   ancDir = 0;
   ancEntry = 0;
   ancTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      if(MathAbs(vol - Inp_Lot1) > 0.005) continue;  // not anchor volume

      datetime tOpen = (datetime)PositionGetInteger(POSITION_TIME);
      if(tOpen >= bestT)
        {
         bestT = tOpen;
         long pType = PositionGetInteger(POSITION_TYPE);
         ancDir = (pType == POSITION_TYPE_BUY) ? 1 : -1;
         ancEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         ancTime = tOpen;
        }
     }
   return (ancDir != 0);
  }

string GetAnchorDuration(datetime ancTime)
  {
   if(ancTime == 0) return "---";
   int elapsed = (int)(TimeCurrent() - ancTime);
   if(elapsed < 0) elapsed = 0;
   int hours = elapsed / 3600;
   int mins  = (elapsed % 3600) / 60;
   if(hours > 0)
      return IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
   return IntegerToString(mins) + "m " + IntegerToString(elapsed % 60) + "s";
  }

// شمارش سفارش‌های نردبانی (Limit با مجیک EA)
int CountLadderPendings()
  {
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != Inp_DashSymbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
         cnt++;
     }
   return cnt;
  }

// بررسی AutoAnchor (Buy Stop / Sell Stop با کامنت HAB_AUTO_ANCHOR)
bool HasAutoAnchorPending(string &info)
  {
   info = "---";
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != Inp_DashSymbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;

      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, "HAB_AUTO_ANCHOR") != 0) continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_SELL_STOP)
        {
         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         string dir = (ot == ORDER_TYPE_BUY_STOP) ? "BUY" : "SELL";
         info = dir + " @ " + DoubleToString(price, 2);
         return true;
        }
     }
   return false;
  }

// --- سبد (Basket) PnL ---
double CalcBasketPnL_Dash()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      total += PositionGetDouble(POSITION_PROFIT)
             + PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

//=====================================================================
//                     BUTTON ACTIONS
//=====================================================================
void ActionAnchorBuy()
  {
   if(CountPositions() >= Inp_MaxPositions)
     { Alert("Max positions reached"); return; }
   if(!SpreadOK()) return;
   double ask = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_ASK);
   double sl = 0, tp = 0;
   CalcDashSLTP(1, ask, sl, tp);
   g_trade.Buy(Inp_Lot1, Inp_DashSymbol, 0, sl, tp, "DASH_ANCHOR_BUY");
   CheckTradeResult("Anchor BUY");
   FireAlert(StringFormat("Anchor BUY %.2f placed", Inp_Lot1));
  }

void ActionAnchorSell()
  {
   if(CountPositions() >= Inp_MaxPositions)
     { Alert("Max positions reached"); return; }
   if(!SpreadOK()) return;
   double bid = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   CalcDashSLTP(-1, bid, sl, tp);
   g_trade.Sell(Inp_Lot1, Inp_DashSymbol, 0, sl, tp, "DASH_ANCHOR_SELL");
   CheckTradeResult("Anchor SELL");
   FireAlert(StringFormat("Anchor SELL %.2f placed", Inp_Lot1));
  }

void ActionBuyMarket()
  {
   double lot = GetNextLot();
   if(lot <= 0) { Alert("Max positions reached"); return; }
   if(!SpreadOK()) return;
   double ask = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_ASK);
   double sl = 0, tp = 0;
   CalcDashSLTP(1, ask, sl, tp);
   g_trade.Buy(lot, Inp_DashSymbol, 0, sl, tp, "DASH_BUY");
   CheckTradeResult("BUY");
  }

void ActionSellMarket()
  {
   double lot = GetNextLot();
   if(lot <= 0) { Alert("Max positions reached"); return; }
   if(!SpreadOK()) return;
   double bid = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   CalcDashSLTP(-1, bid, sl, tp);
   g_trade.Sell(lot, Inp_DashSymbol, 0, sl, tp, "DASH_SELL");
   CheckTradeResult("SELL");
  }

void ActionCloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      g_trade.PositionClose(tk);
     }
  }

void ActionCloseWinners()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      if(PositionGetDouble(POSITION_PROFIT) > 0) g_trade.PositionClose(tk);
     }
  }

void ActionCloseLosers()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      if(PositionGetDouble(POSITION_PROFIT) < 0) g_trade.PositionClose(tk);
     }
  }

void ActionDeletePendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != Inp_DashSymbol) continue;
      g_trade.OrderDelete(tk);
     }
  }

void ActionFlipLong()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         g_trade.PositionClose(tk);
     }
   ActionBuyMarket();
  }

void ActionFlipShort()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         g_trade.PositionClose(tk);
     }
   ActionSellMarket();
  }

void ActionTrailStopAll()
  {
   double atr = g_atrNow;
   if(atr <= 0) { Alert("ATR not available for trail"); return; }
   double trailDist = atr * 1.5;
   int digits = (int)SymbolInfoInteger(Inp_DashSymbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

      double bid = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_ASK);
      double cur = (dir == 1) ? bid : ask;

      double newSL = NormalizeDouble((dir == 1) ? cur - trailDist : cur + trailDist, digits);
      bool better = (dir == 1) ? (newSL > curSL || curSL == 0) : (newSL < curSL || curSL == 0);
      if(better) g_trade.PositionModify(tk, newSL, tp);
     }
  }

void ActionBreakevenAll()
  {
   double point = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(Inp_DashSymbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != Inp_DashSymbol) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

      double bid = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(Inp_DashSymbol, SYMBOL_ASK);
      double cur = (dir == 1) ? bid : ask;

      double profit = (dir == 1) ? (cur - entry) : (entry - cur);
      if(profit < 10 * point) continue;

      double beSL = NormalizeDouble(entry + dir * 5 * point, digits);
      bool better = (dir == 1) ? (beSL > curSL || curSL == 0) : (beSL < curSL || curSL == 0);
      if(better) g_trade.PositionModify(tk, beSL, tp);
     }
  }

void ActionPauseCore()
  {
   GlobalVariableSet(GV_PAUSED, 1.0);
   FireAlert("Core PAUSED");
  }

void ActionResumeCore()
  {
   GlobalVariableSet(GV_PAUSED, 0.0);
   if(Inp_AlertSound) PlaySound("ok.wav");
  }

void ActionPanicNuke()
  {
   ActionCloseAll();
   ActionDeletePendings();
   ActionPauseCore();
   FireAlert("PANIC NUKE!");
  }

void HandleButton(int id)
  {
   switch(id)
     {
      case BTN_BUY:         ActionBuyMarket();     break;
      case BTN_SELL:        ActionSellMarket();    break;
      case BTN_CLOSE_ALL:   if(ConfirmAction(BTN_CLOSE_ALL))   ActionCloseAll();      break;
      case BTN_CLOSE_WIN:   ActionCloseWinners();  break;
      case BTN_CLOSE_LOSE:  ActionCloseLosers();   break;
      case BTN_DEL_PEND:    if(ConfirmAction(BTN_DEL_PEND))    ActionDeletePendings();break;
      case BTN_FLIP_LONG:   if(ConfirmAction(BTN_FLIP_LONG))   ActionFlipLong();      break;
      case BTN_FLIP_SHORT:  if(ConfirmAction(BTN_FLIP_SHORT))  ActionFlipShort();     break;
      case BTN_TRAIL_ALL:   ActionTrailStopAll();  break;
      case BTN_BE_ALL:      ActionBreakevenAll();  break;
      case BTN_PAUSE:       ActionPauseCore();     break;
      case BTN_RESUME:      ActionResumeCore();    break;
      case BTN_RESET:       BuildLayout();         break;
      case BTN_PANIC:       if(ConfirmAction(BTN_PANIC))       ActionPanicNuke();     break;
      case BTN_ANCHOR_BUY:  ActionAnchorBuy();     break;
      case BTN_ANCHOR_SELL: ActionAnchorSell();    break;
     }
   ObjectSetInteger(0, BtnName(id), OBJPROP_STATE, false);
  }

void FireAlert(string msg)
  {
   if(Inp_AlertSound) PlaySound("alert.wav");
   if(Inp_AlertPush)  SendNotification("[HAB] " + msg);
   Alert("[HAB DASHBOARD] " + msg);
  }

//=====================================================================
//              FULL-SCREEN DYNAMIC LAYOUT
//=====================================================================
void DeleteAll()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PREFIX, 0) == 0)
         ObjectDelete(0, name);
     }
  }

void BuildLayout()
  {
   DeleteAll();

   g_chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   ChartSetInteger(0, CHART_SHOW, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, Inp_BgColor);

   int margin = 12;
   int fullW  = g_chartW - margin * 2;

   // === بخش اطلاعاتی (بالا ~50%) ===
   int dataH = (int)(g_chartH * 0.50);
   int dataY = margin;
   MakePanel(PnlName("DATA"), margin, dataY, fullW, dataH, Inp_PanelBg, Inp_BtnBorderColor);

   int hdrH = 36;
   MakePanel(PnlName("DATA_HDR"), margin, dataY, fullW, hdrH, Inp_HeaderBg, Inp_BtnBorderColor);
   MakeLabel(LblName("TITLE"), margin + 15, dataY + 8, "HAB MASTER CYBORG v2.3 | اطلاعات + لنگر + سبد + KillSwitch", Inp_LabelColor, 14);

   int gridY = dataY + hdrH + 12;
   int rowH  = (dataH - hdrH - 24) / 8;  // 8 rows (+ basket + killswitch)
   int colW  = fullW / 4;

   int lx1 = margin + 20;
   int lx2 = margin + colW;
   int lx3 = margin + colW * 2;
   int lx4 = margin + colW * 3;
   int valOff = 100;

   int fD = 11;
   int fV = 12;

   // ردیف ۱
   int ry = gridY;
   MakeLabel(LblName("tBAL"),   lx1, ry, "موجودی:", Inp_TextColor, fD);
   MakeLabel(LblName("vBAL"),   lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tFLOAT"), lx2, ry, "سود شناور:", Inp_TextColor, fD);
   MakeLabel(LblName("vFLOAT"), lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tSPRD"),  lx3, ry, "اسپرد:", Inp_TextColor, fD);
   MakeLabel(LblName("vSPRD"),  lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tREG"),   lx4, ry, "رژیم:", Inp_TextColor, fD);
   MakeLabel(LblName("vREG"),   lx4+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۲
   ry += rowH;
   MakeLabel(LblName("tEQ"),    lx1, ry, "اکوئیتی:", Inp_TextColor, fD);
   MakeLabel(LblName("vEQ"),    lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tDAILY"), lx2, ry, "سود روز:", Inp_TextColor, fD);
   MakeLabel(LblName("vDAILY"), lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tTIME"),  lx3, ry, "سرور:", Inp_TextColor, fD);
   MakeLabel(LblName("vTIME"),  lx3+valOff, ry, "---", Inp_TextColor, fV, Inp_FontMono);
   MakeLabel(LblName("tATR"),   lx4, ry, "ATR:", Inp_TextColor, fD);
   MakeLabel(LblName("vATR"),   lx4+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۳
   ry += rowH;
   MakeLabel(LblName("tFM"),    lx1, ry, "مارجین آزاد:", Inp_TextColor, fD);
   MakeLabel(LblName("vFM"),    lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tWEEK"),  lx2, ry, "سود هفته:", Inp_TextColor, fD);
   MakeLabel(LblName("vWEEK"),  lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tPOS"),   lx3, ry, "پوزیشن‌ها:", Inp_TextColor, fD);
   MakeLabel(LblName("vPOS"),   lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tGRD"),   lx4, ry, "محافظ:", Inp_TextColor, fD);
   MakeLabel(LblName("vGRD"),   lx4+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۴
   ry += rowH;
   MakeLabel(LblName("tML"),    lx1, ry, "سطح مارجین:", Inp_TextColor, fD);
   MakeLabel(LblName("vML"),    lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tMDD"),   lx2, ry, "بیشترین افت:", Inp_TextColor, fD);
   MakeLabel(LblName("vMDD"),   lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tLEXP"), lx3, ry, "حجم خرید:", Inp_TextColor, fD);
   MakeLabel(LblName("vLEXP"), lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tNEWS"), lx4, ry, "اخبار:", Inp_TextColor, fD);
   MakeLabel(LblName("vNEWS"), lx4+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۵
   ry += rowH;
   MakeLabel(LblName("tSEXP"), lx1, ry, "حجم فروش:", Inp_TextColor, fD);
   MakeLabel(LblName("vSEXP"), lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tNEXP"), lx2, ry, "خالص:", Inp_TextColor, fD);
   MakeLabel(LblName("vNEXP"), lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tLAST"), lx3, ry, "مدت باز:", Inp_TextColor, fD);
   MakeLabel(LblName("vLAST"), lx3+valOff, ry, "---", Inp_TextColor, fV, Inp_FontMono);
   MakeLabel(LblName("tPHASE"),lx4, ry, "وضعیت:", Inp_TextColor, fD);
   MakeLabel(LblName("vPHASE"),lx4+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۶ — وضعیت لنگر (Anchor)
   ry += rowH;
   MakeLabel(LblName("tANC"),   lx1, ry, "لنگر:", Inp_LabelColor, fD);
   MakeLabel(LblName("vANC"),   lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tANCDUR"),lx2, ry, "مدت لنگر:", Inp_TextColor, fD);
   MakeLabel(LblName("vANCDUR"),lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tLADDR"), lx3, ry, "نردبان:", Inp_TextColor, fD);
   MakeLabel(LblName("vLADDR"), lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tAANC"),  lx4, ry, "لنگر خودکار:", Inp_TextColor, fD);
   MakeLabel(LblName("vAANC"),  lx4+valOff+20, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۷ — سبد (Basket Terminator)
   ry += rowH;
   MakeLabel(LblName("tBSKT"),  lx1, ry, "سبد:", Inp_LabelColor, fD);
   MakeLabel(LblName("vBSKT"),  lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tBHWM"),  lx2, ry, "بیشترین:", Inp_TextColor, fD);
   MakeLabel(LblName("vBHWM"),  lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tBTRL"),  lx3, ry, "تریل:", Inp_TextColor, fD);
   MakeLabel(LblName("vBTRL"),  lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tBSTS"),  lx4, ry, "وضعیت سبد:", Inp_TextColor, fD);
   MakeLabel(LblName("vBSTS"),  lx4+valOff+20, ry, "---", Inp_ValueColor, fV, Inp_FontMono);

   // ردیف ۸ — Kill-Switch + اخبار EA + اسپرد گیت
   ry += rowH;
   MakeLabel(LblName("tKS"),    lx1, ry, "KillSwitch:", Inp_LabelColor, fD);
   MakeLabel(LblName("vKS"),    lx1+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tNEWS2"), lx2, ry, "اخبار EA:", Inp_TextColor, fD);
   MakeLabel(LblName("vNEWS2"), lx2+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tSPGT"),  lx3, ry, "اسپرد گیت:", Inp_TextColor, fD);
   MakeLabel(LblName("vSPGT"),  lx3+valOff, ry, "---", Inp_ValueColor, fV, Inp_FontMono);
   MakeLabel(LblName("tMGC"),   lx4, ry, "Magic:", Inp_TextColor, fD);
   MakeLabel(LblName("vMGC"),   lx4+valOff, ry, IntegerToString(Inp_MagicNumber), Inp_ValueColor, fV, Inp_FontMono);

   // === مرکز فرمان (پایین ~44%) ===
   int cmdY = dataY + dataH + margin;
   int cmdH = g_chartH - cmdY - margin;
   MakePanel(PnlName("CMD"), margin, cmdY, fullW, cmdH, Inp_PanelBg, Inp_BtnBorderColor);

   MakePanel(PnlName("CMD_HDR"), margin, cmdY, fullW, hdrH, Inp_HeaderBg, Inp_BtnBorderColor);
   MakeLabel(LblName("TITLE2"), margin + 15, cmdY + 8, "HAB MASTER CYBORG | مرکز فرمان", Inp_LabelColor, 14);

   // دکمه‌ها: ۴ ستون × ۴ ردیف (۱۶ دکمه)
   int btnAreaY = cmdY + hdrH + 18;
   int btnAreaH = cmdH - hdrH - 36;
   int btnRows  = 4;
   int btnCols  = 4;
   int btnGap   = 10;
   int btnW     = (fullW - 40 - (btnCols - 1) * btnGap) / btnCols;
   int btnH     = (btnAreaH - (btnRows - 1) * btnGap - 40) / btnRows;
   if(btnH > 60) btnH = 60;
   int btnX0    = margin + 20;
   int fBtn     = 11;

   // تعریف دکمه‌ها — فارسی (۱۶ دکمه)
   int    btnIds[16];
   string btnTexts[16];
   color  btnColors[16];

   // ردیف ۱: لنگر + خرید/فروش
   btnIds[0]=BTN_ANCHOR_BUY;  btnTexts[0]="1. لنگر خرید";        btnColors[0]=C'0,180,100';
   btnIds[1]=BTN_ANCHOR_SELL; btnTexts[1]="2. لنگر فروش";       btnColors[1]=C'220,80,0';
   btnIds[2]=BTN_BUY;         btnTexts[2]="3. خرید نردبانی";     btnColors[2]=C'0,140,50';
   btnIds[3]=BTN_SELL;        btnTexts[3]="4. فروش نردبانی";    btnColors[3]=C'180,0,0';
   // ردیف ۲: بستن
   btnIds[4]=BTN_CLOSE_ALL;   btnTexts[4]="5. بستن همه";          btnColors[4]=C'80,80,80';
   btnIds[5]=BTN_CLOSE_WIN;   btnTexts[5]="6. بستن سوددار";    btnColors[5]=C'0,100,0';
   btnIds[6]=BTN_CLOSE_LOSE;  btnTexts[6]="7. بستن ضرردار";    btnColors[6]=C'140,0,0';
   btnIds[7]=BTN_PANIC;       btnTexts[7]="8. اضطراری!";          btnColors[7]=C'180,20,60';
   // ردیف ۳: مدیریت
   btnIds[8]=BTN_FLIP_LONG;   btnTexts[8]="9. معکوس خرید";       btnColors[8]=C'0,100,100';
   btnIds[9]=BTN_FLIP_SHORT;  btnTexts[9]="10. معکوس فروش";     btnColors[9]=C'0,100,100';
   btnIds[10]=BTN_DEL_PEND;   btnTexts[10]="11. حذف پندینگ";      btnColors[10]=C'80,80,80';
   btnIds[11]=BTN_BE_ALL;     btnTexts[11]="12. سربه‌سر";          btnColors[11]=C'60,60,60';
   // ردیف ۴: کنترل
   btnIds[12]=BTN_TRAIL_ALL;  btnTexts[12]="13. تریل استاپ";      btnColors[12]=C'0,80,100';
   btnIds[13]=BTN_RESET;      btnTexts[13]="14. بازنشانی";         btnColors[13]=C'60,60,60';
   btnIds[14]=BTN_PAUSE;      btnTexts[14]="15. توقف";              btnColors[14]=C'200,80,0';
   btnIds[15]=BTN_RESUME;     btnTexts[15]="16. ادامه";             btnColors[15]=C'0,120,40';

   for(int i = 0; i < 16; i++)
     {
      int row = i / btnCols;
      int col = i % btnCols;
      int bx = btnX0 + col * (btnW + btnGap);
      int by = btnAreaY + row * (btnH + btnGap);
      MakeButton(BtnName(btnIds[i]), bx, by, btnW, btnH, btnTexts[i], btnColors[i], clrWhite, fBtn);
     }

   // نمایشگر لات بعدی
   int lotY = btnAreaY + btnRows * (btnH + btnGap) + 5;
   MakeLabel(LblName("tNLOT"), btnX0, lotY, "لات بعدی:", Inp_TextColor, fD);
   MakeLabel(LblName("vNLOT"), btnX0 + 40, lotY, "---", Inp_ValueColor, 13, Inp_FontMono);
   MakeLabel(LblName("tKEYS"), btnX0 + 200, lotY, "[1-9, 0=10, F1-F6=11-16]", C'80,130,80', 9);

   MakeLabel(LblName("tPING"), fullW - 120, lotY, "تاخیر:", Inp_TextColor, 9);
   MakeLabel(LblName("vPING"), fullW - 80, lotY, "---", Inp_ValueColor, 9, Inp_FontMono);

   ChartRedraw(0);
  }

//=====================================================================
//                      UPDATE DATA (TIMER)
//=====================================================================
void UpdateData()
  {
   double atrBuf[];
   ArrayResize(atrBuf, 1);
   ArraySetAsSeries(atrBuf, true);
   if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 0, 1, atrBuf) > 0)
      g_atrNow = atrBuf[0];

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ml  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double fl  = CalcFloating();
   int    pos = CountPositions();

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime dayStart  = now - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   datetime weekStart = dayStart - (datetime)(dt.day_of_week * 86400);

   if(g_dayAnchor != dayStart)
     { g_dayAnchor = dayStart; g_eqDayStart = eq; g_maxDD = 0; g_alertedDaily = false; }
   if(g_weekAnchor != weekStart)
     { g_weekAnchor = weekStart; g_eqWeekStart = eq; g_alertedWeekly = false; }

   double dailyPnL  = CalcPnLSince(dayStart);
   double weeklyPnL = CalcPnLSince(weekStart);

   if(g_eqDayStart > 0)
     {
      double dd = (g_eqDayStart - eq) / g_eqDayStart * 100.0;
      if(dd > g_maxDD) g_maxDD = dd;
     }

   double longExp  = CalcExposure(1);
   double shortExp = CalcExposure(-1);
   double netExp   = longExp - shortExp;
   string regime   = RegimeText();
   long   spreadPts = SymbolInfoInteger(Inp_DashSymbol, SYMBOL_SPREAD);

   // Guard status
   string guard = "OK";
   color  gClr  = Inp_ValueColor;
   double ddDay = (g_eqDayStart > 0) ? (g_eqDayStart - eq) / g_eqDayStart * 100.0 : 0;
   double ddWeek= (g_eqWeekStart> 0) ? (g_eqWeekStart- eq) / g_eqWeekStart * 100.0 : 0;
   if(ddDay >= Inp_DailyLossLimitPct)
     {
      guard = "DAILY HALT"; gClr = Inp_DangerColor;
      if(!g_alertedDaily) { FireAlert("Daily loss limit!"); g_alertedDaily = true; }
     }
   else if(ddWeek >= Inp_WeeklyLossLimitPct)
     {
      guard = "WEEKLY HALT"; gClr = Inp_DangerColor;
      if(!g_alertedWeekly) { FireAlert("Weekly loss limit!"); g_alertedWeekly = true; }
     }

   bool paused = (GlobalVariableCheck(GV_PAUSED) && GlobalVariableGet(GV_PAUSED) > 0.5);
   string phase = paused ? "PAUSED" : "ACTIVE";
   color phClr  = paused ? Inp_WarningColor : Inp_ValueColor;

   string sTime = TimeToString(now, TIME_SECONDS);

   // مدت زمان باز بودن آخرین معامله
   string lastDuration = GetLastTradeOpenDuration();

   string pingStr = IntegerToString(TerminalInfoInteger(TERMINAL_PING_LAST) / 1000) + " ms";

   color regClr = Inp_ValueColor;
   if(regime == "CALM") regClr = clrDeepSkyBlue;
   if(regime == "HIGH") regClr = Inp_DangerColor;

   double nLot = GetNextLot();
   string nLotStr = (nLot > 0) ? DoubleToString(nLot, 2) + " (#" + IntegerToString(pos + 1) + ")" : "MAX";
   color  nLotClr = (nLot > 0) ? Inp_ValueColor : Inp_DangerColor;

   // --- Anchor status ---
   int ancDir = 0;
   double ancEntry = 0;
   datetime ancTime = 0;
   bool ancActive = GetAnchorInfo(ancDir, ancEntry, ancTime);

   string ancStr = "---";
   color  ancClr = Inp_TextColor;
   string ancDurStr = "---";
   if(ancActive)
     {
      ancStr = (ancDir == 1 ? "BUY" : "SELL") + " @ " + DoubleToString(ancEntry, 2);
      ancClr = (ancDir == 1) ? Inp_ValueColor : Inp_WarningColor;
      ancDurStr = GetAnchorDuration(ancTime);
     }

   int ladderCnt = CountLadderPendings();
   string ladderStr = IntegerToString(ladderCnt) + " pending";
   color  ladderClr = (ladderCnt > 0) ? Inp_ValueColor : Inp_TextColor;

   string autoAncInfo = "";
   bool hasAutoAnc = HasAutoAnchorPending(autoAncInfo);
   color autoAncClr = hasAutoAnc ? Inp_WarningColor : Inp_TextColor;

   // --- بروزرسانی مقادیر ---
   SetLabel(LblName("vBAL"),   DoubleToString(bal, 2), Inp_ValueColor);
   SetLabel(LblName("vEQ"),    DoubleToString(eq, 2), Inp_ValueColor);
   SetLabel(LblName("vFM"),    DoubleToString(fm, 2), Inp_ValueColor);
   SetLabel(LblName("vML"),    (ml > 0 ? DoubleToString(ml, 1) + "%" : "---"), Inp_ValueColor);
   SetLabel(LblName("vFLOAT"), DoubleToString(fl, 2), (fl >= 0 ? Inp_ValueColor : Inp_DangerColor));
   SetLabel(LblName("vDAILY"), DoubleToString(dailyPnL, 2), (dailyPnL >= 0 ? Inp_ValueColor : Inp_DangerColor));
   SetLabel(LblName("vWEEK"),  DoubleToString(weeklyPnL, 2), (weeklyPnL >= 0 ? Inp_ValueColor : Inp_DangerColor));
   SetLabel(LblName("vMDD"),   DoubleToString(g_maxDD, 2) + "%", (g_maxDD < Inp_DailyLossLimitPct ? Inp_ValueColor : Inp_DangerColor));
   SetLabel(LblName("vPOS"),   IntegerToString(pos) + " / " + IntegerToString(Inp_MaxPositions), Inp_ValueColor);
   SetLabel(LblName("vLEXP"), DoubleToString(longExp, 2), Inp_ValueColor);
   SetLabel(LblName("vSEXP"), DoubleToString(shortExp, 2), Inp_ValueColor);
   SetLabel(LblName("vNEXP"), DoubleToString(netExp, 2), (MathAbs(netExp) < 0.001 ? Inp_ValueColor : Inp_WarningColor));
   SetLabel(LblName("vSPRD"), IntegerToString(spreadPts) + " pts", (spreadPts < 50 ? Inp_ValueColor : Inp_WarningColor));
   SetLabel(LblName("vTIME"), sTime, Inp_TextColor);
   SetLabel(LblName("vREG"),  regime, regClr);
   SetLabel(LblName("vATR"),  DoubleToString(g_atrNow, 2), Inp_ValueColor);
   SetLabel(LblName("vGRD"),  guard, gClr);
   // News status from EA via GlobalVariable
   bool newsBlocked = false;
   if(GlobalVariableCheck(GV_NEWS_BLOCK))
      newsBlocked = (GlobalVariableGet(GV_NEWS_BLOCK) > 0.5);
   SetLabel(LblName("vNEWS"), (newsBlocked ? "BLOCKED" : "Clear"),
           (newsBlocked ? Inp_DangerColor : Inp_ValueColor));
   SetLabel(LblName("vLAST"), lastDuration, Inp_TextColor);
   SetLabel(LblName("vPHASE"),phase, phClr);
   SetLabel(LblName("vNLOT"), nLotStr, nLotClr);
   SetLabel(LblName("vPING"), pingStr, Inp_ValueColor);

   // Anchor row
   SetLabel(LblName("vANC"),    ancStr, ancClr);
   SetLabel(LblName("vANCDUR"), ancDurStr, (ancActive ? Inp_ValueColor : Inp_TextColor));
   SetLabel(LblName("vLADDR"), ladderStr, ladderClr);
   SetLabel(LblName("vAANC"),  autoAncInfo, autoAncClr);

   // Basket row
   double bPnl = CalcBasketPnL_Dash();
   color  bClr = (bPnl >= 0) ? Inp_ValueColor : Inp_DangerColor;
   SetLabel(LblName("vBSKT"), "$" + DoubleToString(bPnl, 2), bClr);

   // Read basket HWM from EA via GlobalVariable (EA writes it)
   double bHWM = 0.0;
   if(GlobalVariableCheck("HAB_BASKET_HWM"))
      bHWM = GlobalVariableGet("HAB_BASKET_HWM");
   SetLabel(LblName("vBHWM"), "$" + DoubleToString(bHWM, 2), Inp_ValueColor);

   // Trail status
   bool bTrailing = false;
   if(GlobalVariableCheck("HAB_BASKET_TRAILING"))
      bTrailing = (GlobalVariableGet("HAB_BASKET_TRAILING") > 0.5);
   double trailUSD = 10.0;
   if(GlobalVariableCheck(GV_BASKET_TRAIL))
      trailUSD = GlobalVariableGet(GV_BASKET_TRAIL);
   string trailStr = bTrailing ? ("$" + DoubleToString(bHWM - trailUSD, 2)) : "---";
   color  trailClr = bTrailing ? Inp_WarningColor : Inp_TextColor;
   SetLabel(LblName("vBTRL"), trailStr, trailClr);

   // Basket status text
   string bStatus = "INACTIVE";
   color  bStsClr = Inp_TextColor;
   if(pos > 0)
     {
      if(bTrailing) { bStatus = "TRAILING"; bStsClr = Inp_WarningColor; }
      else          { bStatus = "ACTIVE";   bStsClr = Inp_ValueColor; }
     }
   SetLabel(LblName("vBSTS"), bStatus, bStsClr);

   // Kill-Switch row
   bool ksTriggered = false;
   if(GlobalVariableCheck(GV_KILLSWITCH))
      ksTriggered = (GlobalVariableGet(GV_KILLSWITCH) > 0.5);
   string ksStr = ksTriggered ? "HALT" : "OK";
   color  ksClr = ksTriggered ? Inp_DangerColor : Inp_ValueColor;
   SetLabel(LblName("vKS"), ksStr, ksClr);

   // News from EA
   SetLabel(LblName("vNEWS2"), (newsBlocked ? "BLOCKED" : "Clear"),
           (newsBlocked ? Inp_DangerColor : Inp_ValueColor));

   // Spread gate status
   long curSpread = SymbolInfoInteger(Inp_DashSymbol, SYMBOL_SPREAD);
   bool spreadOk = (curSpread <= Inp_MaxSpreadPoints);
   SetLabel(LblName("vSPGT"),
           IntegerToString(curSpread) + "/" + IntegerToString(Inp_MaxSpreadPoints),
           (spreadOk ? Inp_ValueColor : Inp_DangerColor));
  }

//=====================================================================
//                       MT5 EVENT HOOKS
//=====================================================================
int OnInit()
  {
   // Use EA magic number if configured, otherwise 0 (manual)
   g_trade.SetExpertMagicNumber(Inp_UseMagicForDash ? Inp_MagicNumber : 0);
   g_trade.SetDeviationInPoints(30);

   g_atrHandle = iATR(Inp_DashSymbol, Inp_ATR_TF, Inp_ATR_Period);
   if(g_atrHandle == INVALID_HANDLE)
      Print("[HAB DASH] ATR handle failed");

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_eqDayStart  = eq;
   g_eqWeekStart = eq;

   BuildLayout();
   EventSetTimer(1);
   Print("[HAB DASH] v2.3 Full-Screen + Anchor + Basket + KillSwitch + SpreadGate initialized");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteAll();
   ChartSetInteger(0, CHART_SHOW, true);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
  }

void OnTimer()
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(cw != g_chartW || ch != g_chartH)
      BuildLayout();

   UpdateData();
   ChartRedraw(0);
  }

void OnTick() { }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      for(int i = 1; i <= 16; i++)
        {
         if(sparam == BtnName(i))
           { HandleButton(i); return; }
        }
     }

   if(id == CHARTEVENT_KEYDOWN)
     {
      int key = (int)lparam;
      if(key >= 49 && key <= 57)   { HandleButton(key - 48); return; }  // 1-9
      if(key == 48)                { HandleButton(10); return; }         // 0=10
      if(key >= 112 && key <= 117) { HandleButton(key - 101); return; } // F1-F6=11-16
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(cw != g_chartW || ch != g_chartH)
         BuildLayout();
     }
  }
//+------------------------------------------------------------------+
