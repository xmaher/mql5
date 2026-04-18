//+------------------------------------------------------------------+
//|                                                      Pegasus.mq5 |
//|                        Pegasus Trade Manager v1.0 (MQL5 port)    |
//+------------------------------------------------------------------+
#property copyright "Pegasus Trade Manager"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_SL_METHOD
{
   SL_FROM_ENTRY   = 0, // From Entry Price
   SL_FROM_EXTREME = 1  // From Extreme of Last N Bars
};

//+------------------------------------------------------------------+
//| Static Inputs (no EA restart on change)                         |
//+------------------------------------------------------------------+
sinput int            InpCorner     = 2;                   // Panel Corner (0=TL 1=TR 2=BL 3=BR)
sinput color          InpPanelBg    = C'45,45,45';         // Panel Background Color
sinput color          InpHeaderBg   = C'212,175,55';       // Header Background Color
sinput color          InpHeaderTxt  = clrBlack;            // Header Text Color
sinput string         InpConfigFile = "Pegasus_settings.ini"; // Symbol config file (in MQL5/Files/)

//+------------------------------------------------------------------+
//| Dynamic Inputs                                                   |
//+------------------------------------------------------------------+
input ENUM_SL_METHOD  InpSLMethod  = SL_FROM_ENTRY; // SL Method
input int             InpSLBars    = 5;             // SL Bars (N, from bar 1)

input double          InpFastLot   = 0.15; // FAST Lot Size
input double          InpNormalLot = 0.05; // NORMAL Lot Size
input double          InpSlowLot   = 0.02; // SLOW Lot Size

input int             InpFastTP    = 250;  // FAST TP (pips/pts)
input int             InpNormalTP  = 500;  // NORMAL TP (pips/pts)
input int             InpSlowTP    = 750;  // SLOW TP (pips/pts)

input int             InpFastSL    = 500;  // FAST SL (pips/pts from entry or extreme)
input int             InpNormalSL  = 0;    // NORMAL SL offset from entry (0=BE, neg=profit)
input int             InpSlowSL    = -100; // SLOW SL offset from entry

input int             InpMinSL     = 250;  // Minimum SL (pips/pts)
input bool            InpInternal  = true; // Internal SL/TP Management
input bool            InpBroker    = false;// Set Broker SL (safety net)
input double          InpRiskPct   = 1.0;  // Risk % of equity per trade (Risk Mode)

//+------------------------------------------------------------------+
//| Panel Layout Constants                                           |
//+------------------------------------------------------------------+
#define PFX      "PEG_"
#define MAGIC    20260310

// Panel dimensions
#define P_W      362
#define P_H      262   // +22 for risk row
#define P_PAD    5

// Row heights
#define ROW_HDR  24
#define ROW_BTN  28
#define ROW_CHDR 16
#define ROW_EDIT 24
#define ROW_DATA 19
#define ROW_RISK 20

// Local Y offsets from panel top-left
// All objects use CORNER=0 with absolute pixel coordinates to avoid
// the MQL5 quirk where BUTTON/LABEL/EDIT anchor differently than RECTANGLE_LABEL.
#define LY_HDR    1
#define LY_BTN    26
#define LY_CHDR   56
#define LY_ROW1   74
#define LY_ROW2   100
#define LY_ROW3   126
#define LY_SELBTN 152
#define LY_SEP    174
#define LY_DAT1   177
#define LY_DAT2   196
#define LY_DAT3   215
#define LY_RISK   237  // 215+19+3

// Local X offsets from panel top-left
#define LBL_W    55
#define COL_W    99
#define HALF_W   49
#define LX_C0    57
#define LX_C1    157
#define LX_C2    257
#define BTN_HALF ((P_W-3)/2)
#define BTN_FULL (P_W-2)

// Chart line / label object names
#define LN_SL       "PEG_LN_SL"
#define LN_TP       "PEG_LN_TP"
#define LB_SL       "PEG_LB_SL"
#define LB_TP       "PEG_LB_TP"
#define LN_BUY_LIM  "PEG_LN_BUYLIM"
#define LN_SELL_LIM "PEG_LN_SELLLIM"
#define LN_ENTRY    "PEG_LN_ENTRY"
#define BT_BE       "PEG_BE_BTN"

//+------------------------------------------------------------------+
//| Global Trade State                                               |
//+------------------------------------------------------------------+
CTrade trade;               // MQL5 trade execution helper

ulong  g_magic    = MAGIC;  // per-chart magic (unique per instance)
ulong  g_ticket   = 0;      // active ticket (0 = none)
int    g_dir      = 0;      // 1=BUY  -1=SELL
double g_entry    = 0;      // actual fill price
double g_fastLot  = 0;
double g_normLot  = 0;
double g_slowLot  = 0;
double g_fastTP_p = 0;      // TP price levels
double g_normTP_p = 0;
double g_slowTP_p = 0;
double g_curSL    = 0;      // current SL price
double g_curTP    = 0;      // current monitored TP price
int    g_phase    = 0;      // 0=none 1=fast 2=normal 3=slow
int    g_normSL_v = 0;      // NORMAL SL offset (stored at open)
int    g_slowSL_v = 0;      // SLOW SL offset (stored at open)
double g_pip      = 0;      // pip/point size for symbol
bool   g_built    = false;
int    g_activeLot  = 0;    // active Lot sub-column: 0=A  1=B
int    g_activeTP   = 0;    // active TP  sub-column: 0=A  1=B
int    g_activeSL   = 0;    // active SL  sub-column: 0=A  1=B
datetime g_lastBar  = 0;
int    g_px         = 0;    // panel top-left absolute x
int    g_py         = 0;    // panel top-left absolute y
int    g_chartW     = 0;
int    g_chartH     = 0;
int    g_chartTF    = 0;
int    g_btnState   = -1;   // 0=buy/sell  1=close  -1=unbuilt
int    g_objCount   = -1;
datetime g_entryTime = 0;
int    g_buyLimState  = 0;  // 0=idle  1=placed  2=tracking
int    g_sellLimState = 0;
double g_buyLimPrice  = 0;
double g_sellLimPrice = 0;
bool   g_riskMode     = false; // risk-based lot sizing toggle
int    g_minSL        = 0;    // effective min SL (from INI or InpMinSL)
int    g_dragMinSL    = 10;   // min pip buffer when dragging SL (from INI, default 10)

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string PN(const string s) { return PFX + s; }

string TfTag(const int tf = 0)
{
   int p = (tf > 0) ? tf : (int)Period();
   switch(p)
   {
   case PERIOD_M1:  return "M1";
   case PERIOD_M5:  return "M5";
   case PERIOD_M15: return "M15";
   case PERIOD_M30: return "M30";
   case PERIOD_H1:  return "H1";
   case PERIOD_H4:  return "H4";
   case PERIOD_D1:  return "D1";
   case PERIOD_W1:  return "W1";
   case PERIOD_MN1: return "MN1";
   }
   return "TF" + IntegerToString(p);
}

void CapturePanelEdits(string &vals[])
{
   string eId[19] = {
      "EFASTLOTA","EFASTLOTB","ENORMLOTA","ENORMLOTB","ESLOWLOTA","ESLOWLOTB",
      "EFASTTPA", "EFASTTPB", "ENORMTPA", "ENORMTPB", "ESLOWTPA", "ESLOWTPB",
      "EFASTSLA", "EFASTSLB", "ENORMSLA", "ENORMSLB", "ESLOWSLA", "ESLOWSLB",
      "ERISKPCT"
   };
   ArrayResize(vals, 19);
   for(int i = 0; i < 19; i++)
      vals[i] = (g_built ? EText(eId[i]) : "");
}

void RestorePanelEdits(const string &vals[])
{
   string eId[19] = {
      "EFASTLOTA","EFASTLOTB","ENORMLOTA","ENORMLOTB","ESLOWLOTA","ESLOWLOTB",
      "EFASTTPA", "EFASTTPB", "ENORMTPA", "ENORMTPB", "ESLOWTPA", "ESLOWTPB",
      "EFASTSLA", "EFASTSLB", "ENORMSLA", "ENORMSLB", "ESLOWSLA", "ESLOWSLB",
      "ERISKPCT"
   };
   int count = ArraySize(vals);
   for(int i = 0; i < count && i < 19; i++)
      if(vals[i] != "")
         ObjectSetString(0, PN(eId[i]), OBJPROP_TEXT, vals[i]);
}

// Pip/point size — handles 5-digit forex, 3-digit forex, metals, CFD cash indexes.
double CalcPip()
{
   string sym = _Symbol;
   double pt  = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    dg  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   bool isCommodity = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0 ||
                       StringFind(sym, "XBR") >= 0 || StringFind(sym, "XTI") >= 0);
   bool isCashIdx   = (StringLen(sym) >= 4 &&
                       StringSubstr(sym, StringLen(sym) - 4, 4) == "Cash");

   if(isCommodity || isCashIdx) return pt;
   return (dg == 3 || dg == 5) ? pt * 10.0 : pt;
}

string EText(const string id)   { return ObjectGetString(0, PN(id), OBJPROP_TEXT); }
double EDouble(const string id) { return StringToDouble(EText(id)); }
int    EInt(const string id)    { return (int)StringToInteger(EText(id)); }

