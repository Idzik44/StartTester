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
// -------------------------------------------------------------------
// Opis:  Pobiera mnożnik z CSV (po przecinkach) dla indeksu idx.
// Wywołuje: StringSplit, StringTrimLeft/Right, StringToDouble.
// Używa globalnych: (brak).
// -------------------------------------------------------------------
double __GetMultFromCsv(const string csv, int idx, double defVal=1.0)
{
   string parts[]; int n = StringSplit(csv, ',', parts);
   if(n<=0 || idx<0 || idx>=n) return defVal;
   string s = parts[idx]; StringTrimLeft(s); StringTrimRight(s);
   return (double)StringToDouble(s);
}

// ─────────────────────────────────────────────────────────────
// FILTR CZASU SESJI
// -------------------------------------------------------------------
// Opis:  Wyznacza start i koniec godzinowy sesji dla danego czasu t.
// Wywołuje: GetSession.
// Używa globalnych: definicje enum SESSION_* (z modułu sesji).
// -------------------------------------------------------------------
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

// -------------------------------------------------------------------
// Opis:  Sprawdza, czy bar i mieści się w dozwolonym oknie czasu sesji.
// Wywołuje: __GetSessionBounds, TimeToStruct, PrintFormat.
// Używa globalnych: UseSessionTimeFilter, BlockFirstMinutesOfSession,
//                   BlockLastMinutesOfSession, BlockLastMinutesOfDay,
//                   DebugTimeFilter, TimeFilterLogOnlyLiveBar,
//                   TimeFilterLogOncePerBar, candleHistory[].
// -------------------------------------------------------------------
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
// -------------------------------------------------------------------
// Opis:  Sprawdza, czy istnieje okno [shift..shift+period-1] w candleHistory.
// Wywołuje: ArraySize.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
bool __PD_HasWindow(const int shift, const int period)
{
   const int total = ArraySize(candleHistory);
   if (shift < 1 || period <= 0) return false;
   return (shift + period - 1 < total);
}

// -------------------------------------------------------------------
// Opis:  Prosta średnia ruchoma z cen zamknięcia (SMA) w oknie.
// Wywołuje: __PD_HasWindow.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
double __PD_SMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   double s = 0.0;
   for (int k = shift; k < shift + period; ++k)
      s += candleHistory[k].close;
   return s / period;
}

// -------------------------------------------------------------------
// Opis:  Wykładnicza średnia ruchoma (EMA) z cen zamknięcia.
// Wywołuje: __PD_HasWindow, __PD_SMA_Close.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
double __PD_EMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   const double alpha = 2.0 / (period + 1.0);
   double ema = __PD_SMA_Close(shift, period);
   for (int k = shift + period - 2; k >= shift; --k)
      ema = alpha * candleHistory[k].close + (1.0 - alpha) * ema;
   return ema;
}

// -------------------------------------------------------------------
// Opis:  Smoothed MA (SMMA) z cen zamknięcia.
// Wywołuje: __PD_HasWindow, __PD_SMA_Close.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
double __PD_SMMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   double smma = __PD_SMA_Close(shift, period);
   for (int k = shift + period - 2; k >= shift; --k)
      smma = (smma * (period - 1) + candleHistory[k].close) / period;
   return smma;
}

// -------------------------------------------------------------------
// Opis:  LWMA (ważona liniowo) z cen zamknięcia.
// Wywołuje: __PD_HasWindow.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
double __PD_LWMA_Close(const int shift, const int period)
{
   if (!__PD_HasWindow(shift, period)) return 0.0;
   const int denom = period * (period + 1) / 2;
   double num = 0.0;
   for (int j = 0; j < period; ++j) {
      const int w = period - j;
      num += w * candleHistory[shift + j].close;
   }
   return num / denom;
}

// -------------------------------------------------------------------
// Opis:  Uniwersalny accessor: MA(close) wg metody method w oknie.
// Wywołuje: __PD_SMA_Close/__PD_EMA_Close/__PD_SMMA_Close/__PD_LWMA_Close.
// Używa globalnych: DET_MA_METHOD (domyślna metoda).
// -------------------------------------------------------------------
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
// STAŁE OKRESY MA PER-REGIME (zamiast UsePerRegimeMA/ActiveMA_*)
#ifndef NUM_REGIMES
  #define NUM_REGIMES 4
#endif

static const int FIXED_MA_FAST[NUM_REGIMES] = {20, 20, 20, 20};
static const int FIXED_MA_SLOW[NUM_REGIMES] = {50, 50, 50, 50};

