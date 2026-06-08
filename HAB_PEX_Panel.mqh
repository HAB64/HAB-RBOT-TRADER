//+------------------------------------------------------------------+
//| HAB_PEX_Panel.mqh                                                |
//| پنل آنالیز حرفه‌ای برای HAB PEX Merged EA v2.3                  |
//| نمایش: حساب، پوزیشن‌ها، لنگر، سبد، ریسک، گیت‌ها، سطوح، آمار   |
//+------------------------------------------------------------------+
#ifndef HAB_PEX_PANEL_MQH
#define HAB_PEX_PANEL_MQH

//--- Ensure LADDER_SIZE is available (defined in main EA, guard for safety)
#ifndef LADDER_SIZE
#define LADDER_SIZE 11
#endif

//=====================================================================
//                    PANEL CONFIGURATION
//=====================================================================
#define PANEL_PREFIX       "HAB_PNL_"
#define PANEL_X            10
#define PANEL_Y            30
#define PANEL_WIDTH        320
#define PANEL_ROW_H        18
#define PANEL_HEADER_H     28
#define PANEL_SECTION_H    22
#define PANEL_FONT         "Consolas"
#define PANEL_FONT_SIZE    9
#define PANEL_HEADER_FONT  "Arial Bold"
#define PANEL_HDR_FONT_SZ  11

// Colors
#define CLR_BG             C'20,20,30'
#define CLR_BG_SECTION     C'30,30,45'
#define CLR_BG_HEADER      C'15,80,140'
#define CLR_BORDER         C'60,60,80'
#define CLR_TEXT           C'220,220,220'
#define CLR_TEXT_DIM       C'140,140,160'
#define CLR_TEXT_BRIGHT    C'255,255,255'
#define CLR_PROFIT         C'0,220,100'
#define CLR_LOSS           C'255,60,60'
#define CLR_WARN           C'255,180,0'
#define CLR_GATE_OK        C'0,180,80'
#define CLR_GATE_BLOCK     C'220,40,40'
#define CLR_ANCHOR_ACTIVE  C'0,200,255'
#define CLR_GOLD           C'255,215,0'
#define CLR_BTN_PAUSE      C'180,100,0'
#define CLR_BTN_CLOSE      C'160,30,30'
#define CLR_BTN_TEXT       C'255,255,255'

//=====================================================================
//                     PANEL STATE
//=====================================================================
bool   g_panelVisible    = true;
bool   g_panelMinimized  = false;
int    g_panelTotalH     = 0;
string g_panelObjects[];
int    g_panelObjCount   = 0;

//=====================================================================
//                     HELPER FUNCTIONS
//=====================================================================
void PanelObjAdd(const string name)
  {
   ArrayResize(g_panelObjects, g_panelObjCount + 1);
   g_panelObjects[g_panelObjCount] = name;
   g_panelObjCount++;
  }

void PanelDeleteAll()
  {
   for(int i = 0; i < g_panelObjCount; i++)
      ObjectDelete(0, g_panelObjects[i]);
   g_panelObjCount = 0;
   ArrayResize(g_panelObjects, 0);
  }

string PanelName(const string id)
  { return PANEL_PREFIX + id; }

//--- Create background rectangle
void CreateRect(const string id, int x, int y, int w, int h, color bgClr, color borderClr)
  {
   string name = PanelName(id);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PanelObjAdd(name);
  }

//--- Create text label
void CreateLabel(const string id, int x, int y, const string text,
                 color clr, int fontSize = PANEL_FONT_SIZE,
                 const string font = PANEL_FONT)
  {
   string name = PanelName(id);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PanelObjAdd(name);
  }

//--- Create clickable button
void CreateButton(const string id, int x, int y, int w, int h,
                  const string text, color bgClr, color txtClr)
  {
   string name = PanelName(id);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetString(0, name, OBJPROP_FONT, PANEL_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PANEL_FONT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PanelObjAdd(name);
  }

//--- Update existing label text and color
void UpdateLabel(const string id, const string text, color clr = CLR_TEXT)
  {
   string name = PanelName(id);
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
     }
  }

//--- Update button text
void UpdateButton(const string id, const string text, color bgClr = CLR_BTN_PAUSE)
  {
   string name = PanelName(id);
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
     }
  }

