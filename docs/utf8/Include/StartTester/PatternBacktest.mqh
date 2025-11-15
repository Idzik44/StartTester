//+------------------------------------------------------------------+
//|                                              PatternBacktest.mqh |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict

#ifndef __PATTERN_BACKTEST_MQH__
#define __PATTERN_BACKTEST_MQH__

#include <StartTester/CandleAndTransactionData11.mqh>
#include <StartTester/PatternOptymalizer11.mqh>
#include <StartTester/RegimeExitTypes.mqh>
#include <StartTester/ExitTypes.mqh>

// -------------------------------------------------------------------
// Opis:  Sprawdza, czy bar o indeksie i dotknął/”zahaczył” ceny 'price'
// Wywołuje: (brak)
// Używa globalnych: candleHistory[] (z CandleAndTranactionData11.mqh)
// -------------------------------------------------------------------
bool CrossedUp(double price, int i)   { return (candleHistory[i].high >= price); }

// -------------------------------------------------------------------
// Opis:  Sprawdza, czy bar o indeksie i dotknął/”zahaczył” ceny 'price'
//        od dołu (przecięcie w dół).
// Wywołuje: (brak)
// Używa globalnych: candleHistory[] (z CandleAndTranactionData11.mqh)
// -------------------------------------------------------------------
bool CrossedDown(double price, int i) { return (candleHistory[i].low  <= price); }

// -------------------------------------------------------------------
// Opis:  Symuluje zlecenie oczekujące (pending):
//        1) aktywację w oknie 'expiryBars' barów,
//        2) przebieg SL/TP po aktywacji (konserwatywnie SL przed TP).
//        Zwraca true, jeśli doszło do aktywacji; wynik w 'points' (punkty).
// Wywołuje: PrintFormat (log), MathMax (MQL5)
// Używa globalnych: 
//   - candleHistory[] (przebieg słupków),
//   - _Point (wielkość punktu, MQL5),
//   - inputSimSpreadPoints, inputSimSlippagePoints, DebugPatternBacktest (extern/input).
// -------------------------------------------------------------------
bool SimulatePendingAndTradePoints(int signalIndex,
                                   bool isBuy,
                                   double pendingPrice,
                                   double sl,
                                   double tp,
                                   double &points,
                                   int expiryBars)
{
   points = 0.0;
   int lastIdx = MathMax(signalIndex - expiryBars, 0);
   int actIdx  = -1;

   // 1) aktywacja pendinga (uwzględnij spread na BUY STOP)
   for (int i = signalIndex - 1; i >= lastIdx; --i)
   {
      double H = candleHistory[i].high;
      double L = candleHistory[i].low;
      if (isBuy) {
         double askHighApprox = H + inputSimSpreadPoints * _Point; // Ask ≈ Bid + spread
         if (askHighApprox >= pendingPrice) { actIdx = i; break; }
      } else {
         // SellStop aktywuje się na BID; niskie L wystarczy
         if (L <= pendingPrice) { actIdx = i; break; }
      }
   }
   if (actIdx == -1) {
      if (DebugPatternBacktest)
         PrintFormat("[BT] Brak aktywacji (exp=%d bar) @%.5f", expiryBars, pendingPrice);
      return false;
   }

   // 2) wejście z poślizgiem
   double entry = pendingPrice + (isBuy ?  +inputSimSlippagePoints*_Point
                                        :  -inputSimSlippagePoints*_Point);

   if (DebugPatternBacktest)
      PrintFormat("[BT] Aktywacja: idx=%d, %s @ %.5f (pending=%.5f, slip=%dpt)",
                  actIdx, isBuy?"BUY":"SELL", entry, pendingPrice, inputSimSlippagePoints);

   // 3) przebieg SL/TP (konserwatywnie: SL przed TP)
   for (int i = actIdx; i >= 0; --i)
   {
      double H = candleHistory[i].high;
      double L = candleHistory[i].low;
      if (isBuy) {
         if (L <= sl) { points = (sl - entry) / _Point;  return true; }
         if (H >= tp) { points = (tp - entry) / _Point;  return true; }
      } else {
         if (H >= sl) { points = (entry - sl) / _Point;  return true; }
         if (L <= tp) { points = (entry - tp) / _Point;  return true; }
      }
   }

   points = 0.0;
   return true;
}