// -------------------------------------------------------------------
// Opis:  Sprawdza filtr MA (położenie ceny i MA fast vs MA slow) per-regime.
// Wywołuje: DetectRegimeKey, __MA_Close_PeriodAtShift, MathMax/Min.
// Używa globalnych: candleHistory[], DET_MA_Soft, DET_MA_Soft_Tolerance,
//                   FIXED_MA_FAST[], FIXED_MA_SLOW[], NUM_REGIMES.
// -------------------------------------------------------------------
bool PassesMaCloseFilter_PerRegime(int i, bool isBuy)
{
   int reg = DetectRegimeKey(i);
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

   int fastP = FIXED_MA_FAST[reg];
   int slowP = FIXED_MA_SLOW[reg];
   if (fastP <= 0)     fastP = 20;
   if (slowP <= fastP) slowP = fastP + 1;

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

// -------------------------------------------------------------------
// Opis:  Loguje pojedynczy bar diagnostyczny reżimu z |Zr| i |Zv|.
// Wywołuje: DetectRegimeKey, GetStandardizedRange/Volume, TimeToString, PrintFormat.
// Używa globalnych: DebugRegime, DebugRegime_OnceBar, __REG_lastLogBar, candleHistory[].
// -------------------------------------------------------------------
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

// -------------------------------------------------------------------
// Opis:  Podsumowuje statystyki reżimów na ostatnich 'bars' słupkach.
// Wywołuje: DetectRegimeKey, GetStandardizedRange/Volume, PrintFormat, ArrayInitialize.
// Używa globalnych: candleHistory[], NUM_REGIMES.
// -------------------------------------------------------------------
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

// -------------------------------------------------------------------
// Opis:  Zwraca aktualnie aktywne okresy MA (fast/slow) dla reżimu.
// Wywołuje: (brak).
// Używa globalnych: FIXED_MA_FAST[], FIXED_MA_SLOW[], NUM_REGIMES.
// -------------------------------------------------------------------
void __GetActiveMAPeriods(int reg, int &fastP, int &slowP)
{
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;
   fastP = FIXED_MA_FAST[reg];
   slowP = FIXED_MA_SLOW[reg];
   if (fastP <= 0) fastP = 20;
   if (slowP <= fastP) slowP = fastP + 1;
}

// -------------------------------------------------------------------
// Opis:  Sprawdza „histerezę” MA: 2 kolejne zamknięcia po tej samej stronie obu MA.
// Wywołuje: __MA_Close_PeriodAtShift, MathMax/Min.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
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
// POMOCNICZE: czyszczenie segmentów MA
// -------------------------------------------------------------------
// Opis:  Usuwa wszystkie segmenty linii o danym prefiksie (dla symbolu/TF).
// Wywołuje: ObjectsTotal, ObjectName, StringFind, ObjectDelete.
// Używa globalnych: _Symbol, _Period.
// -------------------------------------------------------------------
void __PD_DeleteAllSegmentsForPrefix(const string prefix)
{
   const string tagPrefix = prefix + "_seg_";
   const string symTag    = StringFormat("_%s_%d", _Symbol, (int)_Period);

   int total = (int)ObjectsTotal(0, 0, -1);
   for (int idx = total - 1; idx >= 0; --idx)
   {
      string nm = ObjectName(0, idx);
      if (StringFind(nm, tagPrefix) == 0 && StringFind(nm, symTag) >= 0)
         ObjectDelete(0, nm);
   }
}

// ─────────────────────────────────────────────────────────────
// Rysowanie 2×MA – segmentami OBJ_TREND
// -------------------------------------------------------------------
// Opis:  Rysuje dwie MA (fast/slow) dla ostatnich 'lastBars' świec jako segmenty.
// Wywołuje: ObjectFind/ObjectDelete, __PD_DeleteAllSegmentsForPrefix, DetectRegimeKey,
//           __GetActiveMAPeriods, __MA_Close_PeriodAtShift, ObjectCreate, ObjectSetInteger.
// Używa globalnych: candleHistory[], PD_UniMA_LastBars, PD_UniMA_FastCol, PD_UniMA_SlowCol,
//                   PD_UniMA_Width, PD_UNI_FAST/PD_UNI_SLOW, _Symbol, _Period.
// -------------------------------------------------------------------
void PD_DrawUnifiedRegimeMA(int lastBars)
{
   if(lastBars<=0) lastBars = 400;

   const int total = ArraySize(candleHistory);
   if (total < 5) return;

   if (ObjectFind(0, PD_UNI_FAST) >= 0) ObjectDelete(0, PD_UNI_FAST);
   if (ObjectFind(0, PD_UNI_SLOW) >= 0) ObjectDelete(0, PD_UNI_SLOW);

   __PD_DeleteAllSegmentsForPrefix(PD_UNI_FAST);
   __PD_DeleteAllSegmentsForPrefix(PD_UNI_SLOW);

   datetime tF[]; double vF[]; ArrayResize(tF,0); ArrayResize(vF,0);
   datetime tS[]; double vS[]; ArrayResize(tS,0); ArrayResize(vS,0);

   const int upto = total - 2;                 
   const int maxN = MathMin(lastBars, upto);   

   for (int i = maxN; i >= 1; --i)
   {
      int reg = DetectRegimeKey(i); if (reg < 0 || reg >= NUM_REGIMES) reg = 0;
      int fP, sP; __GetActiveMAPeriods(reg, fP, sP);

      if (i + sP - 1 >= total) continue; 

      const double fastV = __MA_Close_PeriodAtShift(fP, i);
      const double slowV = __MA_Close_PeriodAtShift(sP, i);
      if (fastV == 0.0 || slowV == 0.0) continue;

      const datetime tt = candleHistory[i].time;

      int nf = ArraySize(tF); ArrayResize(tF, nf+1); ArrayResize(vF, nf+1);
      tF[nf] = tt; vF[nf] = fastV;

      int ns = ArraySize(tS); ArrayResize(tS, ns+1); ArrayResize(vS, ns+1);
      tS[ns] = tt; vS[ns] = slowV;
   }

   const int nF = ArraySize(tF);
   for (int k = 0; k < nF-1; ++k)
   {
      const string name = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_FAST, k, _Symbol, (int)_Period);
      ObjectCreate(0, name, OBJ_TREND, 0, tF[k], vF[k], tF[k+1], vF[k+1]);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      (long)PD_UniMA_FastCol);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      (long)PD_UniMA_Width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   const int nS = ArraySize(tS);
   for (int k = 0; k < nS-1; ++k)
   {
      const string name = StringFormat("%s_seg_%04d_%s_%d", PD_UNI_SLOW, k, _Symbol, (int)_Period);
      ObjectCreate(0, name, OBJ_TREND, 0, tS[k], vS[k], tS[k+1], vS[k+1]); // ✅ brakujący tS[k+1]
      ObjectSetInteger(0, name, OBJPROP_COLOR,      (long)PD_UniMA_SlowCol);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      (long)PD_UniMA_Width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

// ─────────────────────────────────────────────────────────────
// CHECK – sygnał impulsu + kierunek
// -------------------------------------------------------------------
// Opis:  Sprawdza, czy na barze i wystąpił impuls (Zr/Zv per-regime, ADX/DI, czas sesji, MA-histereza).
// Wywołuje: GetCurrentSessionAverageRange/Volume, PassesSessionTimeFilter, DetectRegimeKey,
//           GetStandardizedRange/Volume, __GetMultFromCsv, GetCustomADXAt/ComputeCustomADX/GetCustomPlusDIAt/GetCustomMinusDIAt,
//           __GetActiveMAPeriods, __ComputeMASideTwoClose.
// Używa globalnych: candleHistory[], IMP_ZR_MIN_PD/IMP_ZV_MIN_PD, DET_* (mults/csv), impulseAdxThreshold, impulseMinDiffDI,
//                   NUM_REGIMES.
// -------------------------------------------------------------------
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

   int fastP, slowP; __GetActiveMAPeriods(reg, fastP, slowP);
   bool sideAbove2=false, sideBelow2=false;
   if (!__ComputeMASideTwoClose(i, fastP, slowP, sideAbove2, sideBelow2)) return false;

   isBuy = sideAbove2; 
   return true;
}

// ─────────────────────────────────────────────────────────────
// STRZAŁKI
// -------------------------------------------------------------------
// Opis:  Rysuje strzałkę BUY/SELL na barze o indeksie index.
// Wywołuje: ObjectFind, ObjectCreate, ObjectSetInteger, TimeToString.
// Używa globalnych: candleHistory[], _Point, kolory (clrLime/clrRed).
// -------------------------------------------------------------------
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

// -------------------------------------------------------------------
// The same as DrawTradeArrowByIndex, ale po czasie świecy.
// Wywołuje: FindIndexByTime, DrawTradeArrowByIndex.
// Używa globalnych: candleHistory[].
// -------------------------------------------------------------------
void DrawTradeArrow(datetime t, string prefix, bool isBuy, color clrOverride=-1)
{
   int i = FindIndexByTime(t);
   if (i < 0 || i >= ArraySize(candleHistory)) return;
   DrawTradeArrowByIndex(i, prefix, isBuy, clrOverride);
}

// -------------------------------------------------------------------
// Opis:  Legacy wrapper: określa isBuy po kolorze i deleguje do DrawTradeArrow.
// Wywołuje: DrawTradeArrow.
// Używa globalnych: (brak).
// -------------------------------------------------------------------
void DrawArrow(datetime t, string prefix, color clr) // legacy
{
   bool isBuy = (clr == clrLime || clr == clrGreen);
   DrawTradeArrow(t, prefix, isBuy, clr);
}

// -------------------------------------------------------------------
// Opis:  Wrapper semantyczny dla sygnału (alias do DrawTradeArrow).
// Wywołuje: DrawTradeArrow.
// Używa globalnych: (brak).
// -------------------------------------------------------------------
void DrawSignalArrow(datetime t, string prefix, bool isBuySignal, color clrOverride=-1)
{
   DrawTradeArrow(t, prefix, isBuySignal, clrOverride);
}

// ─────────────────────────────────────────────────────────────
// LIVE
// -------------------------------------------------------------------
// Opis:  Detektor LIVE na świecy 1: rysuje MA, weryfikuje impuls i histerezę MA,
//        pilnuje „one-signal-per-bar-per-direction”, dostosowuje cenę do ograniczeń
//        (stops/freeze), a następnie wywołuje ExecuteImpulseTrade.
// Wywołuje: PD_DrawUnifiedRegimeMA, DetectRegimeKey, CheckImpulseConditions,
//           __GetActiveMAPeriods, __ComputeMASideTwoClose, DrawTradeArrow,
//           SymbolInfoInteger/SymbolInfoDouble, ExecuteImpulseTrade.
// Używa globalnych: candleHistory[], inputOneSignalPerBarPerDirection, inputExecuteMarginPoints,
//                   inputUseSLMethod, inputMagicNumber, _Point, _Symbol,
//                   impulseCandlesSinceLastDetection (modyfikuje).
// -------------------------------------------------------------------
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

   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);

   bool isBuy=false;

   int reg = DetectRegimeKey(i);
   if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

   if (!CheckImpulseConditions(i, isBuy)) {
      impulseCandlesSinceLastDetection++;
      return;
   }

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
// -------------------------------------------------------------------
// Opis:  Skanuje historię, znajduje impulsy (CheckImpulseConditions), symuluje pending + SL/TP,
//        i rysuje strzałkę tylko dla zyskownych przypadków.
// Wywołuje: CheckImpulseConditions, CalculateSLAndTP, SymbolInfoDouble,
//           SimulatePendingAndTradePoints, DrawTradeArrow, PD_DrawUnifiedRegimeMA.
// Używa globalnych: candleHistory[], inputExecuteMarginPoints, inputUseSLMethod,
//                   inputSLMultiplier, inputSLPoints, inputTPMultiplier, inputPendingExpiryBars, _Symbol.
// -------------------------------------------------------------------
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

   PD_DrawUnifiedRegimeMA(PD_UniMA_LastBars);
}

