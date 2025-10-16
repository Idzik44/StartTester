#ifndef __PATTERN_OPTIMIZER_MQH__
#define __PATTERN_OPTIMIZER_MQH__

#property strict


#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/ExitEngine.mqh>
#include <StartTester/PatternBacktest.mqh>
#include <StartTester/PatternDetector11.mqh>

#ifndef NUM_REGIMES
#define NUM_REGIMES 4
#endif


// Parametry (legacy – zostawiamy dla zgodności z wcześniejszymi analizami)
double impulseRangeFactor = 1.6;
double impulseVolumeFactor = 1.5;

double accumulationRangeFactor = 0.8;
double accumulationVolumeFactor = 0.7;

double fakeBreakoutRangeMinFactor = 0.5;
double fakeBreakoutRangeMaxFactor = 1.2;
double fakeBreakoutVolumeFactor  = 1.0;

// Progi DI/ADX (legacy – dziś mniej istotne przy nowym detektorze)
int impulseAdxThreshold = 20;
int impulseMinDiffDI    = 10;

int impulseLiveCandleCounter = 0;

int maxTestCandles = 300;

// ===== Kandydaci wyjść do optymalizacji =====
double CAND_ATR_K[]       = {2.2, 2.6, 3.0, 3.6};
int    CAND_SWING_N[]     = {5, 8, 13};
int    CAND_SWING_OFF[]   = {5, 8, 13};
double CAND_HYB_BE_R[]    = {0.8, 1.0, 1.2};
double CAND_HYB_TRAIL_K[] = {2.6, 3.2, 3.8};

// Zapamiętany „ostatni dobry” zestaw impulsu (legacy)
double lastGoodImpulseRangeFactor = 1.6;
double lastGoodImpulseVolumeFactor= 1.5;
int    lastGoodImpulseAdxThreshold= 20;
int    lastGoodImpulseMinDiffDI   = 10;

int impulseCandlesSinceLastDetection = 0;

// ─────────────────────────────────────────────────────────────
// Skróty Z-score (jak w detektorze)
double ZVol(int shift=1)   { return GetStandardizedVolume(shift); }
double ZRange(int shift=1) { return GetStandardizedRange(shift); }

// ─────────────────────────────────────────────────────────────
// NARZĘDZIA DIAGNOSTYCZNE DETEKTORA

// Pomoc: percentyl z tablicy (kopiuje i sortuje asc).
double __Percentile(const double &src[], int n, double p)
{
   if(n<=0) return 0.0;
   double tmp[]; ArrayResize(tmp, n);
   for(int i=0;i<n;i++) tmp[i]=src[i];

   ArraySort(tmp); // rosnąco

   if(p<=0) return tmp[0];
   if(p>=1) return tmp[n-1];
   double idx = (n-1) * p;
   int lo = (int)MathFloor(idx);
   int hi = (int)MathCeil(idx);
   if(lo==hi) return tmp[lo];
   double w = idx - lo;
   return tmp[lo]*(1.0-w) + tmp[hi]*w;
}

// 1) Profil rozkładu |ZRange| i |ZVol| + rekomendacje progów IMP_ZR_MIN/IMP_ZV_MIN
void RecommendDetectorThresholds(int sampleWindow=400, double pZr=0.75, double pZv=0.75)
{
   const int total = ArraySize(candleHistory);
   const int eff = MathMin(sampleWindow, MathMax(30, total - 2));
   if (eff < 30) { 
      if (DebugOptimizer) PrintFormat("[OPT] BOOTSTRAP: zbyt mało świec (total=%d) – pomijam rekomendacje.", total);
      return;
   }

   double zr[]; double zv[]; ArrayResize(zr,0); ArrayResize(zv,0);
   int collected=0;
   const int lastIdx = MathMin(total - 2, 1 + eff);
   for (int i = 2; i <= lastIdx; ++i) {
      int nz = ArraySize(zr); ArrayResize(zr, nz+1); zr[nz] = MathAbs(ZRange(i));
      nz = ArraySize(zv);     ArrayResize(zv, nz+1); zv[nz] = MathAbs(ZVol(i));
      collected++;
   }
   if (collected < 30) {
      if (DebugOptimizer) PrintFormat("[OPT] BOOTSTRAP: próbek=%d < 30 – pomijam.", collected);
      return;
   }

   double zrP = __Percentile(zr, ArraySize(zr), pZr);
   double zvP = __Percentile(zv, ArraySize(zv), pZv);

   if (DebugOptimizer)
   {
      double minZR=1e9,maxZR=-1e9,sumZR=0, minZV=1e9,maxZV=-1e9,sumZV=0;
      for(int k=0;k<collected;k++){
         double a=zr[k], b=zv[k];
         if(a<minZR) minZR=a; if(a>maxZR) maxZR=a; sumZR+=a;
         if(b<minZV) minZV=b; if(b>maxZV) maxZV=b; sumZV+=b;
      }
      double avgZR=sumZR/collected, avgZV=sumZV/collected;

      PrintFormat("[OPT][Z-Profile] N=%d | |Zr| avg=%.3f min=%.3f max=%.3f | |Zv| avg=%.3f min=%.3f max=%.3f",
                  collected, avgZR, minZR, maxZR, avgZV, minZV, maxZV);
      PrintFormat("[OPT][Suggest] IMP_ZR_MIN ≈ %.2f (%.0f%%-tile), IMP_ZV_MIN ≈ %.2f (%.0f%%-tile)",
                  zrP, pZr*100.0, zvP, pZv*100.0);
   }
}

