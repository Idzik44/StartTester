#ifndef __PATTERN_DETECTOR_MQH__
#define __PATTERN_DETECTOR_MQH__

#property strict

#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>
#include <StartTester/BuySellFunction11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/PatternBacktest.mqh>
#include <StartTester/SmartOrderExecutor11.mqh>

// ─────────────────────────────────────────────────────────────
// USTAWIENIA WIZUALIZACJI 2× MA (rysujemy wyłącznie DWIE linie)
input int   PD_UniMA_LastBars = 400;        // ile ostatnich świec rysować
input color PD_UniMA_FastCol  = clrOrange;  // kolor szybkiej
input color PD_UniMA_SlowCol  = clrRed;     // kolor wolnej
input int   PD_UniMA_Width    = 2;          // grubość linii

// Metoda MA dla detektora i rysunku: MODE_SMA/MODE_EMA/MODE_SMMA/MODE_LWMA
#ifndef DET_MA_METHOD
  #define DET_MA_METHOD MODE_EMA
#endif

// Nazwy (prefiksy) naszych segmentów linii
#define PD_UNI_FAST "PD_UNI_MA_FAST"
#define PD_UNI_SLOW "PD_UNI_MA_SLOW"

// ─────────────────────────────────────────────────────────────
// CSV – tylko dla progów Z/ADX/DI (MA liczymy samodzielnie)
double __GetMultFromCsv(const string csv, int idx, double defVal=1.0)
{
   string parts[]; int n = StringSplit(csv, ',', parts);
   if(n<=0 || idx<0 || idx>=n) return defVal;
   string s = parts[idx]; StringTrimLeft(s); StringTrimRight(s);
   return (double)StringToDouble(s);
}

// ─────────────────────────────────────────────────────────────
// FILTR CZASU SESJI
void __GetSessionBounds(datetime t, int &startHour, int &endHour)
{
   switch(GetSession(t))
   {
      case SESSION_TOKYO:   startHour = 0;  endHour = 8;  break;
      case SESSION_LONDON:  startHour = 8;  endHour = 13; break;
      case SESSION_NEWYORK: startHour = 13; endHour = 22; break;
      default:              startHour = -1; endHour = -1; break;
   }
}

bool PassesSessionTimeFilter(int i)
{
   if (!UseSessionTimeFilter) return true;
   if (i < 1 || i >= ArraySize(candleHistory)) return false;

   datetime t = candleHistory[i].time;
   MqlDateTime dt; TimeToStruct(t, dt);

   int sh=-1, eh=-1;
   __GetSessionBounds(t, sh, eh);
   if (sh<0 || eh<0) return false;

   int minsFromStart = (dt.hour - sh) * 60 + dt.min;
   int minsToEnd     = (eh*60) - (dt.hour*60 + dt.min);
   int minsToDayEnd  = (24*60) - (dt.hour*60 + dt.min);

   enum TFReason { TF_NONE, TF_START, TF_ENDSESSION, TF_ENDDAY };
   TFReason reason = TF_NONE;

   if (minsFromStart < BlockFirstMinutesOfSession)      reason = TF_START;
   else if (minsToEnd <= BlockLastMinutesOfSession)     reason = TF_ENDSESSION;
   else if (minsToDayEnd <= BlockLastMinutesOfDay)      reason = TF_ENDDAY;

   if (reason == TF_NONE) return true;

   if (DebugTimeFilter) {
      if (!TimeFilterLogOnlyLiveBar || i == 1) {
         static datetime lastLogStart=0, lastLogEndSess=0, lastLogEndDay=0;
         bool shouldPrint = true;
         if (TimeFilterLogOncePerBar) {
            if (reason==TF_START)           { if(lastLogStart==t)   shouldPrint=false; lastLogStart=t; }
            else if (reason==TF_ENDSESSION) { if(lastLogEndSess==t) shouldPrint=false; lastLogEndSess=t; }
            else                            { if(lastLogEndDay==t)  shouldPrint=false; lastLogEndDay=t; }
         }
         if (shouldPrint) {
            if (reason==TF_START)
               PrintFormat("[TIME-FILTER] START sesji: %d < %d min -> blokada", minsFromStart, BlockFirstMinutesOfSession);
            else if (reason==TF_ENDSESSION)
               PrintFormat("[TIME-FILTER] KONIEC sesji za %d min <= %d -> blokada", minsToEnd, BlockLastMinutesOfSession);
            else
               PrintFormat("[TIME-FILTER] KONIEC DNIA za %d min <= %d -> blokada", minsToDayEnd, BlockLastMinutesOfDay);
         }
      }
   }
   return false;
}

// ─────────────────────────────────────────────────────────────
// MA – liczenie wartości BEZ iMA (na bazie candleHistory[])