// ─────────────────────────────────────────────────────────────
// TEST HARNESS
// -------------------------------------------------------------------
// Opis:  Tryb testowy po zamknięciu świecy: rysuje MA, ewentualnie wywołuje
//        snapshot sesji, log reżimu albo pełną detekcję live (zgodnie z Test_Mode).
// Wywołuje: PD_DrawUnifiedRegimeMA, SessionAnalyzer_DumpSnapshot, Regime_LogBar, DetectLivePatternAndDraw.
// Używa globalnych: Test_Mode, DebugSessionAnalyzer, Enable_Detector_Live.
// -------------------------------------------------------------------
void TestHarness_OnClosedBar()
{
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
// -------------------------------------------------------------------
// Opis:  Audyt etapów detektora w oknie lookbackBars; opcjonalnie per-regime.
// Wywołuje: ArrayInitialize, PassesSessionTimeFilter, GetStandardizedRange/Volume,
//           __GetMultFromCsv, GetCustomADXAt/ComputeCustomADX/GetCustomPlusDIAt/GetCustomMinusDIAt,
//           PassesMaCloseFilter_PerRegime, CheckImpulseConditions, PrintFormat.
// Używa globalnych: candleHistory[], NUM_REGIMES, IMP_ZR_MIN_PD/IMP_ZV_MIN_PD, DET_* mults,
//                   impulseAdxThreshold, impulseMinDiffDI.
// -------------------------------------------------------------------
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

// -------------------------------------------------------------------
// Opis:  Skrót do audytu – bez rozbicia per-regime.
// Wywołuje: Detector_StageAuditEx.
// Używa globalnych: (brak).
// -------------------------------------------------------------------
void Detector_StageAudit(const int lookbackBars)           { Detector_StageAuditEx(lookbackBars, false); }

// -------------------------------------------------------------------
// Opis:  Skrót do audytu – z rozbiciem per-regime.
// Wywołuje: Detector_StageAuditEx.
// Używa globalnych: (brak).
// -------------------------------------------------------------------
void Detector_StageAudit_PerRegime(const int lookbackBars) { Detector_StageAuditEx(lookbackBars, true ); }

#endif  // __PATTERN_DETECTOR_MQH__