// 2) Walidacja statystyk detektora dla AKTUALNYCH progów (per-regime)
void ValidateImpulseDetectorStats(int lookback=600)
{
   const int total = ArraySize(candleHistory);
   const int effLookback = MathMin(lookback, MathMax(20, total - 10));
   if (effLookback < 20) { 
      if (DebugOptimizer) PrintFormat("[OPT] BOOTSTRAP: lookback=%d – pomijam walidację.", effLookback);
      return; 
   }

   int passByReg[NUM_REGIMES]; ArrayInitialize(passByReg, 0);
   int seenByReg[NUM_REGIMES]; ArrayInitialize(seenByReg, 0);
   int passTotal=0, seenTotal=0;

   for (int i = total - 2; i >= MathMax(10, total - effLookback); --i)
   {
      bool isBuy=false;
      int reg = DetectRegimeKey(i);
      if(reg<0||reg>=NUM_REGIMES) continue;
      seenByReg[reg]++; seenTotal++;

      if(CheckImpulseConditions(i, isBuy)){
         passByReg[reg]++; passTotal++;
      }
   }

   if (DebugOptimizer)
   {
      PrintFormat("[OPT][VAL] LookbackEff=%d | hits=%d/%d (%.1f%%)", effLookback, passTotal, seenTotal,
                  seenTotal>0 ? 100.0*passTotal/seenTotal : 0.0);
      for(int r=0;r<NUM_REGIMES;r++){
         PrintFormat("   - reg=%d -> hits=%d/%d (%.1f%%)", r, passByReg[r], seenByReg[r],
                     seenByReg[r]>0 ? 100.0*passByReg[r]/seenByReg[r] : 0.0);
      }
   }
}

// ─────────────────────────────────────────────────────────────
// LEGACY: Optymalizacje formacji (zostawione dla kompatybilności)

void OptimizeImpulsePattern(double avgRange, double avgVolume)
{
   double bestScore = -1.0;
   double bestR = 0.0, bestV = 0.0;
   int    bestAdx = 0, bestDiff = 0;

   int total = MathMin(ArraySize(candleHistory), maxTestCandles);
   ComputeCustomADX(14);

   if (DebugPatternImpulse)
      Print("🔬 Optymalizacja IMPULSU (legacy – range/volume/ADX/ΔDI)...");

   for (double r = 1.2; r <= 1.7; r += 0.1)
   for (double v = 1.2; v <= 1.8; v += 0.1)
   for (int adxT = 15; adxT <= 30; adxT += 5)
   for (int diffT = 5; diffT <= 20; diffT += 5)
   {
      int found = 0;
      double tradeResults[]; ArrayResize(tradeResults, 0);

      for (int i = total - 2; i >= 10; --i)
      {
         double range  = candleHistory[i].high - candleHistory[i].low;
         double volume = (double)candleHistory[i].tick_volume;
         if (range < avgRange * r || volume < avgVolume * v) continue;

         double adx    = GetCustomADXAt(i);
         double plusDI = GetCustomPlusDIAt(i);
         double minusDI= GetCustomMinusDIAt(i);
         double diff   = MathAbs(plusDI - minusDI);

         bool diCondition = ((plusDI > minusDI && diff >= diffT) ||
                             (minusDI > plusDI && diff >= diffT));
         if (adx >= adxT && diCondition)
         {
            found++;
            bool isBuy = (plusDI > minusDI);

            double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
            double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double margin   = inputExecuteMarginPoints * point;
            double adjusted = isBuy ? (breakout + margin) : (breakout - margin);

            double sl = 0.0, tp = 0.0;
            CalculateSLAndTP(sl, tp, inputUseSLMethod, adjusted, isBuy, inputSLMultiplier, inputSLPoints, inputTPMultiplier);

            if (sl == 0.0 || tp == 0.0)
            {
               double rng  = candleHistory[i].high - candleHistory[i].low;
               double base = MathMax(inputSLPoints * point, inputSLMultiplier * rng);
               if (base <= 0) base = 10 * point;
               if (isBuy) { sl = adjusted - base; tp = adjusted + base * inputTPMultiplier; }
               else       { sl = adjusted + base; tp = adjusted - base * inputTPMultiplier; }
            }

            double points = 0.0;
            bool activated = SimulatePendingAndTradePoints(i, isBuy, adjusted, sl, tp, points, inputPendingExpiryBars);

            if (activated){
               int n = ArraySize(tradeResults);
               ArrayResize(tradeResults, n + 1);
               tradeResults[n] = points;
            }
         }
      }

      if (found >= 2)
      {
         double score = EvaluatePerformance(tradeResults);
         if (DebugPatternImpulse)
            PrintFormat("   ➜ [r=%.2f v=%.2f | ADX≥%d ΔDI≥%d] => found=%d, wynik=%.2f",
                        r, v, adxT, diffT, found, score);

         bool better = (score > bestScore);
         bool tieAndSimpler = (score == bestScore) &&
                              ((r + v + adxT/10.0 + diffT/10.0) <
                               (bestR + bestV + bestAdx/10.0 + bestDiff/10.0));
         if (better || tieAndSimpler) {
            bestScore = score; bestR = r; bestV = v; bestAdx = adxT; bestDiff = diffT;
         }
      }
   }

   if (bestScore >= 0.0)
   {
      impulseRangeFactor = bestR;
      impulseVolumeFactor= bestV;
      impulseAdxThreshold= bestAdx;
      impulseMinDiffDI   = bestDiff;

      if (DebugPatternImpulse)
         PrintFormat("✅ (legacy) Impuls: R>=%.2fx V>=%.2fx ADX≥%d ΔDI≥%d", bestR,bestV,bestAdx,bestDiff);
   }
}