bool __PD_HasWindow(const int shift, const int period)
{
   const int total = ArraySize(candleHistory);
   if (shift < 1 || period <= 0) return false;
   return (shift + period - 1 < total);
}

double __PD_SMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   double s = 0.0;
   for (int k = shift; k < shift + period; ++k)
      s += candleHistory[k].close;
   return s / period;
}

double __PD_EMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   const double alpha = 2.0 / (period + 1.0);
   double ema = __PD_SMA_Close(shift, period);                 // seed
   for (int k = shift + period - 2; k >= shift; --k)           // starsze -> nowsze
      ema = alpha * candleHistory[k].close + (1.0 - alpha) * ema;
   return ema;
}

double __PD_SMMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   double smma = __PD_SMA_Close(shift, period);
   for (int k = shift + period - 2; k >= shift; --k)
      smma = (smma * (period - 1) + candleHistory[k].close) / period;
   return smma;
}

double __PD_LWMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   const int denom = period * (period + 1) / 2;
   double num = 0.0;
   for (int j = 0; j < period; ++j) {
      const int w = period - j; // większa waga bliżej „teraz”
      num += w * candleHistory[shift + j].close;
   }
   return num / denom;
}

// PUBLIC: zachowujemy nazwę używaną w reszcie projektu
double __MA_Close_PeriodAtShift(int period, int shift, ENUM_MA_METHOD method=(ENUM_MA_METHOD)DET_MA_METHOD)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   switch (method)
   {
      case MODE_SMA:  return __PD_SMA_Close(shift, period);
      case MODE_EMA:  return __PD_EMA_Close(shift, period);
      case MODE_SMMA: return __PD_SMMA_Close(shift, period);
      case MODE_LWMA: return __PD_LWMA_Close(shift, period);
      default:        return __PD_EMA_Close(shift, period);
   }
}

// ─────────────────────────────────────────────────────────────
// MA filtr (per-regime) na CLOSE  — bez wywołania PassesMaCloseFilter(...)
bool PassesMaCloseFilter_PerRegime(int i, bool isBuy)
{
   // jeśli UsePerRegimeMA==false, użyj reżimu 0 (stałych okresów)
   int reg = UsePerRegimeMA ? DetectRegimeKey(i) : 0;
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

   int fastP = ActiveMA_Fast_PerRegime[reg];
   int slowP = ActiveMA_Slow_PerRegime[reg];
   if (fastP <= 0)          fastP = 20;
   if (slowP <= fastP)      slowP = fastP + 1;

   const int total = ArraySize(candleHistory);
   if (i < 1 || i >= total) return false;

   const double maF = __MA_Close_PeriodAtShift(fastP, i);
   const double maS = __MA_Close_PeriodAtShift(slowP, i);
   const double c   = candleHistory[i].close;

   bool condBuy, condSell;
   if (DET_MA_Soft)
   {
      const double tol = MathMax(0.0, DET_MA_Soft_Tolerance);
      condBuy  = (c > maS) && (maF >= maS * (1.0 - tol));
      condSell = (c < maS) && (maF <= maS * (1.0 + tol));
   }
   else
   {
      condBuy  = (c > MathMax(maF, maS)) && (maF >= maS);
      condSell = (c < MathMin(maF, maS)) && (maF <= maS);
   }
   return (isBuy ? condBuy : condSell);
}


// ─────────────────────────────────────────────────────────────
// DIAGNOSTYKA reżimu
static datetime __REG_lastLogBar = 0;

void Regime_LogBar(int i)
{
   if(!DebugRegime) return;
   if(i < 1 || i >= ArraySize(candleHistory)) return;

   datetime t = candleHistory[i].time;
   if(DebugRegime_OnceBar && t == __REG_lastLogBar) return;
   __REG_lastLogBar = t;

   int reg = DetectRegimeKey(i);
   double zr = MathAbs(GetStandardizedRange(i));
   double zv = MathAbs(GetStandardizedVolume(i));

   PrintFormat("[REG] t=%s reg=%d | |Zr|=%.2f | |Zv|=%.2f",
               TimeToString(t, TIME_DATE|TIME_MINUTES), reg, zr, zv);
}