//--- Progress bar (simple rectangle within a rectangle)
void CreateProgressBar(const string id, int x, int y, int w, int h,
                       double pct, color barClr, color bgClr)
  {
   // Background
   CreateRect(id + "_BG", x, y, w, h, bgClr, CLR_BORDER);
   // Fill
   int fillW = (int)MathMax(1, MathMin(w - 2, (w - 2) * MathAbs(pct) / 100.0));
   CreateRect(id + "_FILL", x + 1, y + 1, fillW, h - 2, barClr, barClr);
  }

//=====================================================================
//             SECTION DRAWING (called in BuildPanel)
//=====================================================================
int g_curY = 0;  // track current Y position during build

void SectionHeader(const string id, const string title, int &yPos)
  {
   CreateRect("SEC_" + id, PANEL_X, yPos, PANEL_WIDTH, PANEL_SECTION_H, CLR_BG_SECTION, CLR_BORDER);
   CreateLabel("SECLBL_" + id, PANEL_X + 8, yPos + 3, title, CLR_GOLD, PANEL_FONT_SIZE, "Arial Bold");
   yPos += PANEL_SECTION_H;
  }

void DataRow(const string id, const string label, const string value,
             int &yPos, color valClr = CLR_TEXT)
  {
   CreateLabel("L_" + id, PANEL_X + 10, yPos + 1, label, CLR_TEXT_DIM);
   CreateLabel("V_" + id, PANEL_X + 160, yPos + 1, value, valClr);
   yPos += PANEL_ROW_H;
  }