// Akumulacja (legacy)
bool ConfirmAccumulation(int i)
{
   if (i + 3 >= ArraySize(candleHistory)) return false;

   double avgRange  = GetCurrentSessionAverageRange();
   double avgVolume = GetCurrentSessionAverageVolume();
   if (avgRange <= 0 || avgVolume <= 0) return false;

   double range  = candleHistory[i].high - candleHistory[i].low;
   double volume = (double)candleHistory[i].tick_volume;

   bool baseCondition = (range <= avgRange * accumulationRangeFactor &&
                         volume >= avgVolume * accumulationVolumeFactor);
   if (!baseCondition) return false;

   double adx    = GetCustomADXAt(i);
   double plusDI = GetCustomPlusDIAt(i);
   double minusDI= GetCustomMinusDIAt(i);
   double diff   = MathAbs(plusDI - minusDI);

   bool trendWeak = (adx <= 20 && diff <= 10);
   if (!trendWeak) return false;

   bool confirmationFound = false;
   for (int j = i + 1; j <= i + 3 && j < ArraySize(candleHistory); ++j) {
      double nextRange = candleHistory[j].high - candleHistory[j].low;
      bool isBullish   = candleHistory[j].close > candleHistory[j].open;
      bool strong      = nextRange >= avgRange * 1.3;
      if (isBullish && strong) { confirmationFound = true; break; }
   }
   return confirmationFound;
}

void OptimizeAccumulationPattern(double avgRange, double avgVolume)
{
   double bestScore = -1, bestR = 0, bestV = 0;
   int total = MathMin(ArraySize(candleHistory), maxTestCandles);

   for (double r = 0.6; r <= 1.0; r += 0.05)
   for (double v = 0.6; v <= 1.2; v += 0.05)
   {
      int found = 0, confirmed = 0;

      for (int i = total - 2; i >= 10; --i) {
         double range  = candleHistory[i].high - candleHistory[i].low;
         double volume = (double)candleHistory[i].tick_volume;

         if (range <= avgRange * r && volume >= avgVolume * v) {
            found++;
            if (ConfirmAccumulation(i)) confirmed++;
         }
      }

      if (found >= 1) {
         double score = (double)confirmed / found;
         if ( (score > bestScore) || ((score == bestScore) && ((r + v) < (bestR + bestV))) ) {
            bestScore = score; bestR = r; bestV = v;
         }
      }
   }

   if (bestScore >= 0) {
      accumulationRangeFactor = bestR;
      accumulationVolumeFactor= bestV;
   }
}

// Fake breakout (legacy)
bool ConfirmFakeBreakout(int i)
{
   if (i + 1 >= ArraySize(candleHistory)) return false;
   MqlRates c = candleHistory[i], next = candleHistory[i + 1];
   bool upper = c.high > candleHistory[i - 1].high;
   bool lower = c.low  < candleHistory[i - 1].low;
   if (upper && next.close < c.low)  return true;
   if (lower && next.close > c.high) return true;
   return false;
}

