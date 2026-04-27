//+------------------------------------------------------------------+
//|                                     LiquidityMakerCandle.mq5    |
//|  Liquidity-maker candle/zigzag detector with interactive panel. |
//+------------------------------------------------------------------+
#property copyright   "2026"
#property version     "1.52"
#property description "Marks liquidity-maker candles/zigzag pivots based on Daily ATR(14)"
#property indicator_chart_window
#property indicator_plots 0

//=== INPUTS =========================================================
input double           InpATRMultiplier    = 0.125;
input int              InpRectMinutes      = 20;
input color            InpBullishRectColor = clrRed;
input color            InpBearishRectColor = clrGreen;
input bool             InpFillRect         = true;
input color            InpBullishFillColor = clrMistyRose;
input color            InpBearishFillColor = clrHoneydew;
input int              InpLookback         = 500;
input ENUM_BASE_CORNER InpPanelCorner      = CORNER_RIGHT_UPPER;
input int              InpScoreFontSize    = 9;
input color            InpCriteriaColor    = clrBlack;
input color            InpScoreColor       = clrBlue;
input int              InpDivRSIPeriod     = 14;
input int              InpExhaustRSIPeriod = 9;

//=== DATA PREFIXES =================================================
#define PFX_OUTLINE    "LMC_RO_"
#define PFX_FILL_R     "LMC_RF_"
#define PFX_ZZ_OUTLINE "LMC_RZO_"
#define PFX_ZZ_FILL    "LMC_RZF_"
#define PFX_ZZ_LINE    "LMC_RZL_"
#define PFX_DATA       "LMC_R"
#define PFX_ZZ_DATA    "LMC_RZ"
#define PFX_SCRC       "LMC_SCRC_"
#define PFX_SCRV       "LMC_SCRV_"

//=== PANEL NAMES ===================================================
#define PN_BG      "LMCP_BG"
#define PN_TITLE   "LMCP_TI"
#define PN_DIV1    "LMCP_D1"
#define PN_LTF     "LMCP_LT"
#define PN_BTF10   "LMCP_F10"
#define PN_BTF15   "LMCP_F15"
#define PN_BTF30   "LMCP_F30"
#define PN_BTFH1   "LMCP_FH1"
#define PN_DIVTF   "LMCP_DT"
#define PN_BZZMODE "LMCP_ZM"
#define PN_BZZC    "LMCP_ZC"
#define PN_BZZM2   "LMCP_ZM2"
#define PN_BZZM5   "LMCP_ZM5"
#define PN_BZZM10  "LMCP_ZM10"
#define PN_BZZM15  "LMCP_ZM15"
#define PN_DIVZZ   "LMCP_DZ"
#define PN_LZZDEP  "LMCP_ZLD"
#define PN_EZZDEP  "LMCP_ZED"
#define PN_LZZDEV  "LMCP_ZLV"
#define PN_EZZDEV  "LMCP_ZEV"
#define PN_LZZBACK "LMCP_ZLB"
#define PN_EZZBACK "LMCP_ZEB"
#define PN_DIVZZ2  "LMCP_DZ2"
#define PN_LATR    "LMCP_LA"
#define PN_EATR    "LMCP_EA"
#define PN_LMIN    "LMCP_LM"
#define PN_EMIN    "LMCP_EM"
#define PN_BDRAW   "LMCP_BD"
#define PN_DIV2    "LMCP_D2"
#define PN_LFILL   "LMCP_LF"
#define PN_BFILL   "LMCP_BF"
#define PN_LSHOWZZ "LMCP_SZL"
#define PN_BSHOWZZ "LMCP_SZB"
#define PN_DIV3    "LMCP_D3"
#define PN_LSHOW   "LMCP_LS"
#define PN_BBOTH   "LMCP_BB"
#define PN_BBULL   "LMCP_BU"
#define PN_BBEAR   "LMCP_BE"
#define PN_PFX     "LMCP_"

#define PANEL_W    200
#define PANEL_H    337
#define PANEL_MX   10
#define PANEL_MY   25

//=== STATE =========================================================
int             g_atrHandle     = INVALID_HANDLE;
int             g_zzHandle      = INVALID_HANDLE;
int             g_fastZZHandle  = INVALID_HANDLE;
int             g_rsiDivHandle  = INVALID_HANDLE;
int             g_rsiExhHandle  = INVALID_HANDLE;
datetime        g_lastProcessed = 0;
double          g_atrMult       = 0.25;
int             g_rectMins      = 90;
bool            g_fillOn        = false;
int             g_showFilter    = 0;
ENUM_TIMEFRAMES g_baseTF        = PERIOD_M15;
bool            g_useZigZag     = true;
ENUM_TIMEFRAMES g_zzTF          = PERIOD_M15;
int             g_zzDepth       = 12;
int             g_zzDev         = 7;
int             g_zzBack        = 3;
bool            g_showZZLines   = true;