void LblSet(const string name, const string txt)  { ObjectSetString(0, name, OBJPROP_TEXT, txt); }
void LblClr(const string name, color clr)         { ObjectSetInteger(0, name, OBJPROP_COLOR, clr); }

//+------------------------------------------------------------------+
//| UI Factories                                                     |
//+------------------------------------------------------------------+
void MkRect(const string name, int c, int x, int y, int w, int h,
            color bg, color brd, int bw)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      c);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       brd);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       bw);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,      1);
}

void MkLabel(const string name, const string txt, int c, int x, int y,
             color clr = C'170,170,170', int fs = 8, bool bold = false,
             ENUM_ANCHOR_POINT anch = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    c);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString( 0, name, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetString( 0, name, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anch);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,    3);
}

void MkButton(const string name, const string txt, int c,
              int x, int y, int w, int h, color tc, color bg, int fs = 9)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    c);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetString( 0, name, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     tc);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,    4);
}

void MkEdit(const string name, const string txt, int c,
            int x, int y, int w, int h)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       c);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetString( 0, name, OBJPROP_TEXT,         txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        C'200,200,200');
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      C'58,58,58');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'85,85,85');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     8);
   ObjectSetInteger(0, name, OBJPROP_ALIGN,        ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       4);
}

//+------------------------------------------------------------------+
//| Panel Position                                                   |
//+------------------------------------------------------------------+
// All objects use CORNER=0 (absolute pixel coords from chart top-left).
// Mixing corners between OBJ_RECTANGLE_LABEL and OBJ_BUTTON/LABEL/EDIT
// causes misalignment because they interpret CORNER differently.
void CalcPanelPos()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(cw < P_W + P_PAD * 2) cw = P_W + P_PAD * 2;
   if(ch < P_H + P_PAD * 2) ch = P_H + P_PAD * 2;

   switch(InpCorner)
   {
   case 0:  g_px = P_PAD;            g_py = P_PAD;            break;
   case 1:  g_px = cw - P_PAD - P_W; g_py = P_PAD;            break;
   case 2:  g_px = P_PAD;            g_py = ch - P_PAD - P_H; break;
   default: g_px = cw - P_PAD - P_W; g_py = ch - P_PAD - P_H; break;
   }
}

//+------------------------------------------------------------------+
//| Limit Order Lines & Buttons                                      |
//+------------------------------------------------------------------+
void CreateLimitLine(bool isBuy)
{
   string nm    = isBuy ? LN_BUY_LIM : LN_SELL_LIM;
   double price = isBuy ? g_buyLimPrice : g_sellLimPrice;
   color  clr   = isBuy ? C'212,175,55' : C'148,0,211';

   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);
   ChartRedraw(0);
}

void UpdateLimitButtons()
{
   if(!g_built) return;

   string names[2];  names[0] = PN("BUYLIM");       names[1] = PN("SELLLIM");
   int    states[2]; states[0] = g_buyLimState;      states[1] = g_sellLimState;
   string lblIdle[2];lblIdle[0] = "Buy Limit";       lblIdle[1] = "Sell Limit";
   color  bgIdle[2]; bgIdle[0]  = C'0,130,65';       bgIdle[1]  = C'160,35,35';
   color  bgAct[2];  bgAct[0]   = C'212,175,55';     bgAct[1]   = C'128,0,200';
   color  tcIdle[2]; tcIdle[0]  = clrWhite;           tcIdle[1]  = clrWhite;
   color  tcAct[2];  tcAct[0]   = clrBlack;           tcAct[1]   = clrWhite;

   bool disabled = (g_phase > 0);

   for(int i = 0; i < 2; i++)
   {
      if(ObjectFind(0, names[i]) < 0) continue;
      if(disabled)
      {
         ObjectSetString( 0, names[i], OBJPROP_TEXT,   lblIdle[i]);
         ObjectSetInteger(0, names[i], OBJPROP_BGCOLOR, C'55,55,55');
         ObjectSetInteger(0, names[i], OBJPROP_COLOR,   C'90,90,90');
      }
      else if(states[i] == 0)
      {
         ObjectSetString( 0, names[i], OBJPROP_TEXT,   lblIdle[i]);
         ObjectSetInteger(0, names[i], OBJPROP_BGCOLOR, bgIdle[i]);
         ObjectSetInteger(0, names[i], OBJPROP_COLOR,   tcIdle[i]);
      }
      else if(states[i] == 1)
      {
         ObjectSetString( 0, names[i], OBJPROP_TEXT,   "SET");
         ObjectSetInteger(0, names[i], OBJPROP_BGCOLOR, bgAct[i]);
         ObjectSetInteger(0, names[i], OBJPROP_COLOR,   tcAct[i]);
      }
      else
      {
         ObjectSetString( 0, names[i], OBJPROP_TEXT,   "UNSET");
         ObjectSetInteger(0, names[i], OBJPROP_BGCOLOR, bgAct[i]);
         ObjectSetInteger(0, names[i], OBJPROP_COLOR,   tcAct[i]);
      }
   }
   ChartRedraw(0);
}

void CancelBuyLim()
{
   ObjectDelete(0, LN_BUY_LIM);
   g_buyLimState = 0;
   g_buyLimPrice = 0;
}

void CancelSellLim()
{
   ObjectDelete(0, LN_SELL_LIM);
   g_sellLimState = 0;
   g_sellLimPrice = 0;
}

void CancelAllLimits()
{
   CancelBuyLim();
   CancelSellLim();
   UpdateLimitButtons();
   SaveState();
}

void CheckLimitLines()
{
   if(g_buyLimState  > 0 && ObjectFind(0, LN_BUY_LIM)  < 0) CreateLimitLine(true);
   if(g_sellLimState > 0 && ObjectFind(0, LN_SELL_LIM) < 0) CreateLimitLine(false);
}

void CheckLimitHits()
{
   if(g_phase > 0) return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool buyHit  = (g_buyLimState  == 2) && (ask <= g_buyLimPrice);
   bool sellHit = (g_sellLimState == 2) && (bid >= g_sellLimPrice);

   if(buyHit)
   {
      CancelBuyLim();
      CancelSellLim();
      OpenTrade(1);
      UpdateBtnRow();
      UpdateLimitButtons();
   }
   else if(sellHit)
   {
      CancelSellLim();
      CancelBuyLim();
      OpenTrade(-1);
      UpdateBtnRow();
      UpdateLimitButtons();
   }
}

//+------------------------------------------------------------------+
//| Risk-Based Lot Sizing                                            |
//+------------------------------------------------------------------+
// Returns total lots that risk riskPct% of equity over slPips.
// Reads risk % from the panel edit box when available; falls back to InpRiskPct.
// Returns 0 on bad data.
double CalcRiskTotalLots(int slPips)
{
   if(slPips <= 0) return 0;
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(equity <= 0 || tickVal <= 0 || tickSize <= 0) return 0;

   // Monetary value of 1 pip per 1 lot in account currency
   double pipValPerLot = (g_pip / tickSize) * tickVal;
   if(pipValPerLot <= 0) return 0;

   double riskPct = (g_built ? EDouble("ERISKPCT") : InpRiskPct);
   if(riskPct <= 0) riskPct = InpRiskPct;
   double riskAmount = equity * riskPct / 100.0;
   return riskAmount / ((double)slPips * pipValPerLot);
}

// Writes risk-calculated lots into the active Lot column edit boxes.
// Called every tick while risk mode is ON so the boxes always show
// what will actually be used when BUY/SELL is pressed.
void UpdateRiskLots()
{
   if(!g_riskMode || !g_built || g_phase > 0) return;

   string sfx    = (g_activeLot == 0 ? "A" : "B");
   string sfx_sl = (g_activeSL  == 0 ? "A" : "B");
   int slPips    = EInt("EFASTSL" + sfx_sl);

   double totalLots = CalcRiskTotalLots(slPips);
   if(totalLots <= 0) return;

   double minLot = GetMinLot();
   double maxLot = GetMaxLot();
   int    ld     = GetLotDigits();

   // 70 / 20 / 10 split, clamped to broker limits
   double fLot = MathMax(minLot, MathMin(maxLot, NormalizeLotsToBroker(totalLots * 0.70)));
   double nLot = MathMax(minLot, MathMin(maxLot, NormalizeLotsToBroker(totalLots * 0.20)));
   double sLot = MathMax(minLot, MathMin(maxLot, NormalizeLotsToBroker(totalLots * 0.10)));

   ObjectSetString(0, PN("EFASTLOT"+sfx), OBJPROP_TEXT, DoubleToString(fLot, ld));
   ObjectSetString(0, PN("ENORMLOT"+sfx), OBJPROP_TEXT, DoubleToString(nLot, ld));
   ObjectSetString(0, PN("ESLOWLOT"+sfx), OBJPROP_TEXT, DoubleToString(sLot, ld));
}