void OptimizeFakeBreakoutPattern(double avgRange, double avgVolume)
{
   double bestScore = -1, bestMin = 0.5, bestMax = 1.2, bestVol = 1.0;
   int total = MathMin(ArraySize(candleHistory), maxTestCandles);

   for (double r1 = 0.4; r1 <= 0.8; r1 += 0.05)
   for (double r2 = 1.0; r2 <= 1.4; r2 += 0.05)
   for (double v  = 0.5; v  <= 1.2; v  += 0.05)
   {
      int found = 0, confirmed = 0;

      for (int i = total - 2; i >= 10; --i) {
         double range  = candleHistory[i].high - candleHistory[i].low;
         double volume = (double)candleHistory[i].tick_volume;

         if (range >= avgRange * r1 && range <= avgRange * r2 && volume <= avgVolume * v) {
            found++;
            if (ConfirmFakeBreakout(i)) confirmed++;
         }
      }

      if (found >= 5) {
         double score = (double)confirmed / found;
         if (score > bestScore || (score == bestScore && (r2 - r1 + v) < (bestMax - bestMin + bestVol))) {
            bestScore = score; bestMin = r1; bestMax = r2; bestVol = v;
         }
      }
   }

   if (bestScore >= 0) {
      fakeBreakoutRangeMinFactor = bestMin;
      fakeBreakoutRangeMaxFactor = bestMax;
      fakeBreakoutVolumeFactor   = bestVol;
   }
}

// ─────────────────────────────────────────────────────────────
// Auto-optymalizacja co sesję (wywołuj z OnTick/OnTimer po zamknięciu świecy)
SessionType lastOptimizedSession = SESSION_UNKNOWN;

void MaybeOptimizeParametersHistorical()
{
   if (ArraySize(candleHistory) < 2) return;

   impulseLiveCandleCounter++;

   datetime t = candleHistory[1].time;
   SessionType currentSession = GetSession(t);

   bool shouldOptimize = false;

   if (currentSession != lastOptimizedSession && currentSession != SESSION_UNKNOWN && IsSessionDataReady()) {
      lastOptimizedSession = currentSession;
      shouldOptimize = true;
   }

   if ((impulseLiveCandleCounter >= 5 && IsSessionDataReady()) ||
       (impulseLiveCandleCounter >= 10)) {
      shouldOptimize = true;
   }

   if (!shouldOptimize) return;

   if (impulseCandlesSinceLastDetection >= 15) {
      if (DebugPatternEval)
         Print("🛑 15 świec bez impulsu – przywracam ostatnio dobre progi (legacy).");
      impulseRangeFactor   = lastGoodImpulseRangeFactor;
      impulseVolumeFactor  = lastGoodImpulseVolumeFactor;
      impulseAdxThreshold  = lastGoodImpulseAdxThreshold;
      impulseMinDiffDI     = lastGoodImpulseMinDiffDI;
      impulseCandlesSinceLastDetection = 0;
   }

   impulseLiveCandleCounter = 0;

   if (DebugPatternEval)
      PrintFormat("📊 [OPT] Auto (sesja: %s) – exits per regime + diagnostyka detektora", SessionTypeToString(currentSession));

   double avgRange  = GetCurrentSessionAverageRange();
   double avgVolume = GetCurrentSessionAverageVolume();
   if (avgRange == 0 || avgVolume == 0) {
      Print("⚠️ Brak danych do optymalizacji (avgRange/avgVolume == 0)");
      return;
   }

   // (legacy) – nie przeszkadza; główna siła to teraz exits per regime
   // OptimizeImpulsePattern(avgRange, avgVolume);

   // podpowiedzi do progów i sanity-check sygnałów
   RecommendDetectorThresholds(200, 0.75, 0.75);
   ValidateImpulseDetectorStats(500);

   OptimizeExitsPerRegime();
   MaybeRefreshMAPeriods_Auto();
}