// Podsumowanie reżimów
void Regime_Summary(int bars=300)
{
   int total = ArraySize(candleHistory);
   if (total < 2) { Print("[REG] Brak danych."); return; }
   int from = MathMax(2, total - MathMax(20, bars));
   int upto = total - 2;

   int cnt[NUM_REGIMES];       ArrayInitialize(cnt, 0);
   double sumZr[NUM_REGIMES];  ArrayInitialize(sumZr, 0.0);
   double sumZv[NUM_REGIMES];  ArrayInitialize(sumZv, 0.0);

   for (int i = upto; i >= from; --i) {
      int r = DetectRegimeKey(i);
      if (r < 0 || r >= NUM_REGIMES) continue;
      cnt[r]++;
      sumZr[r] += MathAbs(GetStandardizedRange(i));
      sumZv[r] += MathAbs(GetStandardizedVolume(i));
   }

   PrintFormat("[REG] Summary last %d bars:", (upto - from + 1));
   for (int r=0; r<NUM_REGIMES; ++r) {
      double avgZr = (cnt[r] ? sumZr[r]/cnt[r] : 0.0);
      double avgZv = (cnt[r] ? sumZv[r]/cnt[r] : 0.0);
      PrintFormat("   - reg=%d | n=%d | avg|Zr|=%.2f | avg|Zv|=%.2f", r, cnt[r], avgZr, avgZv);
   }
}

// ─────────────────────────────────────────────────────────────
// AKTYWNE OKRESY MA dla reżimu
void __GetActiveMAPeriods(int reg, int &fastP, int &slowP)
{
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;
   fastP = ActiveMA_Fast_PerRegime[reg];
   slowP = ActiveMA_Slow_PerRegime[reg];
   if (fastP <= 0) fastP = 20;
   if (slowP <= fastP) slowP = fastP + 1;
}

// Histereza MA: wymagane 2 zamknięcia po tej samej stronie obu MA
bool __ComputeMASideTwoClose(int i, int fastP, int slowP, bool &isAbove2, bool &isBelow2)
{
   const int total = ArraySize(candleHistory);
   isAbove2 = false; isBelow2 = false;

   if (i < 1 || i+1 >= total) return false;

   double c0 = candleHistory[i].close;
   double c1 = candleHistory[i+1].close;

   double maF0 = __MA_Close_PeriodAtShift(fastP, i);
   double maS0 = __MA_Close_PeriodAtShift(slowP, i);
   double maF1 = __MA_Close_PeriodAtShift(fastP, i+1);
   double maS1 = __MA_Close_PeriodAtShift(slowP, i+1);

   bool above0 = (c0 > MathMax(maF0, maS0));
   bool below0 = (c0 < MathMin(maF0, maS0));
   bool above1 = (c1 > MathMax(maF1, maS1));
   bool below1 = (c1 < MathMin(maF1, maS1));

   isAbove2 = (above0 && above1);
   isBelow2 = (below0 && below1);
   return (isAbove2 || isBelow2);
}

// ─────────────────────────────────────────────────────────────
// RYSOWANIE DWÓCH LINII MA – segmentami OBJ_TREND (bez iMA)
void PD_DrawUnifiedRegimeMA(int lastBars)
{
   if(lastBars<=0) lastBars = 400;

   const int total = ArraySize(candleHistory);
   if (total < 5) return;

   // (jeśli kiedyś były POLYLINE) – usuń je, żeby nie zaśmiecały
   if (ObjectFind(0, PD_UNI_FAST) >= 0) ObjectDelete(0, PD_UNI_FAST);
   if (ObjectFind(0, PD_UNI_SLOW) >= 0) ObjectDelete(0, PD_UNI_SLOW);

   datetime tF[]; double vF[]; ArrayResize(tF,0); ArrayResize(vF,0);
   datetime tS[]; double vS[]; ArrayResize(tS,0); ArrayResize(vS,0);

   const int upto = total - 2;                 // ostatnia zamknięta świeca
   const int maxN = MathMin(lastBars, upto);   // ile świec rysujemy

   // zapełniamy bufory od najstarszych do nowszych (rosnący czas)
   for (int i = maxN; i >= 1; --i)
   {
      int reg = DetectRegimeKey(i); if (reg < 0 || reg >= NUM_REGIMES) reg = 0;
      int fP, sP; __GetActiveMAPeriods(reg, fP, sP);

      if (i + sP - 1 >= total) continue; // brak historii pod wolną MA

      const double fastV = __MA_Close_PeriodAtShift(fP, i);
      const double slowV = __MA_Close_PeriodAtShift(sP, i);
      if (fastV == 0.0 || slowV == 0.0) continue;

      const datetime tt = candleHistory[i].time;

      int nf = ArraySize(tF); ArrayResize(tF, nf+1); ArrayResize(vF, nf+1);
      tF[nf] = tt; vF[nf] = fastV;

      int ns = ArraySize(tS); ArrayResize(tS, ns+1); ArrayResize(vS, ns+1);
      tS[ns] = tt; vS[ns] = slowV;
   }

   // FAST – segmenty
   const int nF = ArraySize(tF);
   for (int k = 0; k < nF-1; ++k)
   {
      const string name = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_FAST, k, _Symbol, (int)_Period);
      if (ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TREND, 0, tF[k], vF[k], tF[k+1], vF[k+1]);
      else {
         ObjectMove(0, name, 0, tF[k],   vF[k]);
         ObjectMove(0, name, 1, tF[k+1], vF[k+1]);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR,      (long)PD_UniMA_FastCol);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      (long)PD_UniMA_Width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   // posprzątaj nadmiarowe segmenty FAST
   for (int k = MathMax(0, nF-1); ; ++k)
   {
      const string nm = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_FAST, k, _Symbol, (int)_Period);
      if (ObjectFind(0, nm) < 0) break;
      ObjectDelete(0, nm);
   }

   // SLOW – segmenty
   const int nS = ArraySize(tS);
   for (int k = 0; k < nS-1; ++k)
   {
      const string name = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_SLOW, k, _Symbol, (int)_Period);
      if (ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TREND, 0, tS[k], vS[k], tS[k+1], vS[k+1]);
      else {
         ObjectMove(0, name, 0, tS[k],   vS[k]);
         ObjectMove(0, name, 1, tS[k+1], vS[k+1]);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR,      (long)PD_UniMA_SlowCol);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      (long)PD_UniMA_Width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   // posprzątaj nadmiarowe segmenty SLOW
   for (int k = MathMax(0, nS-1); ; ++k)
   {
      const string nm = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_SLOW, k, _Symbol, (int)_Period);
      if (ObjectFind(0, nm) < 0) break;
      ObjectDelete(0, nm);
   }
}