// Refreshes the risk toggle button label and colour.
void UpdateRiskBtn()
{
   if(!g_built) return;
   string nm = PN("RISKBTN");
   if(ObjectFind(0, nm) < 0) return;

   if(g_riskMode)
   {
      string sfx_sl  = (g_activeSL == 0 ? "A" : "B");
      int    slPips  = EInt("EFASTSL" + sfx_sl);
      double riskPct = EDouble("ERISKPCT");
      if(riskPct <= 0) riskPct = InpRiskPct;
      double total   = CalcRiskTotalLots(slPips);
      string info    = (total > 0)
         ? StringFormat("  (SL %d pts  →  %.2f lots total)", slPips, total)
         : "  (no data)";
      ObjectSetString( 0, nm, OBJPROP_TEXT,   "Risk Sizing: ON" + info);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, C'0,100,50');
      ObjectSetInteger(0, nm, OBJPROP_COLOR,   clrWhite);
   }
   else
   {
      ObjectSetString( 0, nm, OBJPROP_TEXT,   "Risk Sizing: OFF");
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, C'50,50,50');
      ObjectSetInteger(0, nm, OBJPROP_COLOR,   C'120,120,120');
   }
}

//+------------------------------------------------------------------+
//| Button Row                                                       |
//+------------------------------------------------------------------+
// Shows BUY+SELL when no trade is open, full-width CLOSE when trade active.
void UpdateBtnRow()
{
   int px = g_px, py = g_py;

   if(ObjectFind(0, PN("BUY"))   >= 0) ObjectDelete(0, PN("BUY"));
   if(ObjectFind(0, PN("SELL"))  >= 0) ObjectDelete(0, PN("SELL"));
   if(ObjectFind(0, PN("CLOSE")) >= 0) ObjectDelete(0, PN("CLOSE"));

   if(g_phase == 0)
   {
      MkButton(PN("BUY"),  "BUY",  0, px+1,            py+LY_BTN, BTN_HALF, ROW_BTN, clrWhite, C'0,130,65');
      MkButton(PN("SELL"), "SELL", 0, px+1+BTN_HALF+1, py+LY_BTN, BTN_HALF, ROW_BTN, clrWhite, C'160,35,35');
      g_btnState = 0;
   }
   else
   {
      MkButton(PN("CLOSE"), "CLOSE", 0, px+1, py+LY_BTN, BTN_FULL, ROW_BTN, C'210,210,210', C'65,65,65');
      g_btnState = 1;
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Build panel                                                      |
//+------------------------------------------------------------------+
void BuildPanel()
{
   int px = g_px, py = g_py;

   MkRect(PN("BG"), 0, px, py, P_W, P_H, InpPanelBg, C'65,65,65', 1);

   MkRect (PN("HBG"), 0, px+1, py+LY_HDR, P_W-2, ROW_HDR, InpHeaderBg, InpHeaderBg, 1);
   MkLabel(PN("HTX"), "  Pegasus Trade Manager  ",
           0, px + P_W/2, py + LY_HDR + ROW_HDR/2,
           InpHeaderTxt, 10, true, ANCHOR_CENTER);

   UpdateBtnRow();

   MkLabel(PN("CHLOT"), "LOT",     0, px+LX_C0+COL_W/2, py+LY_CHDR+8, C'110,110,110', 7, false, ANCHOR_CENTER);
   MkLabel(PN("CHTP"),  "TP (pts)",0, px+LX_C1+COL_W/2, py+LY_CHDR+8, C'110,110,110', 7, false, ANCHOR_CENTER);
   MkLabel(PN("CHSL"),  "SL (pts)",0, px+LX_C2+COL_W/2, py+LY_CHDR+8, C'110,110,110', 7, false, ANCHOR_CENTER);

   int    rowLY[3];  rowLY[0] = LY_ROW1; rowLY[1] = LY_ROW2; rowLY[2] = LY_ROW3;
   color  rowC[3];   rowC[0]  = C'80,210,120'; rowC[1] = C'210,175,60'; rowC[2] = C'80,150,220';
   string rowID[3];  rowID[0] = "FAST"; rowID[1] = "NORM"; rowID[2] = "SLOW";
   string rowDisp[3];rowDisp[0]= "FAST"; rowDisp[1]= "NORMAL"; rowDisp[2]= "SLOW";

   double lotDef[3]; lotDef[0] = InpFastLot;  lotDef[1] = InpNormalLot; lotDef[2] = InpSlowLot;
   int    tpDef[3];  tpDef[0]  = InpFastTP;   tpDef[1]  = InpNormalTP;  tpDef[2]  = InpSlowTP;
   int    slDef[3];  slDef[0]  = InpFastSL;   slDef[1]  = InpNormalSL;  slDef[2]  = InpSlowSL;

   for(int i = 0; i < 3; i++)
   {
      int aly = py + rowLY[i];
      MkLabel(PN("RL"+rowID[i]), rowDisp[i], 0, px+3, aly + ROW_EDIT/2, rowC[i], 7, true, ANCHOR_LEFT);
      MkEdit(PN("E"+rowID[i]+"LOTA"), DoubleToString(lotDef[i], 2), 0, px+LX_C0,            aly, HALF_W, ROW_EDIT);
      MkEdit(PN("E"+rowID[i]+"LOTB"), DoubleToString(lotDef[i], 2), 0, px+LX_C0+HALF_W+1,  aly, HALF_W, ROW_EDIT);
      MkEdit(PN("E"+rowID[i]+"TPA"),  IntegerToString(tpDef[i]),    0, px+LX_C1,            aly, HALF_W, ROW_EDIT);
      MkEdit(PN("E"+rowID[i]+"TPB"),  IntegerToString(tpDef[i]),    0, px+LX_C1+HALF_W+1,  aly, HALF_W, ROW_EDIT);
      MkEdit(PN("E"+rowID[i]+"SLA"),  IntegerToString(slDef[i]),    0, px+LX_C2,            aly, HALF_W, ROW_EDIT);
      MkEdit(PN("E"+rowID[i]+"SLB"),  IntegerToString(slDef[i]),    0, px+LX_C2+HALF_W+1,  aly, HALF_W, ROW_EDIT);
   }

   int sby = py + LY_SELBTN;
   MkButton(PN("SELBTN_LOT_A"), "", 0, px+LX_C0,            sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   MkButton(PN("SELBTN_LOT_B"), "", 0, px+LX_C0+HALF_W+1,  sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   MkButton(PN("SELBTN_TP_A"),  "", 0, px+LX_C1,            sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   MkButton(PN("SELBTN_TP_B"),  "", 0, px+LX_C1+HALF_W+1,  sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   MkButton(PN("SELBTN_SL_A"),  "", 0, px+LX_C2,            sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   MkButton(PN("SELBTN_SL_B"),  "", 0, px+LX_C2+HALF_W+1,  sby, HALF_W, 18, clrWhite, C'60,60,60', 8);
   UpdateSelBtnColors();

   MkRect(PN("SEP"), 0, px+1, py+LY_SEP, P_W-2, 1, C'75,75,75', C'75,75,75', 1);

   MkLabel(PN("D1"), "Spread: --  |  " + _Symbol, 0, px+3, py+LY_DAT1, C'140,140,140', 7);
   MkLabel(PN("D2"), "No active trade",             0, px+3, py+LY_DAT2, C'140,140,140', 7);
   MkLabel(PN("D3"), "",                            0, px+3, py+LY_DAT3, C'140,140,140', 7);

   MkButton(PN("BUYLIM"),  "Buy Limit",  0, px+LX_C2, py+LY_DAT1, COL_W, ROW_DATA, clrWhite, C'0,130,65',  7);
   MkButton(PN("SELLLIM"), "Sell Limit", 0, px+LX_C2, py+LY_DAT2, COL_W, ROW_DATA, clrWhite, C'160,35,35', 7);

   // Risk sizing toggle — button fills left, risk % edit box on right (aligned to SL-B column)
   MkButton(PN("RISKBTN"), "Risk Sizing: OFF", 0, px+1, py+LY_RISK, LX_C2+HALF_W-2, ROW_RISK,
            C'120,120,120', C'50,50,50', 7);
   MkEdit(PN("ERISKPCT"), DoubleToString(InpRiskPct, 2), 0, px+LX_C2+HALF_W+1, py+LY_RISK, HALF_W, ROW_RISK);

   g_built    = true;
   UpdateLimitButtons();
   UpdateRiskBtn();
   ChartRedraw(0);
   g_objCount = ObjectsTotal(0, 0, -1);
}

void DeletePanel()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      // Chart line/label objects survive panel rebuilds — user drag positions preserved
      if(StringFind(nm, PFX) == 0 &&
         nm != LN_SL && nm != LN_TP && nm != LB_SL && nm != LB_TP &&
         nm != LN_BUY_LIM && nm != LN_SELL_LIM && nm != LN_ENTRY)
         ObjectDelete(0, nm);
   }
   g_built = false;
}

void UpdateSelBtnColors()
{
   string cols[3]  = {"LOT", "TP", "SL"};
   int    active[3]; active[0] = g_activeLot; active[1] = g_activeTP; active[2] = g_activeSL;
   string rowID[3] = {"FAST", "NORM", "SLOW"};

   for(int c = 0; c < 3; c++)
   {
      int act = active[c];
      string nA = PN("SELBTN_"+cols[c]+"_A");
      string nB = PN("SELBTN_"+cols[c]+"_B");
      if(ObjectFind(0, nA) >= 0)
      {
         ObjectSetString( 0, nA, OBJPROP_TEXT,   "");
         ObjectSetInteger(0, nA, OBJPROP_BGCOLOR, act==0 ? (color)C'0,140,70' : (color)C'60,60,60');
      }
      if(ObjectFind(0, nB) >= 0)
      {
         ObjectSetString( 0, nB, OBJPROP_TEXT,   "");
         ObjectSetInteger(0, nB, OBJPROP_BGCOLOR, act==1 ? (color)C'0,140,70' : (color)C'60,60,60');
      }
      for(int r = 0; r < 3; r++)
      {
         string idA = PN("E"+rowID[r]+cols[c]+"A");
         string idB = PN("E"+rowID[r]+cols[c]+"B");
         if(ObjectFind(0, idA) >= 0)
         {
            ObjectSetInteger(0, idA, OBJPROP_BGCOLOR, act==0 ? (color)C'58,58,58' : (color)C'35,35,35');
            ObjectSetInteger(0, idA, OBJPROP_COLOR,   act==0 ? (color)C'200,200,200' : (color)C'80,80,80');
         }
         if(ObjectFind(0, idB) >= 0)
         {
            ObjectSetInteger(0, idB, OBJPROP_BGCOLOR, act==1 ? (color)C'58,58,58' : (color)C'35,35,35');
            ObjectSetInteger(0, idB, OBJPROP_COLOR,   act==1 ? (color)C'200,200,200' : (color)C'80,80,80');
         }
      }
   }
   ChartRedraw(0);
}

void RebuildPanelInPlace()
{
   if(!g_built) return;
   string eVal[];
   CapturePanelEdits(eVal);
   DeletePanel();
   BuildPanel();
   RestorePanelEdits(eVal);
}

//+------------------------------------------------------------------+
//| Entry Line & Break-Even Button                                   |
//+------------------------------------------------------------------+
int PriceToPixelY(double price)
{
   int bx = 0, by = 0;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 > 0 && ChartTimePriceToXY(0, 0, t0, price, bx, by))
      return by;
   return -1;
}

void CreateEntryLine()
{
   if(!InpInternal) return;
   if(ObjectFind(0, LN_ENTRY) >= 0) ObjectDelete(0, LN_ENTRY);

   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime t1 = (g_entryTime > 0) ? g_entryTime : t0;
   ObjectCreate(0, LN_ENTRY, OBJ_TREND, 0, t1, g_entry, D'2037.01.01', g_entry);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_COLOR,      clrBlack);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_BACK,       false);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_RAY,        false);
   ObjectSetInteger(0, LN_ENTRY, OBJPROP_SELECTABLE, false);
}

void UpdateBEButton()
{
   if(!g_built || !InpInternal || g_phase == 0)
   {
      ObjectDelete(0, BT_BE);
      return;
   }

   int y = PriceToPixelY(g_curSL);
   if(y < 0) { ObjectDelete(0, BT_BE); return; }

   const int btnW = 82, btnH = 15;
   int cw   = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int btnX = cw - 145;
   int btnY = y - btnH - 2;
   if(btnY < 0) btnY = 0;

   if(ObjectFind(0, BT_BE) < 0)
      MkButton(BT_BE, "Break Even", 0, btnX, btnY, btnW, btnH, clrWhite, C'70,70,70', 7);
   else
   {
      ObjectSetInteger(0, BT_BE, OBJPROP_XDISTANCE, btnX);
      ObjectSetInteger(0, BT_BE, OBJPROP_YDISTANCE, btnY);
   }
}

//+------------------------------------------------------------------+
//| Chart Lines (SL / TP / Entry)                                    |
//+------------------------------------------------------------------+
void CreateChartLines(bool bringPanelFront = true)
{
   if(!InpInternal) return;

   if(ObjectFind(0, LN_SL) >= 0) ObjectDelete(0, LN_SL);
   ObjectCreate(0, LN_SL, OBJ_HLINE, 0, 0, g_curSL);
   ObjectSetInteger(0, LN_SL, OBJPROP_COLOR,      clrCrimson);
   ObjectSetInteger(0, LN_SL, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, LN_SL, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, LN_SL, OBJPROP_BACK,       false);
   ObjectSetInteger(0, LN_SL, OBJPROP_SELECTABLE, true);

   if(ObjectFind(0, LN_TP) >= 0) ObjectDelete(0, LN_TP);
   ObjectCreate(0, LN_TP, OBJ_HLINE, 0, 0, g_curTP);
   ObjectSetInteger(0, LN_TP, OBJPROP_COLOR,      clrLimeGreen);
   ObjectSetInteger(0, LN_TP, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, LN_TP, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, LN_TP, OBJPROP_BACK,       false);
   ObjectSetInteger(0, LN_TP, OBJPROP_SELECTABLE, true);

   CreateEntryLine();
   UpdateLineLabels();
   if(bringPanelFront)
      RebuildPanelInPlace();
   ChartRedraw(0);
}

void DeleteChartLines()
{
   ObjectDelete(0, LN_SL);
   ObjectDelete(0, LN_TP);
   ObjectDelete(0, LB_SL);
   ObjectDelete(0, LB_TP);
   ObjectDelete(0, LN_ENTRY);
   ObjectDelete(0, BT_BE);
}

// Move a HLINE to a new price. Called only on explicit price changes —
// NOT on every tick, so lines remain draggable between events.
void MoveHLine(const string name, double price)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}