// Wywołuj tylko na starcie – pełny run
void ForceOptimizeParametersHistorical()
{
   const int total = ArraySize(candleHistory);
   if (DebugPatternEval)
      PrintFormat("🚨 [FORCE] Full pass (bootstrap aware) | total bars=%d", total);

   AnalyzeInitialSessionRangesAndVolumes();

   int effRec  = MathMin(300, MathMax(30, total - 2));   // do rekomendacji progów Z
   int effVal  = MathMin(800, MathMax(20, total - 10));  // do walidacji

   if (effRec >= 30) RecommendDetectorThresholds(effRec, 0.75, 0.75);
   else if (DebugPatternEval) PrintFormat("[FORCE] BOOTSTRAP: effRec=%d < 30 – pomijam RecommendDetectorThresholds.", effRec);

   if (effVal >= 20) ValidateImpulseDetectorStats(effVal);
   else if (DebugPatternEval) PrintFormat("[FORCE] BOOTSTRAP: effVal=%d < 20 – pomijam ValidateImpulseDetectorStats.", effVal);

   OptimizeExitsPerRegime();

   if (UsePerRegimeMA && UsePerRegimeMA_Auto) {
      if (total >= 200) {
         RecommendPerRegimeMA_Apply(MARec_Lookback,
                                    MARec_FastMin, MARec_FastMax, MARec_FastStep,
                                    MARec_SlowMin, MARec_SlowMax, MARec_SlowStep,
                                    MARec_MinSamples);
      } else if (DebugMARecommend) {
         PrintFormat("[MA-AUTO] BOOTSTRAP: total=%d < 200 – najpierw zbierzemy trochę historii.", total);
      }
   }

   if (DebugPatternEval)
      Print("[FORCE] Done (bootstrap-safe).");
}

// ─────────────────────────────────────────────────────────────
// OPT: WYJŚCIA PER-REGIME  (główna, aktualna część)

