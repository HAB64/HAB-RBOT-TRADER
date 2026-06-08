//+------------------------------------------------------------------+
//| HAB_PEX_Merged_EA.mq5                                           |
//| نسخه ترکیبی اکسپرت + اندیکاتور — محاسبه و رسم ۱۱ سطح داخلی   |
//| P + S1..S5 + R1..R5 — مدیریت معاملات دستی و خودکار             |
//| v2.3 — Basket Terminator + استراتژی لنگر (Anchor)                |
//+------------------------------------------------------------------+
#property strict
#property version "2.300"
#property description "HAB PEX Merged EA v2.3\n11-Level Pivot Ladder (S5..P..R5)\nAnchor + Basket Terminator + Manual + Auto Trade Management"

#include <Trade\Trade.mqh>

//=====================================================================
//                         ENUMS
//=====================================================================
enum ENUM_SL_MODE
  {
   SL_SEQ_PIPS   = 0,   // پلکانی بر اساس شماره معامله (پیپ)
   SL_ATR        = 1,   // مبتنی بر ATR
   SL_FIXED_PTS  = 2,   // فاصله‌ی ثابت (پوینت)
   SL_STRUCTURAL = 3    // ساختاری (پشت سطح)
  };

enum ENUM_TP_MODE
  {
   TP_STRUCTURAL  = 0,  // ساختاری (لبه‌ی سطح بعدی)
   TP_R_MULTIPLE  = 1   // ضریب R (چند برابر SL)
  };

//=====================================================================
//                         INPUTS
//=====================================================================
//--- عمومی
input ulong           Inp_MagicNumber          = 777777;
input int             Inp_DeviationPoints      = 30;
input int             Inp_CooldownSeconds      = 15;

//--- نردبان ۱۱ سطحی (محاسبه‌ی داخلی)
input ENUM_TIMEFRAMES Inp_ContextTF            = PERIOD_H1;    // تایم‌فریم ساخت کانتکست
input ENUM_TIMEFRAMES Inp_FilterTF             = PERIOD_M5;    // تایم‌فریم فیلتر اسکالپ
input int             Inp_ATRPeriod            = 14;

//--- منابع سطوح
input bool            Inp_UsePrevDayHL         = true;
input bool            Inp_UsePrevWeekHL        = true;
input bool            Inp_UseQuarterHL         = true;
input bool            Inp_UseRound50           = true;
input bool            Inp_UseH4Swings          = true;
input int             Inp_SwingLen             = 3;
input int             Inp_SwingLookbackH4Bars  = 300;

//--- میکرو راندها
input bool            Inp_EnableMicroRounds    = true;
input int             Inp_MicroStep1_USD       = 10;
input int             Inp_MicroStep2_USD       = 5;
input int             Inp_MicroCountEachSide   = 2;
input double          Inp_MicroMaxDist_ATR_M5  = 1.8;

//--- امتیازدهی H1
input int             Inp_LookbackH1Bars       = 600;
input double          Inp_TouchBand_ATR_H1     = 0.12;
input int             Inp_TouchBand_MinPoints  = 10;
input double          Inp_MinReaction_ATR_H1   = 0.60;
input int             Inp_MaxReactionBars_H1   = 3;
input double          Inp_BodyMin_ATR_H1       = 0.30;
input int             Inp_MinScore             = 65;

//--- فیلتر اسکالپ
input double          Inp_ScalpMaxDistPct      = 0.010;        // افزایش برای ۱۱ سطح
input double          Inp_ScalpMaxDistATR_M5   = 3.0;
input double          Inp_ScalpMergePct        = 0.0015;
input double          Inp_ScalpMergeATR_M5     = 0.8;

//--- ظاهر چارت
input bool            Inp_DrawRectangles       = true;
input int             Inp_RectAlpha            = 110;
input int             Inp_LineWidth            = 2;
input double          Inp_DrawWidth_ATR_M5     = 0.12;
input int             Inp_DrawWidth_MinPoints  = 5;
input bool            Inp_ShowLabels           = true;
input color           Inp_PivotColor           = clrGold;
input string          Inp_DrawPrefix           = "HAB_PEX_L11_";

//--- مدیریت ریسک: حجم نردبانی
input double          Inp_Lot_Seq1             = 0.01;    // معامله ۱
input double          Inp_Lot_Seq2             = 0.02;    // معامله ۲
input double          Inp_Lot_Seq3             = 0.04;    // معامله ۳
input double          Inp_Lot_Seq4             = 0.06;    // معامله ۴
input double          Inp_Lot_Seq5             = 0.10;    // معامله ۵
input int             Inp_MaxPositions         = 5;       // سقف کل (دستی + اتوماتیک)

//--- SL
input ENUM_SL_MODE    Inp_SLMode               = SL_SEQ_PIPS;  // حالت حد ضرر
//--- SL پلکانی بر اساس شماره معامله (پیپ) — حالت پیش‌فرض
input double          Inp_PipSizeInPoints      = 10.0;   // ۱ پیپ = چند پوینت (طلا ۲ رقمی: 10 => 1 pip=$0.10)
input double          Inp_SL_Seq1_Pips         = 500.0;  // حد ضرر معامله ۱ (پیپ)
input double          Inp_SL_Seq2_Pips         = 400.0;  // حد ضرر معامله ۲ (پیپ)
input double          Inp_SL_Seq3_Pips         = 300.0;  // حد ضرر معامله ۳ (پیپ)
input double          Inp_SL_Seq4_Pips         = 200.0;  // حد ضرر معامله ۴ (پیپ)
input double          Inp_SL_Seq5_Pips         = 100.0;  // حد ضرر معامله ۵ (پیپ)
//--- سایر حالت‌های SL
input double          Inp_SL_ATR_Mult          = 1.5;     // ضریب ATR برای SL
input int             Inp_SL_FixedPoints       = 3000;    // فاصله‌ی ثابت SL (پوینت)
input int             Inp_SL_StructBuffer_Pts  = 50;      // بافر پشت سطح (پوینت)

//--- TP
input ENUM_TP_MODE    Inp_TPMode               = TP_STRUCTURAL;
input double          Inp_TP_R_Multiple        = 1.5;     // ضریب R
input int             Inp_TP_EdgeBuffer_Pts    = 25;      // بافر لبه‌ی سطح (پوینت)
input int             Inp_TP_MinProfit_Pts     = 50;      // حداقل سود (پوینت)

//--- مدیریت دستی
input bool            Inp_ManageManualTrades   = true;     // اعمال SL/TP روی معاملات دستی
input bool            Inp_SetManualSL          = true;
input bool            Inp_SetManualTP          = true;
input bool            Inp_ManualSLTP_OnlyEmpty = true;     // فقط وقتی SL/TP تنظیم نشده باشد

//--- معاملات خودکار + استراتژی لنگر
input bool            Inp_EnableAutoTrade      = false;    // پیش‌فرض خاموش (برای ایمنی)
input ENUM_TIMEFRAMES Inp_TrendTF              = PERIOD_H1;
input int             Inp_TrendMAPeriod        = 200;
input int             Inp_TrendSlopeBars       = 2;
input bool            Inp_AutoRequirePZone     = true;
input double          Inp_PZone_HalfWidth_USD  = 2.0;     // P ± $۲

//--- مدیریت سبد (Basket Terminator)
input bool            Inp_EnableBasket         = true;     // فعال‌سازی Basket Terminator
input double          Inp_BasketTP_USD         = 30.0;     // هدف سود کل سبد (دلار)
input double          Inp_BasketSL_USD         = -80.0;    // حد ضرر کل سبد (دلار — منفی)
input double          Inp_BasketTrail_USD      = 10.0;     // تریلینگ سبد (دلار)
input double          Inp_BasketTrailStart_USD = 15.0;     // شروع تریل از این سود (دلار)
input bool            Inp_BasketCloseOnHit     = true;     // بستن همه‌ی معاملات هنگام رسیدن به هدف/حد

//--- استراتژی لنگر (Anchor)
input double          Inp_AnchorLot_Reference  = 0.01;    // حجم شناسایی لنگر
input double          Inp_AnchorLot_Tolerance  = 0.005;   // تلرانس حجم لنگر
input bool            Inp_AnchorMagic0Only     = false;   // true => فقط معاملات دستی لنگر شوند
input bool            Inp_EnableAutoAnchor     = true;    // لنگر خودکار (Buy Stop / Sell Stop)
input int             Inp_AutoAnchorExpiryMin  = 60;      // انقضای لنگر خودکار (دقیقه)
input double          Inp_AutoAnchor_MaxRiskPct = 1.0;    // حداکثر ریسک لنگر خودکار (٪)

//--- گیت‌ها
input int             Inp_MaxSpreadPoints      = 80;
input bool            Inp_EnableATRShock       = true;
input int             Inp_ATRShockLookback     = 20;
input double          Inp_ATRShockFactor       = 1.8;
input int             Inp_MinDist_Points       = 100;
input double          Inp_MaxLevelDist_ATR     = 2.2;

//=====================================================================
//   ماژول‌های الهام‌گرفته از سند کوانت (ریسک / اخبار / رژیم نوسان)
//=====================================================================
//--- (۱) مدیریت ریسک کمّی: سقف ضرر روزانه/هفتگی + Circuit Breaker
input bool            Inp_EnableRiskGuard      = true;     // فعال‌سازی محافظ ریسک
input double          Inp_DailyLossLimitPct    = 3.0;      // سقف ضرر روزانه (٪ از اکوئیتی ابتدای روز)
input double          Inp_WeeklyLossLimitPct   = 6.0;      // سقف ضرر هفتگی (٪ از اکوئیتی ابتدای هفته)
input bool            Inp_CloseAllOnDailyLoss  = false;    // هنگام رسیدن به سقف، همه معاملات بسته شود
input bool            Inp_EnableCircuitBreaker = true;     // قطع‌کننده‌ی حرکت سریع قیمت
input int             Inp_CB_WindowSeconds     = 60;       // پنجره‌ی زمانی Circuit Breaker (ثانیه)
input double          Inp_CB_MoveUSD           = 8.0;      // حرکت قیمت در پنجره (دلار) برای فعال‌شدن
input int             Inp_CB_CooldownSeconds   = 300;      // مدت توقف ورود پس از فعال‌شدن CB (ثانیه)