//=====================================================================
//                    BUILD PANEL LAYOUT
//=====================================================================
void PanelBuild()
  {
   PanelDeleteAll();
   if(!g_panelVisible) return;

   int y = PANEL_Y;

   //--- Main header
   CreateRect("MAIN_HDR", PANEL_X, y, PANEL_WIDTH, PANEL_HEADER_H, CLR_BG_HEADER, CLR_BORDER);
   CreateLabel("HDR_TITLE", PANEL_X + 10, y + 5, "HAB PEX v2.3 Dashboard", CLR_TEXT_BRIGHT, PANEL_HDR_FONT_SZ, PANEL_HEADER_FONT);
   // Minimize button
   CreateButton("BTN_MIN", PANEL_X + PANEL_WIDTH - 25, y + 3, 20, 22,
                (g_panelMinimized ? "+" : "-"), CLR_BG_SECTION, CLR_TEXT_BRIGHT);
   y += PANEL_HEADER_H + 2;

   if(g_panelMinimized)
     {
      g_panelTotalH = y - PANEL_Y;
      // Draw overall background
      CreateRect("MAIN_BG", PANEL_X, PANEL_Y, PANEL_WIDTH, g_panelTotalH, CLR_BG, CLR_BORDER);
      return;
     }

   //=== ACCOUNT SECTION ===
   SectionHeader("ACCT", "\x25C8 Account", y);
   DataRow("BAL",     "Balance:",       "---", y);
   DataRow("EQ",      "Equity:",        "---", y);
   DataRow("FREEMG",  "Free Margin:",   "---", y);
   DataRow("MGLEVEL", "Margin Level:",  "---", y);
   y += 4;

   //=== POSITIONS SECTION ===
   SectionHeader("POS", "\x25C8 Positions", y);
   DataRow("POSOPEN", "Open:",          "---", y);
   DataRow("POSTOT",  "Total Lots:",    "---", y);
   DataRow("POSPNL",  "Float P/L:",     "---", y);
   DataRow("POSSWAP", "Swap:",          "---", y);
   y += 4;

   //=== ANCHOR SECTION ===
   SectionHeader("ANC", "\x25C8 Anchor Strategy", y);
   DataRow("ANCST",   "Status:",        "---", y);
   DataRow("ANCDIR",  "Direction:",     "---", y);
   DataRow("ANCENT",  "Entry:",         "---", y);
   DataRow("ANCLOT",  "Lot:",           "---", y);
   DataRow("ANCSEQ",  "Seq Position:",  "---", y);
   y += 4;

   //=== BASKET SECTION ===
   SectionHeader("BSK", "\x25C8 Basket Terminator", y);
   DataRow("BSKPNL",  "Basket P/L:",    "---", y);
   DataRow("BSKTP",   "TP Target:",     "---", y);
   DataRow("BSKSL",   "SL Limit:",      "---", y);
   DataRow("BSKHWM",  "High Water:",    "---", y);
   DataRow("BSKTRL",  "Trailing:",      "---", y);
   // Progress bar placeholder
   CreateRect("BSK_PROG_BG", PANEL_X + 10, y, PANEL_WIDTH - 20, 10, C'40,40,60', CLR_BORDER);
   CreateRect("BSK_PROG_FILL", PANEL_X + 11, y + 1, 1, 8, CLR_PROFIT, CLR_PROFIT);
   y += 14;
   y += 4;

   //=== RISK GUARD SECTION ===
   SectionHeader("RSK", "\x25C8 Risk Guard", y);
   DataRow("RSKDAY",  "Daily DD:",      "---", y);
   DataRow("RSKWK",   "Weekly DD:",     "---", y);
   DataRow("RSKEQD",  "Eq. Start Day:", "---", y);
   DataRow("RSKEQW",  "Eq. Start Wk:",  "---", y);
   y += 4;

   //=== GATES SECTION ===
   SectionHeader("GATE", "\x25C8 Entry Gates", y);
   DataRow("GTSPRD",  "Spread:",        "---", y);
   DataRow("GTCB",    "Circuit Brk:",   "---", y);
   DataRow("GTNEWS",  "News Filter:",   "---", y);
   DataRow("GTREG",   "Vol. Regime:",   "---", y);
   DataRow("GTATR",   "ATR Shock:",     "---", y);
   DataRow("GTCOOL",  "Cooldown:",      "---", y);
   y += 4;

   //=== LEVELS SECTION ===
   SectionHeader("LVL", "\x25C8 Pivot Ladder (11 Levels)", y);
   for(int i = 0; i < LADDER_SIZE; i++)
     {
      string rowId = "LVL" + IntegerToString(i);
      DataRow(rowId, "---", "---", y);
     }
   y += 4;

   //=== SESSION STATS SECTION ===
   SectionHeader("STAT", "\x25C8 Session Stats", y);
   DataRow("STTOT",   "Trades Today:",  "---", y);
   DataRow("STWINS",  "Wins:",          "---", y);
   DataRow("STLOSS",  "Losses:",        "---", y);
   DataRow("STPF",    "Profit Factor:", "---", y);
   DataRow("STNET",   "Net P/L Today:", "---", y);
   y += 4;

   //=== CONTROL BUTTONS ===
   SectionHeader("CTRL", "\x25C8 Controls", y);
   int btnW = (PANEL_WIDTH - 30) / 2;
   CreateButton("BTN_PAUSE", PANEL_X + 8, y + 2, btnW, 24,
                "PAUSE EA", CLR_BTN_PAUSE, CLR_BTN_TEXT);
   CreateButton("BTN_CLOSEALL", PANEL_X + 8 + btnW + 8, y + 2, btnW, 24,
                "CLOSE ALL", CLR_BTN_CLOSE, CLR_BTN_TEXT);
   y += 30;

   g_panelTotalH = y - PANEL_Y + 4;

   // Draw overall background (behind everything)
   CreateRect("MAIN_BG", PANEL_X, PANEL_Y, PANEL_WIDTH, g_panelTotalH, CLR_BG, CLR_BORDER);
  }