void UpdateLineLabels()
{
   if(!InpInternal || g_phase == 0) return;

   if(ObjectFind(0, LN_SL) < 0 || ObjectFind(0, LN_TP) < 0)
   {
      CreateChartLines();
      return;
   }

   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 == 0) return;
   datetime ft = t0 + (datetime)(PeriodSeconds() * 30);

   string phaseTag = (g_phase == 1 ? "[F]" : g_phase == 2 ? "[N]" : "[S]");

   // SL label
   string slTxt = "SL " + DoubleToString(g_curSL, _Digits);
   if(ObjectFind(0, LB_SL) < 0)
   {
      ObjectCreate(0, LB_SL, OBJ_TEXT, 0, ft, g_curSL);
      ObjectSetInteger(0, LB_SL, OBJPROP_COLOR,      C'220,80,80');
      ObjectSetInteger(0, LB_SL, OBJPROP_FONTSIZE,   8);
      ObjectSetString( 0, LB_SL, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, LB_SL, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, LB_SL, OBJPROP_BACK,       false);
      ObjectSetInteger(0, LB_SL, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectMove(0, LB_SL, 0, ft, g_curSL);
   }
   ObjectSetString(0, LB_SL, OBJPROP_TEXT, slTxt);

   // TP label
   string tpTxt = "TP " + DoubleToString(g_curTP, _Digits) + " " + phaseTag;
   if(ObjectFind(0, LB_TP) < 0)
   {
      ObjectCreate(0, LB_TP, OBJ_TEXT, 0, ft, g_curTP);
      ObjectSetInteger(0, LB_TP, OBJPROP_COLOR,      C'80,210,80');
      ObjectSetInteger(0, LB_TP, OBJPROP_FONTSIZE,   8);
      ObjectSetString( 0, LB_TP, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, LB_TP, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, LB_TP, OBJPROP_BACK,       false);
      ObjectSetInteger(0, LB_TP, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectMove(0, LB_TP, 0, ft, g_curTP);
   }
   ObjectSetString(0, LB_TP, OBJPROP_TEXT, tpTxt);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| State Persistence via GlobalVariables                            |
//+------------------------------------------------------------------+
string GK(const string k) { return "PEG_" + (string)ChartID() + "_" + k; }

void SaveState()
{
   GlobalVariableSet(GK("magic"),   (double)g_magic);
   GlobalVariableSet(GK("ticket"),  (double)g_ticket);
   GlobalVariableSet(GK("dir"),     (double)g_dir);
   GlobalVariableSet(GK("entry"),   g_entry);
   GlobalVariableSet(GK("phase"),   (double)g_phase);
   GlobalVariableSet(GK("curSL"),   g_curSL);
   GlobalVariableSet(GK("curTP"),   g_curTP);
   GlobalVariableSet(GK("fLot"),    g_fastLot);
   GlobalVariableSet(GK("nLot"),    g_normLot);
   GlobalVariableSet(GK("sLot"),    g_slowLot);
   GlobalVariableSet(GK("fTP"),     g_fastTP_p);
   GlobalVariableSet(GK("nTP"),     g_normTP_p);
   GlobalVariableSet(GK("sTP"),     g_slowTP_p);
   GlobalVariableSet(GK("nSL"),     (double)g_normSL_v);
   GlobalVariableSet(GK("sSL"),     (double)g_slowSL_v);
   GlobalVariableSet(GK("bLimSt"),  (double)g_buyLimState);
   GlobalVariableSet(GK("sLimSt"),  (double)g_sellLimState);
   GlobalVariableSet(GK("bLimPx"),  g_buyLimPrice);
   GlobalVariableSet(GK("sLimPx"),  g_sellLimPrice);
   GlobalVariableSet(GK("entryT"),  (double)g_entryTime);
}

void LoadState()
{
   if(!GlobalVariableCheck(GK("ticket"))) return;
   if(GlobalVariableCheck(GK("magic"))) g_magic  = (ulong)GlobalVariableGet(GK("magic"));
   g_ticket   = (ulong) GlobalVariableGet(GK("ticket"));
   g_dir      = (int)   GlobalVariableGet(GK("dir"));
   g_entry    =         GlobalVariableGet(GK("entry"));
   g_phase    = (int)   GlobalVariableGet(GK("phase"));
   g_curSL    =         GlobalVariableGet(GK("curSL"));
   g_curTP    =         GlobalVariableGet(GK("curTP"));
   g_fastLot  =         GlobalVariableGet(GK("fLot"));
   g_normLot  =         GlobalVariableGet(GK("nLot"));
   g_slowLot  =         GlobalVariableGet(GK("sLot"));
   g_fastTP_p =         GlobalVariableGet(GK("fTP"));
   g_normTP_p =         GlobalVariableGet(GK("nTP"));
   g_slowTP_p =         GlobalVariableGet(GK("sTP"));
   g_normSL_v = (int)   GlobalVariableGet(GK("nSL"));
   g_slowSL_v = (int)   GlobalVariableGet(GK("sSL"));
   if(GlobalVariableCheck(GK("bLimSt"))) g_buyLimState  = (int)   GlobalVariableGet(GK("bLimSt"));
   if(GlobalVariableCheck(GK("sLimSt"))) g_sellLimState = (int)   GlobalVariableGet(GK("sLimSt"));
   if(GlobalVariableCheck(GK("bLimPx"))) g_buyLimPrice  =         GlobalVariableGet(GK("bLimPx"));
   if(GlobalVariableCheck(GK("sLimPx"))) g_sellLimPrice =         GlobalVariableGet(GK("sLimPx"));
   if(GlobalVariableCheck(GK("entryT"))) g_entryTime    = (datetime)GlobalVariableGet(GK("entryT"));
}

void ClearSavedState()
{
   string keys[20];
   keys[0]="ticket"; keys[1]="dir";    keys[2]="entry";   keys[3]="phase";
   keys[4]="curSL";  keys[5]="curTP";  keys[6]="fLot";    keys[7]="nLot";
   keys[8]="sLot";   keys[9]="fTP";    keys[10]="nTP";    keys[11]="sTP";
   keys[12]="nSL";   keys[13]="sSL";   keys[14]="magic";
   keys[15]="bLimSt"; keys[16]="sLimSt"; keys[17]="bLimPx"; keys[18]="sLimPx";
   keys[19]="entryT";
   for(int i = 0; i < 20; i++) GlobalVariableDel(GK(keys[i]));
}

//+------------------------------------------------------------------+
//| Symbol Config File                                               |
//+------------------------------------------------------------------+
void SetConfigPair(const string idA, const string idB, const string val)
{
   if(val == "") return;
   ObjectSetString(0, PN(idA), OBJPROP_TEXT, val);
   ObjectSetString(0, PN(idB), OBJPROP_TEXT, val);
}

// Reads INI-style settings from MQL5/Files/.
//
// Section precedence (each overrides the previous):
//   [DEFAULT]      global fallback
//   [DEFAULT-TF]   e.g. [DEFAULT-H1]
//   [SYMBOL]       e.g. [EURUSD]
//   [SYMBOL-TF]    e.g. [EURUSD-M1]   ← most specific wins
//
// Supported keys:
//   FastLot, NormalLot, SlowLot
//   FastTP, NormalTP, SlowTP
//   FastSL, NormalSL, SlowSL
//   MinSL      — minimum SL distance in pips (overrides InpMinSL input)
//   DragMinSL  — minimum pip buffer when dragging the SL line (default 10)
//
// Values populate both A and B panel columns; user can still edit manually.
void LoadSymbolConfig(const string filename)
{
   // Reset runtime overrides to EA-input defaults before every load so that
   // a section without MinSL/DragMinSL never carries stale values from a prior load.
   g_minSL     = InpMinSL;
   g_dragMinSL = 10;

   int fh = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      Print("Pegasus: Config file '", filename, "' not found in MQL5/Files/ — using input defaults.");
      return;
   }

   string sym = _Symbol;
   string tf  = TfTag();

   string vFastLot="", vNormLot="", vSlowLot="";
   string vFastTP ="", vNormTP ="", vSlowTP ="";
   string vFastSL ="", vNormSL ="", vSlowSL ="";
   string vMinSL  ="", vDragMinSL="";
   string appliedSection = "";

   // Sections checked in ascending specificity; later matches override earlier ones.
   string targets[4];
   targets[0] = "DEFAULT";
   targets[1] = "DEFAULT-" + tf;   // e.g. [DEFAULT-H1]
   targets[2] = sym;               // e.g. [EURUSD]
   targets[3] = sym + "-" + tf;    // e.g. [EURUSD-M1]

   for(int pass = 0; pass < 4; pass++)
   {
      FileSeek(fh, 0, SEEK_SET);
      string target  = targets[pass];
      bool   inSect  = false;
      bool   matched = false;

      while(!FileIsEnding(fh))
      {
         string line = FileReadString(fh);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0 || StringSubstr(line, 0, 1) == ";") continue;

         if(StringSubstr(line, 0, 1) == "[")
         {
            int cl = StringFind(line, "]");
            inSect = (cl > 1 && StringSubstr(line, 1, cl - 1) == target);
            continue;
         }

         if(!inSect) continue;

         int    eq  = StringFind(line, "=");
         if(eq  < 1) continue;
         string key = StringSubstr(line, 0, eq);
         StringTrimRight(key);
         string val = StringSubstr(line, eq + 1);
         StringTrimLeft(val);

         int sc = StringFind(val, ";");
         if(sc >= 0) { val = StringSubstr(val, 0, sc); StringTrimRight(val); }
         if(StringLen(val) == 0) continue;

         if     (key == "FastLot")   { vFastLot   = val; matched = true; }
         else if(key == "NormalLot") { vNormLot   = val; matched = true; }
         else if(key == "SlowLot")   { vSlowLot   = val; matched = true; }
         else if(key == "FastTP")    { vFastTP    = val; matched = true; }
         else if(key == "NormalTP")  { vNormTP    = val; matched = true; }
         else if(key == "SlowTP")    { vSlowTP    = val; matched = true; }
         else if(key == "FastSL")    { vFastSL    = val; matched = true; }
         else if(key == "NormalSL")  { vNormSL    = val; matched = true; }
         else if(key == "SlowSL")    { vSlowSL    = val; matched = true; }
         else if(key == "MinSL")     { vMinSL     = val; matched = true; }
         else if(key == "DragMinSL") { vDragMinSL = val; matched = true; }
      }

      if(matched) appliedSection = target;
   }
   FileClose(fh);

   // Panel lot/tp/sl edit boxes
   SetConfigPair("EFASTLOTA","EFASTLOTB", vFastLot);
   SetConfigPair("ENORMLOTA","ENORMLOTB", vNormLot);
   SetConfigPair("ESLOWLOTA","ESLOWLOTB", vSlowLot);
   SetConfigPair("EFASTTPA", "EFASTTPB",  vFastTP);
   SetConfigPair("ENORMTPA", "ENORMTPB",  vNormTP);
   SetConfigPair("ESLOWTPA", "ESLOWTPB",  vSlowTP);
   SetConfigPair("EFASTSLA", "EFASTSLB",  vFastSL);
   SetConfigPair("ENORMSLA", "ENORMSLB",  vNormSL);
   SetConfigPair("ESLOWSLA", "ESLOWSLB",  vSlowSL);

   // Runtime overrides (not panel boxes)
   if(vMinSL     != "") g_minSL     = (int)StringToInteger(vMinSL);
   if(vDragMinSL != "") g_dragMinSL = (int)StringToInteger(vDragMinSL);

   Print("Pegasus: Config loaded — [",
         (appliedSection == "" ? "none, using defaults" : appliedSection),
         "] from '", filename, "'",
         (vMinSL     != "" ? StringFormat("  MinSL=%d",     g_minSL)     : ""),
         (vDragMinSL != "" ? StringFormat("  DragMinSL=%d", g_dragMinSL) : ""),
         ".");
}