//--- (۲) فیلتر اخبار / تقویم اقتصادی
input bool            Inp_EnableNewsFilter     = true;     // فعال‌سازی فیلتر اخبار
input int             Inp_ServerGMTOffset      = 0;        // اختلاف ساعت سرور با GMT (مثلاً +2 یا +3)
input bool            Inp_News_UseCalendar     = true;     // استفاده از تقویم داخلی MQL5 (در بک‌تست کار نمی‌کند)
input bool            Inp_News_HighOnly        = true;     // فقط اخبار با اهمیت بالا
input int             Inp_News_MinutesBefore   = 30;       // توقف ورود از چند دقیقه قبل
input int             Inp_News_MinutesAfter    = 15;       // توقف ورود تا چند دقیقه بعد
input string          Inp_News_Currencies      = "USD,XAU";// ارزهای مرتبط (با کاما)
input string          Inp_News_ManualWindows   = "";       // پنجره‌های دستی GMT مثل: 15:30-16:15,18:00-18:30

//--- (۳) فیلتر رژیم نوسان
input bool            Inp_EnableRegimeFilter   = true;     // فعال‌سازی فیلتر رژیم نوسان
input int             Inp_Regime_ATRavgPeriod  = 50;       // دوره‌ی میانگین ATR مرجع
input double          Inp_Regime_CalmRatio     = 0.6;      // زیر این نسبت = آرامِ بیش‌ازحد (ورود ممنوع)
input double          Inp_Regime_HighRatio     = 1.8;      // بالای این نسبت = پرنوسانِ بیش‌ازحد (ورود ممنوع)
input bool            Inp_Regime_BlockCalm     = true;     // مسدودکردن ورود در رژیم آرام
input bool            Inp_Regime_BlockHigh     = true;     // مسدودکردن ورود در رژیم پرنوسان

//--- لاگ
input bool            Inp_EnableLog            = true;

//=====================================================================
//                       INTERNALS
//=====================================================================
#define SRC_D1    0x01
#define SRC_W1    0x02
#define SRC_QTR   0x04
#define SRC_R50   0x08
#define SRC_R10   0x10
#define SRC_R5    0x20
#define SRC_H4SW  0x40

#define LADDER_SIZE 11
#define LADDER_UP   5
#define LADDER_DN   5

#include "HAB_PEX_Panel.mqh"

struct Level
  {
   double            price;
   int               score;
   int               reactions;
   int               ageBars;
   int               srcMask;
  };

// تگ‌های ۱۱ سطح: S5..S1, P, R1..R5
string g_tags[LADDER_SIZE]   = {"S5","S4","S3","S2","S1","P","R1","R2","R3","R4","R5"};
string g_fbTags[LADDER_SIZE] = {"S5_FB","S4_FB","S3_FB","S2_FB","S1_FB","P_FB","R1_FB","R2_FB","R3_FB","R4_FB","R5_FB"};

// سطوح محاسبه‌شده (داخلی — بدون وابستگی به آبجکت)
double g_levelPrice[LADDER_SIZE];
bool   g_levelValid[LADDER_SIZE];
bool   g_useFallback = false;

// هندل‌ها
int      g_atrH1       = INVALID_HANDLE;
int      g_atrM5       = INVALID_HANDLE;
int      g_atrEA       = INVALID_HANDLE;
int      g_trendMA     = INVALID_HANDLE;
double   g_atrNowEA    = 0.0;
datetime g_lastCtxBar  = 0;
datetime g_lastDrawBar = 0;
datetime g_lastAction  = 0;

Level    g_scored[];
bool     g_hasContext = false;

CTrade   trade;

// --- استراتژی لنگر (Anchor) ---
bool     g_anchorActive  = false;
ulong    g_anchorTicket  = 0;
int      g_anchorDir     = 0;      // 1=buy, -1=sell
double   g_anchorLot     = 0.0;
double   g_anchorEntry   = 0.0;

// --- Basket Terminator ---
double   g_basketHighWaterMark = 0.0;   // بیشترین سود سبد (برای تریل)
bool     g_basketTrailing      = false; // آیا تریل فعال شده

// --- وضعیت ماژول‌های ریسک/اخبار/رژیم ---
datetime g_dayAnchor    = 0;           // ابتدای روز جاری
datetime g_weekAnchor   = 0;           // ابتدای هفته‌ی جاری
double   g_equityDayStart  = 0.0;      // اکوئیتی ابتدای روز
double   g_equityWeekStart = 0.0;      // اکوئیتی ابتدای هفته
bool     g_dailyHalt    = false;       // توقف به‌خاطر سقف ضرر روزانه
bool     g_weeklyHalt   = false;       // توقف به‌خاطر سقف ضرر هفتگی
// Circuit Breaker
double   g_cbRefPrice   = 0.0;
datetime g_cbRefTime    = 0;
datetime g_cbBlockUntil = 0;
int      g_atrRegime    = INVALID_HANDLE;  // هندل ATR برای رژیم نوسان
// وضعیت گیت‌ها (یک‌بار در هر تیک ارزیابی می‌شوند)
bool     g_blkCB        = false;
bool     g_blkNews      = false;
bool     g_blkRegime    = false;

//=====================================================================
//                         UTILITIES
//=====================================================================
void Log(const string msg)
  {
   if(Inp_EnableLog)
      PrintFormat("[HAB_PEX_v2] %s", msg);
  }

int    DigitsSym()         { return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS); }
double NPrice(double p)    { return NormalizeDouble(p, DigitsSym()); }
double Pts(int pts)        { return pts * _Point; }

double MidPrice()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return 0.0;
   return (bid + ask) * 0.5;
  }

bool NewBar(ENUM_TIMEFRAMES tf, datetime &last)
  {
   datetime t = iTime(_Symbol, tf, 0);
   if(t <= 0) return false;
   if(t != last) { last = t; return true; }
   return false;
  }

double GetATR(int handle)
  {
   if(handle == INVALID_HANDLE) return 0.0;
   double b[];
   if(CopyBuffer(handle, 0, 0, 1, b) != 1) return 0.0;
   return b[0];
  }

double NormalizeLot(double lot)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(lot, minL);
   lot = MathMin(lot, maxL);
   lot = MathFloor((lot / step) + 0.5) * step;
   lot = NormalizeDouble(lot, 8);
   if(lot < minL) lot = minL;
   if(lot > maxL) lot = maxL;
   return lot;
  }

double RoundStep(double price, double step)
  {
   if(step <= 0) return price;
   return MathRound(price / step) * step;
  }

color AlphaColor(color c, int a)
  {
   a = (int)MathMax(0, MathMin(255, a));
   int r = (c & 0x0000FF);
   int g = (c & 0x00FF00) >> 8;
   int b = (c & 0xFF0000) >> 16;
   return (color)((a << 24) | (b << 16) | (g << 8) | r);
  }

//=====================================================================
//               LEVEL ENGINE (ported from indicator)
//=====================================================================
Level MakeLevel(double price, int score, int srcMask)
  {
   Level L;
   L.price     = NPrice(price);
   L.score     = score;
   L.reactions = 0;
   L.ageBars   = 0;
   L.srcMask   = srcMask;
   return L;
  }

void Append(Level &arr[], const Level &x)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = x;
  }

void CopyLevels(Level &dst[], const Level &src[])
  {
   int n = ArraySize(src);
   ArrayResize(dst, n);
   for(int i = 0; i < n; i++) dst[i] = src[i];
  }

void AddOrMerge(Level &cand[], double price, int mask)
  {
   double p = NPrice(price);
   double thr = Pts(2);
   int n = ArraySize(cand);
   for(int i = 0; i < n; i++)
     {
      if(MathAbs(cand[i].price - p) <= thr)
        {
         cand[i].srcMask |= mask;
         return;
        }
     }
   Append(cand, MakeLevel(p, 0, mask));
  }

bool BodyOK(const MqlRates &b, double bodyMin)
  { return (MathAbs(b.close - b.open) >= bodyMin); }

int CountValidReactions(const MqlRates &h1[], int total,
                        double lvl, double band,
                        double minReact, int maxBars, double bodyMin)
  {
   int r = 0;
   int i = 0;
   while(i < total - 1 - maxBars)
     {
      bool touched = (MathAbs(h1[i].high - lvl) <= band || MathAbs(h1[i].low - lvl) <= band);
      if(!touched) { i++; continue; }

      double maxH = h1[i+1].high;
      double minL = h1[i+1].low;
      bool bull = false, bear = false;

      for(int j = i + 1; j <= i + maxBars && j < total; j++)
        {
         if(h1[j].high > maxH) maxH = h1[j].high;
         if(h1[j].low  < minL) minL = h1[j].low;
         if(BodyOK(h1[j], bodyMin))
           {
            if(h1[j].close > h1[j].open) bull = true;
            if(h1[j].close < h1[j].open) bear = true;
           }
        }
      bool upReact   = ((maxH - lvl) >= minReact) && bull;
      bool downReact = ((lvl - minL) >= minReact) && bear;
      if(upReact || downReact) { r++; i += (maxBars + 1); }
      else i++;
     }
   return r;
  }

int ScoreReacts(int r)
  {
   if(r <= 0) return 0;
   if(r == 1) return 13;
   if(r == 2) return 26;
   return 40;
  }

