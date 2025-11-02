//+------------------------------------------------------------------+
//|                          ExitOptimizer.mqh                       |
//| Grid-search wyjść (BE, trailing, partial, time, DI-exit)        |
//| per reżim rynku + zapis najlepszych parametrów                   |
//+------------------------------------------------------------------+
#property strict

#ifndef __EXIT_OPTIMIZER_MQH__
#define __EXIT_OPTIMIZER_MQH__

#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/PatternBacktest.mqh>     // SimulatePendingAndTradePointsAdvanced + ewentualnie EvaluatePerformance(...)
#include <StartTester/ExitTypes.mqh>         // TrailMethod enum
#include <StartTester/ExitPolicy.mqh>          // ExitParams + Save/Load per reżim
#include <StartTester/RegimeDetector.mqh>      // MarketRegime + klasyfikacja reżimu
#include <StartTester/Position_Size11.mqh>     // CalculateSLAndTP

input int  ExitOpt_MinBarsFallback      = 30;   // minimalne okno skanowania
input bool DebugExitOptimizer           = true; // podsumowania (ile świec, ile sygnałów, best)
input bool DebugExitOptimizerGridVerbose= true;// bardzo szczegółowe logi z grida
input bool DebugExitSignals             = true;// wypisz indeksy/czasy sygnałów

// Opis: Zwraca efektywną liczbę świec do skanowania z uwzględnieniem dostępnych danych.
// Wywołania: ArraySize, MathMin, MathMax.
// Globalne/extern: candleHistory[], ExitOpt_MinBarsFallback.
int EffectiveScanBars(int requested)
{
   int total = ArraySize(candleHistory);
   if(total <= 20) return 0;
   // użyj: min(requested, total-10), ale nie mniej niż ExitOpt_MinBarsFallback
   int usable = MathMin(requested, total - 10);
   return MathMax(ExitOpt_MinBarsFallback, usable);
}


// ------------------------------------------------------------------
// Metryka jakości (odporna na outliery)
//   score = zysk netto + premia za PF i winrate - kara za DD i małą próbkę
// ------------------------------------------------------------------
// Opis: Liczy PF, max DD, winrate oraz zwraca złożony score strategii na listwie zysków.
// Wywołania: ArraySize, MathMin.
// Globalne/extern: (brak).
double EvaluatePerformanceAdvanced(const double &profits[],
                                   double &profitFactor,
                                   double &maxDrawdown,
                                   double &winrate)
{
   int n = ArraySize(profits);
   if(n==0){ profitFactor=0; maxDrawdown=0; winrate=0; return -1; }

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
   profitFactor = (lossSum>0 ? profitSum/lossSum : (wins>0 ? 10.0 : 0.0)); // brak strat -> wysoki PF

   double net   = equity;
   double pfCap = MathMin(profitFactor, 3.0);   // limit wpływu jednego „strzału”
   double score = net
                + 100.0*(pfCap - 1.0)
                + 200.0*(winrate - 0.5)
                - 0.5*maxDrawdown;

   // Kara za małą próbkę
   if(n < 8)       score -= 200.0;
   else if(n < 15) score -= 60.0;

   return score;
}