// -------------------------------------------------------------------
// Opis:  Obcięta średnia (trimmed mean) — usuwa alfa-część elementów
//        skrajnych (z dołu i z góry) i liczy średnią ze środka.
// Wywołuje: ArraySize, ArrayResize, ArraySort (MQL5), MathFloor
// Używa globalnych: (brak)
// -------------------------------------------------------------------
double __TrimmedMean(const double &a[], double alpha)
{
   int n = ArraySize(a);
   if (n == 0) return 0.0;
   double t[]; ArrayResize(t, n);
   for (int i=0;i<n;i++) t[i]=a[i];
   ArraySort(t); // rosnąco

   int k = (int)MathFloor(alpha * n);
   int from = k;
   int to   = n - k - 1;
   if (from > to) { from = 0; to = n-1; }

   double s=0.0; int c=0;
   for (int i=from;i<=to;i++){ s+=t[i]; c++; }
   return (c>0 ? s/c : 0.0);
}

// -------------------------------------------------------------------
// Opis:  Zwraca długość najdłuższej serii strat w tablicy wyników.
// Wywołuje: ArraySize (MQL5)
// Używa globalnych: (brak)
// -------------------------------------------------------------------
int __MaxLosingStreak(const double &a[])
{
   int n = ArraySize(a), cur=0, mx=0;
   for (int i=0;i<n;i++){
      if (a[i] < 0) { cur++; if (cur>mx) mx=cur; }
      else cur=0;
   }
   return mx;
}

// -------------------------------------------------------------------
// Opis:  Ocena jakości wyników (punkty): łączy obciętą średnią,
//        winrate, średni zysk/stratę i karę za serię strat w jeden score.
// Wywołuje: __TrimmedMean, __MaxLosingStreak, PrintFormat (log), ArraySize
// Używa globalnych: DebugPatternBacktest (extern/input)
// -------------------------------------------------------------------
double EvaluatePerformance(const double &profits[])
{
   int n = ArraySize(profits);
   if (n == 0) return -1.0;

   double sum=0.0, profitSum=0.0, lossSum=0.0;
   int wins=0, losses=0;
   for (int i=0;i<n;i++){
      double p = profits[i];
      sum += p;
      if (p > 0) { profitSum += p; wins++; }
      else if (p < 0) { lossSum += -p; losses++; }
   }
   if (wins + losses == 0) return -1.0;

   double avgProfit = (wins   >0 ? profitSum/wins   : 0.0);
   double avgLoss   = (losses >0 ? lossSum  /losses : 0.0);
   double winrate   = (double)wins / (wins + losses);

   // Nowości:
   double tmean     = __TrimmedMean(profits, 0.10);      // 10% obcięcia z obu stron
   int    maxLS     = __MaxLosingStreak(profits);        // długość najdłuższej serii strat
   double penLS     = 0.35 * maxLS * avgLoss;            // kara za serie strat

   // końcowy score (stabilniejszy niż goła suma)
   double score = (tmean * n) + (avgProfit * winrate * 2.0) - (avgLoss * (1.0 - winrate)) - penLS;

   if (DebugPatternBacktest)
      PrintFormat("📊 BT: n=%d | sum=%.1f | win=%.1f%% | avgP=%.1f avgL=%.1f | tmean=%.1f | maxLS=%d | score=%.1f",
                  n, sum, 100.0*winrate, avgProfit, avgLoss, tmean, maxLS, score);

   return score;
}