// ─────────────────────────────────────────────────────────────
// CHECK – sygnał impulsu + kierunek
bool CheckImpulseConditions(int i, bool &isBuy)
{
   if (i + 1 >= ArraySize(candleHistory)) return false;

   double avgRange  = GetCurrentSessionAverageRange();
   double avgVolume = GetCurrentSessionAverageVolume();
   if (avgRange <= 0.0 || avgVolume <= 0.0) return false;

   if (!PassesSessionTimeFilter(i)) return false;

   int reg = DetectRegimeKey(i);
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

   double zr  = MathAbs(GetStandardizedRange(i));
   double zv  = MathAbs(GetStandardizedVolume(i));
   double thrZR = IMP_ZR_MIN_PD * DET_ZR_Mult_PD * __GetMultFromCsv(DET_ZR_Mults_PD, reg, 1.0);
   double thrZV = IMP_ZV_MIN_PD * DET_ZV_Mult_PD * __GetMultFromCsv(DET_ZV_Mults_PD, reg, 1.0);
   if (zr < thrZR || zv < thrZV) return false;

   double adx = GetCustomADXAt(i);
   double pdi = GetCustomPlusDIAt(i);
   double mdi = GetCustomMinusDIAt(i);
   if (adx < 0 || pdi < 0 || mdi < 0) {
      ComputeCustomADX(14);
      adx = GetCustomADXAt(i);
      pdi = GetCustomPlusDIAt(i);
      mdi = GetCustomMinusDIAt(i);
   }

   double thrADX = (double)impulseAdxThreshold * __GetMultFromCsv(DET_ADX_Mults_PD, reg, 1.0);
   double thrDI  = (double)impulseMinDiffDI    * __GetMultFromCsv(DET_DI_Mults_PD,  reg, 1.0);

   if (adx < thrADX) return false;
   double diff = MathAbs(pdi - mdi);
   if (diff < thrDI) return false;

   // Kierunek: MA + 2 zamknięcia po tej samej stronie
   int fastP, slowP; __GetActiveMAPeriods(reg, fastP, slowP);
   bool sideAbove2=false, sideBelow2=false;
   if (!__ComputeMASideTwoClose(i, fastP, slowP, sideAbove2, sideBelow2)) return false;

   isBuy = sideAbove2; // 2xAbove => BUY, 2xBelow => SELL
   return true;
}

// ─────────────────────────────────────────────────────────────
// STRZAŁKI
void DrawTradeArrowByIndex(int index, string prefix, bool isBuy, color clrOverride=-1)
{
   if (index < 0 || index >= ArraySize(candleHistory)) return;

   const MqlRates c = candleHistory[index];
   const double rng = MathMax(c.high - c.low, 1.0 * _Point);
   const double pad = MathMax(3.0 * _Point, 0.15 * rng);

   const int    arrowCode = isBuy ? 233 : 234;
   const double y         = isBuy ? (c.low  - pad) : (c.high + pad);
   const color  clr       = (clrOverride >= 0) ? clrOverride : (isBuy ? clrLime : clrRed);

   const string label = prefix + "_" + TimeToString(c.time, TIME_DATE | TIME_MINUTES);
   if (ObjectFind(0, label) >= 0) return;

   ObjectCreate(0, label, OBJ_ARROW, 0, c.time, y);
   ObjectSetInteger(0, label, OBJPROP_COLOR,      (long)clr);
   ObjectSetInteger(0, label, OBJPROP_ARROWCODE,  arrowCode);
   ObjectSetInteger(0, label, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, label, OBJPROP_SELECTABLE, false);
}