// ------------------------------------------------------------------
// Optymalizacja parametrów WYJŚCIA *dla konkretnego reżimu*
//  - zbiera sygnały impulsu, które powstały w danym reżimie,
//  - skanuje siatkę wyjść (warunkowo, by nie eksplodować kombinatoryki),
//  - symuluje pending + SL/TP + BE/Trailing/Partial/Time/DI,
//  - wybiera najlepszy zestaw parametrów i zapisuje go per reżim.
// Zwraca true, jeśli znaleziono jakikolwiek sensowny zestaw.
// ------------------------------------------------------------------
// Opis: Pełny grid-search parametrów wyjścia dla wskazanego reżimu rynku.
// Wywołania: ArraySize, MathMax, Print/PrintFormat, TimeToString, EffectiveScanBars,
//            CheckImpulseConditions, GetRegimeFeatures, ClassifyRegime,
//            SymbolInfoDouble, CalculateSLAndTP, MathMax, SimulatePendingAndTradePointsAdvanced,
//            EvaluatePerformanceAdvanced, CopyExitParams, SaveBestExitForRegime.
// Globalne/extern: candleHistory[], _Symbol, inputExecuteMarginPoints, inputUseSLMethod,
//                  inputSLMultiplier, inputSLPoints, inputTPMultiplier,
//                  DebugExitSignals, DebugExitOptimizer, DebugExitOptimizerGridVerbose.
bool OptimizeExitParametersForRegime(MarketRegime targetRegime,
                                     int minBarsToScan,
                                     ExitParams &bestParamsOut,
                                     double &bestScoreOut)
{
   bestScoreOut = -1e100;

   int total  = ArraySize(candleHistory);
   int effScan= EffectiveScanBars(minBarsToScan);
   if(total <= 20 || effScan <= 0)
   {
      Print("⚠️ ExitOptimizer: za mało świec do optymalizacji (total=", total, ").");
      return false;
   }

   // 1) Zbierz sygnały impulsu z danego reżimu
   int start = MathMax(10, total - effScan);
   int signals[]; ArrayResize(signals, 0);

   for(int i = total - 2; i >= start; --i)
   {
      if(!CheckImpulseConditions(i, false, false, false)) continue;

      RegimeFeatures f; GetRegimeFeatures(i, f);
      MarketRegime r = ClassifyRegime(f);
      if(r != targetRegime) continue;

      int n = ArraySize(signals);
      ArrayResize(signals, n+1);
      signals[n] = i;

      if(DebugExitSignals)
         PrintFormat("    [Sig %d] regime=%d time=%s", i, (int)r,
                     TimeToString(candleHistory[i].time, TIME_DATE|TIME_SECONDS));
   }

   if(DebugExitOptimizer)
      PrintFormat("🧪 ExitOpt[%d]: total=%d, requested=%d, effective=%d, startIndex=%d, signals=%d",
                  (int)targetRegime, total, minBarsToScan, effScan, start, ArraySize(signals));

   if(ArraySize(signals) < 5)  // pozwól ruszyć na małej próbce
   {
      PrintFormat("⚠️ ExitOptimizer[%d]: za mało sygnałów (%d).",
                  (int)targetRegime, ArraySize(signals));
      return false;
   }

   // 2) Siatka parametrów
   bool   beOn[]     = {false, true};
   double beR[]      = {0.8, 1.0, 1.2};
   int    beOffPts[] = {0, 5, 10};

   bool   partOn[]   = {false, true};
   double partR[]    = {0.8, 1.0, 1.2};
   double partPct[]  = {0.3, 0.5, 0.67};

   TrailMethod trails[] = {TRAIL_NONE, TRAIL_ATR, TRAIL_STEP, TRAIL_CANDLE};
   int    atrPer[]   = {10, 14, 20};
   double atrMul[]   = {1.8, 2.2, 2.8};

   int    stepEvery[] = {50, 100, 150};
   int    stepLock[]  = {25, 50, 75};

   bool   timeOn[]   = {false, true};
   int    maxBars[]  = {10, 20, 30};

   bool   diOn[]     = {false, true};
   int    diAdx[]    = {15, 20};
   int    diMin[]    = {15, 20};
   int    diDiff[]   = {5, 10};

   // 3) Grid – warunkowo rozwijany
   double bestScore = -1e100;
   ExitParams bestP;

   for(int b1=0; b1<ArraySize(beOn); ++b1)
   for(int b2=0; b2<(beOn[b1]?ArraySize(beR):1); ++b2)
   for(int b3=0; b3<(beOn[b1]?ArraySize(beOffPts):1); ++b3)
   for(int p1=0; p1<ArraySize(partOn); ++p1)
   for(int p2=0; p2<(partOn[p1]?ArraySize(partR):1); ++p2)
   for(int p3=0; p3<(partOn[p1]?ArraySize(partPct):1); ++p3)
   for(int t=0; t<ArraySize(trails); ++t)
   for(int a1=0; a1<(trails[t]==TRAIL_ATR?ArraySize(atrPer):1); ++a1)
   for(int a2=0; a2<(trails[t]==TRAIL_ATR?ArraySize(atrMul):1); ++a2)
   for(int s1=0; s1<(trails[t]==TRAIL_STEP?ArraySize(stepEvery):1); ++s1)
   for(int s2=0; s2<(trails[t]==TRAIL_STEP?ArraySize(stepLock):1); ++s2)
   for(int tm=0; tm<ArraySize(timeOn); ++tm)
   for(int mb=0; mb<(timeOn[tm]?ArraySize(maxBars):1); ++mb)
   for(int dox=0; dox<ArraySize(diOn); ++dox)
   for(int dx1=0; dx1<(diOn[dox]?ArraySize(diAdx):1); ++dx1)
   for(int dx2=0; dx2<(diOn[dox]?ArraySize(diMin):1); ++dx2)
   for(int dx3=0; dx3<(diOn[dox]?ArraySize(diDiff):1); ++dx3)
   {
      double results[]; ArrayResize(results, 0);

      // iteruj po sygnałach i symuluj
      for(int si=0; si<ArraySize(signals); ++si)
      {
         int i = signals[si];
         bool isBuy = (candleHistory[i].close > candleHistory[i].open);

         // Wejście = pending (breakout ± margin)
         double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
         double margin   = inputExecuteMarginPoints * point;
         double adjusted = isBuy ? (breakout + margin) : (breakout - margin);

         // SL/TP
         double sl = 0.0, tp = 0.0;
         CalculateSLAndTP(sl, tp,
                          inputUseSLMethod,
                          adjusted,
                          isBuy,
                          inputSLMultiplier,
                          inputSLPoints,
                          inputTPMultiplier);

         // Fallback (awaryjnie, gdyby 0)
         if(sl==0.0 || tp==0.0)
         {
            double range = candleHistory[i].high - candleHistory[i].low;
            double base  = MathMax(inputSLPoints*point, inputSLMultiplier*range);
            if(base <= 0) base = 10*point;

            if(isBuy){ sl = adjusted - base; tp = adjusted + base*inputTPMultiplier; }
            else     { sl = adjusted + base; tp = adjusted - base*inputTPMultiplier; }
         }

         // Symulacja z zaawansowanymi wyjściami
         double pts = 0.0;
         bool ok = SimulatePendingAndTradePointsAdvanced(
                      i, isBuy, adjusted, sl, tp, pts, /*expiryBars*/ 1,
                      // BE
                      beOn[b1], (beOn[b1]?beR[b2]:0.0), (beOn[b1]?beOffPts[b3]:0),
                      // Trailing
                      trails[t],
                      (trails[t]==TRAIL_ATR?atrPer[a1]:0),
                      (trails[t]==TRAIL_ATR?atrMul[a2]:0.0),
                      (trails[t]==TRAIL_STEP?stepEvery[s1]:0),
                      (trails[t]==TRAIL_STEP?stepLock[s2]:0),
                      // Partial
                      partOn[p1], (partOn[p1]?partR[p2]:0.0), (partOn[p1]?partPct[p3]:0.0),
                      // Time stop
                      timeOn[tm], (timeOn[tm]?maxBars[mb]:0),
                      // DI exit
                      diOn[dox],
                      (diOn[dox]?diAdx[dx1]:0), (diOn[dox]?diMin[dx2]:0), (diOn[dox]?diDiff[dx3]:0)
                    );

         if(ok)
         {
            int rn = ArraySize(results);
            ArrayResize(results, rn+1);
            results[rn] = pts;
         }
      } // sygnały

      if(ArraySize(results)==0) continue;

      double pf, dd, wr;
      double score = EvaluatePerformanceAdvanced(results, pf, dd, wr);

      if(DebugExitOptimizerGridVerbose)
      {
         PrintFormat("ExitGrid[%d]: BE=%d(%.1f/%d) PART=%d(%.1f/%.2f) TR=%d(AP:%d AM:%.1f SE:%d SL:%d) TM=%d(%d) DI=%d(%d/%d/%d) -> n=%d, score=%.1f, PF=%.2f, DD=%.1f, WR=%.1f%%",
            (int)targetRegime,
            (int)beOn[b1], (beOn[b1]?beR[b2]:0.0), (beOn[b1]?beOffPts[b3]:0),
            (int)partOn[p1], (partOn[p1]?partR[p2]:0.0), (partOn[p1]?partPct[p3]:0.0),
            (int)trails[t], (trails[t]==TRAIL_ATR?atrPer[a1]:0), (trails[t]==TRAIL_ATR?atrMul[a2]:0.0),
            (trails[t]==TRAIL_STEP?stepEvery[s1]:0), (trails[t]==TRAIL_STEP?stepLock[s2]:0),
            (int)timeOn[tm], (timeOn[tm]?maxBars[mb]:0),
            (int)diOn[dox], (diOn[dox]?diAdx[dx1]:0), (diOn[dox]?diMin[dx2]:0), (diOn[dox]?diDiff[dx3]:0),
            ArraySize(results), score, pf, dd, wr*100.0);
      }

      if(score > bestScore)
      {
         bestScore = score;

         ExitParams p;
         p.useBE = beOn[b1];           p.beR = (beOn[b1]?beR[b2]:0.0);      p.beOffsetPts = (beOn[b1]?beOffPts[b3]:0);
         p.usePartial = partOn[p1];    p.partialR = (partOn[p1]?partR[p2]:0.0); p.partialPct = (partOn[p1]?partPct[p3]:0.0);
         p.trail = trails[t];          p.atrPeriod = (trails[t]==TRAIL_ATR?atrPer[a1]:0); p.atrMult = (trails[t]==TRAIL_ATR?atrMul[a2]:0.0);
         p.stepEveryPts = (trails[t]==TRAIL_STEP?stepEvery[s1]:0);  p.stepLockPts = (trails[t]==TRAIL_STEP?stepLock[s2]:0);
         p.useTimeStop = timeOn[tm];   p.maxBars = (timeOn[tm]?maxBars[mb]:0);
         p.useDIExit  = diOn[dox];     p.adxMin = (diOn[dox]?diAdx[dx1]:0); p.diMin = (diOn[dox]?diMin[dx2]:0); p.diDiff = (diOn[dox]?diDiff[dx3]:0);

         CopyExitParams(bestP, p); // ⬅️ brak deprecated assign
      }
   } // grid

   if(bestScore <= -1e90)
   {
      PrintFormat("❌ ExitOptimizer[%d]: brak sensownego wyniku.", (int)targetRegime);
      return false;
   }

   SaveBestExitForRegime(targetRegime, bestP);
   CopyExitParams(bestParamsOut, bestP);
   bestScoreOut  = bestScore;

   PrintFormat("🏁 BEST Exit[%d]: score=%.1f | BE=%d(%.2f/%d) PART=%d(%.2f/%.2f) TR=%d(AP:%d AM:%.2f SE:%d SL:%d) TM=%d(%d) DI=%d(%d/%d/%d)",
      (int)targetRegime,
      bestScore,
      (int)bestP.useBE, bestP.beR, bestP.beOffsetPts,
      (int)bestP.usePartial, bestP.partialR, bestP.partialPct,
      (int)bestP.trail, bestP.atrPeriod, bestP.atrMult, bestP.stepEveryPts, bestP.stepLockPts,
      (int)bestP.useTimeStop, bestP.maxBars,
      (int)bestP.useDIExit, bestP.adxMin, bestP.diMin, bestP.diDiff);

   return true;
}