int ScoreTF(int mask)
  {
   int s = 0;
   if((mask & SRC_W1)  != 0) s += 10;
   if((mask & SRC_QTR) != 0) s += 7;
   if((mask & SRC_H4SW)!= 0) s += 5;
   if(s > 20) s = 20;
   return s;
  }

int ScoreInst(int mask)
  {
   int s = 0;
   if((mask & SRC_R50) != 0) s = MathMax(s, 15);
   if((mask & SRC_QTR) != 0) s = MathMax(s, 12);
   if((mask & SRC_W1)  != 0) s = MathMax(s, 10);
   if(s > 15) s = 15;
   return s;
  }

int ScoreAge(int reactions, int ageBars, int recentTouches)
  {
   if(reactions <= 0) return 0;
   int maxAge = 240;
   double x = (double)ageBars / (double)maxAge;
   if(x > 1.0) x = 1.0;
   double s = 25.0 * x;
   if(recentTouches >= 3) s *= 0.5;
   return (int)MathRound(s);
  }

int TouchesRecent(const MqlRates &h1[], int total, double lvl, double band, int recentBars)
  {
   int t = 0;
   int start = (int)MathMax(0, total - recentBars);
   for(int i = start; i < total; i++)
      if(MathAbs(h1[i].high - lvl) <= band || MathAbs(h1[i].low - lvl) <= band) t++;
   return t;
  }

int BarsSinceTouch(const MqlRates &h1[], int total, double lvl, double band)
  {
   for(int i = total - 1; i >= 0; i--)
      if(MathAbs(h1[i].high - lvl) <= band || MathAbs(h1[i].low - lvl) <= band)
         return (total - 1 - i);
   return total;
  }

//--- Build context (H1)
bool BuildContext()
  {
   g_hasContext = false;
   ArrayResize(g_scored, 0);

   double atrH1 = GetATR(g_atrH1);
   if(atrH1 <= 0.0) { Log("ATR(H1)=0"); return false; }

   MqlRates h1[];
   int need = (int)MathMax(200, Inp_LookbackH1Bars);
   int got  = CopyRates(_Symbol, Inp_ContextTF, 0, need, h1);
   if(got < 200) { Log(StringFormat("CopyRates(H1) got=%d <200", got)); return false; }
   ArraySetAsSeries(h1, false);

   Level cand[];
   ArrayResize(cand, 0);
   double mid = MidPrice();

   //--- D1
   if(Inp_UsePrevDayHL)
     {
      double dh = iHigh(_Symbol, PERIOD_D1, 1);
      double dl = iLow(_Symbol, PERIOD_D1, 1);
      double dc = iClose(_Symbol, PERIOD_D1, 1);
      if(dh > 0 && dl > 0) { AddOrMerge(cand, dh, SRC_D1); AddOrMerge(cand, dl, SRC_D1); }
      if(dc > 0) AddOrMerge(cand, dc, SRC_D1);
     }

   //--- W1
   if(Inp_UsePrevWeekHL)
     {
      double wh = iHigh(_Symbol, PERIOD_W1, 1);
      double wl = iLow(_Symbol, PERIOD_W1, 1);
      double wc = iClose(_Symbol, PERIOD_W1, 1);
      if(wh > 0 && wl > 0) { AddOrMerge(cand, wh, SRC_W1); AddOrMerge(cand, wl, SRC_W1); }
      if(wc > 0) AddOrMerge(cand, wc, SRC_W1);
     }

   //--- Quarter
   if(Inp_UseQuarterHL)
     {
      MqlRates d1[];
      int gd = CopyRates(_Symbol, PERIOD_D1, 0, 120, d1);
      if(gd >= 90)
        {
         ArraySetAsSeries(d1, false);
         double qH = d1[0].high, qL = d1[0].low;
         for(int i = 0; i < 90; i++)
           {
            if(d1[i].high > qH) qH = d1[i].high;
            if(d1[i].low  < qL) qL = d1[i].low;
           }
         AddOrMerge(cand, qH, SRC_QTR);
         AddOrMerge(cand, qL, SRC_QTR);
        }
     }

   //--- Round 50
   if(Inp_UseRound50)
     {
      double base = RoundStep(mid, 50.0);
      for(int k = -4; k <= 4; k++)
         AddOrMerge(cand, base + 50.0 * k, SRC_R50);
     }

   //--- H4 Swings
   if(Inp_UseH4Swings)
     {
      MqlRates h4[];
      int gh = CopyRates(_Symbol, PERIOD_H4, 0, Inp_SwingLookbackH4Bars, h4);
      if(gh >= Inp_SwingLen * 2 + 1)
        {
         ArraySetAsSeries(h4, false);
         for(int i = Inp_SwingLen; i < gh - Inp_SwingLen; i++)
           {
            bool isHigh = true, isLow = true;
            for(int j = 1; j <= Inp_SwingLen; j++)
              {
               if(h4[i].high <= h4[i-j].high || h4[i].high <= h4[i+j].high) isHigh = false;
               if(h4[i].low  >= h4[i-j].low  || h4[i].low  >= h4[i+j].low)  isLow  = false;
              }
            if(isHigh) AddOrMerge(cand, h4[i].high, SRC_H4SW);
            if(isLow)  AddOrMerge(cand, h4[i].low,  SRC_H4SW);
           }
        }
     }

   //--- Micro rounds
   if(Inp_EnableMicroRounds && mid > 0)
     {
      double atrM5v = GetATR(g_atrM5);
      double maxDist = (atrM5v > 0) ? Inp_MicroMaxDist_ATR_M5 * atrM5v : 50.0;
      for(int s = 0; s < 2; s++)
        {
         int stepUSD = (s == 0) ? Inp_MicroStep1_USD : Inp_MicroStep2_USD;
         if(stepUSD <= 0) continue;
         double base2 = RoundStep(mid, (double)stepUSD);
         for(int k = -Inp_MicroCountEachSide; k <= Inp_MicroCountEachSide; k++)
           {
            double p = base2 + (double)stepUSD * k;
            if(MathAbs(p - mid) <= maxDist)
               AddOrMerge(cand, p, (s == 0) ? SRC_R10 : SRC_R5);
           }
        }
     }

   //--- Scoring
   double band    = MathMax(Inp_TouchBand_ATR_H1 * atrH1, Pts(Inp_TouchBand_MinPoints));
   double minR    = Inp_MinReaction_ATR_H1 * atrH1;
   double bodyMin = Inp_BodyMin_ATR_H1 * atrH1;

   Level scored[];
   ArrayResize(scored, 0);

   for(int i = 0; i < ArraySize(cand); i++)
     {
      Level L = cand[i];
      L.reactions = CountValidReactions(h1, got, L.price, band, minR, Inp_MaxReactionBars_H1, bodyMin);
      L.ageBars   = BarsSinceTouch(h1, got, L.price, band);
      int recent  = TouchesRecent(h1, got, L.price, band, 60);

      int sc = ScoreReacts(L.reactions) + ScoreTF(L.srcMask) + ScoreInst(L.srcMask)
               + ScoreAge(L.reactions, L.ageBars, recent);
      L.score = sc;

      if(sc >= Inp_MinScore)
         Append(scored, L);
     }

   CopyLevels(g_scored, scored);
   g_hasContext = (ArraySize(g_scored) > 0);
   Log(StringFormat("Context built: %d candidates, %d scored", ArraySize(cand), ArraySize(g_scored)));
   return true;
  }

//--- Sort helpers
void SortByScoreDesc(Level &arr[])
  {
   int n = ArraySize(arr);
   for(int i = 0; i < n - 1; i++)
      for(int j = i + 1; j < n; j++)
         if(arr[j].score > arr[i].score)
           { Level t = arr[i]; arr[i] = arr[j]; arr[j] = t; }
  }

void DistanceFilter(Level &arr[], double ref, double maxDist)
  {
   Level out[];
   ArrayResize(out, 0);
   for(int i = 0; i < ArraySize(arr); i++)
      if(MathAbs(arr[i].price - ref) <= maxDist) Append(out, arr[i]);
   CopyLevels(arr, out);
  }

void MergeProximity(Level &arr[], double thr)
  {
   Level out[];
   ArrayResize(out, 0);
   for(int i = 0; i < ArraySize(arr); i++)
     {
      bool merged = false;
      for(int k = 0; k < ArraySize(out); k++)
        {
         if(MathAbs(arr[i].price - out[k].price) < thr)
           {
            out[k].srcMask |= arr[i].srcMask;
            if(arr[i].score > out[k].score) out[k].score = arr[i].score;
            merged = true;
            break;
           }
        }
      if(!merged) Append(out, arr[i]);
     }
   CopyLevels(arr, out);
  }

//--- Select 11-level ladder: P + 5 up + 5 down
bool SelectPivotLadder11(Level &arr[], double mid, Level &finalOut[])
  {
   ArrayResize(finalOut, 0);
   int n = ArraySize(arr);
   if(n == 0) return false;

   // pivot = closest to mid with score tiebreak
   int pIdx = 0;
   double bestKey = 1e100;
   for(int i = 0; i < n; i++)
     {
      double dist = MathAbs(arr[i].price - mid);
      double key  = dist - 0.0001 * arr[i].score;
      if(key < bestKey) { bestKey = key; pIdx = i; }
     }
   Level P = arr[pIdx];

   Level up[], dn[];
   ArrayResize(up, 0);
   ArrayResize(dn, 0);
   for(int i = 0; i < n; i++)
     {
      if(i == pIdx) continue;
      if(arr[i].price > P.price)      Append(up, arr[i]);
      else if(arr[i].price < P.price) Append(dn, arr[i]);
     }

   // sort by proximity to P
   for(int i = 0; i < ArraySize(up) - 1; i++)
      for(int j = i + 1; j < ArraySize(up); j++)
         if(MathAbs(up[j].price - P.price) < MathAbs(up[i].price - P.price))
           { Level t = up[i]; up[i] = up[j]; up[j] = t; }

   for(int i = 0; i < ArraySize(dn) - 1; i++)
      for(int j = i + 1; j < ArraySize(dn); j++)
         if(MathAbs(dn[j].price - P.price) < MathAbs(dn[i].price - P.price))
           { Level t = dn[i]; dn[i] = dn[j]; dn[j] = t; }

   // Build: S5..S1, P, R1..R5
   if(ArraySize(dn) < LADDER_DN || ArraySize(up) < LADDER_UP)
      return false;

   for(int i = LADDER_DN - 1; i >= 0; i--)
      Append(finalOut, dn[i]);   // S5, S4, S3, S2, S1
   Append(finalOut, P);           // P
   for(int i = 0; i < LADDER_UP; i++)
      Append(finalOut, up[i]);    // R1..R5

   return (ArraySize(finalOut) == LADDER_SIZE);
  }