void DrawTradeArrow(datetime t, string prefix, bool isBuy, color clrOverride=-1)
{
   int i = FindIndexByTime(t);
   if (i < 0 || i >= ArraySize(candleHistory)) return;
   DrawTradeArrowByIndex(i, prefix, isBuy, clrOverride);
}

void DrawArrow(datetime t, string prefix, color clr) // legacy
{
   bool isBuy = (clr == clrLime || clr == clrGreen);
   DrawTradeArrow(t, prefix, isBuy, clr);
}

void DrawSignalArrow(datetime t, string prefix, bool isBuySignal, color clrOverride=-1)
{
   DrawTradeArrow(t, prefix, isBuySignal, clrOverride);
}

// ─────────────────────────────────────────────────────────────
// LIVE
void DetectLivePatternAndDraw()
{
   if (ArraySize(candleHistory) < 2) return;

   static datetime lastProcessedBarTime = 0;
   static datetime lastSigBuyTime  = 0;
   static datetime lastSigSellTime = 0;

   const int i = 1;
   datetime  t1 = candleHistory[i].time;
   if (t1 == lastProcessedBarTime) return;
   lastProcessedBarTime = t1;

   // odśwież 2×MA (ciągła linia z okresami per-bar/per-regime)
   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);

   bool isBuy=false;

   int reg = DetectRegimeKey(i);
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

   double zr  = MathAbs(GetStandardizedRange(i));
   double zv  = MathAbs(GetStandardizedVolume(i));
   double thrZR = IMP_ZR_MIN_PD * DET_ZR_Mult_PD * __GetMultFromCsv(DET_ZR_Mults_PD, reg, 1.0);
   double thrZV = IMP_ZV_MIN_PD * DET_ZV_Mult_PD * __GetMultFromCsv(DET_ZV_Mults_PD, reg, 1.0);

   double adx = GetCustomADXAt(i);
   double pdi = GetCustomPlusDIAt(i);
   double mdi = GetCustomMinusDIAt(i);
   if (adx < 0 || pdi < 0 || mdi < 0) {
      ComputeCustomADX(14);
      adx = GetCustomADXAt(i);
      pdi = GetCustomPlusDIAt(i);
      mdi = GetCustomMinusDIAt(i);
   }
   double diff = MathAbs(pdi - mdi);

   double thrADX = (double)impulseAdxThreshold * __GetMultFromCsv(DET_ADX_Mults_PD, reg, 1.0);
   double thrDI  = (double)impulseMinDiffDI    * __GetMultFromCsv(DET_DI_Mults_PD,  reg, 1.0);

   if (!CheckImpulseConditions(i, isBuy)) {
      impulseCandlesSinceLastDetection++;
      return;
   }

   // safety – kierunek zgodny z MA (powinien już być)
   {
      int f2, s2; __GetActiveMAPeriods(reg, f2, s2);
      bool ab2=false, bl2=false;
      if (!__ComputeMASideTwoClose(i, f2, s2, ab2, bl2)) return;
      if ((ab2 && !isBuy) || (bl2 && isBuy)) return;
   }

   if (inputOneSignalPerBarPerDirection) {
      if ((isBuy  && lastSigBuyTime  == t1) ||
          (!isBuy && lastSigSellTime == t1)) return;
   }

   DrawTradeArrow(t1, "Live_Imp", isBuy);

   double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
   double adj      = isBuy ? (breakout + inputExecuteMarginPoints * _Point)
                           : (breakout - inputExecuteMarginPoints * _Point);

   int    stops   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freeze  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double market  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double req     = (stops + 2) * _Point;
   if ((isBuy  && (adj - market) < req) ||
       (!isBuy && (market - adj) < req)) {
      adj = isBuy ? (market + req) : (market - req);
   }

   ExecuteImpulseTrade(isBuy, adj, t1, inputUseSLMethod, inputMagicNumber);

   if (isBuy) lastSigBuyTime = t1; else lastSigSellTime = t1;
   impulseCandlesSinceLastDetection = 0;
}