// Opis: Buduje „sąsiedztwo” wartości double wokół center z klamrowaniem do [low, high] i bez duplikatów.
// Wywołania: ArrayResize, MathAbs.
// Globalne/extern: (brak).
void BuildNeighborhoodDouble(double center, double step, double low, double high, double &out[])
{
   ArrayResize(out, 0);
   double vals[5];
   vals[0]=center - 2*step; vals[1]=center - step; vals[2]=center; vals[3]=center + step; vals[4]=center + 2*step;
   for(int i=0;i<5;i++)
   {
      double v = vals[i];
      if(v < low)  v = low;
      if(v > high) v = high;
      // unikaj duplikatów
      bool dup=false;
      for(int k=0;k<ArraySize(out);++k) if(MathAbs(out[k]-v) < 1e-9) { dup=true; break; }
      if(!dup){ int n=ArraySize(out); ArrayResize(out,n+1); out[n]=v; }
   }
}

// Opis: Buduje „sąsiedztwo” wartości int wokół center z klamrowaniem do [low, high] i bez duplikatów.
// Wywołania: ArrayResize.
// Globalne/extern: (brak).
void BuildNeighborhoodInt(int center, int step, int low, int high, int &out[])
{
   ArrayResize(out, 0);
   int vals[5]={center-2*step, center-step, center, center+step, center+2*step};
   for(int i=0;i<5;i++)
   {
      int v = vals[i];
      if(v < low)  v = low;
      if(v > high) v = high;
      bool dup=false;
      for(int k=0;k<ArraySize(out);++k) if(out[k]==v) { dup=true; break; }
      if(!dup){ int n=ArraySize(out); ArrayResize(out,n+1); out[n]=v; }
   }
}