void OptimizeExitsPerRegime()
{
   const int total = ArraySize(candleHistory);

   if (total < 40) {
      if (DebugOptimizer) PrintFormat("[OPT-EXIT] BOOTSTRAP: świec=%d < 40 – ustawiam domyślne wyjścia.", total);
      ExitParamsATR dATR; dATR.kATR = Exit_ATR_K_Default; dATR.atrPeriod = Exit_ATR_Period;
      ExitParamsSW  dSW;  dSW.swingN = Exit_Swing_N_Default; dSW.offsetPts = Exit_Swing_OffsetPts;
      ExitParamsHYB dHYB; dHYB.tp1R = Exit_HYB_TP1_R; dHYB.beAfterR = Exit_HYB_BE_After_R; dHYB.trailATRk = Exit_HYB_TrailATR_K;
      dHYB.timeStopBars = Exit_HYB_TimeStop_Bars; dHYB.timeStopMinR = Exit_HYB_TimeStop_MinR; dHYB.partialFrac = Exit_HYB_PartialFrac;
      for (int r=0; r<NUM_REGIMES; ++r) ExitEngine_SetBestForRegime(r, EXIT_HYBRID, dATR, dSW, dHYB);
      return;
   }

   const int minSignals = MathMax(2, total / 50);

   ExitParamsATR candATR[16]; int nATR = 0;
   for (int ia = 0; ia < ArraySize(CAND_ATR_K); ++ia) {
      candATR[nATR].kATR      = CAND_ATR_K[ia];
      candATR[nATR].atrPeriod = Exit_ATR_Period;
      nATR++;
   }

   ExitParamsSW candSW[32]; int nSW = 0;
   for (int in = 0; in < ArraySize(CAND_SWING_N); ++in)
   for (int io = 0; io < ArraySize(CAND_SWING_OFF); ++io) {
      candSW[nSW].swingN    = CAND_SWING_N[in];
      candSW[nSW].offsetPts = CAND_SWING_OFF[io];
      nSW++;
   }

   ExitParamsHYB candHYB[64]; int nHYB = 0;
   for (int ibe = 0; ibe < ArraySize(CAND_HYB_BE_R); ++ibe)
   for (int itk = 0; itk < ArraySize(CAND_HYB_TRAIL_K); ++itk) {
      candHYB[nHYB].tp1R         = Exit_HYB_TP1_R;
      candHYB[nHYB].beAfterR     = CAND_HYB_BE_R[ibe];
      candHYB[nHYB].trailATRk    = CAND_HYB_TRAIL_K[itk];
      candHYB[nHYB].timeStopBars = Exit_HYB_TimeStop_Bars;
      candHYB[nHYB].timeStopMinR = Exit_HYB_TimeStop_MinR;
      candHYB[nHYB].partialFrac  = Exit_HYB_PartialFrac;
      nHYB++;
   }

   ComputeCustomADX(14);

   struct ExitSignal { int i; bool isBuy; int regime; double adjusted; double sl; double tp; };
   ExitSignal sigs[]; ArrayResize(sigs, 0);

   const int upto  = total - 2;
   const int from  = MathMax(10, total - MathMin(maxTestCandles, total-2));
   for (int i = upto; i >= from; --i)
   {
      bool isBuy=false;
      if(!CheckImpulseConditions(i, isBuy)) continue;

      int  regime = DetectRegimeKey(i);

      double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
      double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double margin   = inputExecuteMarginPoints * point;
      double adjusted = isBuy ? (breakout + margin) : (breakout - margin);

      double sl = 0.0, tp = 0.0;
      CalculateSLAndTP(sl, tp, inputUseSLMethod, adjusted, isBuy,
                       inputSLMultiplier, inputSLPoints, inputTPMultiplier);

      if (sl == 0.0 || tp == 0.0) {
         double base = MathMax(inputSLPoints * point,
                               inputSLMultiplier * (candleHistory[i].high - candleHistory[i].low));
         if (base <= 0) base = 10 * point;
         if (isBuy) { sl = adjusted - base; tp = adjusted + base * inputTPMultiplier; }
         else       { sl = adjusted + base; tp = adjusted - base * inputTPMultiplier; }
      }

      int n = ArraySize(sigs); ArrayResize(sigs, n + 1);
      sigs[n].i = i; sigs[n].isBuy = isBuy; sigs[n].regime = regime;
      sigs[n].adjusted = adjusted; sigs[n].sl = sl; sigs[n].tp = tp;
   }

   if (ArraySize(sigs) < minSignals) {
      if (DebugOptimizer)
         PrintFormat("[OPT-EXIT] BOOTSTRAP: signals=%d < %d – ustawiam domyślne wyjścia.", ArraySize(sigs), minSignals);
      ExitParamsATR dATR; dATR.kATR = Exit_ATR_K_Default; dATR.atrPeriod = Exit_ATR_Period;
      ExitParamsSW  dSW;  dSW.swingN = Exit_Swing_N_Default; dSW.offsetPts = Exit_Swing_OffsetPts;
      ExitParamsHYB dHYB; dHYB.tp1R = Exit_HYB_TP1_R; dHYB.beAfterR = Exit_HYB_BE_After_R; dHYB.trailATRk = Exit_HYB_TrailATR_K;
      dHYB.timeStopBars = Exit_HYB_TimeStop_Bars; dHYB.timeStopMinR = Exit_HYB_TimeStop_MinR; dHYB.partialFrac = Exit_HYB_PartialFrac;
      for (int r=0; r<NUM_REGIMES; ++r) ExitEngine_SetBestForRegime(r, EXIT_HYBRID, dATR, dSW, dHYB);
      return;
   }

   ExitParamsATR dummyATR; dummyATR.kATR = Exit_ATR_K_Default; dummyATR.atrPeriod = Exit_ATR_Period;
   ExitParamsSW  dummySW;  dummySW.swingN = Exit_Swing_N_Default; dummySW.offsetPts = Exit_Swing_OffsetPts;
   ExitParamsHYB dummyHYB; dummyHYB.tp1R = Exit_HYB_TP1_R; dummyHYB.beAfterR = Exit_HYB_BE_After_R; dummyHYB.trailATRk = Exit_HYB_TrailATR_K;
   dummyHYB.timeStopBars = Exit_HYB_TimeStop_Bars;
   dummyHYB.timeStopMinR = Exit_HYB_TimeStop_MinR;
   dummyHYB.partialFrac  = Exit_HYB_PartialFrac;

   for (int r = 0; r < NUM_REGIMES; ++r)
   {
      double bestScore = -1.0;
      ExitPolicy   bestPol = EXIT_HYBRID;
      ExitParamsATR bestA  = dummyATR;
      ExitParamsSW  bestS  = dummySW;
      ExitParamsHYB bestH  = dummyHYB;

      // --- ATR ---
      for (int a = 0; a < nATR; ++a) {
         double buf[]; ArrayResize(buf, 0);
         for (int s = 0; s < ArraySize(sigs); ++s) {
            if (sigs[s].regime != r) continue;
            double pts;
            bool ok = SimulateTradeWithExit(sigs[s].i, sigs[s].isBuy, sigs[s].adjusted, sigs[s].sl, sigs[s].tp,
                                            EXIT_ATR, candATR[a], dummySW, dummyHYB, pts, 1);
            if (ok) { int m = ArraySize(buf); ArrayResize(buf, m + 1); buf[m] = pts; }
         }
         if (ArraySize(buf) >= 3) {
            double score = EvaluatePerformance(buf);
            if (score > bestScore) { bestScore = score; bestPol = EXIT_ATR; bestA = candATR[a]; }
         }
      }

      // --- SWING ---
      for (int sidx = 0; sidx < nSW; ++sidx) {
         double buf[]; ArrayResize(buf, 0);
         for (int t = 0; t < ArraySize(sigs); ++t) {
            if (sigs[t].regime != r) continue;
            double pts;
            bool ok = SimulateTradeWithExit(sigs[t].i, sigs[t].isBuy, sigs[t].adjusted, sigs[t].sl, sigs[t].tp,
                                            EXIT_SWING, dummyATR, candSW[sidx], dummyHYB, pts, 1);
            if (ok) { int m = ArraySize(buf); ArrayResize(buf, m + 1); buf[m] = pts; }
         }
         if (ArraySize(buf) >= 3) {
            double score = EvaluatePerformance(buf);
            if (score > bestScore) { bestScore = score; bestPol = EXIT_SWING; bestS = candSW[sidx]; }
         }
      }

      // --- HYBRID ---
      for (int h = 0; h < nHYB; ++h) {
         double buf[]; ArrayResize(buf, 0);
         for (int t = 0; t < ArraySize(sigs); ++t) {
            if (sigs[t].regime != r) continue;
            double pts;
            bool ok = SimulateTradeWithExit(sigs[t].i, sigs[t].isBuy, sigs[t].adjusted, sigs[t].sl, sigs[t].tp,
                                            EXIT_HYBRID, dummyATR, dummySW, candHYB[h], pts, 1);
            if (ok) { int m = ArraySize(buf); ArrayResize(buf, m + 1); buf[m] = pts; }
         }
         if (ArraySize(buf) >= 3) {
            double score = EvaluatePerformance(buf);
            if (score > bestScore) { bestScore = score; bestPol = EXIT_HYBRID; bestH = candHYB[h]; }
         }
      }

      ExitEngine_SetBestForRegime(r, bestPol, bestA, bestS, bestH);

      if (DebugOptimizer)
         PrintFormat("[OPT-EXIT] regime=%d -> policy=%d score=%.3f", r, (int)bestPol, bestScore);
   }
}