// ─────────────────────────────────────────────────────────────
// HISTORIA
void DetectHistoricalImpulsesWithProfitCheck()
{
   if (ArraySize(candleHistory) < 50) return;

   for (int i = ArraySize(candleHistory) - 2; i >= 10; --i)
   {
      bool isBuy = false;
      bool passed = CheckImpulseConditions(i, isBuy);
      if (!passed) continue;

      double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
      double margin   = inputExecuteMarginPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double adjusted = isBuy ? (breakout + margin) : (breakout - margin);

      double sl = 0.0, tp = 0.0;
      CalculateSLAndTP(sl, tp, inputUseSLMethod, adjusted, isBuy,
                       inputSLMultiplier, inputSLPoints, inputTPMultiplier);

      if (sl == 0.0 || tp == 0.0)
      {
         double range = candleHistory[i].high - candleHistory[i].low;
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double base  = MathMax(inputSLPoints * point, inputSLMultiplier * range);
         if (base <= 0) base = 10 * point;

         if (isBuy) { sl = adjusted - base; tp = adjusted + base * inputTPMultiplier; }
         else       { sl = adjusted + base; tp = adjusted - base * inputTPMultiplier; }
      }

      double points = 0.0;
      bool activated = SimulatePendingAndTradePoints(i, isBuy, adjusted, sl, tp, points, inputPendingExpiryBars);

      if (activated && points > 0.0)
         DrawTradeArrow(candleHistory[i].time, "Hist_Imp_Profit", isBuy);
   }

   // odśwież 2×MA po batchu
   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);
}

// ─────────────────────────────────────────────────────────────
// TEST HARNESS – wywołuj raz na zamkniętą świecę
void TestHarness_OnClosedBar()
{
   // lekkie odświeżenie MA zawsze na nowy bar
   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);

   if(Test_Mode == TEST_SESSION_ONLY)
   {
      if(DebugSessionAnalyzer) SessionAnalyzer_DumpSnapshot();
      return;
   }

   if(Test_Mode == TEST_REGIME_ONLY)
   {
      Regime_LogBar(1);
      return;
   }

   if(Test_Mode == TEST_ENTRY_NO_EXIT || Test_Mode == TEST_FILTER_TUNE || Test_Mode == TEST_FULL)
   {
      if(Enable_Detector_Live)
         DetectLivePatternAndDraw();
      return;
   }
}

// ─────────────────────────────────────────────────────────────
// AUDYT
void Detector_StageAuditEx(const int lookbackBars, const bool perRegime)
{
   const int total = ArraySize(candleHistory);
   if (total < 20) { PrintFormat("[DET-AUD] Za mało świec (total=%d).", total); return; }

   const int upto = total - 2;
   const int from = MathMax(10, total - MathMax(50, lookbackBars));
   if (from >= upto) { PrintFormat("[DET-AUD] Zbyt małe okno (from=%d, upto=%d).", from, upto); return; }

   if (GetCustomADXAt(upto) < 0) ComputeCustomADX(14);

   int seen=0, timeOK=0, zOK=0, adxOK=0, maOK=0, passOK=0;

   int seenR[NUM_REGIMES];  ArrayInitialize(seenR,  0);
   int timeR[NUM_REGIMES];  ArrayInitialize(timeR,  0);
   int zR[NUM_REGIMES];     ArrayInitialize(zR,     0);
   int adxR[NUM_REGIMES];   ArrayInitialize(adxR,   0);
   int maR[NUM_REGIMES];    ArrayInitialize(maR,    0);
   int passR[NUM_REGIMES];  ArrayInitialize(passR,  0);

   for (int i = upto; i >= from; --i)
   {
      int reg = DetectRegimeKey(i); if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

      seen++; if (perRegime) seenR[reg]++;

      bool time_ok = PassesSessionTimeFilter(i);
      if (time_ok) { timeOK++; if (perRegime) timeR[reg]++; } else { continue; }

      double zr = MathAbs(GetStandardizedRange(i));
      double zv = MathAbs(GetStandardizedVolume(i));
      double thrZR = IMP_ZR_MIN_PD * DET_ZR_Mult_PD * __GetMultFromCsv(DET_ZR_Mults_PD, reg, 1.0);
      double thrZV = IMP_ZV_MIN_PD * DET_ZV_Mult_PD * __GetMultFromCsv(DET_ZV_Mults_PD, reg, 1.0);
      bool z_ok = (zr >= thrZR && zv >= thrZV);
      if (z_ok) { zOK++; if (perRegime) zR[reg]++; } else { continue; }

      double adx = GetCustomADXAt(i);
      double pdi = GetCustomPlusDIAt(i);
      double mdi = GetCustomMinusDIAt(i);
      if (adx < 0 || pdi < 0 || mdi < 0) { ComputeCustomADX(14); adx = GetCustomADXAt(i); pdi = GetCustomPlusDIAt(i); mdi = GetCustomMinusDIAt(i); }
      double diff = MathAbs(pdi - mdi);

      double thrADX = (double)impulseAdxThreshold * __GetMultFromCsv(DET_ADX_Mults_PD, reg, 1.0);
      double thrDI  = (double)impulseMinDiffDI    * __GetMultFromCsv(DET_DI_Mults_PD,  reg, 1.0);
      bool adx_ok   = (adx >= thrADX && diff >= thrDI);
      if (adx_ok) { adxOK++; if (perRegime) adxR[reg]++; } else { continue; }

      bool dir = (pdi >= mdi);
      bool ma_ok = PassesMaCloseFilter_PerRegime(i, dir);
      if (ma_ok) { maOK++; if (perRegime) maR[reg]++; } else { continue; }

      bool isBuy2=false;
      if (CheckImpulseConditions(i, isBuy2)) {
         passOK++; if (perRegime) passR[reg]++;
      }
   }

   const int effN = (upto - from + 1);
   const double d = (seen>0) ? seen : 1.0;

   PrintFormat("[DET-AUD] Window last %d bars (eff=%d). Stages: seen=%d | time=%d (%.0f%%) | Z=%d (%.0f%%) | ADX/DI=%d (%.0f%%) | MA=%d (%.0f%%) | PASS=%d (%.0f%%)",
               lookbackBars, effN, seen,
               timeOK, 100.0*timeOK/d,
               zOK,    100.0*zOK/d,
               adxOK,  100.0*adxOK/d,
               maOK,   100.0*maOK/d,
               passOK, 100.0*passOK/d);

   if (perRegime)
   {
      Print("[DET-AUD] Per-regime:");
      for (int r=0; r<NUM_REGIMES; ++r)
      {
         double dr = (seenR[r]>0 ? seenR[r] : 1.0);
         PrintFormat("   - reg=%d | seen=%d | time=%d (%.0f%%) | Z=%d (%.0f%%) | ADX/DI=%d (%.0f%%) | MA=%d (%.0f%%) | PASS=%d (%.0f%%)",
                     r, seenR[r],
                     timeR[r], 100.0*timeR[r]/dr,
                     zR[r],    100.0*zR[r]/dr,
                     adxR[r],  100.0*adxR[r]/dr,
                     maR[r],   100.0*maR[r]/dr,
                     passR[r], 100.0*passR[r]/dr);
      }
   }
}