//+------------------------------------------------------------------+
//| Broker / Lot Helpers                                             |
//+------------------------------------------------------------------+
double GetLotStep()  { double s = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);  return (s > 0.0) ? s : 0.01; }
double GetMinLot()   { double m = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);   return (m > 0.0) ? m : GetLotStep(); }
double GetMaxLot()   { double m = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);   return (m > 0.0) ? m : 100.0; }

// Detect the order filling mode the broker supports for this symbol.
// SYMBOL_FILLING_MODE is a bitmask: bit0=FOK allowed, bit1=IOC allowed, 0=RETURN only.
ENUM_ORDER_TYPE_FILLING GetSymbolFilling()
{
   uint mode = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mode & 1) != 0) return ORDER_FILLING_FOK;
   if((mode & 2) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

int GetLotDigits()
{
   double step = GetLotStep();
   int digits = 0;
   while(digits < 8 && MathAbs(step - MathRound(step)) > 1e-8)
   {
      step *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeLotsToBroker(double lots)
{
   double step = GetLotStep();
   return NormalizeDouble(MathRound(lots / step) * step, GetLotDigits());
}

bool IsValidLotAmount(double lots)
{
   double step   = GetLotStep();
   double minLot = GetMinLot();
   double maxLot = GetMaxLot();
   double tol    = step * 0.001;
   if(lots < minLot - tol || lots > maxLot + tol) return false;
   return (MathAbs(NormalizeLotsToBroker(lots) - lots) <= tol);
}

//+------------------------------------------------------------------+
//| Trade Logic                                                      |
//+------------------------------------------------------------------+
void ResetState()
{
   g_ticket = 0; g_dir = 0; g_entry = 0; g_entryTime = 0; g_phase = 0;
   g_curSL = 0; g_curTP = 0;
   g_fastLot = g_normLot = g_slowLot = 0;
   g_fastTP_p = g_normTP_p = g_slowTP_p = 0;
   ClearSavedState();
}

bool TradeIsOpen()
{
   if(g_ticket == 0) return false;
   if(!PositionSelectByTicket(g_ticket)) return false;
   return (PositionGetString(POSITION_SYMBOL)  == _Symbol &&
           PositionGetInteger(POSITION_MAGIC)  == (long)g_magic);
}

void FinalizeTrackedTrade()
{
   DeleteChartLines();
   ResetState();
}

// Partial close using raw MqlTradeRequest — preserves ticket in MQL5
// (no ticket-scan loop needed unlike MQL4 where some brokers reassigned tickets).
bool DoPartialClose(double lots)
{
   if(!PositionSelectByTicket(g_ticket)) return false;

   double curLots    = PositionGetDouble(POSITION_VOLUME);
   double step       = GetLotStep();
   double minLot     = GetMinLot();
   double tol        = step * 0.001;
   double closeLots  = NormalizeLotsToBroker(lots);

   if(closeLots <= 0.0)
   {
      Print("Pegasus: Partial close rejected. Invalid close volume=", lots);
      return false;
   }
   if(closeLots > curLots + tol)
   {
      Print("Pegasus: Partial close rejected. Close volume ", closeLots, " exceeds current lots ", curLots);
      return false;
   }
   if(MathAbs(closeLots - curLots) <= tol)
      closeLots = curLots;
   else if(closeLots < minLot - tol)
   {
      Print("Pegasus: Partial close rejected. Close volume ", closeLots, " below broker minimum ", minLot);
      return false;
   }

   double remainLots = NormalizeLotsToBroker(curLots - closeLots);
   if(remainLots > tol && remainLots < minLot - tol)
   {
      Print("Pegasus: Partial close rejected. Remaining lots ", remainLots, " below broker minimum ", minLot);
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.position     = g_ticket;
   req.symbol       = _Symbol;
   req.volume       = closeLots;
   req.type         = (g_dir == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price        = (g_dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.deviation    = 3;
   req.magic        = g_magic;
   req.comment      = "Pegasus partial";
   req.type_filling = GetSymbolFilling();

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
   {
      Print("Pegasus: Partial close failed. Err=", GetLastError(), " Retcode=", res.retcode);
      return false;
   }
   return true;
}

void DoUpdateSL(double newSL)
{
   newSL   = NormalizeDouble(newSL, _Digits);
   g_curSL = newSL;
   MoveHLine(LN_SL, newSL);   // explicit move only — not called every tick
   if(InpBroker && PositionSelectByTicket(g_ticket))
   {
      double tp = PositionGetDouble(POSITION_TP);
      if(!trade.PositionModify(g_ticket, newSL, tp))
         Print("Pegasus: SL modify failed. Err=", GetLastError());
   }
   SaveState();
   UpdateLineLabels();
}

void OpenTrade(int dir)
{
   if(g_phase != 0) { Alert("Pegasus: A trade is already tracked on this chart."); return; }
   CancelAllLimits();

   string sfx_lot = (g_activeLot == 0 ? "A" : "B");
   string sfx_tp  = (g_activeTP  == 0 ? "A" : "B");
   string sfx_sl  = (g_activeSL  == 0 ? "A" : "B");

   double fastLotIn = EDouble("EFASTLOT"+sfx_lot);
   double normLotIn = EDouble("ENORMLOT"+sfx_lot);
   double slowLotIn = EDouble("ESLOWLOT"+sfx_lot);
   int    fastTP    = EInt("EFASTTP"+sfx_tp);
   int    normTP    = EInt("ENORMTP"+sfx_tp);
   int    slowTP    = EInt("ESLOWTP"+sfx_tp);
   int    fastSL    = EInt("EFASTSL"+sfx_sl);
   int    normSL    = EInt("ENORMSL"+sfx_sl);
   int    slowSL    = EInt("ESLOWSL"+sfx_sl);
   double lotStep   = GetLotStep();
   double minLot    = GetMinLot();
   double maxLot    = GetMaxLot();
   int    lotDigits = GetLotDigits();

   if(!IsValidLotAmount(fastLotIn) || !IsValidLotAmount(normLotIn) || !IsValidLotAmount(slowLotIn))
   {
      Alert("Pegasus: Lot sizes must match broker rules.\n" +
            "Min=" + DoubleToString(minLot, lotDigits) +
            " Step=" + DoubleToString(lotStep, lotDigits) +
            " Max=" + DoubleToString(maxLot, lotDigits));
      return;
   }

   double fastLot = NormalizeLotsToBroker(fastLotIn);
   double normLot = NormalizeLotsToBroker(normLotIn);
   double slowLot = NormalizeLotsToBroker(slowLotIn);

   if(fastTP >= normTP || normTP >= slowTP)
   {
      Alert("Pegasus: TP must satisfy FAST < NORMAL < SLOW.\nGot: " +
            (string)fastTP + " / " + (string)normTP + " / " + (string)slowTP);
      return;
   }

   if(fastSL <= 0) { Alert("Pegasus: FAST SL must be a positive number."); return; }

   double pip      = g_pip;
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryEst = (dir == 1) ? ask : bid;

   // Compute FAST SL price
   double slPrice;
   if(InpSLMethod == SL_FROM_EXTREME)
   {
      if(dir == 1)
      {
         int bar  = iLowest(_Symbol, 0, MODE_LOW, InpSLBars, 1);
         slPrice  = iLow(_Symbol, 0, bar) - fastSL * pip;
      }
      else
      {
         int bar  = iHighest(_Symbol, 0, MODE_HIGH, InpSLBars, 1);
         slPrice  = iHigh(_Symbol, 0, bar) + fastSL * pip;
      }
   }
   else
   {
      slPrice = (dir == 1) ? entryEst - fastSL * pip : entryEst + fastSL * pip;
   }
   slPrice = NormalizeDouble(slPrice, _Digits);

   double slDist = MathRound(MathAbs(entryEst - slPrice) / pip);
   if(slDist < g_minSL)
   {
      Alert("Pegasus: SL distance (" + DoubleToString(slDist, 1) +
            " pts) < MinSL (" + (string)g_minSL + "). Trade cancelled.");
      return;
   }

   double tpFast = NormalizeDouble((dir==1) ? entryEst+fastTP*pip : entryEst-fastTP*pip, _Digits);
   double tpNorm = NormalizeDouble((dir==1) ? entryEst+normTP*pip : entryEst-normTP*pip, _Digits);
   double tpSlow = NormalizeDouble((dir==1) ? entryEst+slowTP*pip : entryEst-slowTP*pip, _Digits);

   double totalLots = NormalizeLotsToBroker(fastLot + normLot + slowLot);
   if(totalLots < minLot || totalLots > maxLot)
   {
      Alert("Pegasus: Total lots must be within broker range.\n" +
            "Total=" + DoubleToString(totalLots, lotDigits) +
            " Allowed=" + DoubleToString(minLot, lotDigits) +
            "..." + DoubleToString(maxLot, lotDigits));
      return;
   }

   double brokerSL = InpBroker ? slPrice : 0;

   trade.SetExpertMagicNumber(g_magic);
   trade.SetDeviationInPoints(3);

   bool ok = (dir == 1)
      ? trade.Buy(totalLots, _Symbol, 0, brokerSL, 0, "Pegasus")
      : trade.Sell(totalLots, _Symbol, 0, brokerSL, 0, "Pegasus");

   if(!ok)
   {
      uint rc = trade.ResultRetcode();
      string hint = "";
      if(rc == 10027) hint = " (AutoTrading disabled — enable the Algo Trading button in MT5 toolbar)";
      else if(rc == 10017) hint = " (Trading disabled by broker for this account/symbol)";
      else if(rc == 10019) hint = " (Not enough money)";
      else if(rc == 10014) hint = " (Invalid volume — check lot sizes)";
      else if(rc == 10016) hint = " (Invalid stops — check SL/TP distance)";
      Alert("Pegasus: OrderSend failed. Error=" + (string)GetLastError() +
            " Retcode=" + (string)rc + hint);
      return;
   }

   ulong ticket = trade.ResultOrder();
   if(ticket == 0)
   {
      Alert("Pegasus: Trade sent but no ticket returned.");
      return;
   }

   // Store state
   g_ticket   = ticket;
   g_dir      = dir;
   g_fastLot  = fastLot;
   g_normLot  = normLot;
   g_slowLot  = slowLot;
   g_normSL_v = normSL;
   g_slowSL_v = slowSL;
   g_phase    = 1;

   // Get actual fill price; recompute SL/TP from fill if using SL_FROM_ENTRY
   if(PositionSelectByTicket(ticket))
   {
      g_entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      g_entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   }
   else
   {
      g_entry     = (dir == 1) ? ask : bid;
      g_entryTime = TimeCurrent();
   }

   if(InpSLMethod == SL_FROM_ENTRY)
   {
      slPrice = NormalizeDouble((dir==1) ? g_entry-fastSL*pip : g_entry+fastSL*pip, _Digits);
      tpFast  = NormalizeDouble((dir==1) ? g_entry+fastTP*pip : g_entry-fastTP*pip, _Digits);
      tpNorm  = NormalizeDouble((dir==1) ? g_entry+normTP*pip : g_entry-normTP*pip, _Digits);
      tpSlow  = NormalizeDouble((dir==1) ? g_entry+slowTP*pip : g_entry-slowTP*pip, _Digits);
      if(InpBroker && MathAbs(slPrice - brokerSL) > _Point * 0.5)
         if(!trade.PositionModify(ticket, slPrice, 0))
            Print("Pegasus: SL adjust on fill failed. Err=", GetLastError());
   }

   g_fastTP_p = tpFast;
   g_normTP_p = tpNorm;
   g_slowTP_p = tpSlow;
   g_curSL    = slPrice;
   g_curTP    = tpFast;

   if(InpInternal) CreateChartLines();
   SaveState();

   Print("Pegasus: Trade opened. Ticket=", ticket,
         " ", (dir==1?"BUY":"SELL"),
         " Lots=", totalLots,
         " Entry=", g_entry,
         " SL=", slPrice,
         " TP1=", tpFast, " TP2=", tpNorm, " TP3=", tpSlow);
}

void CloseAll()
{
   if(g_ticket == 0) { Alert("Pegasus: No active trade."); return; }

   if(!TradeIsOpen())
   {
      FinalizeTrackedTrade();
      return;
   }

   if(PositionSelectByTicket(g_ticket))
   {
      if(!trade.PositionClose(g_ticket, 3))
      {
         Alert("Pegasus: Close failed. Err=" + (string)GetLastError() +
               " Retcode=" + (string)trade.ResultRetcode());
         return;
      }
      FinalizeTrackedTrade();
      return;
   }

   if(!TradeIsOpen())
      FinalizeTrackedTrade();
   else
      Alert("Pegasus: Unable to select tracked trade for close.");
}

void CheckTPHits()
{
   if(!InpInternal || g_phase == 0 || g_ticket == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(g_phase == 1)
   {
      bool hit = (g_dir == 1) ? (bid >= g_fastTP_p) : (ask <= g_fastTP_p);
      if(hit && DoPartialClose(g_fastLot))
      {
         g_phase = 2;
         g_curTP = g_normTP_p;
         MoveHLine(LN_TP, g_curTP);
         double newSL = NormalizeDouble(
            (g_dir==1) ? g_entry - g_normSL_v*g_pip : g_entry + g_normSL_v*g_pip, _Digits);
         DoUpdateSL(newSL);
         Print("Pegasus: FAST TP hit → Phase NORMAL. SL=", newSL);
      }
   }
   else if(g_phase == 2)
   {
      bool hit = (g_dir == 1) ? (bid >= g_normTP_p) : (ask <= g_normTP_p);
      if(hit && DoPartialClose(g_normLot))
      {
         g_phase = 3;
         g_curTP = g_slowTP_p;
         MoveHLine(LN_TP, g_curTP);
         double newSL = NormalizeDouble(
            (g_dir==1) ? g_entry - g_slowSL_v*g_pip : g_entry + g_slowSL_v*g_pip, _Digits);
         DoUpdateSL(newSL);
         Print("Pegasus: NORMAL TP hit → Phase SLOW. SL=", newSL);
      }
   }
   else if(g_phase == 3)
   {
      bool hit = (g_dir == 1) ? (bid >= g_slowTP_p) : (ask <= g_slowTP_p);
      if(hit && DoPartialClose(g_slowLot))
      {
         Print("Pegasus: SLOW TP hit. Trade complete.");
         FinalizeTrackedTrade();
      }
   }

   if(g_phase > 0) { SaveState(); UpdateLineLabels(); }
}

void CheckSLHit()
{
   if(!InpInternal || g_phase == 0 || g_ticket == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool hit = (g_dir == 1) ? (bid <= g_curSL) : (ask >= g_curSL);
   if(!hit) return;

   if(PositionSelectByTicket(g_ticket))
   {
      if(trade.PositionClose(g_ticket, 3))
      {
         Print("Pegasus: Internal SL hit. Trade closed.");
         FinalizeTrackedTrade();
      }
      else
         Print("Pegasus: SL close failed. Err=", GetLastError(),
               " Retcode=", trade.ResultRetcode());
      return;
   }

   if(!TradeIsOpen())
      FinalizeTrackedTrade();
}

//+------------------------------------------------------------------+
//| Panel Update                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!g_built) return;

   int newBtnState = (g_phase == 0) ? 0 : 1;
   if(newBtnState != g_btnState)
   {
      UpdateBtnRow();
      UpdateLimitButtons();
   }

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / g_pip;
   LblSet(PN("D1"), "Spread: " + DoubleToString(spread, 1) + "  |  " + _Symbol);

   if(g_phase == 0)
   {
      LblSet(PN("D2"), "No active trade");
      LblClr(PN("D2"), C'140,140,140');

      string wp_lot = (g_activeLot==0 ? "A" : "B");
      string wp_tp  = (g_activeTP ==0 ? "A" : "B");
      string wp_sl  = (g_activeSL ==0 ? "A" : "B");
      int fTP = EInt("EFASTTP"+wp_tp), nTP = EInt("ENORMTP"+wp_tp), sTP = EInt("ESLOWTP"+wp_tp);
      int fSL = EInt("EFASTSL"+wp_sl);
      double fL = EDouble("EFASTLOT"+wp_lot), nL = EDouble("ENORMLOT"+wp_lot), sL = EDouble("ESLOWLOT"+wp_lot);
      double minLot  = GetMinLot();
      double lotStep = GetLotStep();
      int    lotDig  = GetLotDigits();

      string warn = "";
      color  wclr = C'220,120,50';
      if(!IsValidLotAmount(fL) || !IsValidLotAmount(nL) || !IsValidLotAmount(sL))
         warn = "! Lots must match broker min/step: " +
                DoubleToString(minLot, lotDig) + " / " + DoubleToString(lotStep, lotDig);
      else if(fSL < g_minSL)
         warn = "! FAST SL (" + (string)fSL + ") < MinSL (" + (string)g_minSL + ")";
      else if(fSL <= 0)
         warn = "! FAST SL must be positive";
      else if(fTP >= nTP || nTP >= sTP)
         warn = "! TP order: FAST < NORMAL < SLOW required";

      LblSet(PN("D3"), warn);
      LblClr(PN("D3"), warn == "" ? C'140,140,140' : wclr);
   }
   else
   {
      if(PositionSelectByTicket(g_ticket))
      {
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         string phase  = (g_phase==1 ? "FAST" : g_phase==2 ? "NORMAL" : "SLOW");
         string d2 = "Entry: " + DoubleToString(g_entry, _Digits) +
                     "  SL: " + DoubleToString(g_curSL, _Digits) +
                     "  TP: " + DoubleToString(g_curTP, _Digits);
         string d3 = "P&L: " + (profit >= 0 ? "+" : "") + DoubleToString(profit, 2) +
                     " " + AccountInfoString(ACCOUNT_CURRENCY) + "  [" + phase + "]";
         LblSet(PN("D2"), d2);
         LblClr(PN("D2"), C'170,170,170');
         LblSet(PN("D3"), d3);
         LblClr(PN("D3"), profit >= 0 ? C'80,200,80' : C'200,80,80');
      }
   }
   // Risk mode: keep lot boxes current and refresh button label
   if(g_riskMode) UpdateRiskLots();
   UpdateRiskBtn();

   UpdateBEButton();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| EA Event Handlers                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pip = CalcPip();
   if(!InpInternal && !InpBroker)
      Print("Pegasus WARNING: Both InpInternal and InpBroker are false — no SL/TP protection active.");

   // Stable per-chart magic — survives EA reload (restored from GlobalVariables).
   // New instances mint a unique magic via a shared instance counter.
   if(GlobalVariableCheck(GK("magic")))
   {
      g_magic = (ulong)GlobalVariableGet(GK("magic"));
   }
   else
   {
      string cntKey = "PEG_INST_CNT";
      int cnt = GlobalVariableCheck(cntKey) ? (int)GlobalVariableGet(cntKey) + 1 : 1;
      GlobalVariableSet(cntKey, cnt);
      g_magic = (ulong)(MAGIC + cnt);
      GlobalVariableSet(GK("magic"), (double)g_magic);
   }
   Print("Pegasus: ChartID=", ChartID(), " Magic=", g_magic);

   trade.SetExpertMagicNumber(g_magic);
   trade.SetDeviationInPoints(3);
   trade.SetTypeFilling(GetSymbolFilling());

   // Trading permission checks — warn early so the journal is clear
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Pegasus WARNING: AutoTrading is DISABLED in the terminal toolbar. Enable it to trade.");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("Pegasus WARNING: Algo Trading is DISABLED for this EA. Enable via EA Properties → Common → Allow Algo Trading.");
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      Print("Pegasus WARNING: The broker/account has disabled automated trading.");

   g_chartW  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_chartH  = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   g_chartTF = (int)Period();
   CalcPanelPos();
   BuildPanel();

   LoadState();
   if(g_phase > 0)
   {
      if(TradeIsOpen())
      {
         if(InpInternal) CreateChartLines();
         Print("Pegasus: Restored active trade. Ticket=", g_ticket, " Phase=", g_phase);
      }
      else
      {
         Print("Pegasus: Tracked trade no longer open. Resetting.");
         ResetState();
      }
   }

   if(g_phase == 0)
      LoadSymbolConfig(InpConfigFile);

   if(g_buyLimState  > 0) CreateLimitLine(true);
   if(g_sellLimState > 0) CreateLimitLine(false);
   UpdateLimitButtons();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeletePanel();
   if(reason == REASON_REMOVE)
      DeleteChartLines();
}

void OnTick()
{
   if(!g_built) return;

   // Rebuild check runs first — before UpdatePanel/UpdateLineLabels create any objects,
   // so our own newly-created objects don't falsely trigger another rebuild next tick.
   if(ObjectsTotal(0, 0, -1) > g_objCount || ObjectFind(0, PN("BG")) < 0)
      RebuildPanelInPlace();

   // Detect external close
   if(g_phase > 0 && !TradeIsOpen())
   {
      Print("Pegasus: Trade closed externally. Resetting.");
      DeleteChartLines();
      ResetState();
   }

   if(InpInternal && g_phase > 0)
   {
      CheckSLHit();
      CheckTPHits();
   }

   CheckLimitLines();
   CheckLimitHits();

   UpdatePanel();

   // Update chart line labels only on new bar — HLINE objects themselves are moved
   // only by DoUpdateSL/CheckTPHits, never here, so user dragging stays possible.
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(InpInternal && g_phase > 0 && t0 != g_lastBar && t0 > 0)
   {
      g_lastBar = t0;
      UpdateLineLabels();
   }

   // Snapshot at END of tick — after all our objects are created, so the count
   // includes them and they won't spuriously trigger a rebuild next tick.
   g_objCount = ObjectsTotal(0, 0, -1);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Reposition panel only when chart WINDOW SIZE actually changes.
   // CHARTEVENT_CHART_CHANGE also fires on scroll/zoom — guard with pixel dims.
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int tf = (int)Period();
      bool tfChanged = (tf != g_chartTF);
      if(cw == g_chartW && ch == g_chartH && !tfChanged) return;
      g_chartW  = cw;
      g_chartH  = ch;
      g_chartTF = tf;

      string eVal[];
      CapturePanelEdits(eVal);

      CalcPanelPos();
      DeletePanel();
      BuildPanel();

      // On TF change reload config (no active trade); on resize preserve edits
      if(tfChanged && g_phase == 0)
         LoadSymbolConfig(InpConfigFile);
      else
         RestorePanelEdits(eVal);

      if(g_phase > 0 && InpInternal)
      {
         if(ObjectFind(0, LN_SL) < 0 || ObjectFind(0, LN_TP) < 0)
            CreateChartLines();
         else
            UpdateLineLabels();
      }

      ChartRedraw(0);
      return;
   }

   // Button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PN("BUY"))
      {
         ObjectSetInteger(0, PN("BUY"), OBJPROP_STATE, false);
         OpenTrade(1);
         UpdateBtnRow();
      }
      else if(sparam == PN("SELL"))
      {
         ObjectSetInteger(0, PN("SELL"), OBJPROP_STATE, false);
         OpenTrade(-1);
         UpdateBtnRow();
      }
      else if(sparam == PN("CLOSE"))
      {
         ObjectSetInteger(0, PN("CLOSE"), OBJPROP_STATE, false);
         CloseAll();
         UpdateBtnRow();
         UpdateLimitButtons();
      }
      else if(sparam == BT_BE)
      {
         ObjectSetInteger(0, BT_BE, OBJPROP_STATE, false);
         if(g_phase > 0)
         {
            double spreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
            double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double minGap    = (spreadPts + (double)g_dragMinSL) * g_pip;
            bool   valid     = (g_dir == 1) ? (g_entry < bid - minGap)
                                            : (g_entry > ask + minGap);
            if(!valid)
               Alert("Pegasus: Cannot set Break Even — entry is too close to or past current price.");
            else
               DoUpdateSL(g_entry);
         }
      }
      else if(sparam == PN("RISKBTN"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_riskMode = !g_riskMode;
         if(g_riskMode)
            UpdateRiskLots();           // populate boxes immediately on enable
         else if(g_phase == 0)
            LoadSymbolConfig(InpConfigFile); // restore config lot sizes when disabled
         UpdateRiskBtn();
      }
      else if(sparam == PN("SELBTN_LOT_A")) { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeLot=0; UpdateSelBtnColors(); }
      else if(sparam == PN("SELBTN_LOT_B")) { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeLot=1; UpdateSelBtnColors(); }
      else if(sparam == PN("SELBTN_TP_A"))  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeTP=0;  UpdateSelBtnColors(); }
      else if(sparam == PN("SELBTN_TP_B"))  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeTP=1;  UpdateSelBtnColors(); }
      else if(sparam == PN("SELBTN_SL_A"))  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeSL=0;  UpdateSelBtnColors(); }
      else if(sparam == PN("SELBTN_SL_B"))  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_activeSL=1;  UpdateSelBtnColors(); }
      else if(sparam == PN("BUYLIM"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_phase > 0) return;
         if(g_buyLimState == 0)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            g_buyLimPrice = NormalizeDouble(bid - 50.0 * g_pip, _Digits);
            CreateLimitLine(true);
            g_buyLimState = 1;
         }
         else if(g_buyLimState == 1)
         {
            double limPrice = NormalizeDouble(ObjectGetDouble(0, LN_BUY_LIM, OBJPROP_PRICE), _Digits);
            double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(limPrice >= ask)
               Alert("Pegasus: Buy Limit price must be below current Ask (", ask, "). Drag the line lower.");
            else
            {
               g_buyLimPrice = limPrice;
               g_buyLimState = 2;
               SaveState();
            }
         }
         else
         {
            CancelBuyLim();
            SaveState();
         }
         UpdateLimitButtons();
      }
      else if(sparam == PN("SELLLIM"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(g_phase > 0) return;
         if(g_sellLimState == 0)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            g_sellLimPrice = NormalizeDouble(ask + 50.0 * g_pip, _Digits);
            CreateLimitLine(false);
            g_sellLimState = 1;
         }
         else if(g_sellLimState == 1)
         {
            double limPrice = NormalizeDouble(ObjectGetDouble(0, LN_SELL_LIM, OBJPROP_PRICE), _Digits);
            double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(limPrice <= bid)
               Alert("Pegasus: Sell Limit price must be above current Bid (", bid, "). Drag the line higher.");
            else
            {
               g_sellLimPrice = limPrice;
               g_sellLimState = 2;
               SaveState();
            }
         }
         else
         {
            CancelSellLim();
            SaveState();
         }
         UpdateLimitButtons();
      }
   }

   // Draggable SL / TP lines
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(sparam == LN_SL && g_phase > 0)
      {
         double newPrice  = NormalizeDouble(ObjectGetDouble(0, LN_SL, OBJPROP_PRICE), _Digits);
         double spreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double minGap    = (spreadPts + (double)g_dragMinSL) * g_pip;
         bool   validSL   = (g_dir == 1) ? (newPrice < bid - minGap)
                                          : (newPrice > ask + minGap);
         if(!validSL)
         {
            // Snap back — ObjectSetDouble on HLINE resets price without needing ObjectMove
            ObjectSetDouble(0, LN_SL, OBJPROP_PRICE, g_curSL);
            ChartRedraw(0);
            Alert("Pegasus: SL too close to current price. Must be at least spread+" + (string)g_dragMinSL + " pts away.");
         }
         else
         {
            DoUpdateSL(newPrice);
            Print("Pegasus: SL dragged to ", newPrice);
            ChartRedraw(0);
         }
      }
      else if(sparam == LN_TP && g_phase > 0)
      {
         double newPrice = NormalizeDouble(ObjectGetDouble(0, LN_TP, OBJPROP_PRICE), _Digits);
         g_curTP = newPrice;
         if(g_phase == 1)      g_fastTP_p = newPrice;
         else if(g_phase == 2) g_normTP_p = newPrice;
         else if(g_phase == 3) g_slowTP_p = newPrice;
         SaveState();
         UpdateLineLabels();
         Print("Pegasus: TP dragged to ", newPrice);
         ChartRedraw(0);
      }
      else if(sparam == LN_BUY_LIM && g_buyLimState > 0)
      {
         g_buyLimPrice = NormalizeDouble(ObjectGetDouble(0, LN_BUY_LIM, OBJPROP_PRICE), _Digits);
         ChartRedraw(0);
      }
      else if(sparam == LN_SELL_LIM && g_sellLimState > 0)
      {
         g_sellLimPrice = NormalizeDouble(ObjectGetDouble(0, LN_SELL_LIM, OBJPROP_PRICE), _Digits);
         ChartRedraw(0);
      }
   }
}