// Opis: Zapewnia, że tablica int ma przynajmniej jeden element; jeśli pusta — wstaw v.
// Wywołania: ArraySize, ArrayResize.
// Globalne/extern: (brak).
void EnsureIntArrayHasOne(int &arr[], int v)
{
   if(ArraySize(arr)==0){ ArrayResize(arr,1); arr[0]=v; }
}

// Opis: Zapewnia, że tablica double ma przynajmniej jeden element; jeśli pusta — wstaw v.
// Wywołania: ArraySize, ArrayResize.
// Globalne/extern: (brak).
void EnsureDblArrayHasOne(double &arr[], double v)
{
   if(ArraySize(arr)==0){ ArrayResize(arr,1); arr[0]=v; }
}


// Opis: „Fine-tune” — strojenie parametrów wokół seedParams dla wskazanego reżimu (wąskie sąsiedztwa).
// Wywołania: ArraySize, EffectiveScanBars, MathMax, CheckImpulseConditions,
//            GetRegimeFeatures, ClassifyRegime, SymbolInfoDouble, CalculateSLAndTP,
//            MathMax, SimulatePendingAndTradePointsAdvanced, EvaluatePerformanceAdvanced,
//            BuildNeighborhoodDouble/Int, Ensure*ArrayHasOne, CopyExitParams,
//            SaveBestExitForRegime, PrintFormat.
// Globalne/extern: candleHistory[], _Symbol, inputExecuteMarginPoints, inputUseSLMethod,
//                  inputSLMultiplier, inputSLPoints, inputTPMultiplier.
bool RefineExitParametersForRegime(MarketRegime regime,
                                   int minBarsToScan,
                                   const ExitParams &seedParams,
                                   ExitParams &bestParamsOut,
                                   double &bestScoreOut)
{
   bestScoreOut = -1e100;

   int total  = ArraySize(candleHistory);
   int effScan= EffectiveScanBars(minBarsToScan);
   if(total <= 20 || effScan <= 0) return false;

   // 1) sygnały w danym reżimie
   int start = MathMax(10, total - effScan);
   int signals[]; ArrayResize(signals, 0);

   for(int i=total-2; i>=start; --i)
   {
      if(!CheckImpulseConditions(i, false, false, false)) continue;
      RegimeFeatures f; GetRegimeFeatures(i, f);
      if(ClassifyRegime(f) != regime) continue;
      int n=ArraySize(signals); ArrayResize(signals,n+1); signals[n]=i;
   }
   if(ArraySize(signals) < 5) return false;

   // 2) sąsiedztwa tylko dla włączonych elementów
   bool useBE       = seedParams.useBE;
   bool usePartial  = seedParams.usePartial;
   TrailMethod trail= seedParams.trail;   // w fine nie zmieniamy typu trailing
   bool useTimeStop = seedParams.useTimeStop;
   bool useDIExit   = seedParams.useDIExit;

   double beRArr[];   int beOffArr[];
   double pRArr[];    double pPctArr[];
   int atrPerArr[];   double atrMulArr[];
   int stepEveryArr[];int stepLockArr[];
   int maxBarsArr[];
   int diAdxArr[];    int diMinArr[]; int diDiffArr[];

   if(useBE){
      BuildNeighborhoodDouble(seedParams.beR, 0.1, 0.5, 1.5, beRArr);
      BuildNeighborhoodInt   (seedParams.beOffsetPts, 5, 0, 20, beOffArr);
   }
   if(usePartial){
      BuildNeighborhoodDouble(seedParams.partialR, 0.1, 0.6, 1.6, pRArr);
      BuildNeighborhoodDouble(seedParams.partialPct, 0.1, 0.2, 0.8, pPctArr);
   }
   if(trail==TRAIL_ATR){
      BuildNeighborhoodInt   (seedParams.atrPeriod, 2, 8, 30, atrPerArr);
      BuildNeighborhoodDouble(seedParams.atrMult, 0.2, 1.2, 3.5, atrMulArr);
   }
   else if(trail==TRAIL_STEP){
      BuildNeighborhoodInt(seedParams.stepEveryPts, 25, 25, 300, stepEveryArr);
      BuildNeighborhoodInt(seedParams.stepLockPts,  25, 10,  200, stepLockArr);
   }
   if(useTimeStop){
      BuildNeighborhoodInt(seedParams.maxBars, 5, 5, 40, maxBarsArr);
   }
   if(useDIExit){
      BuildNeighborhoodInt(seedParams.adxMin,  2, 10, 30, diAdxArr);
      BuildNeighborhoodInt(seedParams.diMin,   2, 10, 30, diMinArr);
      BuildNeighborhoodInt(seedParams.diDiff,  2,  3, 20, diDiffArr);
   }

   // fallback gdy puste listy
   EnsureDblArrayHasOne(beRArr,      seedParams.beR);
   EnsureIntArrayHasOne(beOffArr,    seedParams.beOffsetPts);
   EnsureDblArrayHasOne(pRArr,       seedParams.partialR);
   EnsureDblArrayHasOne(pPctArr,     seedParams.partialPct);
   EnsureIntArrayHasOne(atrPerArr,   seedParams.atrPeriod);
   EnsureDblArrayHasOne(atrMulArr,   seedParams.atrMult);
   EnsureIntArrayHasOne(stepEveryArr,seedParams.stepEveryPts);
   EnsureIntArrayHasOne(stepLockArr, seedParams.stepLockPts);
   EnsureIntArrayHasOne(maxBarsArr,  seedParams.maxBars);
   EnsureIntArrayHasOne(diAdxArr,    seedParams.adxMin);
   EnsureIntArrayHasOne(diMinArr,    seedParams.diMin);
   EnsureIntArrayHasOne(diDiffArr,   seedParams.diDiff);

   // 3) pętle tylko po aktywnych elementach
   double bestScore = -1e100;
   ExitParams bestP; CopyExitParams(bestP, seedParams);

   int beRlen   = useBE      ? ArraySize(beRArr)    : 1;
   int beOlen   = useBE      ? ArraySize(beOffArr)  : 1;
   int pRlen    = usePartial ? ArraySize(pRArr)     : 1;
   int pPctlen  = usePartial ? ArraySize(pPctArr)   : 1;
   int atrPlen  = (trail==TRAIL_ATR)  ? ArraySize(atrPerArr)   : 1;
   int atrMlen  = (trail==TRAIL_ATR)  ? ArraySize(atrMulArr)   : 1;
   int stepElen = (trail==TRAIL_STEP) ? ArraySize(stepEveryArr): 1;
   int stepLlen = (trail==TRAIL_STEP) ? ArraySize(stepLockArr) : 1;
   int maxBlen  = useTimeStop ? ArraySize(maxBarsArr) : 1;
   int diAlen   = useDIExit   ? ArraySize(diAdxArr)   : 1;
   int diMlen   = useDIExit   ? ArraySize(diMinArr)   : 1;
   int diDlen   = useDIExit   ? ArraySize(diDiffArr)  : 1;

   for(int b1=0; b1<beRlen;   ++b1)
   for(int b2=0; b2<beOlen;   ++b2)
   for(int p1=0; p1<pRlen;    ++p1)
   for(int p2=0; p2<pPctlen;  ++p2)
   for(int a1=0; a1<atrPlen;  ++a1)
   for(int a2=0; a2<atrMlen;  ++a2)
   for(int s1=0; s1<stepElen; ++s1)
   for(int s2=0; s2<stepLlen; ++s2)
   for(int tm=0; tm<maxBlen;  ++tm)
   for(int d1=0; d1<diAlen;   ++d1)
   for(int d2=0; d2<diMlen;   ++d2)
   for(int d3=0; d3<diDlen;   ++d3)
   {
      double results[]; ArrayResize(results, 0);

      for(int si=0; si<ArraySize(signals); ++si)
      {
         int i = signals[si];
         bool isBuy = (candleHistory[i].close > candleHistory[i].open);

         // Pending jak LIVE
         double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
         double margin   = inputExecuteMarginPoints * point;
         double adjusted = isBuy ? (breakout + margin) : (breakout - margin);

         // SL/TP z inputów (fallback awaryjny)
         double sl=0.0, tp=0.0;
         CalculateSLAndTP(sl, tp, inputUseSLMethod, adjusted, isBuy,
                          inputSLMultiplier, inputSLPoints, inputTPMultiplier);
         if(sl==0.0 || tp==0.0)
         {
            double range = candleHistory[i].high - candleHistory[i].low;
            double base  = MathMax(inputSLPoints*point, inputSLMultiplier*range);
            if(base<=0) base = 10*point;
            if(isBuy){ sl = adjusted - base; tp = adjusted + base*inputTPMultiplier; }
            else     { sl = adjusted + base; tp = adjusted - base*inputTPMultiplier; }
         }

         // Kandydat = seed + korekty
         ExitParams p; CopyExitParams(p, seedParams);
         if(useBE){       p.beR = beRArr[b1];         p.beOffsetPts = beOffArr[b2]; }
         if(usePartial){  p.partialR = pRArr[p1];     p.partialPct  = pPctArr[p2]; }
         if(trail==TRAIL_ATR){  p.atrPeriod = atrPerArr[a1]; p.atrMult = atrMulArr[a2]; }
         if(trail==TRAIL_STEP){ p.stepEveryPts= stepEveryArr[s1]; p.stepLockPts= stepLockArr[s2]; }
         if(useTimeStop){ p.maxBars = maxBarsArr[tm]; }
         if(useDIExit){   p.adxMin  = diAdxArr[d1];   p.diMin = diMinArr[d2]; p.diDiff = diDiffArr[d3]; }

         double pts=0.0;
         bool ok = SimulatePendingAndTradePointsAdvanced(
                     i, isBuy, adjusted, sl, tp, pts, 1,
                     p.useBE, p.beR, p.beOffsetPts,
                     p.trail, p.atrPeriod, p.atrMult, p.stepEveryPts, p.stepLockPts,
                     p.usePartial, p.partialR, p.partialPct,
                     p.useTimeStop, p.maxBars,
                     p.useDIExit, p.adxMin, p.diMin, p.diDiff
                   );
         if(ok){ int n=ArraySize(results); ArrayResize(results,n+1); results[n]=pts; }
      }

      if(ArraySize(results)==0) continue;

      double pf, dd, wr;
      double score = EvaluatePerformanceAdvanced(results, pf, dd, wr);
      if(score > bestScore)
      {
         bestScore = score;
         // ⬇️ tu JEST 'p' w zasięgu (wewnątrz pętli), ale kopiujemy bestP dopiero z „ostatniego p”
         // Aby mieć poprawny „p” do kopiowania, zróbmy to przez kopię kandydata:
         ExitParams tmp;
         // odtwórz kandydata (ten sam, co użyty do symulacji w tej iteracji):
         CopyExitParams(tmp, seedParams);
         if(useBE){       tmp.beR = beRArr[b1];         tmp.beOffsetPts = beOffArr[b2]; }
         if(usePartial){  tmp.partialR = pRArr[p1];     tmp.partialPct  = pPctArr[p2]; }
         if(trail==TRAIL_ATR){  tmp.atrPeriod = atrPerArr[a1]; tmp.atrMult = atrMulArr[a2]; }
         if(trail==TRAIL_STEP){ tmp.stepEveryPts= stepEveryArr[s1]; tmp.stepLockPts= stepLockArr[s2]; }
         if(useTimeStop){ tmp.maxBars = maxBarsArr[tm]; }
         if(useDIExit){   tmp.adxMin  = diAdxArr[d1];   tmp.diMin = diMinArr[d2]; tmp.diDiff = diDiffArr[d3]; }

         CopyExitParams(bestP, tmp);
      }
   }

   if(bestScore <= -1e90) return false;

   SaveBestExitForRegime(regime, bestP);
   CopyExitParams(bestParamsOut, bestP);
   bestScoreOut = bestScore;

   PrintFormat("🎯 FINE BEST Exit[%d]: score=%.1f | BE=%d(%.2f/%d) PART=%d(%.2f/%.2f) TR=%d(AP:%d AM:%.2f SE:%d SL:%d) TM=%d(%d) DI=%d(%d/%d/%d)",
      (int)regime,
      bestScore,
      (int)bestP.useBE, bestP.beR, bestP.beOffsetPts,
      (int)bestP.usePartial, bestP.partialR, bestP.partialPct,
      (int)bestP.trail, bestP.atrPeriod, bestP.atrMult, bestP.stepEveryPts, bestP.stepLockPts,
      (int)bestP.useTimeStop, bestP.maxBars,
      (int)bestP.useDIExit, bestP.adxMin, bestP.diMin, bestP.diDiff);

   return true;
}