// -------------------------------------------------------------------
// Opis:  Zaawansowana symulacja: pending + BE + trailing + partial +
//        time stop + wyjście na odwróceniu DI. Zwraca true, jeśli
//        doszło do aktywacji; wynik w punktach w 'pointsOut'.
// Wywołuje: Array/MQL5 (ArraySize/Resize), Math*, SymbolInfoDouble,
//           GetCustomADXAt/GetCustomPlusDIAt/GetCustomMinusDIAt (z CandleAndTranactionData11.mqh),
//           Print/PrintFormat (pośrednio), funkcje pomocnicze wewn.
// Używa globalnych:
//   - candleHistory[], _Symbol, _Point,
//   - (pośrednio) wartości DI/ADX z buforów własnych systemu.
// -------------------------------------------------------------------
bool SimulatePendingAndTradePointsAdvanced(int signalIndex,
                                           bool isBuy,
                                           double pendingPrice,
                                           double entrySL,
                                           double entryTP,
                                           double &pointsOut,
                                           int expiryBars,
                                           // parametry wyjścia:
                                           bool useBE, double beR, int beOffsetPts,
                                           TrailMethod tMethod, int atrPeriod, double atrMult,
                                           int stepEveryPts, int stepLockPts,
                                           bool usePartial, double partialR, double partialPct,
                                           bool useTimeStop, int maxBars,
                                           bool useOppositeDI,
                                           int exitAdxMin, int exitDiMin, int exitDiDiff)
{
   pointsOut = 0.0;

   // 1) aktywacja pendinga
   int actIdx = -1;
   int lastIdx = MathMax(signalIndex - expiryBars, 0);
   for(int i=signalIndex-1; i>=lastIdx; --i)
   {
      double H=candleHistory[i].high, L=candleHistory[i].low;
      if( isBuy && H>=pendingPrice ) { actIdx=i; break; }
      if(!isBuy && L<=pendingPrice ) { actIdx=i; break; }
   }
   if(actIdx==-1) return false;

   // 2) po aktywacji – bieżące SL/TP
   double entry = pendingPrice;
   double sl    = entrySL;
   double tp    = entryTP;

   // partial – “udział” wolumenu po częściowym wyjściu
   bool partialDone=false;
   double partialWeight = 1.0;      // w uproszczeniu: 100% wolumenu; po partialu: 50% w dalszej części
   double closedPoints  = 0.0;      // wynik z zamkniętej części

   // liczymy R (risk) względem startowego SL
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double risk  = MathAbs(entry - sl);
   if(risk<=0) risk = 10*point;

   // 3) iteruj po kolejnych barach
   int bars=0;
   for(int i=actIdx; i>=0; --i)
   {
      ++bars;
      double H=candleHistory[i].high, L=candleHistory[i].low;
      double priceForTrail = isBuy ? H : L; // optymistycznie trailing po ekstrema

      // 3a) partial TP
      if(usePartial && !partialDone)
      {
         double move = MathAbs(priceForTrail - entry);
         double rNow = move / risk;
         if(rNow >= partialR)
         {
            // zamknij część po aktualnej cenie (punkty)
            double p = isBuy ? (priceForTrail - entry) : (entry - priceForTrail);
            closedPoints += p * partialPct;        // zaksięguj część zysku
            partialWeight = 1.0 - partialPct;      // zostaje X% pozycji
            partialDone = true;
         }
      }

      // 3b) BE
      if(useBE)
      {
         double move = MathAbs(priceForTrail - entry);
         double rNow = move / risk;
         if(rNow >= beR)
         {
            double be = isBuy ? (entry + beOffsetPts*point) : (entry - beOffsetPts*point);
            if( (isBuy && be>sl) || (!isBuy && be<sl) ) sl = be;
         }
      }

      // 3c) Trailing
      if(tMethod!=TRAIL_NONE)
      {
         if(tMethod==TRAIL_ATR)
         {
            // ATR z perspektywy i+1, i+2 ...
            int period = atrPeriod;                       // ✅ używamy parametru funkcji
            int atrIdx = MathMin(i, ArraySize(candleHistory)-period-2);
            double atr=0.0;
            if(period>0 && atrIdx+period+1 < ArraySize(candleHistory))
            {
               double sum=0;
               for(int k=atrIdx; k<atrIdx+period; ++k)
               {
                  double h=candleHistory[k].high, l=candleHistory[k].low, pc=candleHistory[k+1].close;
                  double tr1=h-l, tr2=MathAbs(h-pc), tr3=MathAbs(l-pc);
                  sum += MathMax(tr1, MathMax(tr2,tr3));
               }
               atr = sum/period;
            }
            if(atr>0)
            {
               double candidate = isBuy ? priceForTrail - atrMult*atr
                                        : priceForTrail + atrMult*atr;
               if( (isBuy && candidate>sl) || (!isBuy && candidate<sl) )
                  sl = candidate;
            }
         }
         else if(tMethod==TRAIL_CANDLE)
         {
            if(i+1 < ArraySize(candleHistory))
            {
               double buffer=5*point;
               double base = isBuy ? candleHistory[i+1].low - buffer
                                   : candleHistory[i+1].high + buffer;
               if( (isBuy && base>sl) || (!isBuy && base<sl) )
                  sl = base;
            }
         }
         else if(tMethod==TRAIL_STEP)
         {
            double advance = MathFloor(MathAbs(priceForTrail - entry)/(stepEveryPts*point)) * stepLockPts*point;
            double base    = isBuy ? (entry + advance) : (entry - advance);
            if( (isBuy && base>sl) || (!isBuy && base<sl) )
               sl = base;
         }
      }

      // 3d) wyjście “twarde”
      // DI odwrócenie
      if(useOppositeDI)
      {
         double adx = GetCustomADXAt(i);
         double pdi = GetCustomPlusDIAt(i);
         double mdi = GetCustomMinusDIAt(i);
         double d   = MathAbs(pdi-mdi);
         if(adx>=exitAdxMin && pdi>=exitDiMin && mdi>=exitDiMin)
         {
            if( (isBuy && (mdi>pdi) && d>=exitDiDiff) ||
                (!isBuy && (pdi>mdi) && d>=exitDiDiff) )
            {
               // zamykamy po cenie “priceForTrail”
               double p = isBuy ? (priceForTrail - entry) : (entry - priceForTrail);
               pointsOut = closedPoints + p*partialWeight;
               return true;
            }
         }
      }

      if(useTimeStop && bars>=maxBars)
      {
         double p = isBuy ? (priceForTrail - entry) : (entry - priceForTrail);
         pointsOut = closedPoints + p*partialWeight;
         return true;
      }

      // 3e) SL / TP
      // kolejność konserwatywna: SL najpierw
      if( (isBuy && L<=sl) || (!isBuy && H>=sl) )
      {
         double p = isBuy ? (sl - entry) : (entry - sl);
         pointsOut = closedPoints + p*partialWeight;
         return true;
      }
      if( (isBuy && H>=tp) || (!isBuy && L<=tp) )   // ✅ używamy zmiennej tp, nie literówki entryTP
      {
         double p = isBuy ? (tp - entry) : (entry - tp);
         pointsOut = closedPoints + p*partialWeight;
         return true;
      }
   }

   // nie padł SL/TP ani twarde warunki – rozlicz po ostatniej znanej cenie
   double last = candleHistory[0].close;
   double pEnd = isBuy ? (last - entry) : (entry - last);
   pointsOut = closedPoints + pEnd*partialWeight;
   return true;
}