//=====================================================================
//                    UPDATE PANEL DATA
//=====================================================================
void PanelUpdate(
   // Account
   double balance, double equity, double freeMargin, double marginLevel,
   // Positions
   int openCount, int maxPos, double totalLots, double floatPnL, double totalSwap,
   // Anchor
   bool anchorActive, int anchorDir, ulong anchorTicket,
   double anchorEntry, double anchorLot, int seqPosition,
   // Basket
   bool basketEnabled, double basketPnL, double basketTP,
   double basketSL, double basketHWM, bool basketTrailing,
   // Risk Guard
   bool riskEnabled, double dailyDD, double dailyLimit,
   bool dailyHalt, double weeklyDD, double weeklyLimit,
   bool weeklyHalt, double eqDayStart, double eqWeekStart,
   // Gates
   int spreadPts, int maxSpread, bool gateSpreadOK,
   bool gateCB, bool gateNews, bool gateRegime,
   bool gateATRShock, bool gateCooldownOK,
   // Levels
   double &levelPrices[], bool &levelValid[], bool useFallback,
   // Stats
   int tradesToday, int wins, int losses, double profitFactor, double netPnLToday
)
  {
   if(!g_panelVisible || g_panelMinimized) return;

   //--- Account
   UpdateLabel("V_BAL",     StringFormat("$%.2f", balance), CLR_TEXT_BRIGHT);
   UpdateLabel("V_EQ",      StringFormat("$%.2f", equity),
               (equity >= balance) ? CLR_PROFIT : CLR_LOSS);
   UpdateLabel("V_FREEMG",  StringFormat("$%.2f", freeMargin), CLR_TEXT);
   UpdateLabel("V_MGLEVEL", (marginLevel > 0) ? StringFormat("%.1f%%", marginLevel) : "---",
               (marginLevel > 200) ? CLR_PROFIT : (marginLevel > 100 ? CLR_WARN : CLR_LOSS));

   //--- Positions
   color posClr = (openCount >= maxPos) ? CLR_LOSS : CLR_TEXT_BRIGHT;
   UpdateLabel("V_POSOPEN", StringFormat("%d / %d", openCount, maxPos), posClr);
   UpdateLabel("V_POSTOT",  StringFormat("%.2f", totalLots), CLR_TEXT);
   UpdateLabel("V_POSPNL",  StringFormat("$%.2f", floatPnL),
               (floatPnL >= 0) ? CLR_PROFIT : CLR_LOSS);
   UpdateLabel("V_POSSWAP", StringFormat("$%.2f", totalSwap),
               (totalSwap >= 0) ? CLR_TEXT : CLR_LOSS);

   //--- Anchor
   if(anchorActive)
     {
      UpdateLabel("V_ANCST",  "ACTIVE", CLR_ANCHOR_ACTIVE);
      UpdateLabel("V_ANCDIR", (anchorDir == 1) ? "BUY \x25B2" : "SELL \x25BC",
                  (anchorDir == 1) ? CLR_PROFIT : CLR_LOSS);
      UpdateLabel("V_ANCENT", StringFormat("%.2f", anchorEntry), CLR_TEXT_BRIGHT);
      UpdateLabel("V_ANCLOT", StringFormat("%.2f", anchorLot), CLR_TEXT);
      UpdateLabel("V_ANCSEQ", StringFormat("%d / %d", seqPosition, maxPos), CLR_TEXT);
     }
   else
     {
      UpdateLabel("V_ANCST",  "WAITING", CLR_WARN);
      UpdateLabel("V_ANCDIR", "---", CLR_TEXT_DIM);
      UpdateLabel("V_ANCENT", "---", CLR_TEXT_DIM);
      UpdateLabel("V_ANCLOT", "---", CLR_TEXT_DIM);
      UpdateLabel("V_ANCSEQ", "---", CLR_TEXT_DIM);
     }

   //--- Basket
   if(basketEnabled)
     {
      UpdateLabel("V_BSKPNL", StringFormat("$%.2f", basketPnL),
                  (basketPnL >= 0) ? CLR_PROFIT : CLR_LOSS);
      UpdateLabel("V_BSKTP",  StringFormat("$%.0f", basketTP), CLR_PROFIT);
      UpdateLabel("V_BSKSL",  StringFormat("$%.0f", basketSL), CLR_LOSS);
      UpdateLabel("V_BSKHWM", StringFormat("$%.2f", basketHWM), CLR_GOLD);
      UpdateLabel("V_BSKTRL", basketTrailing ? "ACTIVE \x25B2" : "---",
                  basketTrailing ? CLR_ANCHOR_ACTIVE : CLR_TEXT_DIM);

      // Progress bar
      double range = basketTP - basketSL;
      double pct = 0;
      if(range > 0) pct = (basketPnL - basketSL) / range * 100.0;
      pct = MathMax(0, MathMin(100, pct));
      int barW = PANEL_WIDTH - 22;
      int fillW = (int)MathMax(1, barW * pct / 100.0);
      color barClr = (basketPnL >= 0) ? CLR_PROFIT : CLR_LOSS;
      string fillName = PanelName("BSK_PROG_FILL");
      if(ObjectFind(0, fillName) >= 0)
        {
         ObjectSetInteger(0, fillName, OBJPROP_XSIZE, fillW);
         ObjectSetInteger(0, fillName, OBJPROP_BGCOLOR, barClr);
         ObjectSetInteger(0, fillName, OBJPROP_BORDER_COLOR, barClr);
        }
     }
   else
     {
      UpdateLabel("V_BSKPNL", "DISABLED", CLR_TEXT_DIM);
      UpdateLabel("V_BSKTP",  "---", CLR_TEXT_DIM);
      UpdateLabel("V_BSKSL",  "---", CLR_TEXT_DIM);
      UpdateLabel("V_BSKHWM", "---", CLR_TEXT_DIM);
      UpdateLabel("V_BSKTRL", "---", CLR_TEXT_DIM);
     }

   //--- Risk Guard
   if(riskEnabled)
     {
      color dayClr = dailyHalt ? CLR_LOSS : ((dailyDD > dailyLimit * 0.7) ? CLR_WARN : CLR_PROFIT);
      UpdateLabel("V_RSKDAY", StringFormat("%.2f%% / %.1f%% %s",
                  dailyDD, dailyLimit, dailyHalt ? "[HALT]" : ""), dayClr);
      color wkClr = weeklyHalt ? CLR_LOSS : ((weeklyDD > weeklyLimit * 0.7) ? CLR_WARN : CLR_PROFIT);
      UpdateLabel("V_RSKWK",  StringFormat("%.2f%% / %.1f%% %s",
                  weeklyDD, weeklyLimit, weeklyHalt ? "[HALT]" : ""), wkClr);
      UpdateLabel("V_RSKEQD", StringFormat("$%.2f", eqDayStart), CLR_TEXT);
      UpdateLabel("V_RSKEQW", StringFormat("$%.2f", eqWeekStart), CLR_TEXT);
     }
   else
     {
      UpdateLabel("V_RSKDAY", "DISABLED", CLR_TEXT_DIM);
      UpdateLabel("V_RSKWK",  "---", CLR_TEXT_DIM);
      UpdateLabel("V_RSKEQD", "---", CLR_TEXT_DIM);
      UpdateLabel("V_RSKEQW", "---", CLR_TEXT_DIM);
     }

   //--- Gates (traffic lights)
   UpdateLabel("V_GTSPRD", StringFormat("%d / %d %s", spreadPts, maxSpread,
               gateSpreadOK ? "\x25CF" : "\x25CF"),
               gateSpreadOK ? CLR_GATE_OK : CLR_GATE_BLOCK);
   UpdateLabel("V_GTCB",   gateCB ? "\x25CF BLOCKED" : "\x25CF OK",
               gateCB ? CLR_GATE_BLOCK : CLR_GATE_OK);
   UpdateLabel("V_GTNEWS", gateNews ? "\x25CF BLOCKED" : "\x25CF OK",
               gateNews ? CLR_GATE_BLOCK : CLR_GATE_OK);
   UpdateLabel("V_GTREG",  gateRegime ? "\x25CF BLOCKED" : "\x25CF OK",
               gateRegime ? CLR_GATE_BLOCK : CLR_GATE_OK);
   UpdateLabel("V_GTATR",  gateATRShock ? "\x25CF SHOCK" : "\x25CF OK",
               gateATRShock ? CLR_GATE_BLOCK : CLR_GATE_OK);
   UpdateLabel("V_GTCOOL", gateCooldownOK ? "\x25CF READY" : "\x25CF WAIT",
               gateCooldownOK ? CLR_GATE_OK : CLR_WARN);

   //--- Levels (11 levels)
   string tags[11] = {"S5","S4","S3","S2","S1","P","R1","R2","R3","R4","R5"};
   string fbTags[11] = {"S5_FB","S4_FB","S3_FB","S2_FB","S1_FB","P_FB","R1_FB","R2_FB","R3_FB","R4_FB","R5_FB"};
   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;

   for(int i = 0; i < LADDER_SIZE; i++)
     {
      string rowId = "LVL" + IntegerToString(i);
      if(i < ArraySize(levelPrices) && i < ArraySize(levelValid) && levelValid[i])
        {
         string tag = useFallback ? fbTags[i] : tags[i];
         double p = levelPrices[i];
         double dist = p - mid;
         color lvlClr = CLR_TEXT;
         if(tag == "P" || tag == "P_FB") lvlClr = CLR_GOLD;
         else if(p > mid) lvlClr = CLR_LOSS;     // resistance
         else             lvlClr = CLR_PROFIT;    // support

         UpdateLabel("L_" + rowId, StringFormat("  %s:", tag), lvlClr);
         UpdateLabel("V_" + rowId, StringFormat("%.2f  (%+.1f)", p, dist), lvlClr);
        }
      else
        {
         UpdateLabel("L_" + rowId, "  ---:", CLR_TEXT_DIM);
         UpdateLabel("V_" + rowId, "---", CLR_TEXT_DIM);
        }
     }

   //--- Session Stats
   UpdateLabel("V_STTOT",  IntegerToString(tradesToday), CLR_TEXT_BRIGHT);
   UpdateLabel("V_STWINS", IntegerToString(wins), CLR_PROFIT);
   UpdateLabel("V_STLOSS", IntegerToString(losses), CLR_LOSS);
   UpdateLabel("V_STPF",   (profitFactor > 0) ? StringFormat("%.2f", profitFactor) : "---",
               (profitFactor >= 1.5) ? CLR_PROFIT : (profitFactor >= 1.0 ? CLR_WARN : CLR_LOSS));
   UpdateLabel("V_STNET",  StringFormat("$%.2f", netPnLToday),
               (netPnLToday >= 0) ? CLR_PROFIT : CLR_LOSS);

   //--- Update Pause button text
   bool paused = (GlobalVariableCheck("HAB_PEX_PAUSED") && GlobalVariableGet("HAB_PEX_PAUSED") > 0.5);
   UpdateButton("BTN_PAUSE", paused ? "RESUME" : "PAUSE EA",
                paused ? CLR_GATE_OK : CLR_BTN_PAUSE);

   ChartRedraw(0);
  }