//+------------------------------------------------------------------+
int OnInit() {
    // Release any stale handles from a previous symbol/TF (e.g. symbol drag)
    ClearZZHandle();
    if(g_atrHandle != INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle = INVALID_HANDLE; }

    if(Period() > PERIOD_H1) {
        Alert("LiquidityMakerCandle: Attach to H1 or lower timeframe.");
        return INIT_FAILED;
    }
    g_atrHandle = iATR(_Symbol, PERIOD_D1, 14);
    if(g_atrHandle == INVALID_HANDLE) {
        Alert("LiquidityMakerCandle: Cannot create ATR(14,D1) handle.");
        return INIT_FAILED;
    }
    g_atrMult       = InpATRMultiplier;
    g_rectMins      = InpRectMinutes;
    g_fillOn        = InpFillRect;
    g_showFilter    = 0;
    g_baseTF        = PERIOD_M15;
    g_useZigZag     = true;
    g_zzTF          = (ENUM_TIMEFRAMES)Period();
    g_showZZLines   = true;
    g_lastProcessed = 0;
    PurgeData();
    BuildPanel();
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    PurgeData();
    PurgePanel();
    if(g_atrHandle != INVALID_HANDLE) { IndicatorRelease(g_atrHandle); g_atrHandle = INVALID_HANDLE; }
    ClearZZHandle();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {
    ScanAndDraw();
    return rates_total;
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_CHART_CHANGE) {
        BuildPanel();
        if(g_useZigZag) {
            PurgeZZData();
            ScanAndDrawZZ();
        }
        return;
    }
    if(id == CHARTEVENT_OBJECT_CLICK) {
        ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

        if(sparam == PN_BDRAW) {
            double v = StringToDouble(ObjectGetString(0, PN_EATR, OBJPROP_TEXT));
            int    m = (int)StringToInteger(ObjectGetString(0, PN_EMIN, OBJPROP_TEXT));
            if(v > 0) g_atrMult  = v;
            if(m > 0) g_rectMins = m;
            if(g_useZigZag) {
                int dep  = (int)StringToInteger(ObjectGetString(0, PN_EZZDEP,  OBJPROP_TEXT));
                int dev  = (int)StringToInteger(ObjectGetString(0, PN_EZZDEV,  OBJPROP_TEXT));
                int back = (int)StringToInteger(ObjectGetString(0, PN_EZZBACK, OBJPROP_TEXT));
                if(dep  > 0) g_zzDepth = dep;
                if(dev  > 0) g_zzDev   = dev;
                if(back > 0) g_zzBack  = back;
                ClearZZHandle();
            }
            Redraw(); return;
        }
        if(sparam == PN_BFILL)   { g_fillOn     = !g_fillOn;     BuildPanel(); Redraw(); return; }
        if(sparam == PN_BSHOWZZ) { g_showZZLines= !g_showZZLines;BuildPanel(); Redraw(); return; }
        if(sparam == PN_BBOTH)   { g_showFilter = 0; BuildPanel(); Redraw(); return; }
        if(sparam == PN_BBULL)   { g_showFilter = 1; BuildPanel(); Redraw(); return; }
        if(sparam == PN_BBEAR)   { g_showFilter = 2; BuildPanel(); Redraw(); return; }

        // ZigZag main toggle
        if(sparam == PN_BZZMODE) {
            g_useZigZag = !g_useZigZag;
            if(!g_useZigZag) ClearZZHandle();
            BuildPanel(); Redraw(); return;
        }

        // ZigZag TF buttons — activate ZZ mode with chosen TF
        if(sparam == PN_BZZC)   { g_zzTF = Period();      g_useZigZag = true; ClearZZHandle(); BuildPanel(); Redraw(); return; }
        if(sparam == PN_BZZM2)  { g_zzTF = PERIOD_M2;     g_useZigZag = true; ClearZZHandle(); BuildPanel(); Redraw(); return; }
        if(sparam == PN_BZZM5)  { g_zzTF = PERIOD_M5;     g_useZigZag = true; ClearZZHandle(); BuildPanel(); Redraw(); return; }
        if(sparam == PN_BZZM10) { g_zzTF = PERIOD_M10;    g_useZigZag = true; ClearZZHandle(); BuildPanel(); Redraw(); return; }
        if(sparam == PN_BZZM15) { g_zzTF = PERIOD_M15;    g_useZigZag = true; ClearZZHandle(); BuildPanel(); Redraw(); return; }

        // Candle TF buttons — cancel ZZ mode
        if(sparam == PN_BTF10) { g_useZigZag = false; ClearZZHandle(); g_baseTF = PERIOD_M10; BuildPanel(); Redraw(); return; }
        if(sparam == PN_BTF15) { g_useZigZag = false; ClearZZHandle(); g_baseTF = PERIOD_M15; BuildPanel(); Redraw(); return; }
        if(sparam == PN_BTF30) { g_useZigZag = false; ClearZZHandle(); g_baseTF = PERIOD_M30; BuildPanel(); Redraw(); return; }
        if(sparam == PN_BTFH1) { g_useZigZag = false; ClearZZHandle(); g_baseTF = PERIOD_H1;  BuildPanel(); Redraw(); return; }
    }
}

//+------------------------------------------------------------------+
void Redraw() { PurgeData(); g_lastProcessed = 0; ScanAndDraw(); }

void ScanAndDraw() {
    if(g_useZigZag) ScanAndDrawZZ();
    else            ScanAndDrawCandles();
}