void Detector_StageAudit(const int lookbackBars)           { Detector_StageAuditEx(lookbackBars, false); }
void Detector_StageAudit_PerRegime(const int lookbackBars) { Detector_StageAuditEx(lookbackBars, true ); }

// ─────────────────────────────────────────────────────────────
// GRID-SEARCH: fast/slow MA per-regime (bez iMA)
// ─────────────────────────────────────────────────────────────

// Ustawienia (możesz zrobić z tego inputy, jeśli chcesz)
input bool   MA_Opt_Enable     = false;   // włącz optymalizację w OnInit
input int    MA_Opt_ScanBars   = 300;     // ile ostatnich świec skanować
input int    MA_Opt_MinSignals = 8;       // minimalna liczba sygnałów w danym reżimie

// Kandydaci (celowo konserwatywny zakres)
static int __MA_FastSet[] = {8,10,12,14,18,20,24,26};
static int __MA_SlowSet[] = {26,30,34,40,50,60,80};

// Lekki evaluator — podobny do tego z ExitOptimizer (net + PF/WR - DD)
double __MAEvalScore(const double &profits[], double &profitFactor, double &maxDrawdown, double &winrate)
{
   int n = ArraySize(profits);
   if(n==0){ profitFactor=0; maxDrawdown=0; winrate=0; return -1e9; }

   double equity=0.0, peak=0.0, dd=0.0; maxDrawdown=0.0;
   double profitSum=0.0, lossSum=0.0; int wins=0, losses=0;

   for(int i=0;i<n;i++)
   {
      double p = profits[i];
      equity += p;
      if(equity > peak) peak = equity;
      dd = peak - equity;
      if(dd > maxDrawdown) maxDrawdown = dd;

      if(p > 0){ profitSum += p; wins++; }
      else if(p < 0){ lossSum += -p; losses++; }
   }
   winrate = (wins+losses>0 ? (double)wins/(wins+losses) : 0.0);
   profitFactor = (lossSum>0 ? profitSum/lossSum : (wins>0 ? 10.0 : 0.0));

   double net   = equity;
   double pfCap = MathMin(profitFactor, 3.0);   // limit wpływu pojedynczych outlierów
   double score = net
                + 100.0*(pfCap - 1.0)
                + 200.0*(winrate - 0.5)
                - 0.5*maxDrawdown;

   if(n < 8)       score -= 200.0;
   else if(n < 15) score -= 60.0;
   return score;
}