//--- Fallback: round-10 grid
void BuildFallbackLadder(double mid)
  {
   double Pp = NPrice(RoundStep(mid, 10.0));
   for(int i = 0; i < LADDER_SIZE; i++)
     {
      int offset = i - LADDER_DN;  // -5..+5
      g_levelPrice[i] = NPrice(Pp + 10.0 * offset);
      g_levelValid[i] = true;
     }
   g_useFallback = true;
  }

//--- Compute levels (called on new context bar or M5 bar)
void ComputeLevels()
  {
   double mid = MidPrice();
   if(mid <= 0) return;

   double atrM5 = GetATR(g_atrM5);
   if(atrM5 <= 0) { BuildFallbackLadder(mid); return; }

   if(!g_hasContext || ArraySize(g_scored) == 0)
     {
      BuildFallbackLadder(mid);
      return;
     }

   double maxDist  = MathMax(Inp_ScalpMaxDistPct * mid, Inp_ScalpMaxDistATR_M5 * atrM5);
   double mergeThr = MathMax(Inp_ScalpMergePct * mid,   Inp_ScalpMergeATR_M5 * atrM5);

   Level work[];
   CopyLevels(work, g_scored);
   SortByScoreDesc(work);
   DistanceFilter(work, mid, maxDist);
   MergeProximity(work, mergeThr);
   SortByScoreDesc(work);

   Level finalLvls[];
   if(!SelectPivotLadder11(work, mid, finalLvls) || ArraySize(finalLvls) != LADDER_SIZE)
     {
      BuildFallbackLadder(mid);
      return;
     }

   for(int i = 0; i < LADDER_SIZE; i++)
     {
      g_levelPrice[i] = finalLvls[i].price;
      g_levelValid[i] = true;
     }
   g_useFallback = false;
  }

//=====================================================================
//                      DRAWING ON CHART
//=====================================================================
void DeleteDrawObjects()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, Inp_DrawPrefix, 0) == 0)
         ObjectDelete(0, name);
     }
  }

void DrawLevel(const string tag, double price, double mid, double halfW)
  {
   bool supply = (price > mid);
   bool isPivot = (tag == "P" || tag == "P_FB");
   color base = isPivot ? Inp_PivotColor : (supply ? clrRed : clrLime);
   color fill = AlphaColor(base, Inp_RectAlpha);

   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 80);
   if(t1 <= 0) t1 = TimeCurrent();
   datetime t2 = TimeCurrent() + 86400;

   string name = Inp_DrawPrefix + tag;

   if(Inp_DrawRectangles)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price - halfW, t2, price + halfW);
      ObjectSetInteger(0, name, OBJPROP_COLOR, fill);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

      // خط وسط/پیوت: یک خط افقی طلایی پررنگ و واضح روی مستطیل
      if(isPivot)
        {
         string pl = name + "_LINE";
         ObjectCreate(0, pl, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, pl, OBJPROP_COLOR, Inp_PivotColor);
         ObjectSetInteger(0, pl, OBJPROP_WIDTH, MathMax(Inp_LineWidth, 2));
         ObjectSetInteger(0, pl, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, pl, OBJPROP_BACK, false);
         ObjectSetInteger(0, pl, OBJPROP_SELECTABLE, false);
        }
     }
   else
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, base);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, isPivot ? MathMax(Inp_LineWidth, 2) : Inp_LineWidth);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }

   if(Inp_ShowLabels)
     {
      string lbl = name + "_LBL";
      ObjectCreate(0, lbl, OBJ_TEXT, 0, t2, price);
      ObjectSetString(0, lbl, OBJPROP_TEXT, tag);
      ObjectSetInteger(0, lbl, OBJPROP_COLOR, base);
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
     }
  }

void DrawAllLevels()
  {
   DeleteDrawObjects();

   double mid = MidPrice();
   if(mid <= 0) return;

   double atrM5 = GetATR(g_atrM5);
   double halfW = MathMax(Inp_DrawWidth_ATR_M5 * atrM5, Pts(Inp_DrawWidth_MinPoints));

   for(int i = 0; i < LADDER_SIZE; i++)
     {
      if(!g_levelValid[i]) continue;
      string tag = g_useFallback ? g_fbTags[i] : g_tags[i];
      DrawLevel(tag, g_levelPrice[i], mid, halfW);
     }
  }

//=====================================================================
//                   TRADE ENVIRONMENT CHECKS
//=====================================================================
bool IsTradeEnvOK()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   return false;
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0 || ask <= bid) return false;
   return true;
  }

bool SpreadOK()
  {
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (sp > 0 && sp <= Inp_MaxSpreadPoints);
  }

bool CooldownOK()
  {
   return ((long)(TimeCurrent() - g_lastAction) >= Inp_CooldownSeconds);
  }

int StopLevelPts() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); }
int FreezePts()    { return (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL); }

//=====================================================================
//              POSITION / ORDER COUNTING
//=====================================================================
int CountAllOpenSymbol()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk > 0 && PositionSelectByTicket(tk))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
     }
   return c;
  }

int CountAllPendingSymbol()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT ||
         ot == ORDER_TYPE_BUY_STOP  || ot == ORDER_TYPE_SELL_STOP)
         c++;
     }
   return c;
  }

int CountAllActiveSymbol()
  { return CountAllOpenSymbol() + CountAllPendingSymbol(); }

bool CapOK()
  { return (CountAllActiveSymbol() < Inp_MaxPositions); }

//--- Lot by sequence index (1-based)
double LotForSeqIndex(int idx)
  {
   if(idx <= 0 || idx > 5) return 0.0;
   double lots[5];
   lots[0] = Inp_Lot_Seq1;
   lots[1] = Inp_Lot_Seq2;
   lots[2] = Inp_Lot_Seq3;
   lots[3] = Inp_Lot_Seq4;
   lots[4] = Inp_Lot_Seq5;

   if(idx > Inp_MaxPositions) return 0.0;
   return NormalizeLot(lots[idx - 1]);
  }

double NextEALot()
  {
   int active = CountAllActiveSymbol();
   if(active >= Inp_MaxPositions) return 0.0;
   return LotForSeqIndex(active + 1);
  }

//--- Sequence number of a ticket (1-based) ranked by open time among
//    ALL symbol trades (positions + pendings, manual + EA). Oldest = 1.
int GetSequenceNumberForTicket(ulong targetTicket)
  {
   ulong    tickets[];
   datetime times[];
   int      n = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(times,   n + 1);
      tickets[n] = tk;
      times[n]   = (datetime)PositionGetInteger(POSITION_TIME);
      n++;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(times,   n + 1);
      tickets[n] = tk;
      times[n]   = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      n++;
     }

   // sort ascending by time (oldest first)
   for(int i = 0; i < n - 1; i++)
      for(int j = i + 1; j < n; j++)
         if(times[j] < times[i])
           {
            datetime tt = times[i]; times[i] = times[j]; times[j] = tt;
            ulong   tk2 = tickets[i]; tickets[i] = tickets[j]; tickets[j] = tk2;
           }

   for(int i = 0; i < n; i++)
      if(tickets[i] == targetTicket)
         return i + 1;

   return 0;
  }

//--- Sequence pips for a given 1-based index
double SeqPips(int idx)
  {
   if(idx <= 1) return Inp_SL_Seq1_Pips;
   if(idx == 2) return Inp_SL_Seq2_Pips;
   if(idx == 3) return Inp_SL_Seq3_Pips;
   if(idx == 4) return Inp_SL_Seq4_Pips;
   return Inp_SL_Seq5_Pips;
  }

//=====================================================================
//                 SL / TP COMPUTATION
//=====================================================================
bool UpdateATRForEA()
  {
   g_atrNowEA = 0.0;
   if(g_atrEA == INVALID_HANDLE) return false;
   double b[];
   if(CopyBuffer(g_atrEA, 0, 1, 1, b) != 1) return false;
   if(b[0] <= 0) return false;
   g_atrNowEA = b[0];
   return true;
  }

// Find nearest level index in given direction (1=above, -1=below)
int FindNearestLevel(double ref, int direction, int excludeIdx)
  {
   int bestIdx = -1;
   double bestDist = 1e100;
   for(int i = 0; i < LADDER_SIZE; i++)
     {
      if(!g_levelValid[i] || i == excludeIdx) continue;
      double p = g_levelPrice[i];
      if(direction == 1 && p <= ref) continue;
      if(direction == -1 && p >= ref) continue;
      double dist = MathAbs(p - ref);
      if(dist < bestDist) { bestDist = dist; bestIdx = i; }
     }
   return bestIdx;
  }