//+------------------------------------------------------------------+
void ScanAndDrawCandles() {
    MqlRates bars[];
    ArraySetAsSeries(bars, true);
    int barCnt = CopyRates(_Symbol, g_baseTF, 0, InpLookback + 1, bars);
    if(barCnt < 2) return;

    const int D1_BUF = 500;
    datetime d1Time[]; double d1Atr[];
    ArraySetAsSeries(d1Time, true); ArraySetAsSeries(d1Atr, true);
    if(CopyTime(_Symbol, PERIOD_D1, 0, D1_BUF, d1Time) < 1) return;
    if(CopyBuffer(g_atrHandle, 0, 0, D1_BUF, d1Atr)   < 1) return;

    for(int i = barCnt - 1; i >= 1; i--) {
        datetime t = bars[i].time;
        if(t <= g_lastProcessed) continue;
        double atr = FindD1ATR(t, d1Time, d1Atr, ArraySize(d1Time));
        if(atr > 0.0 && (bars[i].high - bars[i].low) >= g_atrMult * atr)
            DrawCandleRect(t, bars[i].open, bars[i].close, bars[i].high, bars[i].low);
        g_lastProcessed = t;
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
void MakeScoreText(const string name, datetime t, double price,
                   const string txt, color clr, ENUM_ANCHOR_POINT anchor,
                   const string tooltip) {
    if(ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) {
        ObjectSetString( 0, name, OBJPROP_TEXT,       txt);
        ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpScoreFontSize);
        ObjectSetString( 0, name, OBJPROP_FONT,       "Arial Bold");
        ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
        ObjectSetString( 0, name, OBJPROP_TOOLTIP,    tooltip);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    }
}

string ShortDivKind(const string kind) {
    if(kind == "Regular bearish") return "RB";
    if(kind == "Hidden bearish")  return "HB";
    if(kind == "Regular bullish") return "RU";
    if(kind == "Hidden bullish")  return "HU";
    return kind;
}

string CompactFloat(double v) {
    return DoubleToString(v, 1);
}

string MakeCompactTip(const string fiboLvl, int fiboScore,
                      const string divTip, int divScore,
                      const string exhTip, int exhScore,
                      const string candleTip, int candleScore) {
    string tip = "Z " + fiboLvl + "/" + IntegerToString(fiboScore);
    if(divScore > 0)    tip += " D " + divTip + "/" + IntegerToString(divScore);
    if(exhScore > 0)    tip += " E " + exhTip + "/" + IntegerToString(exhScore);
    if(candleScore > 0) tip += " C " + candleTip + "/" + IntegerToString(candleScore);
    return tip;
}

void TrimCandleTip(string &tip) {
    StringReplace(tip, "Gravestone Doji", "GDoji");
    StringReplace(tip, "Dragonfly Doji", "DDoji");
    StringReplace(tip, "Two consecutive SpinTops", "2Spin");
    StringReplace(tip, "Spinning Top", "Spin");
    StringReplace(tip, "Bull-body Shooting Star", "BullSS");
    StringReplace(tip, "Bear-body Hammer", "BearHam");
    StringReplace(tip, "Tweezer Top", "TwTop");
    StringReplace(tip, "Tweezer Bottom", "TwBot");
    StringReplace(tip, "Bearish Engulfing", "BrEng");
    StringReplace(tip, "Bullish Engulfing", "BuEng");
    StringReplace(tip, " (+", "+");
    StringReplace(tip, ")", "");
    StringReplace(tip, "\n", ",");
}

double ScoreLabelFallbackOffset(const double atr) {
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(point <= 0.0) point = _Point;

    double minOffset = point * MathMax(8.0, (double)InpScoreFontSize * 1.5);
    double atrOffset = atr * 0.03;
    return MathMax(minOffset, atrOffset);
}

bool ShiftChartPoint(datetime refTime, double refPrice, int dx, int dy,
                     datetime &outTime, double &outPrice) {
    outTime  = refTime;
    outPrice = refPrice;

    int x = 0, y = 0;
    if(!ChartTimePriceToXY(0, 0, refTime, refPrice, x, y))
        return false;

    int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    int tgtX   = x + dx;
    int tgtY   = y + dy;

    if(chartW > 0) {
        if(tgtX < 0)         tgtX = 0;
        if(tgtX >= chartW)   tgtX = chartW - 1;
    }
    if(chartH > 0) {
        if(tgtY < 0)         tgtY = 0;
        if(tgtY >= chartH)   tgtY = chartH - 1;
    }

    int subWindow = 0;
    return ChartXYToTimePrice(0, tgtX, tgtY, subWindow, outTime, outPrice);
}

int EstimateLabelPixelWidth(const string txt) {
    int chars = StringLen(txt);
    return MathMax(22, chars * MathMax(6, InpScoreFontSize));
}

double CandleRange(const MqlRates &bar) {
    return bar.high - bar.low;
}

double CandleBody(const MqlRates &bar) {
    return MathAbs(bar.close - bar.open);
}

double UpperShadow(const MqlRates &bar) {
    return bar.high - MathMax(bar.open, bar.close);
}

double LowerShadow(const MqlRates &bar) {
    return MathMin(bar.open, bar.close) - bar.low;
}

bool IsBullishCandle(const MqlRates &bar) {
    return bar.close > bar.open;
}

bool IsBearishCandle(const MqlRates &bar) {
    return bar.close < bar.open;
}

bool NearEqual(double a, double b, double tolerance) {
    return MathAbs(a - b) <= tolerance;
}

bool IsSpinningTop(const MqlRates &bar) {
    double range = CandleRange(bar);
    if(range <= 0.0) return false;

    double body  = CandleBody(bar);
    double upper = UpperShadow(bar);
    double lower = LowerShadow(bar);
    return (body <= range * 0.35 &&
            upper >= range * 0.25 &&
            lower >= range * 0.25);
}

bool IsGravestoneDoji(const MqlRates &bar) {
    double range = CandleRange(bar);
    if(range <= 0.0) return false;

    double body  = CandleBody(bar);
    double upper = UpperShadow(bar);
    double lower = LowerShadow(bar);
    return (body <= range * 0.10 &&
            upper >= range * 0.60 &&
            lower <= range * 0.10);
}

bool IsDragonflyDoji(const MqlRates &bar) {
    double range = CandleRange(bar);
    if(range <= 0.0) return false;

    double body  = CandleBody(bar);
    double upper = UpperShadow(bar);
    double lower = LowerShadow(bar);
    return (body <= range * 0.10 &&
            lower >= range * 0.60 &&
            upper <= range * 0.10);
}

bool IsBullBodyShootingStar(const MqlRates &bar) {
    double range = CandleRange(bar);
    if(range <= 0.0) return false;

    double body  = CandleBody(bar);
    double upper = UpperShadow(bar);
    double lower = LowerShadow(bar);
    if(!IsBullishCandle(bar) || body <= 0.0) return false;

    return (upper >= body * 2.0 &&
            lower <= MathMax(body * 0.25, range * 0.10) &&
            (MathMax(bar.open, bar.close) - bar.low) <= range * 0.35);
}

bool IsBearBodyHammer(const MqlRates &bar) {
    double range = CandleRange(bar);
    if(range <= 0.0) return false;

    double body  = CandleBody(bar);
    double upper = UpperShadow(bar);
    double lower = LowerShadow(bar);
    if(!IsBearishCandle(bar) || body <= 0.0) return false;

    return (lower >= body * 2.0 &&
            upper <= MathMax(body * 0.25, range * 0.10) &&
            (bar.high - MathMin(bar.open, bar.close)) <= range * 0.35);
}

bool IsBearishEngulfing(const MqlRates &left, const MqlRates &right) {
    return (IsBullishCandle(left) &&
            IsBearishCandle(right) &&
            right.open >= left.close &&
            right.close <= left.open);
}

bool IsBullishEngulfing(const MqlRates &left, const MqlRates &right) {
    return (IsBearishCandle(left) &&
            IsBullishCandle(right) &&
            right.open <= left.close &&
            right.close >= left.open);
}

bool IsTweezerTop(const MqlRates &left, const MqlRates &right) {
    double tol = MathMax(_Point * 3.0, MathMax(CandleRange(left), CandleRange(right)) * 0.08);
    return NearEqual(left.high, right.high, tol);
}

bool IsTweezerBottom(const MqlRates &left, const MqlRates &right) {
    double tol = MathMax(_Point * 3.0, MathMax(CandleRange(left), CandleRange(right)) * 0.08);
    return NearEqual(left.low, right.low, tol);
}

int AddPattern(string &detail, int score, const string name) {
    if(detail != "") detail += "\n";
    detail += StringFormat("%s (+%d)", name, score);
    return score;
}

int ScoreCandlestickPatterns(bool isHigh, int pivotIdx, const MqlRates &bars[], int totalBars,
                             string &detail) {
    detail = "";
    if(pivotIdx < 0 || pivotIdx >= totalBars) return 0;

    const MqlRates pivotBar = bars[pivotIdx];
    const bool hasPrev = (pivotIdx + 1 < totalBars);
    const bool hasNext = (pivotIdx - 1 >= 0);
    const MqlRates prevBar = hasPrev ? bars[pivotIdx + 1] : pivotBar;
    const MqlRates nextBar = hasNext ? bars[pivotIdx - 1] : pivotBar;

    int score = 0;

    if(isHigh) {
        if(IsGravestoneDoji(pivotBar))
            score += AddPattern(detail, 3, "Gravestone Doji");
        if(IsBullBodyShootingStar(pivotBar))
            score += AddPattern(detail, 2, "Bull-body Shooting Star");
        if(IsSpinningTop(pivotBar))
            score += AddPattern(detail, 2, "Spinning Top");

        bool twoSpin = (hasPrev && IsSpinningTop(prevBar) && IsSpinningTop(pivotBar)) ||
                       (hasNext && IsSpinningTop(pivotBar) && IsSpinningTop(nextBar));
        if(twoSpin)
            score += AddPattern(detail, 3, "Two consecutive SpinTops");

        bool tweezer = (hasPrev && IsTweezerTop(prevBar, pivotBar)) ||
                       (hasNext && IsTweezerTop(pivotBar, nextBar));
        if(tweezer)
            score += AddPattern(detail, 1, "Tweezer Top");

        bool engulf = (hasPrev && IsBearishEngulfing(prevBar, pivotBar)) ||
                      (hasNext && IsBearishEngulfing(pivotBar, nextBar));
        if(engulf)
            score += AddPattern(detail, 1, "Bearish Engulfing");
    } else {
        if(IsDragonflyDoji(pivotBar))
            score += AddPattern(detail, 3, "Dragonfly Doji");
        if(IsBearBodyHammer(pivotBar))
            score += AddPattern(detail, 2, "Bear-body Hammer");
        if(IsSpinningTop(pivotBar))
            score += AddPattern(detail, 2, "Spinning Top");

        bool twoSpin = (hasPrev && IsSpinningTop(prevBar) && IsSpinningTop(pivotBar)) ||
                       (hasNext && IsSpinningTop(pivotBar) && IsSpinningTop(nextBar));
        if(twoSpin)
            score += AddPattern(detail, 3, "Two consecutive SpinTops");

        bool tweezer = (hasPrev && IsTweezerBottom(prevBar, pivotBar)) ||
                       (hasNext && IsTweezerBottom(pivotBar, nextBar));
        if(tweezer)
            score += AddPattern(detail, 1, "Tweezer Bottom");

        bool engulf = (hasPrev && IsBullishEngulfing(prevBar, pivotBar)) ||
                      (hasNext && IsBullishEngulfing(pivotBar, nextBar));
        if(engulf)
            score += AddPattern(detail, 1, "Bullish Engulfing");
    }

    return score;
}

void CollectPivotIndices(const double &buf[], int total, int &pIdx[]) {
    ArrayResize(pIdx, 0);
    for(int i = 0; i < total; i++) {
        if(buf[i] != 0.0) {
            int sz = ArraySize(pIdx);
            ArrayResize(pIdx, sz + 1);
            pIdx[sz] = i;
        }
    }
}

bool HasRSIDivergence(bool isHigh, double newerPrice, double olderPrice,
                      double newerRsi, double olderRsi, string &kind) {
    kind = "";
    if(isHigh) {
        if(newerPrice > olderPrice && newerRsi < olderRsi) {
            kind = "Regular bearish";
            return true;
        }
        if(newerPrice < olderPrice && newerRsi > olderRsi) {
            kind = "Hidden bearish";
            return true;
        }
    } else {
        if(newerPrice < olderPrice && newerRsi > olderRsi) {
            kind = "Regular bullish";
            return true;
        }
        if(newerPrice > olderPrice && newerRsi < olderRsi) {
            kind = "Hidden bullish";
            return true;
        }
    }
    return false;
}

int FindClosestFastPivotPos(const int &fastIdx[], const double &fastBuf[],
                            const MqlRates &bars[], datetime mainTime, bool isHigh) {
    int  fastCount = ArraySize(fastIdx);
    int  bestPos   = -1;
    long bestDist  = LONG_MAX;

    for(int f = 0; f + 2 < fastCount; f++) {
        bool fastIsHigh = (fastBuf[fastIdx[f]] > fastBuf[fastIdx[f + 1]]);
        if(fastIsHigh != isHigh) continue;

        long dist = (long)MathAbs((double)(bars[fastIdx[f]].time - mainTime));
        if(dist < bestDist) {
            bestDist = dist;
            bestPos  = f;
        }
    }
    return bestPos;
}

bool FindFastZZDivergence(bool isHigh, int mainIdx, double mainPrice, datetime mainTime,
                          const double &fastBuf[], const int &fastIdx[],
                          const MqlRates &bars[], const double &rsiBuf[], int rsiCnt,
                          string &detail) {
    detail = "";

    int fastPos = FindClosestFastPivotPos(fastIdx, fastBuf, bars, mainTime, isHigh);
    if(fastPos < 0) return false;

    int refIdx = fastIdx[fastPos + 2];
    if(mainIdx >= rsiCnt || refIdx >= rsiCnt) return false;

    string kind;
    if(!HasRSIDivergence(isHigh, mainPrice, fastBuf[refIdx], rsiBuf[mainIdx], rsiBuf[refIdx], kind))
        return false;

    detail = StringFormat(
        "F%s %s/%s",
        ShortDivKind(kind), CompactFloat(rsiBuf[mainIdx]), CompactFloat(rsiBuf[refIdx]));
    return true;
}

void ScoreAndDrawZ(const double &zzBuf[], const MqlRates &bars[], int gotBars,
                   const double &fastZZBuf[], const double &rsiDivBuf[], int rsiDivCnt,
                   const double &rsiExhBuf[], int rsiExhCnt,
                   const datetime &d1Time[], const double &d1Atr[], int d1Cnt) {
    // Collect bar indices of all pivots, series order: pIdx[0]=most recent
    int pIdx[];
    CollectPivotIndices(zzBuf, gotBars, pIdx);
    int pCount = ArraySize(pIdx);
    if(pCount < 3) return;

    int fastIdx[];
    CollectPivotIndices(fastZZBuf, gotBars, fastIdx);

    for(int p = 0; p < pCount - 2; p++) {
        int iN  = pIdx[p];    // pivot[n]
        int iN1 = pIdx[p+1];  // pivot[n+1]
        int iN2 = pIdx[p+2];  // pivot[n+2]

        double p0 = zzBuf[iN];
        double p1 = zzBuf[iN1];
        double p2 = zzBuf[iN2];

        // ATR condition must be met between pivot[n] and pivot[n+1]
        double atr = FindD1ATR(bars[iN].time, d1Time, d1Atr, d1Cnt);
        if(atr <= 0.0) continue;
        if(MathAbs(p0 - p1) < g_atrMult * atr) continue;

        // Fibo retracement ratio: how far pivot[n] moved relative to [n+2]→[n+1] swing
        double base = MathAbs(p2 - p1);
        if(base < _Point) continue;
        double ratio = MathAbs(p0 - p1) / base;

        int fiboScore = 0;
        if(ratio >= 0.5)   fiboScore = 1;
        if(ratio >= 0.618) fiboScore = 2;
        if(ratio >= 1.0)   fiboScore += 1;
        if(ratio >= 1.618) fiboScore += 1;
        if(fiboScore == 0) continue;

        bool isHigh = (p0 > p1);
        if(g_showFilter == 1 && !isHigh) continue;
        if(g_showFilter == 2 &&  isHigh) continue;

        int    divScore = 0;
        string divTip   = "";
        if(iN < rsiDivCnt && iN2 < rsiDivCnt) {
            string kind;
            if(HasRSIDivergence(isHigh, p0, p2, rsiDivBuf[iN], rsiDivBuf[iN2], kind)) {
                divScore = 2;
                divTip = StringFormat(
                    "M%s %s/%s",
                    ShortDivKind(kind), CompactFloat(rsiDivBuf[iN]), CompactFloat(rsiDivBuf[iN2]));
            } else {
                string fastTip;
                if(FindFastZZDivergence(isHigh, iN, p0, bars[iN].time,
                                        fastZZBuf, fastIdx, bars, rsiDivBuf, rsiDivCnt, fastTip)) {
                    divScore = 1;
                    divTip   = fastTip;
                }
            }
        }

        int    exhScore = 0;
        string exhTip   = "";
        if(iN < rsiExhCnt) {
            double exhRsi = rsiExhBuf[iN];
            if(isHigh && exhRsi > 70.0) {
                exhScore = 1;
                exhTip = CompactFloat(exhRsi) + ">70";
            } else if(!isHigh && exhRsi < 30.0) {
                exhScore = 1;
                exhTip = CompactFloat(exhRsi) + "<30";
            }
        }

        string candleTip = "";
        int candleScore = ScoreCandlestickPatterns(isHigh, iN, bars, gotBars, candleTip);
        TrimCandleTip(candleTip);

        int totalScore = fiboScore + divScore + exhScore + candleScore;

        string fiboLvl;
        if(ratio >= 1.618)      fiboLvl = "161.8%";
        else if(ratio >= 1.0)   fiboLvl = "100%";
        else if(ratio >= 0.618) fiboLvl = "61.8%";
        else                    fiboLvl = "50%";
        string tip = MakeCompactTip(fiboLvl, fiboScore, divTip, divScore, exhTip, exhScore, candleTip, candleScore);

        string ts  = (string)bars[iN].time;
        string criteriaTxt = "[Z";
        if(divScore > 0) criteriaTxt += "D";
        if(exhScore > 0) criteriaTxt += "E";
        if(candleScore > 0) criteriaTxt += "C";
        criteriaTxt += "] ";

        datetime boxLeftTime = bars[iN].time + (datetime)PeriodSeconds(g_zzTF);
        int      yPad        = MathMax(10, InpScoreFontSize + 6);
        int      dxCriteria  = 4;
        int      dxScore     = dxCriteria + EstimateLabelPixelWidth(criteriaTxt);
        int      dy          = isHigh ? -yPad : yPad;

        double   fallbackOff = ScoreLabelFallbackOffset(atr);
        double   fallbackPx  = p0 + (isHigh ? fallbackOff : -fallbackOff);
        datetime criteriaTime = boxLeftTime;
        datetime scoreTime    = boxLeftTime;
        double   criteriaPrice = fallbackPx;
        double   scorePrice    = fallbackPx;
        ShiftChartPoint(boxLeftTime, p0, dxCriteria, dy, criteriaTime, criteriaPrice);
        ShiftChartPoint(boxLeftTime, p0, dxScore,    dy, scoreTime,    scorePrice);

        ENUM_ANCHOR_POINT anchor = isHigh ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;

        MakeScoreText(PFX_SCRC + ts, criteriaTime, criteriaPrice, criteriaTxt,                         InpCriteriaColor, anchor, tip);
        MakeScoreText(PFX_SCRV + ts, scoreTime,    scorePrice,    "(" + IntegerToString(totalScore) + ")", InpScoreColor,    anchor, tip);
    }
}

//+------------------------------------------------------------------+
void ScanAndDrawZZ() {
    if(!EnsureZZHandle())      return;
    if(!EnsureFastZZHandle())  return;
    if(!EnsureRSIHandles())    return;

    const int barCnt = InpLookback + 1;
    MqlRates  bars[];
    double    zzBuf[];
    double    fastZZBuf[];
    double    rsiDivBuf[];
    double    rsiExhBuf[];
    datetime  d1Time[];
    double    d1Atr[];
    ArraySetAsSeries(bars,   true);
    ArraySetAsSeries(zzBuf,  true);
    ArraySetAsSeries(fastZZBuf, true);
    ArraySetAsSeries(rsiDivBuf, true);
    ArraySetAsSeries(rsiExhBuf, true);
    ArraySetAsSeries(d1Time, true);
    ArraySetAsSeries(d1Atr,  true);

    int gotBars = CopyRates(_Symbol, g_zzTF, 0, barCnt, bars);
    if(gotBars < 2) return;
    if(CopyBuffer(g_zzHandle, 0, 0, barCnt, zzBuf) < 2) return;
    if(CopyBuffer(g_fastZZHandle, 0, 0, barCnt, fastZZBuf) < 2) return;
    if(CopyBuffer(g_rsiDivHandle, 0, 0, barCnt, rsiDivBuf) < 2) return;
    if(CopyBuffer(g_rsiExhHandle, 0, 0, barCnt, rsiExhBuf) < 2) return;
    if(CopyTime(_Symbol, PERIOD_D1, 0, 500, d1Time) < 1) return;
    if(CopyBuffer(g_atrHandle, 0, 0, 500, d1Atr)   < 1) return;

    // ZigZag repaints near the live end — always wipe and redraw all ZZ objects
    // so stale objects from retroactive pivot changes never accumulate.
    PurgeZZData();

    // All confirmed pivots (bars 1..gotBars-1)
    for(int i = gotBars - 1; i >= 1; i--) {
        if(zzBuf[i] == 0.0) continue;
        datetime t       = bars[i].time;
        int      prevIdx = FindPrevZZPivotIdx(zzBuf, i + 1, gotBars);
        if(prevIdx < 0) continue;

        // ZZ line: draw for every segment when Show ZigZag is ON
        if(g_showZZLines)
            MakeZZLine(PFX_ZZ_LINE + (string)t,
                       bars[prevIdx].time, zzBuf[prevIdx], t, zzBuf[i]);

        // Rect: only for qualifying swings
        double diff = MathAbs(zzBuf[i] - zzBuf[prevIdx]);
        double atr  = FindD1ATR(t, d1Time, d1Atr, ArraySize(d1Time));
        if(atr > 0.0 && diff >= g_atrMult * atr)
            DrawZZRect(t, zzBuf[i], zzBuf[prevIdx]);
    }

    // Live pivot at bar 0 — draw with same naming scheme; PurgeZZData already cleared slate
    if(zzBuf[0] != 0.0) {
        int prevIdx = FindPrevZZPivotIdx(zzBuf, 1, gotBars);
        if(prevIdx >= 0) {
            if(g_showZZLines)
                MakeZZLine(PFX_ZZ_LINE + (string)bars[0].time,
                           bars[prevIdx].time, zzBuf[prevIdx], bars[0].time, zzBuf[0]);
            double diff = MathAbs(zzBuf[0] - zzBuf[prevIdx]);
            double atr  = FindD1ATR(bars[0].time, d1Time, d1Atr, ArraySize(d1Time));
            if(atr > 0.0 && diff >= g_atrMult * atr)
                DrawZZRect(bars[0].time, zzBuf[0], zzBuf[prevIdx]);
        }
    }

    ScoreAndDrawZ(zzBuf, bars, gotBars,
                  fastZZBuf,
                  rsiDivBuf, ArraySize(rsiDivBuf),
                  rsiExhBuf, ArraySize(rsiExhBuf),
                  d1Time, d1Atr, ArraySize(d1Time));
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
int FindPrevZZPivotIdx(const double &buf[], int startIdx, int total) {
    for(int j = startIdx; j < total; j++)
        if(buf[j] != 0.0) return j;
    return -1;
}

bool EnsureZZHandle() {
    if(g_zzHandle != INVALID_HANDLE) return true;
    g_zzHandle = iCustom(_Symbol, g_zzTF, "Examples\\ZigZag",
                         g_zzDepth, g_zzDev, g_zzBack);
    if(g_zzHandle == INVALID_HANDLE)
        Alert("LiquidityMakerCandle: Cannot create ZigZag handle. Compile Examples\\ZigZag first.");
    return (g_zzHandle != INVALID_HANDLE);
}

bool EnsureFastZZHandle() {
    if(g_fastZZHandle != INVALID_HANDLE) return true;
    g_fastZZHandle = iCustom(_Symbol, g_zzTF, "Examples\\ZigZag", 5, 3, 3);
    if(g_fastZZHandle == INVALID_HANDLE)
        Alert("LiquidityMakerCandle: Cannot create fast ZigZag handle. Compile Examples\\ZigZag first.");
    return (g_fastZZHandle != INVALID_HANDLE);
}

bool EnsureRSIHandles() {
    if(g_rsiDivHandle == INVALID_HANDLE)
        g_rsiDivHandle = iRSI(_Symbol, g_zzTF, InpDivRSIPeriod, PRICE_CLOSE);
    if(g_rsiExhHandle == INVALID_HANDLE)
        g_rsiExhHandle = iRSI(_Symbol, g_zzTF, InpExhaustRSIPeriod, PRICE_CLOSE);

    if(g_rsiDivHandle == INVALID_HANDLE || g_rsiExhHandle == INVALID_HANDLE)
        Alert("LiquidityMakerCandle: Cannot create RSI handles.");
    return (g_rsiDivHandle != INVALID_HANDLE && g_rsiExhHandle != INVALID_HANDLE);
}

void ClearZZHandle() {
    if(g_zzHandle != INVALID_HANDLE) { IndicatorRelease(g_zzHandle); g_zzHandle = INVALID_HANDLE; }
    if(g_fastZZHandle != INVALID_HANDLE) { IndicatorRelease(g_fastZZHandle); g_fastZZHandle = INVALID_HANDLE; }
    if(g_rsiDivHandle != INVALID_HANDLE) { IndicatorRelease(g_rsiDivHandle); g_rsiDivHandle = INVALID_HANDLE; }
    if(g_rsiExhHandle != INVALID_HANDLE) { IndicatorRelease(g_rsiExhHandle); g_rsiExhHandle = INVALID_HANDLE; }
}

double FindD1ATR(datetime t, const datetime &d1t[], const double &d1a[], int cnt) {
    for(int i = 0; i < cnt; i++)
        if(d1t[i] <= t) return d1a[i];
    return 0.0;
}

//+------------------------------------------------------------------+
void DrawCandleRect(datetime t, double op, double cl, double hi, double lo) {
    bool  isBullish = cl > op;
    if(g_showFilter == 1 && !isBullish) return;
    if(g_showFilter == 2 &&  isBullish) return;
    color    borderClr = isBullish ? InpBullishRectColor : InpBearishRectColor;
    color    fillClr   = isBullish ? InpBullishFillColor : InpBearishFillColor;
    datetime tClose    = t + (datetime)PeriodSeconds(g_baseTF);
    datetime t2        = tClose + (datetime)(g_rectMins * 60);
    if(g_fillOn) {
        MakeRect(PFX_FILL_R  + (string)t, tClose, hi, t2, lo, fillClr, true, true);
    } else {
        MakeRect(PFX_OUTLINE + (string)t, tClose, hi, t2, lo, borderClr, false, true);
    }
}

//+------------------------------------------------------------------+
void DrawZZRect(datetime t, double pivot, double prevPivot) {
    bool  isBullish = pivot > prevPivot;
    if(g_showFilter == 1 && !isBullish) return;
    if(g_showFilter == 2 &&  isBullish) return;
    color    borderClr = isBullish ? InpBullishRectColor : InpBearishRectColor;
    color    fillClr   = isBullish ? InpBullishFillColor : InpBearishFillColor;
    double   hi        = MathMax(pivot, prevPivot);
    double   lo        = MathMin(pivot, prevPivot);
    datetime tStart    = t + (datetime)PeriodSeconds(g_zzTF);
    datetime tEnd      = tStart + (datetime)(g_rectMins * 60);
    if(g_fillOn) {
        MakeRect(PFX_ZZ_FILL + (string)t, tStart, hi, tEnd, lo, fillClr, true, true);
    } else {
        MakeRect(PFX_ZZ_OUTLINE + (string)t, tStart, hi, tEnd, lo, borderClr, false, true);
    }
}

//+------------------------------------------------------------------+
void MakeRect(const string name, datetime t1, double hi, datetime t2, double lo,
              color clr, bool filled, bool inBackground) {
    if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
        ObjectSetInteger(0, name, OBJPROP_FILL,       filled);
        ObjectSetInteger(0, name, OBJPROP_BACK,       inBackground);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
    }
}

void MakeZZLine(const string name, datetime t1, double p1, datetime t2, double p2) {
    if(ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR,      clrSilver);
        ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
        ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
        ObjectSetInteger(0, name, OBJPROP_BACK,       false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
    }
}

//=== PANEL =========================================================
void GetPanelOrigin(int &px, int &py) {
    int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    if(cw < PANEL_W + PANEL_MX * 2) cw = PANEL_W + PANEL_MX * 2;
    if(ch < PANEL_H + PANEL_MY * 2) ch = PANEL_H + PANEL_MY * 2;
    switch(InpPanelCorner) {
        case CORNER_RIGHT_UPPER: px = cw - PANEL_W - PANEL_MX; py = PANEL_MY;                 break;
        case CORNER_LEFT_LOWER:  px = PANEL_MX;                 py = ch - PANEL_H - PANEL_MY; break;
        case CORNER_RIGHT_LOWER: px = cw - PANEL_W - PANEL_MX; py = ch - PANEL_H - PANEL_MY; break;
        default:                 px = PANEL_MX;                 py = PANEL_MY;                 break;
    }
}

//+------------------------------------------------------------------+
void BuildPanel() {
    string curATR  = (ObjectFind(0, PN_EATR)   >= 0) ? ObjectGetString(0, PN_EATR,   OBJPROP_TEXT) : DoubleToString(g_atrMult, 2);
    string curMin  = (ObjectFind(0, PN_EMIN)   >= 0) ? ObjectGetString(0, PN_EMIN,   OBJPROP_TEXT) : IntegerToString(g_rectMins);
    string curDep  = (ObjectFind(0, PN_EZZDEP) >= 0) ? ObjectGetString(0, PN_EZZDEP, OBJPROP_TEXT) : IntegerToString(g_zzDepth);
    string curDev  = (ObjectFind(0, PN_EZZDEV) >= 0) ? ObjectGetString(0, PN_EZZDEV, OBJPROP_TEXT) : IntegerToString(g_zzDev);
    string curBack = (ObjectFind(0, PN_EZZBACK)>= 0) ? ObjectGetString(0, PN_EZZBACK,OBJPROP_TEXT) : IntegerToString(g_zzBack);
    PurgePanel();

    int px, py; GetPanelOrigin(px, py);
    int x = px, y = py;

    PnBG(PN_BG, x, y, PANEL_W, PANEL_H, C'28,28,28');
    PnLabel(PN_TITLE, x+8, y+7, "Liquidity Maker Candle", clrSilver, 8);
    PnBG(PN_DIV1, x, y+22, PANEL_W, 1, C'70,70,70');

    // --- Candle TF selector ---
    PnLabel(PN_LTF, x+8, y+28, "Candle TF:", clrSilver);
    int tw = (PANEL_W - 16 - 6) / 4;
    color cTF10 = (!g_useZigZag && g_baseTF == PERIOD_M10) ? C'20,100,210' : C'55,55,55';
    color cTF15 = (!g_useZigZag && g_baseTF == PERIOD_M15) ? C'20,100,210' : C'55,55,55';
    color cTF30 = (!g_useZigZag && g_baseTF == PERIOD_M30) ? C'20,100,210' : C'55,55,55';
    color cTFH1 = (!g_useZigZag && g_baseTF == PERIOD_H1 ) ? C'20,100,210' : C'55,55,55';
    PnButton(PN_BTF10, x+8,          y+42, tw,   21, "M10", cTF10);
    PnButton(PN_BTF15, x+8+tw+2,     y+42, tw,   21, "M15", cTF15);
    PnButton(PN_BTF30, x+8+(tw+2)*2, y+42, tw,   21, "M30", cTF30);
    PnButton(PN_BTFH1, x+8+(tw+2)*3, y+42, tw+2, 21, "H1",  cTFH1);
    PnBG(PN_DIVTF, x, y+68, PANEL_W, 1, C'70,70,70');

    // --- ZigZag mode toggle ---
    color  zzBg = g_useZigZag ? C'100,0,180' : C'55,55,55';
    string zzTx = g_useZigZag ? "ZigZag: ON" : "ZigZag: OFF";
    PnButton(PN_BZZMODE, x+8, y+74, PANEL_W-16, 21, zzTx, zzBg);

    // --- ZigZag TF row ---
    int ztw = (PANEL_W - 16 - 8) / 5;  // 5 buttons, 4 gaps of 2px
    ENUM_TIMEFRAMES chartTF = (ENUM_TIMEFRAMES)Period();
    color cZZC   = (g_useZigZag && g_zzTF == chartTF)    ? C'100,0,180' : C'55,55,55';
    color cZZM2  = (g_useZigZag && g_zzTF == PERIOD_M2)  ? C'100,0,180' : C'55,55,55';
    color cZZM5  = (g_useZigZag && g_zzTF == PERIOD_M5)  ? C'100,0,180' : C'55,55,55';
    color cZZM10 = (g_useZigZag && g_zzTF == PERIOD_M10) ? C'100,0,180' : C'55,55,55';
    color cZZM15 = (g_useZigZag && g_zzTF == PERIOD_M15) ? C'100,0,180' : C'55,55,55';
    PnButton(PN_BZZC,   x+8,            y+99, ztw,   21, "C",   cZZC);
    PnButton(PN_BZZM2,  x+8+ztw+2,      y+99, ztw,   21, "M2",  cZZM2);
    PnButton(PN_BZZM5,  x+8+(ztw+2)*2,  y+99, ztw,   21, "M5",  cZZM5);
    PnButton(PN_BZZM10, x+8+(ztw+2)*3,  y+99, ztw,   21, "M10", cZZM10);
    PnButton(PN_BZZM15, x+8+(ztw+2)*4,  y+99, PANEL_W-16-(ztw+2)*4, 21, "M15", cZZM15);
    PnBG(PN_DIVZZ, x, y+124, PANEL_W, 1, C'70,70,70');

    // --- ZigZag params compact row ---
    color zzClr = g_useZigZag ? clrSilver : C'80,80,80';
    int   zx    = x + 8;
    PnLabel(PN_LZZDEP,  zx,     y+134, "Dep:",  zzClr);
    PnEdit (PN_EZZDEP,  zx+26,  y+130, 34, 18,  curDep);
    PnLabel(PN_LZZDEV,  zx+64,  y+134, "Dev:",  zzClr);
    PnEdit (PN_EZZDEV,  zx+90,  y+130, 34, 18,  curDev);
    PnLabel(PN_LZZBACK, zx+128, y+134, "Bk:",   zzClr);
    PnEdit (PN_EZZBACK, zx+150, y+130, 34, 18,  curBack);
    PnBG(PN_DIVZZ2, x, y+152, PANEL_W, 1, C'70,70,70');

    // --- ATR / Minutes / Redraw ---
    PnLabel(PN_LATR, x+8,  y+162, "ATR Mult:", clrSilver);
    PnEdit (PN_EATR, x+90, y+158, 102, 18, curATR);
    PnLabel(PN_LMIN, x+8,  y+186, "Rect Min:", clrSilver);
    PnEdit (PN_EMIN, x+90, y+182, 102, 18, curMin);
    PnButton(PN_BDRAW, x+8, y+206, PANEL_W-16, 21, "Redraw", C'160,85,0');
    PnBG(PN_DIV2, x, y+232, PANEL_W, 1, C'70,70,70');

    // --- Fill toggle ---
    PnLabel(PN_LFILL, x+8, y+242, "Fill:", clrSilver);
    color  fillBg = g_fillOn ? C'0,130,0' : C'65,65,65';
    PnButton(PN_BFILL, x+90, y+237, 102, 21, g_fillOn ? "ON" : "OFF", fillBg);

    // --- Show ZigZag lines toggle ---
    PnLabel(PN_LSHOWZZ, x+8, y+268, "Show ZigZag:", clrSilver);
    color  zzLineBg = g_showZZLines ? C'0,130,0' : C'65,65,65';
    PnButton(PN_BSHOWZZ, x+90, y+263, 102, 21, g_showZZLines ? "ON" : "OFF", zzLineBg);
    PnBG(PN_DIV3, x, y+289, PANEL_W, 1, C'70,70,70');

    // --- Show filter ---
    PnLabel(PN_LSHOW, x+8, y+295, "Show:", clrSilver);
    int bw = (PANEL_W - 16 - 4) / 3;
    color cBoth = (g_showFilter == 0) ? C'20,100,210' : C'55,55,55';
    color cBull = (g_showFilter == 1) ? C'20,100,210' : C'55,55,55';
    color cBear = (g_showFilter == 2) ? C'20,100,210' : C'55,55,55';
    PnButton(PN_BBOTH, x+8,          y+311, bw,   21, "Both",  cBoth);
    PnButton(PN_BBULL, x+8+bw+2,     y+311, bw,   21, "Red",   cBull);
    PnButton(PN_BBEAR, x+8+(bw+2)*2, y+311, bw+2, 21, "Green", cBear);

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
void PnBG(const string nm, int x, int y, int w, int h, color bg) {
    ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, nm, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,   x);
    ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,   y);
    ObjectSetInteger(0, nm, OBJPROP_XSIZE,       w);
    ObjectSetInteger(0, nm, OBJPROP_YSIZE,       h);
    ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,     bg);
    ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, nm, OBJPROP_COLOR,       C'60,60,60');
    ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,  false);
    ObjectSetInteger(0, nm, OBJPROP_HIDDEN,      true);
    ObjectSetInteger(0, nm, OBJPROP_ZORDER,      0);
}