// rdzeń: optymalizacja dwóch okresów MA dla jednego reżimu
bool OptimizeMAPeriodsForRegime(const int targetRegime,
                                const int scanBars,
                                const int &fastSet[], const int &slowSet[],
                                int &bestFast, int &bestSlow, double &bestScore)
{
   bestScore = -1e100; bestFast=0; bestSlow=0;

   // snapshot aktualnych tablic (przywrócimy po zakończeniu)
   int fastBak[NUM_REGIMES], slowBak[NUM_REGIMES];
   ArrayCopy(fastBak, ActiveMA_Fast_PerRegime);
   ArrayCopy(slowBak, ActiveMA_Slow_PerRegime);

   const int total = ArraySize(candleHistory);
   if (total < 50) return false;
   const int start = MathMax(10, total - MathMax(50, scanBars));

   for (int fi=0; fi<ArraySize(fastSet); ++fi)
   for (int si=0; si<ArraySize(slowSet); ++si)
   {
      const int f = fastSet[fi];
      const int s = slowSet[si];
      if (s <= f) continue;

      ActiveMA_Fast_PerRegime[targetRegime] = f;
      ActiveMA_Slow_PerRegime[targetRegime] = s;

      double results[]; ArrayResize(results, 0);

      for (int i = total-2; i >= start; --i)
      {
         if (DetectRegimeKey(i) != targetRegime) continue;
         if (!PassesSessionTimeFilter(i))        continue;

         // wymagane okno pod wolną MA
         if (i + s - 1 >= total) continue;

         bool isBuy=false;
         if (!CheckImpulseConditions(i, isBuy))  continue;

         // wejście jak w LIVE/HIST
         const double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         const double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
         double adjusted       = isBuy ? (breakout + inputExecuteMarginPoints*point)
                                       : (breakout - inputExecuteMarginPoints*point);

         double sl=0.0, tp=0.0;
         CalculateSLAndTP(sl, tp, inputUseSLMethod, adjusted, isBuy,
                          inputSLMultiplier, inputSLPoints, inputTPMultiplier);

         if (sl==0.0 || tp==0.0) {
            double range = candleHistory[i].high - candleHistory[i].low;
            double base  = MathMax(inputSLPoints*point, inputSLMultiplier*range);
            if (base <= 0) base = 10*point;
            if (isBuy){ sl = adjusted - base; tp = adjusted + base*inputTPMultiplier; }
            else      { sl = adjusted + base; tp = adjusted - base*inputTPMultiplier; }
         }

         double pts=0.0;
         bool ok = SimulatePendingAndTradePoints(i, isBuy, adjusted, sl, tp, pts, inputPendingExpiryBars);
         if (ok) { int n=ArraySize(results); ArrayResize(results, n+1); results[n]=pts; }
      }

      if (ArraySize(results) < MA_Opt_MinSignals) continue;

      double pf, dd, wr;
      double score = __MAEvalScore(results, pf, dd, wr);

      PrintFormat("[MA-OPT][reg=%d] fast=%d slow=%d | n=%d score=%.1f PF=%.2f DD=%.1f WR=%.0f%%",
                  targetRegime, f, s, ArraySize(results), score, pf, dd, wr*100.0);

      if (score > bestScore) { bestScore=score; bestFast=f; bestSlow=s; }
   }

   // restore
   ArrayCopy(ActiveMA_Fast_PerRegime, fastBak);
   ArrayCopy(ActiveMA_Slow_PerRegime, slowBak);

   return (bestScore > -1e90);
}

// pętla po 9 reżimach — zapisuje wygrane do ActiveMA_*_PerRegime
void OptimizeMAPeriodsAllRegimes(int scanBars)
{
   int bestF, bestS; double bestSc;

   for (int reg=0; reg<NUM_REGIMES; ++reg)
   {
      bool ok = OptimizeMAPeriodsForRegime(reg, scanBars, __MA_FastSet, __MA_SlowSet, bestF, bestS, bestSc);
      if (!ok) {
         PrintFormat("❌ [MA-OPT] regime=%d — brak wyniku (za mała próbka?)", reg);
         continue;
      }

      ActiveMA_Fast_PerRegime[reg] = bestF;
      ActiveMA_Slow_PerRegime[reg] = bestS;

      PrintFormat("✅ [MA-OPT] regime=%d -> FAST=%d SLOW=%d (score=%.1f)", reg, bestF, bestS, bestSc);
   }

   // po optymalizacji odśwież rysunek 2×MA
   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);
}


#endif  // __PATTERN_DETECTOR_MQH__