double ComputeSL(int dir, double entry, int seqIdx)
  {
   double sl = 0.0;

   if(Inp_SLMode == SL_SEQ_PIPS)
     {
      int idx = (seqIdx >= 1) ? seqIdx : 1;
      double pips = SeqPips(idx);
      double dist = pips * Inp_PipSizeInPoints * _Point;
      if(dist <= 0) return 0.0;
      sl = (dir == 1) ? entry - dist : entry + dist;
     }
   else if(Inp_SLMode == SL_ATR)
     {
      if(g_atrNowEA <= 0) return 0.0;
      double dist = Inp_SL_ATR_Mult * g_atrNowEA;
      sl = (dir == 1) ? entry - dist : entry + dist;
     }
   else if(Inp_SLMode == SL_FIXED_PTS)
     {
      double dist = Inp_SL_FixedPoints * _Point;
      sl = (dir == 1) ? entry - dist : entry + dist;
     }
   else if(Inp_SLMode == SL_STRUCTURAL)
     {
      int idx = FindNearestLevel(entry, (dir == 1) ? -1 : 1, -1);
      if(idx < 0) return 0.0;
      double buf = Inp_SL_StructBuffer_Pts * _Point;
      sl = (dir == 1) ? g_levelPrice[idx] - buf : g_levelPrice[idx] + buf;
     }

   return (sl > 0) ? NPrice(sl) : 0.0;
  }

double ComputeTP(int dir, double entry, double sl)
  {
   double tp = 0.0;

   if(Inp_TPMode == TP_STRUCTURAL)
     {
      int idx = FindNearestLevel(entry, dir, -1);
      if(idx < 0) return 0.0;
      double buf = Inp_TP_EdgeBuffer_Pts * _Point;
      if(dir == 1)
         tp = g_levelPrice[idx] - buf;
      else
         tp = g_levelPrice[idx] + buf;

      double minProfit = Inp_TP_MinProfit_Pts * _Point;
      if(dir == 1 && tp <= entry + minProfit) return 0.0;
      if(dir == -1 && tp >= entry - minProfit) return 0.0;
     }
   else if(Inp_TPMode == TP_R_MULTIPLE)
     {
      if(sl <= 0) return 0.0;
      double slDist = MathAbs(entry - sl);
      double tpDist = slDist * Inp_TP_R_Multiple;
      tp = (dir == 1) ? entry + tpDist : entry - tpDist;
     }

   return (tp > 0) ? NPrice(tp) : 0.0;
  }

//=====================================================================
//          MANUAL TRADE MANAGEMENT (SL / TP)
//=====================================================================
bool ModifySLTP(ulong posTicket, double sl, double tp)
  {
   MqlTradeRequest req;
   ZeroMemory(req);
   MqlTradeResult  res;
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = posTicket;
   req.symbol   = _Symbol;
   req.sl       = sl;
   req.tp       = tp;

   bool ok = OrderSend(req, res);
   if(!ok)
      Log(StringFormat("ModifySLTP FAIL ticket=%I64u ret=%d", posTicket, (int)res.retcode));
   return ok && (res.retcode == 10009 || res.retcode == 10008);
  }

void ManageManualTrades()
  {
   if(!Inp_ManageManualTrades) return;
   if(!IsTradeEnvOK()) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != 0) continue;  // فقط دستی

      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      int seqIdx = GetSequenceNumberForTicket(tk);
      double newSL = ComputeSL(dir, entry, seqIdx);
      double newTP = ComputeTP(dir, entry, newSL);

      bool doSL = Inp_SetManualSL;
      bool doTP = Inp_SetManualTP;

      if(Inp_ManualSLTP_OnlyEmpty)
        {
         if(currentSL > 0) doSL = false;
         if(currentTP > 0) doTP = false;
        }
      else
        {
         // هیسترزیس: فقط اگر تفاوت بیش از ۵ پوینت باشد
         if(doSL && newSL > 0 && MathAbs(currentSL - newSL) < 5.0 * _Point) doSL = false;
         if(doTP && newTP > 0 && MathAbs(currentTP - newTP) < 5.0 * _Point) doTP = false;
        }

      if(!doSL && !doTP) continue;

      double finalSL = doSL ? newSL : currentSL;
      double finalTP = doTP ? newTP : currentTP;

      if(finalSL <= 0 && finalTP <= 0) continue;

      if(ModifySLTP(tk, finalSL, finalTP))
         Log(StringFormat("Manual trade #%I64u SL=%.2f TP=%.2f set", tk, finalSL, finalTP));
     }
  }

// Pivot index in g_levelPrice = LADDER_DN (index 5)
#define PIVOT_IDX LADDER_DN

//=====================================================================
//               ANCHOR STRATEGY (استراتژی لنگر)
//=====================================================================
bool IsAnchorVolume(double vol)
  {
   if(Inp_AnchorLot_Reference <= 0) return false;
   return (MathAbs(vol - Inp_AnchorLot_Reference) <= Inp_AnchorLot_Tolerance);
  }

// Find anchor trade among open positions (newest 0.01 lot trade)
bool FindAnchor(ulong &ticketOut, int &dirOut, double &lotOut, double &entryOut)
  {
   datetime bestT = 0;
   ulong bestTicket = 0;
   int bestDir = 0;
   double bestLot = 0.0;
   double bestEntry = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long pType = PositionGetInteger(POSITION_TYPE);
      int d = 0;
      if(pType == POSITION_TYPE_BUY) d = 1;
      else if(pType == POSITION_TYPE_SELL) d = -1;
      else continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      if(!IsAnchorVolume(vol)) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(Inp_AnchorMagic0Only && magic != 0) continue;

      datetime tOpen = (datetime)PositionGetInteger(POSITION_TIME);
      if(tOpen >= bestT)
        {
         bestT = tOpen;
         bestTicket = ticket;
         bestDir = d;
         bestLot = vol;
         bestEntry = PositionGetDouble(POSITION_PRICE_OPEN);
        }
     }

   if(bestTicket == 0) return false;
   ticketOut = bestTicket;
   dirOut = bestDir;
   lotOut = bestLot;
   entryOut = bestEntry;
   return true;
  }

void ResetAnchorCycle()
  {
   g_anchorActive = false;
   g_anchorTicket = 0;
   g_anchorDir = 0;
   g_anchorLot = 0.0;
   g_anchorEntry = 0.0;
  }

// Delete all EA ladder pending orders (Buy Limit / Sell Limit with our magic)
void DeleteAllEALadderPendings(const string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_SELL_LIMIT)
        {
         trade.OrderDelete(tk);
         Log(StringFormat("Ladder pending deleted ticket=%I64u (%s)", tk, reason));
        }
     }
  }

// Delete AutoAnchor pending (Buy Stop / Sell Stop with comment)
void DeleteAutoAnchorPending(const string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;

      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, "HAB_AUTO_ANCHOR") != 0) continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_SELL_STOP)
        {
         trade.OrderDelete(tk);
         Log(StringFormat("AutoAnchor pending deleted ticket=%I64u (%s)", tk, reason));
        }
     }
  }

// Check if AutoAnchor pending exists
bool HasAutoAnchorPending(ulong &ticketOut, int &dirOut, datetime &setupOut)
  {
   ticketOut = 0;
   dirOut = 0;
   setupOut = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0 || !OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != Inp_MagicNumber) continue;

      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, "HAB_AUTO_ANCHOR") != 0) continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_SELL_STOP)
        {
         ticketOut = tk;
         dirOut = (ot == ORDER_TYPE_BUY_STOP) ? 1 : -1;
         setupOut = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         return true;
        }
     }
   return false;
  }

// Manage existing AutoAnchor pending (expiry + trend flip check)
void ManageAutoAnchorPending()
  {
   ulong tk = 0;
   int dir = 0;
   datetime ts = 0;
   if(!HasAutoAnchorPending(tk, dir, ts)) return;

   // Expiry check
   if(ts > 0 && Inp_AutoAnchorExpiryMin > 0)
     {
      long ageSec = (long)(TimeCurrent() - ts);
      if(ageSec > (long)Inp_AutoAnchorExpiryMin * 60)
        {
         DeleteAutoAnchorPending("expired");
         return;
        }
     }

   // Trend flip check
   int td = TrendDir();
   if(td != 0 && td != dir)
     {
      DeleteAutoAnchorPending("trend flip");
      return;
     }
  }