// Opis: Pipeline „coarse→fine” dla wszystkich reżimów; coarse szuka seedów, fine może je doprecyzować.
// Wywołania: EffectiveScanBars, PrintFormat, OptimizeExitParametersForRegime,
//            RefineExitParametersForRegime (komentarz), SaveBestExitParamsToFile.
// Globalne/extern: candleHistory[], DebugExitOptimizer.
void OptimizeExitParametersAllRegimes_CoarseFine(int minBarsToScan = 300, bool saveToFile = true)
{
   int effScan = EffectiveScanBars(minBarsToScan);
   if(DebugExitOptimizer)
      PrintFormat("🔧 ExitOpt: request=%d, effective=%d (total=%d)",
                  minBarsToScan, effScan, ArraySize(candleHistory));

   MarketRegime regimes[4] = { REG_TREND_STRONG, REG_TREND_WEAK, REG_CHOP, REG_VOL_SPIKE };

   for(int ri=0; ri<4; ++ri)
   {
      MarketRegime R = regimes[ri];

      // 1) Coarse (szeroka siatka)
      ExitParams coarseBest; double coarseScore;
      bool okCoarse = OptimizeExitParametersForRegime(R, effScan, coarseBest, coarseScore);

      // 2) Fine (jeśli masz RefineExitParametersForRegime — zostaw; jeśli nie, można pominąć)
      if(okCoarse)
      {
         // Jeśli używasz wersji z Refine:
         // ExitParams fineBest; double fineScore;
         // bool okFine = RefineExitParametersForRegime(R, effScan, coarseBest, fineBest, fineScore);
         // if(okFine) SaveBestExitForRegime(R, fineBest);
      }
   }

   if(saveToFile) SaveBestExitParamsToFile();
}