// ===============================
// Backtest: pełna symulacja z polityką wyjścia (pending->aktywacja->SL/TP/trailing)
// ===============================

// -------------------------------------------------------------------
// Opis:  Pomocniczo: konwersja punktów (pts) na cenę w pipetach (pts*_Point).
// Wywołuje: (brak)
// Używa globalnych: _Point
// -------------------------------------------------------------------
double __Pts(double pts) { return pts * _Point; }

// -------------------------------------------------------------------
// Opis:  Prosty ATR wstecz (True Range uśredniony) z okna [centerShift..centerShift+period].
// Wywołuje: ArraySize, MathMax, MathAbs
// Używa globalnych: candleHistory[]
// -------------------------------------------------------------------
double __ATR_Back(int centerShift, int period)
{
   int total = ArraySize(candleHistory);
   if (period <= 1 || centerShift + period >= total) return 0.0;
   double sumTR = 0.0;
   for (int k = centerShift; k < centerShift + period; ++k) {
      double h  = candleHistory[k].high;
      double l  = candleHistory[k].low;
      double pc = candleHistory[k+1].close;
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      sumTR += tr;
   }
   return sumTR / period;
}

// -------------------------------------------------------------------
// Opis:  Najwyższe high z zakresu [fromShift .. fromShift+bars).
// Wywołuje: ArraySize, MathMax
// Używa globalnych: candleHistory[]
// -------------------------------------------------------------------
double __HighestHigh_Back(int fromShift, int bars)
{
   int total = ArraySize(candleHistory);
   double hh = candleHistory[fromShift].high;
   for (int k = fromShift; k < fromShift + bars && k < total; ++k)
      hh = MathMax(hh, candleHistory[k].high);
   return hh;
}