// AutoAnchor engine: place Buy Stop / Sell Stop near P-Zone
void AutoAnchorEngine()
  {
   if(!Inp_EnableAutoAnchor) return;
   if(!Inp_EnableAutoTrade) return;

   // If an AutoAnchor pending already exists, manage it
   ulong tk = 0;
   int pdir = 0;
   datetime ts = 0;
   if(HasAutoAnchorPending(tk, pdir, ts))
     {
      ManageAutoAnchorPending();
      return;
     }

   // Check trend direction
   int dir = TrendDir();
   if(dir == 0) { Log("AutoAnchor: No trend => skip"); return; }

   // P-zone check
   if(!g_levelValid[PIVOT_IDX]) return;
   double P = g_levelPrice[PIVOT_IDX];
   double mid = MidPrice();
   if(mid <= 0) return;

   if(Inp_AutoRequirePZone)
     {
      double w = Inp_PZone_HalfWidth_USD;
      if(mid < P - w || mid > P + w)
        { Log("AutoAnchor: Outside P-zone => skip"); return; }
     }

   // Gates
   if(!SpreadOK()) return;
   if(ATRShockActive()) return;
   if(RiskGuardBlocksEntry()) return;
   if(g_blkCB || g_blkNews || g_blkRegime) return;

   // Calculate entry price for Stop order
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return;

   int minPts = MathMax(Inp_MinDist_Points, (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   double pad = (double)minPts * _Point;

   double entry = 0.0;
   if(dir == 1)
      entry = MathMax(P, ask + pad);
   else
      entry = MathMin(P, bid - pad);

   // Clamp entry to stay inside P-Zone if required
   if(Inp_AutoRequirePZone)
     {
      double lo = P - Inp_PZone_HalfWidth_USD;
      double hi = P + Inp_PZone_HalfWidth_USD;
      entry = MathMax(entry, lo);
      entry = MathMin(entry, hi);
     }
   entry = NPrice(entry);

   // Verify entry is far enough
   if(dir == 1 && (entry - ask) / _Point < Inp_MinDist_Points) return;
   if(dir == -1 && (bid - entry) / _Point < Inp_MinDist_Points) return;

   // Anchor lot and SL
   double lot = NormalizeLot(Inp_AnchorLot_Reference);  // 0.01
   double slPips = Inp_SL_Seq1_Pips;   // Trade 1 SL = 500 pips
   double slDist = slPips * Inp_PipSizeInPoints * _Point;
   double sl = (dir == 1) ? entry - slDist : entry + slDist;
   sl = NPrice(sl);

   // Risk check
   if(Inp_AutoAnchor_MaxRiskPct > 0)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > 0)
        {
         double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickVal > 0 && tickSz > 0)
           {
            double vpp = tickVal * (_Point / tickSz);
            double riskMoney = lot * (slPips * Inp_PipSizeInPoints) * vpp;
            double riskPct = 100.0 * riskMoney / eq;
            if(riskPct > Inp_AutoAnchor_MaxRiskPct)
              { Log(StringFormat("AutoAnchor: Risk %.2f%% > max %.2f%% => skip", riskPct, Inp_AutoAnchor_MaxRiskPct)); return; }
           }
        }
     }

   // Structural TP
   double tp = ComputeTP(dir, entry, sl);

   // Place Buy Stop / Sell Stop
   trade.SetExpertMagicNumber(Inp_MagicNumber);
   trade.SetDeviationInPoints(Inp_DeviationPoints);

   string cmt = StringFormat("HAB_AUTO_ANCHOR_%s", (dir == 1 ? "BUY" : "SELL"));
   bool ok = false;
   if(dir == 1)
      ok = trade.BuyStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else
      ok = trade.SellStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);

   if(ok)
     {
      g_lastAction = TimeCurrent();
      Log(StringFormat("AutoAnchor %s Stop placed @ %.2f lot=%.2f SL=%.2f TP=%.2f",
                       (dir == 1 ? "BUY" : "SELL"), entry, lot, sl, tp));
     }
   else
      Log(StringFormat("AutoAnchor FAILED ret=%d (%s)",
                       (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()));
  }

//=====================================================================
//               AUTO TRADE (OPTIONAL) — Ladder (requires active anchor)
//=====================================================================
int TrendDir()
  {
   if(g_trendMA == INVALID_HANDLE) return 0;

   int need = Inp_TrendSlopeBars + 2;
   double ma[];
   ArrayResize(ma, need);
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_trendMA, 0, 1, need, ma) != need) return 0;

   MqlRates r[];
   ArrayResize(r, 2);
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, Inp_TrendTF, 1, 2, r) != 2) return 0;

   bool slopeUp   = (ma[0] > ma[Inp_TrendSlopeBars]);
   bool slopeDown = (ma[0] < ma[Inp_TrendSlopeBars]);

   bool up   = (r[0].close > ma[0]) && slopeUp;
   bool down = (r[0].close < ma[0]) && slopeDown;

   if(up && !down) return +1;
   if(down && !up) return -1;
   return 0;
  }

// ATR shock
bool ATRShockActive()
  {
   if(!Inp_EnableATRShock || g_atrNowEA <= 0) return false;
   if(g_atrEA == INVALID_HANDLE) return false;

   double b[];
   int lkb = Inp_ATRShockLookback;
   if(lkb < 3) return false;
   ArrayResize(b, lkb);
   ArraySetAsSeries(b, true);
   int got = CopyBuffer(g_atrEA, 0, 1, lkb, b);
   if(got < 3) return false;

   double t[];
   ArrayResize(t, got);
   for(int i = 0; i < got; i++) t[i] = b[i];
   ArraySort(t);
   double median = t[got / 2];
   if(median <= 0) return false;

   return (g_atrNowEA > median * Inp_ATRShockFactor);
  }

//=====================================================================
//   ماژول‌های کوانت: ریسک‌گارد / Circuit Breaker / اخبار / رژیم نوسان
//=====================================================================

// --- زمان GMT از روی زمان سرور (پشتیبانی از آفست منفی) ---
datetime ServerToGMT(datetime tServer)
  {
   return (datetime)((long)tServer - (long)Inp_ServerGMTOffset * 3600);
  }

// --- بستن همه‌ی معاملات نماد (پوزیشن‌ها + حذف پندینگ‌ها) ---
void CloseAllSymbol(bool includePending)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(tk);
     }
   if(includePending)
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !OrderSelect(tk)) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         trade.OrderDelete(tk);
        }
  }

// --- به‌روزرسانی لنگرهای روز/هفته و وضعیت سقف ضرر ---
void UpdateRiskGuard()
  {
   if(!Inp_EnableRiskGuard) { g_dailyHalt = false; g_weeklyHalt = false; return; }

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // ابتدای روز (نیمه‌شب سرور)
   datetime dayStart = now - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   // ابتدای هفته (یکشنبه = شروع هفته‌ی سرور متاتریدر)
   datetime weekStart = dayStart - (datetime)(dt.day_of_week * 86400);

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_dayAnchor != dayStart)
     {
      g_dayAnchor = dayStart;
      g_equityDayStart = eq;
      g_dailyHalt = false;
     }
   if(g_weekAnchor != weekStart)
     {
      g_weekAnchor = weekStart;
      g_equityWeekStart = eq;
      g_weeklyHalt = false;
     }

   if(g_equityDayStart > 0 && Inp_DailyLossLimitPct > 0)
     {
      double ddPct = (g_equityDayStart - eq) / g_equityDayStart * 100.0;
      if(ddPct >= Inp_DailyLossLimitPct && !g_dailyHalt)
        {
         g_dailyHalt = true;
         Log(StringFormat("DAILY loss limit hit: %.2f%% >= %.2f%% => halt", ddPct, Inp_DailyLossLimitPct));
         if(Inp_CloseAllOnDailyLoss) CloseAllSymbol(true);
        }
     }
   if(g_equityWeekStart > 0 && Inp_WeeklyLossLimitPct > 0)
     {
      double ddPct = (g_equityWeekStart - eq) / g_equityWeekStart * 100.0;
      if(ddPct >= Inp_WeeklyLossLimitPct && !g_weeklyHalt)
        {
         g_weeklyHalt = true;
         Log(StringFormat("WEEKLY loss limit hit: %.2f%% >= %.2f%% => halt", ddPct, Inp_WeeklyLossLimitPct));
         if(Inp_CloseAllOnDailyLoss) CloseAllSymbol(true);
        }
     }
  }

bool RiskGuardBlocksEntry()
  {
   if(!Inp_EnableRiskGuard) return false;
   return (g_dailyHalt || g_weeklyHalt);
  }

// --- Circuit Breaker: حرکت سریع قیمت در پنجره‌ی زمانی ---
bool CircuitBreakerBlocks()
  {
   if(!Inp_EnableCircuitBreaker) return false;

   datetime now = TimeCurrent();
   if(now < g_cbBlockUntil) return true;  // هنوز در دوره‌ی توقف

   double mid = MidPrice();
   if(mid <= 0) return false;

   if(g_cbRefTime == 0 || (long)(now - g_cbRefTime) >= Inp_CB_WindowSeconds)
     {
      g_cbRefTime  = now;
      g_cbRefPrice = mid;
      return false;
     }

   double move = MathAbs(mid - g_cbRefPrice);
   if(move >= Inp_CB_MoveUSD)
     {
      g_cbBlockUntil = now + (datetime)Inp_CB_CooldownSeconds;
      g_cbRefTime  = now;
      g_cbRefPrice = mid;
      Log(StringFormat("Circuit Breaker: move=$%.2f in %ds => block %ds",
                       move, Inp_CB_WindowSeconds, Inp_CB_CooldownSeconds));
      return true;
     }
   return false;
  }

// --- پارس کردن یک پنجره‌ی زمانی "HH:MM-HH:MM" و بررسی عضویت ---
bool InManualNewsWindow(datetime gmtNow)
  {
   if(StringLen(Inp_News_ManualWindows) == 0) return false;

   MqlDateTime g;
   TimeToStruct(gmtNow, g);
   int curMin = g.hour * 60 + g.min;

   string parts[];
   int np = StringSplit(Inp_News_ManualWindows, ',', parts);
   for(int i = 0; i < np; i++)
     {
      string w = parts[i];
      StringTrimLeft(w); StringTrimRight(w);
      if(StringLen(w) == 0) continue;
      string se[];
      if(StringSplit(w, '-', se) != 2) continue;
      string a = se[0], b = se[1];
      StringTrimLeft(a); StringTrimRight(a);
      StringTrimLeft(b); StringTrimRight(b);
      string ah[], bh[];
      if(StringSplit(a, ':', ah) != 2) continue;
      if(StringSplit(b, ':', bh) != 2) continue;
      int s = (int)StringToInteger(ah[0]) * 60 + (int)StringToInteger(ah[1]);
      int e = (int)StringToInteger(bh[0]) * 60 + (int)StringToInteger(bh[1]);
      if(s <= e)
        { if(curMin >= s && curMin <= e) return true; }
      else
        { if(curMin >= s || curMin <= e) return true; } // پنجره‌ی عبوری از نیمه‌شب
     }
   return false;
  }

// --- بررسی تطابق ارز رویداد با لیست ارزهای مرتبط ---
bool NewsCurrencyMatches(const string evCur)
  {
   string list[];
   int n = StringSplit(Inp_News_Currencies, ',', list);
   for(int i = 0; i < n; i++)
     {
      string c = list[i];
      StringTrimLeft(c); StringTrimRight(c);
      if(StringLen(c) == 0) continue;
      if(StringCompare(c, evCur, false) == 0) return true;
     }
   return false;
  }