// =====================================================================
//  MA AUTO per-regime
// =====================================================================
int  ActiveMA_Fast_PerRegime[NUM_REGIMES] = {20,20,20,20};
int  ActiveMA_Slow_PerRegime[NUM_REGIMES] = {50,50,50,50};
bool ActiveMA_Ready = false;

static datetime __MA_lastBarTime = 0;
static int      __MA_barsSince   = 0;
static SessionType __MA_lastSess = SESSION_UNKNOWN;

double __MAREC_SMA_Close(int shift, int period)
{
   int total = ArraySize(candleHistory);
   if (period <= 0 || shift < 1 || shift + period - 1 >= total) return 0.0;
   double s = 0.0;
   for (int k=shift; k<shift+period; ++k) s += candleHistory[k].close;
   return s / period;
}

struct __MARec { int fast; int slow; double acc; int samples; };

bool __MARecBetter(const __MARec &a, const __MARec &b)
{
   if (a.acc     != b.acc)     return a.acc > b.acc;
   if (a.samples != b.samples) return a.samples > b.samples;
   return (a.fast + a.slow) < (b.fast + b.slow);
}

// Główna: policz i ZASTOSUJ okresy MA per-regime
void RecommendPerRegimeMA_Apply(int lookback,
                                int fastMin, int fastMax, int fastStep,
                                int slowMin, int slowMax, int slowStep,
                                int minSamples)
{
   const int total = ArraySize(candleHistory);
   const int effLookback = MathMin(lookback, MathMax(20, total - 2));

   // BOOTSTRAP: bardzo mało danych -> fallback do aktualnych ActiveMA_* lub 20/50
   if (effLookback < 20) {
      if (DebugMARecommend)
         PrintFormat("[MA-AUTO] BOOTSTRAP: total=%d – używam fallback (ActiveMA/domysły) bez skanowania.", total);

      for (int reg = 0; reg < NUM_REGIMES; ++reg) {
         int f = ActiveMA_Fast_PerRegime[reg] > 0 ? ActiveMA_Fast_PerRegime[reg] : 20;
         int s = ActiveMA_Slow_PerRegime[reg] > f ? ActiveMA_Slow_PerRegime[reg] : 50;
         f = MathMax(fastMin, MathMin(fastMax, f));
         s = MathMax(f+1,     MathMin(slowMax, s));
         ActiveMA_Fast_PerRegime[reg] = f;
         ActiveMA_Slow_PerRegime[reg] = s;
         if (DebugMARecommend)
            PrintFormat("[MA-AUTO] reg=%d Fallback -> fast=%d slow=%d", reg, f, s);
      }
      ActiveMA_Ready = true;
      return;
   }

   int slowMaxEff = MathMin(slowMax, MathMax(slowMin, effLookback - 2));
   int fastMaxEff = MathMin(fastMax, MathMax(fastMin, slowMaxEff - 1));

   int effMinSamples = MathMin(minSamples, MathMax(5, effLookback / 8));
   int from = MathMax(10, total - effLookback);
   int upto = total - 2;

   ComputeCustomADX(14);
   int updated = 0;

   for (int reg = 0; reg < NUM_REGIMES; ++reg)
   {
      __MARec best; best.fast=0; best.slow=0; best.acc=-1.0; best.samples=0;

      for (int f = fastMin; f <= fastMaxEff; f += fastStep)
      for (int s = MathMax(slowMin, f+1); s <= slowMaxEff; s += slowStep)
      {
         int hits=0, miss=0;

         for (int i = upto; i >= from; --i)
         {
            if (DetectRegimeKey(i) != reg) continue;

            double maF = __MAREC_SMA_Close(i, f);
            double maS = __MAREC_SMA_Close(i, s);
            if (maF <= 0.0 || maS <= 0.0) continue;

            double c = candleHistory[i].close;
            bool condBuy  = (c > MathMax(maF, maS)) && (maF >= maS);
            bool condSell = (c < MathMin(maF, maS)) && (maF <= maS);
            if (!condBuy && !condSell) continue;

            double adx = GetCustomADXAt(i);
            double pdi = GetCustomPlusDIAt(i);
            double mdi = GetCustomMinusDIAt(i);
            if (adx < impulseAdxThreshold) continue;

            int dirDI = (pdi >= mdi) ? +1 : -1;
            int dirMA = condBuy ? +1 : -1;

            if (dirMA == dirDI) hits++; else miss++;
         }

         int samples = hits + miss;
         if (samples < effMinSamples) continue;

         double acc = (double)hits / MathMax(1, samples);
         __MARec cand; cand.fast=f; cand.slow=s; cand.acc=acc; cand.samples=samples;

         bool take = true;
         #ifdef __MARecBetter_available
            take = __MARecBetter(cand, best);
         #else
            if (cand.acc != best.acc)         take = (cand.acc > best.acc);
            else if (cand.samples != best.samples) take = (cand.samples > best.samples);
            else take = ((cand.fast + cand.slow) < (best.fast + best.slow));
         #endif

         if (take) { best = cand; }
      }

      if (best.acc >= 0.0)
      {
         int oldF = ActiveMA_Fast_PerRegime[reg];
         int oldS = ActiveMA_Slow_PerRegime[reg];
         ActiveMA_Fast_PerRegime[reg] = best.fast;
         ActiveMA_Slow_PerRegime[reg] = best.slow;
         updated++;
         if (DebugMARecommend)
            PrintFormat("[MA-AUTO] reg=%d -> fast=%d slow=%d (acc=%.1f%% n=%d)  [was: %d/%d]",
                        reg, best.fast, best.slow, 100.0*best.acc, best.samples, oldF, oldS);
      }
      else
      {
         // lokalny fallback: trzymaj obecne ActiveMA lub 20/50 w rozsądnych granicach
         int f = ActiveMA_Fast_PerRegime[reg] > 0 ? ActiveMA_Fast_PerRegime[reg] : 20;
         int s = ActiveMA_Slow_PerRegime[reg] > f ? ActiveMA_Slow_PerRegime[reg] : 50;
         f = MathMax(fastMin, MathMin(fastMaxEff, f));
         s = MathMax(f+1,     MathMin(slowMaxEff, s));
         ActiveMA_Fast_PerRegime[reg] = f;
         ActiveMA_Slow_PerRegime[reg] = s;

         if (DebugMARecommend)
            PrintFormat("[MA-AUTO] reg=%d: fallback (samples<%d). Ustawiam fast=%d slow=%d",
                        reg, effMinSamples, f, s);
      }
   }

   ActiveMA_Ready = true;

   if (DebugMARecommend)
      PrintFormat("[MA-AUTO] Zakończono. updated=%d/%d | effLookback=%d | effMinSamples=%d",
                  updated, NUM_REGIMES, effLookback, effMinSamples);
}