// Opis: Alias — uruchamia coarse/fine z zapisem do pliku.
// Wywołania: OptimizeExitParametersAllRegimes_CoarseFine.
// Globalne/extern: (brak).
void OptimizeExitParameters(int minBarsToScan = 300)
{
   OptimizeExitParametersAllRegimes_CoarseFine(minBarsToScan, /*saveToFile=*/true);
}


// --- TRWAŁOŚĆ najlepszych parametrów do pliku (COMMON) ---
// Opis: Zapisuje „best exit params” dla reżimów, które mają wynik (g_hasBest/g_best) do CSV.
// Wywołania: FileOpen/FileWrite/FileClose, Print, CopyExitParams.
// Globalne/extern: g_hasBest[4], g_best[4] (z ExitPolicy.mqh).
bool SaveBestExitParamsToFile(string fname = "best_exit_params.csv")
{
   int h = FileOpen(fname, FILE_WRITE | FILE_COMMON | FILE_TXT, ';');
   if(h == INVALID_HANDLE) { Print("SaveBestExitParamsToFile: FileOpen failed"); return false; }

   // zapisujemy tylko te reżimy, które mamy
   // format: regime;useBE;beR;beOffset;usePartial;partialR;partialPct;trail;atrPeriod;atrMult;stepEvery;stepLock;useTimeStop;maxBars;useDIExit;adxMin;diMin;diDiff
   for(int r=0; r<4; ++r)
   {
      if(!g_hasBest[r]) continue;
      ExitParams p; CopyExitParams(p, g_best[r]);     // ✅ bez referencji i bez assign
      FileWrite(h,
         r,
         (int)p.useBE,     p.beR,        (int)p.beOffsetPts,
         (int)p.usePartial,p.partialR,   p.partialPct,
         (int)p.trail,     (int)p.atrPeriod, p.atrMult,
         (int)p.stepEveryPts, (int)p.stepLockPts,
         (int)p.useTimeStop, (int)p.maxBars,
         (int)p.useDIExit, (int)p.adxMin, (int)p.diMin, (int)p.diDiff
      );
   }
   FileClose(h);
   Print("💾 Zapisano best exit params do COMMON/Files/", fname);
   return true;
}