void PnLabel(const string nm, int x, int y, const string txt, color clr, int sz = 8) {
    ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y);
    ObjectSetString( 0, nm, OBJPROP_TEXT,       txt);
    ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   sz);
    ObjectSetString( 0, nm, OBJPROP_FONT,       "Arial");
    ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
    ObjectSetInteger(0, nm, OBJPROP_ZORDER,     1);
}

void PnEdit(const string nm, int x, int y, int w, int h, const string txt) {
    ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, nm, OBJPROP_XSIZE,      w);
    ObjectSetInteger(0, nm, OBJPROP_YSIZE,      h);
    ObjectSetString( 0, nm, OBJPROP_TEXT,       txt);
    ObjectSetInteger(0, nm, OBJPROP_COLOR,      C'20,20,20');
    ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    C'225,225,225');
    ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   8);
    ObjectSetString( 0, nm, OBJPROP_FONT,       "Arial");
    ObjectSetInteger(0, nm, OBJPROP_ALIGN,      ALIGN_LEFT);
    ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
    ObjectSetInteger(0, nm, OBJPROP_ZORDER,     2);
}

void PnButton(const string nm, int x, int y, int w, int h,
              const string txt, color bg, color textClr = clrWhite) {
    ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, nm, OBJPROP_XSIZE,      w);
    ObjectSetInteger(0, nm, OBJPROP_YSIZE,      h);
    ObjectSetString( 0, nm, OBJPROP_TEXT,       txt);
    ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    bg);
    ObjectSetInteger(0, nm, OBJPROP_COLOR,      textClr);
    ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   8);
    ObjectSetString( 0, nm, OBJPROP_FONT,       "Arial Bold");
    ObjectSetInteger(0, nm, OBJPROP_STATE,      false);
    ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
    ObjectSetInteger(0, nm, OBJPROP_ZORDER,     2);
}