// --- فیلتر اخبار: true یعنی ورود مسدود است ---
bool NewsBlocksEntry()
  {
   if(!Inp_EnableNewsFilter) return false;

   datetime gmtNow = ServerToGMT(TimeCurrent());

   // (الف) پنجره‌های دستی — همیشه و در بک‌تست هم کار می‌کند
   if(InManualNewsWindow(gmtNow)) return true;

   // (ب) تقویم داخلی MQL5 (در Strategy Tester کار نمی‌کند)
   if(!Inp_News_UseCalendar) return false;
   // در بک‌تست/بهینه‌سازی تقویم در دسترس نیست → فقط پنجره‌های دستی
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return false;

   datetime from = gmtNow - (datetime)(Inp_News_MinutesBefore * 60);
   datetime to   = gmtNow + (datetime)(Inp_News_MinutesAfter  * 60);

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to, NULL, NULL);
   if(total <= 0) return false;

   for(int i = 0; i < total; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;

      MqlCalendarCountry country;
      string evCur = "";
      if(CalendarCountryById(ev.country_id, country)) evCur = country.currency;

      if(StringLen(Inp_News_Currencies) > 0 && !NewsCurrencyMatches(evCur)) continue;
      if(Inp_News_HighOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;

      // رویداد داخل بازه => مسدود
      return true;
     }
   return false;
  }

// --- فیلتر رژیم نوسان: true یعنی ورود مسدود است ---
bool RegimeBlocksEntry()
  {
   if(!Inp_EnableRegimeFilter) return false;
   if(g_atrRegime == INVALID_HANDLE || g_atrNowEA <= 0) return false;

   double b[];
   int p = Inp_Regime_ATRavgPeriod;
   if(p < 5) return false;
   ArrayResize(b, p);
   ArraySetAsSeries(b, true);
   int got = CopyBuffer(g_atrRegime, 0, 1, p, b);
   if(got < 5) return false;

   double sum = 0.0;
   for(int i = 0; i < got; i++) sum += b[i];
   double avg = sum / got;
   if(avg <= 0) return false;

   double ratio = g_atrNowEA / avg;
   if(Inp_Regime_BlockCalm && ratio < Inp_Regime_CalmRatio)
     { Log(StringFormat("Regime CALM ratio=%.2f => block", ratio)); return true; }
   if(Inp_Regime_BlockHigh && ratio > Inp_Regime_HighRatio)
     { Log(StringFormat("Regime HIGH ratio=%.2f => block", ratio)); return true; }
   return false;
  }

// Ladder placement — only called when anchor is active
// Uses g_anchorDir for direction (not recalculated)
void AutoTradeEngine()
  {
   if(!Inp_EnableAutoTrade) return;
   if(!g_anchorActive) return;  // *** لنگر باید فعال باشد ***
   if(!IsTradeEnvOK() || !SpreadOK() || !CooldownOK()) return;
   if(!CapOK()) return;
   if(ATRShockActive()) { Log("ATR shock => auto trade blocked"); return; }

   // --- گیت‌های ماژول‌های کوانت ---
   if(RiskGuardBlocksEntry())  { Log("Risk guard => auto trade blocked"); return; }
   if(g_blkCB)                 { Log("Circuit breaker => auto trade blocked"); return; }
   if(g_blkNews)               { Log("News window => auto trade blocked"); return; }
   if(g_blkRegime)             { Log("Volatility regime => auto trade blocked"); return; }

   // Direction comes from anchor (no independent trend/P-zone check needed for ladder)
   int dir = g_anchorDir;
   if(dir == 0) return;

   double mid = MidPrice();
   if(mid <= 0) return;

   // Place ladder of limit orders at support (buy) or resistance (sell) levels
   int startIdx, endIdx, step;
   if(dir == 1)
     {
      startIdx = PIVOT_IDX - 1;  // S1
      endIdx   = 0;               // S5
      step     = -1;
     }
   else
     {
      startIdx = PIVOT_IDX + 1;  // R1
      endIdx   = LADDER_SIZE - 1; // R5
      step     = 1;
     }

   for(int idx = startIdx; (step == -1 ? idx >= endIdx : idx <= endIdx); idx += step)
     {
      if(!g_levelValid[idx]) continue;
      if(!CapOK()) break;
      if(!CooldownOK()) break;

      double lvl = g_levelPrice[idx];
      if(g_atrNowEA > 0 && MathAbs(lvl - mid) > Inp_MaxLevelDist_ATR * g_atrNowEA)
         continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cur = (dir == 1) ? bid : ask;
      if(MathAbs(lvl - cur) / _Point < Inp_MinDist_Points) continue;

      // Check if pending already exists at this tag
      string tag = g_tags[idx];
      string cmt = "HAB_PEX@" + tag;
      bool exists = false;
      for(int oi = OrdersTotal() - 1; oi >= 0; oi--)
        {
         ulong otk = OrderGetTicket(oi);
         if(otk == 0 || !OrderSelect(otk)) continue;
         if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == Inp_MagicNumber &&
            OrderGetString(ORDER_COMMENT) == cmt)
           { exists = true; break; }
        }
      if(exists) continue;

      double lot = NextEALot();
      if(lot <= 0) break;

      int seqIdx = CountAllActiveSymbol() + 1;  // شماره معامله‌ی بعدی
      double sl = ComputeSL(dir, lvl, seqIdx);
      double tp = ComputeTP(dir, lvl, sl);

      trade.SetExpertMagicNumber(Inp_MagicNumber);
      trade.SetDeviationInPoints(Inp_DeviationPoints);

      bool ok = false;
      if(dir == 1)
         ok = trade.BuyLimit(lot, lvl, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
      else
         ok = trade.SellLimit(lot, lvl, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);

      if(ok)
        {
         g_lastAction = TimeCurrent();
         Log(StringFormat("Auto %s limit @ %.2f lot=%.2f SL=%.2f TP=%.2f tag=%s",
                          (dir == 1 ? "BUY" : "SELL"), lvl, lot, sl, tp, tag));
        }
      else
         Log(StringFormat("Auto limit FAILED ret=%d (%s)",
                          (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
  }

//=====================================================================
//                   EA POSITION SL/TP MANAGEMENT
//=====================================================================
void ManageEAPositions()
  {
   if(!IsTradeEnvOK()) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      // EA positions: only set SL/TP if missing
      if(currentSL > 0 && currentTP > 0) continue;

      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);

      int seqIdx = GetSequenceNumberForTicket(tk);
      double newSL = (currentSL <= 0) ? ComputeSL(dir, entry, seqIdx) : currentSL;
      double newTP = (currentTP <= 0) ? ComputeTP(dir, entry, newSL) : currentTP;

      if(newSL <= 0 && newTP <= 0) continue;

      ModifySLTP(tk, newSL, newTP);
     }
  }

//=====================================================================
//               BASKET TERMINATOR (مدیریت سبدی)
//=====================================================================
// Calculate total PnL of all open positions for this symbol
double CalcBasketPnL()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      total += PositionGetDouble(POSITION_PROFIT)
             + PositionGetDouble(POSITION_SWAP);
     }
   return total;
  }

// Close all positions for this symbol (basket close)
void CloseAllBasket(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(tk);
     }
   // Delete all pending orders too
   DeleteAllEALadderPendings(reason);
   DeleteAutoAnchorPending(reason);
   // Reset anchor cycle
   ResetAnchorCycle();
   // Reset basket tracking
   g_basketHighWaterMark = 0.0;
   g_basketTrailing = false;
   Log(StringFormat("BASKET CLOSED: %s", reason));
  }

// Main Basket Terminator logic
void BasketTerminator()
  {
   if(!Inp_EnableBasket) return;

   // Need at least one open position
   int posCount = CountAllOpenSymbol();
   if(posCount == 0)
     {
      // Reset tracking when no positions
      g_basketHighWaterMark = 0.0;
      g_basketTrailing = false;
      return;
     }

   double pnl = CalcBasketPnL();

   // --- Hard Stop Loss (basket) ---
   if(pnl <= Inp_BasketSL_USD && Inp_BasketCloseOnHit)
     {
      CloseAllBasket(StringFormat("BASKET SL HIT: PnL=%.2f <= %.2f", pnl, Inp_BasketSL_USD));
      return;
     }

   // --- Update high water mark ---
   if(pnl > g_basketHighWaterMark)
      g_basketHighWaterMark = pnl;

   // --- Activate trailing when profit >= start threshold ---
   if(!g_basketTrailing && pnl >= Inp_BasketTrailStart_USD)
     {
      g_basketTrailing = true;
      Log(StringFormat("BASKET TRAIL ACTIVATED: PnL=%.2f >= %.2f", pnl, Inp_BasketTrailStart_USD));
     }

   // --- Take Profit (basket) ---
   if(pnl >= Inp_BasketTP_USD && Inp_BasketCloseOnHit)
     {
      CloseAllBasket(StringFormat("BASKET TP HIT: PnL=%.2f >= %.2f", pnl, Inp_BasketTP_USD));
      return;
     }

   // --- Trailing Stop (basket) ---
   if(g_basketTrailing)
     {
      double trailLevel = g_basketHighWaterMark - Inp_BasketTrail_USD;
      if(pnl <= trailLevel && Inp_BasketCloseOnHit)
        {
         CloseAllBasket(StringFormat("BASKET TRAIL STOP: PnL=%.2f <= HWM(%.2f) - Trail(%.2f) = %.2f",
                                    pnl, g_basketHighWaterMark, Inp_BasketTrail_USD, trailLevel));
         return;
        }
     }

   // --- Export state to GV for Dashboard ---
   GlobalVariableSet("HAB_BASKET_HWM", g_basketHighWaterMark);
   GlobalVariableSet("HAB_BASKET_TRAILING", g_basketTrailing ? 1.0 : 0.0);
  }