// Opis: Wczytuje „best exit params” z CSV do struktur g_best/g_hasBest.
// Wywołania: FileOpen/FileReadNumber/FileIsEnding/FileClose, Print, CopyExitParams (pośrednio przez przypis).
// Globalne/extern: g_best[4], g_hasBest[4].
bool LoadBestExitParamsFromFile(string fname = "best_exit_params.csv")
{
   int h = FileOpen(fname, FILE_READ | FILE_COMMON | FILE_TXT, ';');
   if(h == INVALID_HANDLE) { Print("LoadBestExitParamsFromFile: FileOpen failed (brak pliku?)"); return false; }

   while(!FileIsEnding(h))
   {
      int regime = (int)FileReadNumber(h);
      if(FileIsEnding(h)) break;

      ExitParams p;
      p.useBE       = (bool)FileReadNumber(h); p.beR        = FileReadNumber(h);     p.beOffsetPts = (int)FileReadNumber(h);
      p.usePartial  = (bool)FileReadNumber(h); p.partialR   = FileReadNumber(h);     p.partialPct  = FileReadNumber(h);
      p.trail       = (TrailMethod)(int)FileReadNumber(h);  p.atrPeriod = (int)FileReadNumber(h); p.atrMult = FileReadNumber(h);
      p.stepEveryPts= (int)FileReadNumber(h);  p.stepLockPts= (int)FileReadNumber(h);
      p.useTimeStop = (bool)FileReadNumber(h); p.maxBars    = (int)FileReadNumber(h);
      p.useDIExit   = (bool)FileReadNumber(h); p.adxMin     = (int)FileReadNumber(h); p.diMin = (int)FileReadNumber(h); p.diDiff = (int)FileReadNumber(h);

      if(regime >=0 && regime < 4)
      {
         g_best[regime]    = p;
         g_hasBest[regime] = true;
      }
   }
   FileClose(h);
   Print("📥 Wczytano best exit params z COMMON/Files/", fname);
   return true;
}

// ------------------------------------------------------------------
// Skan 4 reżimów „za jednym zamachem”
// ------------------------------------------------------------------
// Opis: Uruchamia OptimizeExitParametersForRegime dla czterech klasycznych reżimów.
// Wywołania: OptimizeExitParametersForRegime.
// Globalne/extern: (brak).
void OptimizeExitParametersAllRegimes(int minBarsToScan = 300)
{
   ExitParams bp; double bs;

   OptimizeExitParametersForRegime(REG_TREND_STRONG, minBarsToScan, bp, bs);
   OptimizeExitParametersForRegime(REG_TREND_WEAK,   minBarsToScan, bp, bs);
   OptimizeExitParametersForRegime(REG_CHOP,         minBarsToScan, bp, bs);
   OptimizeExitParametersForRegime(REG_VOL_SPIKE,    minBarsToScan, bp, bs);
}

// ------------------------------------------------------------------
// Alias kompatybilności (jeśli gdzieś wołałeś OptimizeExitParameters(...))
// ------------------------------------------------------------------


#endif // __EXIT_OPTIMIZER_MQH__