//=====================================================================
//             SESSION STATISTICS CALCULATOR
//=====================================================================
struct SessionStats
  {
   int    tradesToday;
   int    wins;
   int    losses;
   double grossProfit;
   double grossLoss;
   double profitFactor;
   double netPnL;
  };

void CalcSessionStats(SessionStats &stats)
  {
   stats.tradesToday  = 0;
   stats.wins         = 0;
   stats.losses       = 0;
   stats.grossProfit  = 0.0;
   stats.grossLoss    = 0.0;
   stats.profitFactor = 0.0;
   stats.netPnL       = 0.0;

   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   if(!HistorySelect(dayStart, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      stats.tradesToday++;
      stats.netPnL += profit;

      if(profit >= 0)
        {
         stats.wins++;
         stats.grossProfit += profit;
        }
      else
        {
         stats.losses++;
         stats.grossLoss += MathAbs(profit);
        }
     }

   stats.profitFactor = (stats.grossLoss > 0) ? stats.grossProfit / stats.grossLoss : 0.0;
  }

//=====================================================================
//          PANEL EVENT HANDLER (call from OnChartEvent)
//=====================================================================
bool PanelOnChartEvent(const int id, const long &lparam,
                       const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return false;

   // Minimize/Maximize button
   if(sparam == PanelName("BTN_MIN"))
     {
      g_panelMinimized = !g_panelMinimized;
      PanelBuild();
      ObjectSetInteger(0, PanelName("BTN_MIN"), OBJPROP_STATE, false);
      ChartRedraw(0);
      return true;
     }

   // Pause/Resume button
   if(sparam == PanelName("BTN_PAUSE"))
     {
      bool paused = (GlobalVariableCheck("HAB_PEX_PAUSED") && GlobalVariableGet("HAB_PEX_PAUSED") > 0.5);
      if(paused)
         GlobalVariableSet("HAB_PEX_PAUSED", 0.0);
      else
         GlobalVariableSet("HAB_PEX_PAUSED", 1.0);
      ObjectSetInteger(0, PanelName("BTN_PAUSE"), OBJPROP_STATE, false);
      ChartRedraw(0);
      return true;
     }

   // Close All button
   if(sparam == PanelName("BTN_CLOSEALL"))
     {
      // Set GV flag — the EA will pick it up and close all
      GlobalVariableSet("HAB_PEX_CLOSEALL", 1.0);
      ObjectSetInteger(0, PanelName("BTN_CLOSEALL"), OBJPROP_STATE, false);
      ChartRedraw(0);
      return true;
     }

   return false;
  }

//=====================================================================
//          PANEL INIT / DEINIT (call from OnInit/OnDeinit)
//=====================================================================
void PanelInit()
  {
   g_panelVisible   = true;
   g_panelMinimized = false;
   g_panelObjCount  = 0;
   ArrayResize(g_panelObjects, 0);
   PanelBuild();
  }

void PanelDeinit()
  {
   PanelDeleteAll();
   ChartRedraw(0);
  }

#endif // HAB_PEX_PANEL_MQH
//+------------------------------------------------------------------+