// Wywołuj cyklicznie: co nową zamkniętą świecę zliczaj, a gdy dojdzie do progu – odśwież
void MaybeRefreshMAPeriods_Auto()
{
   if (!UsePerRegimeMA || !UsePerRegimeMA_Auto) return;
   if (ArraySize(candleHistory) < 2) return;

   datetime t1 = candleHistory[1].time;
   if (t1 != __MA_lastBarTime) {
      __MA_lastBarTime = t1;
      __MA_barsSince++;
   }

   SessionType sess = GetSession(t1);
   bool sessionChanged = (sess != __MA_lastSess && sess != SESSION_UNKNOWN);
   bool enoughBars     = (__MA_barsSince >= MARec_RefreshEveryBars);

   if ((sessionChanged || enoughBars) && IsSessionDataReady())
   {
      if (DebugMARecommend)
         PrintFormat("[MA-AUTO] Refresh (bars=%d, session%schange) ...",
                     __MA_barsSince, sessionChanged? "=":" no ");

      RecommendPerRegimeMA_Apply(MARec_Lookback,
                                 MARec_FastMin, MARec_FastMax, MARec_FastStep,
                                 MARec_SlowMin, MARec_SlowMax, MARec_SlowStep,
                                 MARec_MinSamples);

      __MA_barsSince = 0;
      __MA_lastSess  = sess;
   }
}

#endif // __PATTERN_OPTIMIZER_MQH__