// -------------------------------------------------------------------
// Opis:  Najniższe low z zakresu [fromShift .. fromShift+bars).
// Wywołuje: ArraySize, MathMin
// Używa globalnych: candleHistory[]
// -------------------------------------------------------------------
double __LowestLow_Back(int fromShift, int bars)
{
   int total = ArraySize(candleHistory);
   double ll = candleHistory[fromShift].low;
   for (int k = fromShift; k < fromShift + bars && k < total; ++k)
      ll = MathMin(ll, candleHistory[k].low);
   return ll;
}

// -------------------------------------------------------------------
// Opis:  Szuka świecy aktywacji zlecenia oczekującego (pending) w oknie
//        'expiryBars' za sygnałem i (uwzględnia spread dla BUY).
// Wywołuje: MathMax
// Używa globalnych: candleHistory[], inputSimSpreadPoints, _Point
// -------------------------------------------------------------------
int __FindActivationShift(int i, bool isBuy, double entryPrice, int expiryBars)
{
   for (int j = i - 1; j >= MathMax(1, i - expiryBars); --j) {
      double H = candleHistory[j].high;
      double L = candleHistory[j].low;
      if (isBuy) {
         double askHighApprox = H + inputSimSpreadPoints * _Point;
         if (askHighApprox >= entryPrice) return j;
      } else {
         if (L <= entryPrice) return j;
      }
   }
   return -1;
}