//=====================================================================
//                       CORE PROCESS
//=====================================================================
void Process()
  {
   if(!IsTradeEnvOK()) return;

   UpdateATRForEA();

   // Update risk guard (daily/weekly loss caps)
   UpdateRiskGuard();

   // Evaluate entry gates ONCE per tick (CB window/calendar are stateful/costly)
   g_blkCB     = CircuitBreakerBlocks();
   g_blkNews   = NewsBlocksEntry();
   g_blkRegime = RegimeBlocksEntry();

   // Check if dashboard Pause is active (GV set by HAB_Dashboard)
   bool dashPaused = (GlobalVariableCheck("HAB_PEX_PAUSED") &&
                      GlobalVariableGet("HAB_PEX_PAUSED") > 0.5);

   // Manage manual trades (SL/TP assignment) — continues even if paused
   ManageManualTrades();

   // Manage EA-owned positions (SL/TP if missing) — continues even if paused
   ManageEAPositions();

   // ============ BASKET TERMINATOR ============
   // Runs even if paused — protects capital at all times
   BasketTerminator();

   // ============ ANCHOR CYCLE MANAGEMENT ============
   if(!dashPaused && Inp_EnableAutoTrade)
     {
      // Try to detect anchor among open positions
      ulong ancTk = 0;
      int ancDir = 0;
      double ancLot = 0.0, ancEntry = 0.0;
      bool nowAnchor = FindAnchor(ancTk, ancDir, ancLot, ancEntry);

      if(!nowAnchor)
        {
         // Anchor was closed or doesn't exist
         if(g_anchorActive)
           {
            // Cycle ended — delete all ladder pendings
            DeleteAllEALadderPendings("anchor closed - cycle reset");
            ResetAnchorCycle();
            Log("ANCHOR RESET: anchor trade closed => cycle ended, ladder deleted");
           }

         // Try to place AutoAnchor (if enabled)
         AutoAnchorEngine();
        }
      else
        {
         // Anchor exists — delete any AutoAnchor pendings (no longer needed)
         DeleteAutoAnchorPending("anchor present");

         // Detect new anchor or confirm existing
         if(!g_anchorActive || g_anchorTicket != ancTk)
           {
            // New anchor detected — start new cycle
            g_anchorActive = true;
            g_anchorTicket = ancTk;
            g_anchorDir    = ancDir;
            g_anchorLot    = ancLot;
            g_anchorEntry  = ancEntry;

            // Delete old ladder pendings from any previous cycle
            DeleteAllEALadderPendings("new anchor cycle");
            Log(StringFormat("NEW ANCHOR: ticket=%I64u dir=%s lot=%.2f entry=%.2f",
                             g_anchorTicket, (g_anchorDir == 1 ? "BUY" : "SELL"),
                             g_anchorLot, g_anchorEntry));
           }

         // Place ladder orders in anchor direction
         AutoTradeEngine();
        }
     }
   else if(!dashPaused)
     {
      // AutoTrade disabled — still check/reset anchor state
      if(g_anchorActive)
        {
         ulong ancTk2 = 0; int ancDir2 = 0; double ancLot2 = 0, ancEntry2 = 0;
         if(!FindAnchor(ancTk2, ancDir2, ancLot2, ancEntry2))
           {
            DeleteAllEALadderPendings("anchor closed (auto off)");
            ResetAnchorCycle();
           }
        }
     }

   // وضعیت ماژول‌ها روی چارت
   UpdateStatusComment();
  }

// --- به‌روزرسانی پنل آنالیز حرفه‌ای ---
void UpdateStatusComment()
  {
   // Gather all data for the panel
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLvl  = (margin > 0) ? (equity / margin * 100.0) : 0.0;

   // Positions data
   int openCount  = CountAllOpenSymbol();
   double totLots = 0.0;
   double floatPnL = 0.0;
   double totSwap  = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      totLots  += PositionGetDouble(POSITION_VOLUME);
      floatPnL += PositionGetDouble(POSITION_PROFIT);
      totSwap  += PositionGetDouble(POSITION_SWAP);
     }

   // Sequence position
   int seqPos = CountAllActiveSymbol();

   // Basket
   double bskPnL = CalcBasketPnL();

   // Risk guard
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dPct = (g_equityDayStart  > 0) ? (g_equityDayStart  - eq) / g_equityDayStart  * 100.0 : 0.0;
   double wPct = (g_equityWeekStart > 0) ? (g_equityWeekStart - eq) / g_equityWeekStart * 100.0 : 0.0;
   if(dPct < 0) dPct = 0;
   if(wPct < 0) wPct = 0;

   // Gates
   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   bool spreadOK = SpreadOK();
   bool atrShock = ATRShockActive();
   bool coolOK   = CooldownOK();

   // Session stats
   SessionStats stats;
   CalcSessionStats(stats);

   // Close All handler (GV flag from panel button)
   if(GlobalVariableCheck("HAB_PEX_CLOSEALL") && GlobalVariableGet("HAB_PEX_CLOSEALL") > 0.5)
     {
      CloseAllSymbol(true);
      ResetAnchorCycle();
      g_basketHighWaterMark = 0.0;
      g_basketTrailing = false;
      GlobalVariableSet("HAB_PEX_CLOSEALL", 0.0);
      Log("PANEL: Close All triggered by user");
     }

   // Call panel update
   PanelUpdate(
      balance, equity, freeMargin, marginLvl,
      openCount, Inp_MaxPositions, totLots, floatPnL, totSwap,
      g_anchorActive, g_anchorDir, g_anchorTicket, g_anchorEntry, g_anchorLot, seqPos,
      Inp_EnableBasket, bskPnL, Inp_BasketTP_USD, Inp_BasketSL_USD,
      g_basketHighWaterMark, g_basketTrailing,
      Inp_EnableRiskGuard, dPct, Inp_DailyLossLimitPct, g_dailyHalt,
      wPct, Inp_WeeklyLossLimitPct, g_weeklyHalt, g_equityDayStart, g_equityWeekStart,
      spreadPts, Inp_MaxSpreadPoints, spreadOK,
      g_blkCB, g_blkNews, g_blkRegime, atrShock, coolOK,
      g_levelPrice, g_levelValid, g_useFallback,
      stats.tradesToday, stats.wins, stats.losses, stats.profitFactor, stats.netPnL
   );
  }

//=====================================================================
//                      MT5 EVENT HOOKS
//=====================================================================
int OnInit()
  {
   trade.SetExpertMagicNumber(Inp_MagicNumber);
   trade.SetDeviationInPoints(Inp_DeviationPoints);

   // ATR handles
   g_atrH1 = iATR(_Symbol, Inp_ContextTF, Inp_ATRPeriod);
   if(g_atrH1 == INVALID_HANDLE)
     { Log("Failed ATR(H1) handle"); return INIT_FAILED; }

   g_atrM5 = iATR(_Symbol, Inp_FilterTF, Inp_ATRPeriod);
   if(g_atrM5 == INVALID_HANDLE)
     { Log("Failed ATR(M5) handle"); return INIT_FAILED; }

   g_atrEA = iATR(_Symbol, Inp_FilterTF, Inp_ATRPeriod);
   if(g_atrEA == INVALID_HANDLE)
     { Log("Failed ATR(EA) handle"); return INIT_FAILED; }

   // ATR handle for volatility-regime filter (on filter TF)
   g_atrRegime = iATR(_Symbol, Inp_FilterTF, Inp_ATRPeriod);
   if(g_atrRegime == INVALID_HANDLE)
     { Log("Failed ATR(Regime) handle"); return INIT_FAILED; }

   // Trend MA (for auto trade / AutoAnchor)
   if(Inp_EnableAutoTrade || Inp_EnableAutoAnchor)
     {
      g_trendMA = iMA(_Symbol, Inp_TrendTF, Inp_TrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
      if(g_trendMA == INVALID_HANDLE)
        { Log("Failed Trend MA handle"); return INIT_FAILED; }
     }

   // Initialize levels
   for(int i = 0; i < LADDER_SIZE; i++)
     { g_levelPrice[i] = 0; g_levelValid[i] = false; }

   g_lastCtxBar  = 0;
   g_lastDrawBar = 0;
   g_lastAction  = 0;

   // Initial build
   BuildContext();
   ComputeLevels();
   DrawAllLevels();

   EventSetTimer(1);
   // Reset anchor state
   ResetAnchorCycle();

   // Initialize professional analysis panel
   PanelInit();

   Log("EA INIT OK — HAB PEX Merged v2.3 (Anchor + Basket + 11-Level + Quant Guards + Panel)");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   PanelDeinit();
   DeleteDrawObjects();
   Comment("");

   if(g_atrH1    != INVALID_HANDLE) IndicatorRelease(g_atrH1);
   if(g_atrM5    != INVALID_HANDLE) IndicatorRelease(g_atrM5);
   if(g_atrEA    != INVALID_HANDLE) IndicatorRelease(g_atrEA);
   if(g_atrRegime!= INVALID_HANDLE) IndicatorRelease(g_atrRegime);
   if(g_trendMA  != INVALID_HANDLE) IndicatorRelease(g_trendMA);
  }

void OnTimer()
  {
   // Rebuild context on new H1 bar
   bool newCtx = NewBar(Inp_ContextTF, g_lastCtxBar);
   if(newCtx) BuildContext();

   // Recompute & redraw levels on new M5 bar (or H1)
   bool newDraw = NewBar(Inp_FilterTF, g_lastDrawBar);
   if(newDraw || newCtx)
     {
      ComputeLevels();
      DrawAllLevels();
     }

   // Trade management (every tick via timer)
   Process();
  }

void OnTick() { /* timer-driven */ }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   // Handle panel button clicks
   PanelOnChartEvent(id, lparam, dparam, sparam);
  }
//+------------------------------------------------------------------+