//+------------------------------------------------------------------+
void PurgeData() {
    int n = ObjectsTotal(0, 0, -1);
    for(int i = n - 1; i >= 0; i--) {
        string nm = ObjectName(0, i, 0, -1);
        if(StringFind(nm, PFX_DATA) == 0 ||
           StringFind(nm, PFX_SCRC) == 0 ||
           StringFind(nm, PFX_SCRV) == 0)
            ObjectDelete(0, nm);
    }
}

// Deletes ZZ drawing objects and score labels. Called every tick in ZZ mode.
void PurgeZZData() {
    int n = ObjectsTotal(0, 0, -1);
    for(int i = n - 1; i >= 0; i--) {
        string nm = ObjectName(0, i, 0, -1);
        if(StringFind(nm, PFX_ZZ_DATA) == 0 ||
           StringFind(nm, PFX_SCRC)    == 0 ||
           StringFind(nm, PFX_SCRV)    == 0)
            ObjectDelete(0, nm);
    }
}

void PurgePanel() {
    int n = ObjectsTotal(0, 0, -1);
    for(int i = n - 1; i >= 0; i--) {
        string nm = ObjectName(0, i, 0, -1);
        if(StringFind(nm, PN_PFX) == 0)
            ObjectDelete(0, nm);
    }
}
//+------------------------------------------------------------------+