// -------------------------------------------------------------------
// Opis:  Główna funkcja backtestowa pozycji: symulacja od aktywacji
//        pendinga, przez modyfikacje SL w zależności od polityki
//        (ATR/SWING/HYBRID), częściowe wyjścia, BE, time-stop, aż do
//        wyjścia (SL/TP/close na barze 1). Zwraca true jeśli aktywowano.
// Wywołuje: __FindActivationShift, __Pts, __ATR_Back, __HighestHigh_Back,
//           __LowestLow_Back, ArraySize/Math* (MQL5)
// Używa globalnych:
//   - candleHistory[], _Point,
//   - inputSimSlippagePoints (slippage dla wejścia),
//   - Exit_ATR_Period, Exit_Swing_N_Default, Exit_Swing_OffsetPts (parametry domyślne z modułów wyjścia).
// -------------------------------------------------------------------
bool SimulateTradeWithExit(int i, bool isBuy, double entryPrice, double slInit, double tpInit,
                           ExitPolicy pol,
                           const ExitParamsATR &pATR,
                           const ExitParamsSW  &pSW,
                           const ExitParamsHYB &pHYB,
                           double &points, int expiryBars)
{
   points = 0.0;

   // 1) Aktywacja pendinga w oknie expiryBars
   int act = __FindActivationShift(i, isBuy, entryPrice, expiryBars);
   if (act < 0) return false;

   // 2) Wejście z poślizgiem (slippage) względem ceny pendinga
   double entry = entryPrice + (isBuy ? +inputSimSlippagePoints * _Point
                                      : -inputSimSlippagePoints * _Point);

   // 3) Stany początkowe
   double sl = slInit, tp = tpInit;
   double oneR  = MathMax(1e-8, MathAbs(entry - slInit)); // ryzyko na 1R liczone od ENTRY
   double exitPx = entry;

   // Częściowa realizacja (hybrydowe wyjście)
   bool   partialDone = false;
   double partFrac    = MathMax(0.0, MathMin(1.0, pHYB.partialFrac));
   double partExitPx  = entry;

   bool exited = false;

   // 4) Przebieg po aktywacji aż do świecy 1
   for (int j = act; j >= 1; --j)
   {
      double closej = candleHistory[j].close;
      double highj  = candleHistory[j].high;
      double lowj   = candleHistory[j].low;

      // postęp w R względem ENTRY
      double move = isBuy ? (closej - entry) : (entry - closej);
      double rNow = (oneR > 0.0 ? move / oneR : 0.0);

      int bars_elapsed = (act - j);

      // 4a) TIME-STOP (HYBRID)
      if (pol == EXIT_HYBRID && pHYB.timeStopBars > 0) {
         if (bars_elapsed >= pHYB.timeStopBars && rNow < pHYB.timeStopMinR) {
            exitPx = closej;
            exited = true;
            break;
         }
      }

      // 4b) PARTIAL (HYBRID) — jednorazowo przy osiągnięciu TP1 (w R)
      if (pol == EXIT_HYBRID && pHYB.tp1R > 0.0 && !partialDone && partFrac > 0.0) {
         if (rNow >= pHYB.tp1R) {
            partialDone = true;
            partExitPx  = closej; // realizujemy po cenie close bara
         }
      }

      // 4c) Trailing / BE wg polityki
      if (pol == EXIT_ATR)
      {
         int period = (pATR.atrPeriod > 0 ? pATR.atrPeriod : Exit_ATR_Period);
         double atr = __ATR_Back(j, period);
         if (atr > 0.0) {
            double cand = isBuy ? (closej - pATR.kATR * atr)
                                : (closej + pATR.kATR * atr);
            sl = isBuy ? MathMax(sl, cand) : MathMin(sl, cand);
         }
      }
      else if (pol == EXIT_SWING)
      {
         int swingN  = (pSW.swingN > 0 ? pSW.swingN : Exit_Swing_N_Default);
         int offsPts = pSW.offsetPts;
         if (isBuy) {
            double ll   = __LowestLow_Back(j, swingN);
            double base = ll - __Pts(offsPts);
            if (base > sl) sl = base;
         } else {
            double hh   = __HighestHigh_Back(j, swingN);
            double base = hh + __Pts(offsPts);
            if (base < sl) sl = base;
         }
      }
      else if (pol == EXIT_HYBRID)
      {
         // Break-even po osiągnięciu określonego R
         if (pHYB.beAfterR > 0.0 && rNow >= pHYB.beAfterR) {
            double be = isBuy ? (entry + __Pts((int)MathMax(2, Exit_Swing_OffsetPts)))
                              : (entry - __Pts((int)MathMax(2, Exit_Swing_OffsetPts)));
            sl = isBuy ? MathMax(sl, be) : MathMin(sl, be);
         }

         // ATR trailing
         double atr = __ATR_Back(j, Exit_ATR_Period);
         if (atr > 0.0) {
            double cand = isBuy ? (closej - pHYB.trailATRk * atr)
                                : (closej + pHYB.trailATRk * atr);
            sl = isBuy ? MathMax(sl, cand) : MathMin(sl, cand);
         }
      }

      // 4d) Kolejność w barze: najpierw SL, potem TP (konserwatywnie)
      if (isBuy) {
         if (lowj <= sl) { exitPx = sl; exited = true; break; }
         if (tp > 0.0 && highj >= tp) { exitPx = tp; exited = true; break; }
      } else {
         if (highj >= sl) { exitPx = sl; exited = true; break; }
         if (tp > 0.0 && lowj  <= tp) { exitPx = tp; exited = true; break; }
      }
   }

   // 5) Jeśli nie wyszliśmy wcześniej — zamknięcie na close świecy 1
   if (!exited)
      exitPx = candleHistory[1].close;

   // 6) Wynik w punktach (z uwzględnieniem częściowej realizacji)
   if (partialDone) {
      double legA = partFrac        * ((isBuy ? (partExitPx - entry) : (entry - partExitPx)) / _Point);
      double legB = (1.0 - partFrac) * ((isBuy ? (exitPx     - entry) : (entry - exitPx    )) / _Point);
      points = legA + legB;
   } else {
      points = (isBuy ? (exitPx - entry) : (entry - exitPx)) / _Point;
   }

   return true;
}

#endif
