//+------------------------------------------------------------------+
//|                        ExitManager.mqh                           |
//| Zaawansowane zarządzanie wyjściem: BE, trailing, partial, time  |
//+------------------------------------------------------------------+
#property strict

#ifndef __EXIT_MANAGER_MQH__
#define __EXIT_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include <StartTester/CandleAndTransactionData11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>
#include <StartTester/RegimeDetector.mqh>
#include <StartTester/ExitTypes.mqh>   // enum TrailMethod
#include <StartTester/ExitPolicy.mqh>  // struct ExitParams + load/save best


// ---- USTAWIENIA (inputs) ----
input bool UseExitManager         = true;    // włącz ExitManager

input bool UseBreakeven           = true;    //włącz Breakeven
input double BE_Trigger_R         = 1.0;     // po ilu %R przesunąć do BE
input int BE_OffsetPoints         = 5;       // BE +/– offset względem ceny wejścia (w punktach)

input bool UsePartialTP           = true;    //włącz PartialTP
input double PartialTP_R          = 1.0;     // pierwsze TP po %R
input double PartialTP_Percent    = 0.50;    // zamknij % pozycji

input TrailMethod UseTrailing     = TRAIL_ATR; //

input int ATR_Period              = 14;
input double ATR_Multiplier       = 2.0;

input int TrailStepEveryPoints    = 100;     // co ile punktów dociągać
input int TrailStepLockPoints     = 50;      // ile punktów “zablokować” od dołu/góry

input bool UseTimeStop            = true;    // wyjśice po xSwiecach
input int MaxBarsInTrade          = 30;      // zamknij po X świecach

input bool UseOppositeDIExit      = true;
input int ExitAdxMin              = 15;
input int ExitDiMin               = 15;
input int ExitDiDiff              = 5;

// (opcjonalnie) zamknij przy zmianie sesji
input bool UseSessionCloseExit    = false;

// -------------------------------------------------------------------
// OPIS: Powiązanie „ticket → parametry wyjścia + reżim”.
// Używane przez: EnsureBindingForPosition(), ManageOpenPositions().
// -------------------------------------------------------------------
struct ExitBinding {
   ulong ticket;
   ExitParams params;
   MarketRegime regime;
   bool initialized;
};
ExitBinding g_exitBindings[];

// -------------------------------------------------------------------
// OPIS FUNKCJI: FindBinding
// Co robi: Szuka istniejącego wiązania ticket→ExitParams/Regime.
// Woła: (brak).
// Używa: g_exitBindings (tablica).
// Zwraca: indeks wiązania lub -1.
// -------------------------------------------------------------------
int FindBinding(ulong ticket) {
   for(int i=ArraySize(g_exitBindings)-1;i>=0;--i)
      if(g_exitBindings[i].ticket==ticket) return i;
   return -1;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: EnsureBindingForPosition
// Co robi: Tworzy/aktualizuje wiązanie dla pozycji. Klasyfikuje reżim (1 bar wstecz),
//          ładuje najlepsze parametry dla reżimu, wyłącza partial gdy wolumen nie pozwala.
// Woła: FindBinding, GetRegimeFeatures(shift,f), ClassifyRegime(f), LoadBestExitForRegime(r,p),
//       CanPartialByLot(), ArrayResize, CopyExitParams.
// Używa: g_exitBindings[], candleHistory (pośrednio przez klasyfikację).
// Zwraca: void.
// -------------------------------------------------------------------
void EnsureBindingForPosition(ulong ticket, bool isBuy)
{
   int idx = FindBinding(ticket);
   if(idx>=0 && g_exitBindings[idx].initialized) return;

   // ustal reżim i wczytaj najlepsze parametry
   RegimeFeatures f; 
   GetRegimeFeatures(1, f);
   MarketRegime r = ClassifyRegime(f);

   ExitParams p;                 // deklaracja bez inicjalizacji
   LoadBestExitForRegime(r, p);  // wypełnienie out-param

   // partial tylko gdy wolumen pozwala
   if(!CanPartialByLot()) p.usePartial = false;

   if(idx < 0)
   {
      int slot = ArraySize(g_exitBindings);
      ArrayResize(g_exitBindings, slot + 1);

      g_exitBindings[slot].ticket = ticket;
      CopyExitParams(g_exitBindings[slot].params, p);
      g_exitBindings[slot].regime = r;
      g_exitBindings[slot].initialized = true;
   }
   else
   {
      CopyExitParams(g_exitBindings[idx].params, p);
      g_exitBindings[idx].regime = r;
      g_exitBindings[idx].initialized = true;
   }
}


// ---- WEWNĘTRZNE ----
CTrade tradeExit;

// --- Jednorazowość partial TP per ticket ---
ulong g_partialDoneTickets[];

// -------------------------------------------------------------------
// OPIS FUNKCJI: PartialAlreadyDone
// Co robi: Sprawdza, czy dla ticket wykonano już częściowe wyjście.
// Woła: (brak).
// Używa: g_partialDoneTickets.
// Zwraca: true/false.
// -------------------------------------------------------------------
bool PartialAlreadyDone(ulong ticket) {
   for (int i = ArraySize(g_partialDoneTickets) - 1; i >= 0; --i)
      if (g_partialDoneTickets[i] == ticket) return true;
   return false;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MarkPartialDone
// Co robi: Oznacza ticket jako obsłużony (partial TP wykonany).
// Woła: ArrayResize.
// Używa: g_partialDoneTickets.
// Zwraca: void.
// -------------------------------------------------------------------
void MarkPartialDone(ulong ticket) {
   int n = ArraySize(g_partialDoneTickets);
   ArrayResize(g_partialDoneTickets, n + 1);
   g_partialDoneTickets[n] = ticket;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: GetATR
// Co robi: Lokalny, prosty ATR na bazie candleHistory – średnia TR z ostatnich 'period'
//          barów od 'index' (używa TR=max(high-low,|high-prevClose|,|low-prevClose|)).
// Woła: ArraySize, MathAbs, MathMax.
// Używa: candleHistory[].
// Zwraca: ATR (double) lub 0.0 gdy za mało danych.
// -------------------------------------------------------------------
double GetATR(int period, int index=1)
{
   // prosta wersja ATR na bazie candleHistory (True Range 1-barowy * EMA pseudo)
   int total = ArraySize(candleHistory);
   if(total < period+index+2) return 0.0;

   double trSum = 0.0;
   for(int i=index; i<index+period; ++i)
   {
      double h = candleHistory[i].high;
      double l = candleHistory[i].low;
      double pc= candleHistory[i+1].close;
      double tr1 = h - l;
      double tr2 = MathAbs(h - pc);
      double tr3 = MathAbs(l - pc);
      trSum += MathMax(tr1, MathMax(tr2, tr3));
   }
   return trSum/period;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: GetPositionByMagic
// Co robi: Wyszukuje pozycję po magicu i symbolu; zwraca podstawowe parametry.
// Woła: PositionsTotal, PositionGetTicket, PositionSelectByTicket, PositionGetString/Integer/Double.
// Używa: (brak globali).
// Zwraca: true/false + parametry przez referencję.
// -------------------------------------------------------------------
bool GetPositionByMagic(ulong magic, string symbol, ulong &ticket, bool &isBuy,
                        double &entry, double &sl, double &tp, datetime &timeOpen)
{
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong t = PositionGetTicket(i);
      if(t>0 && PositionSelectByTicket(t))
      {
         if(PositionGetString(POSITION_SYMBOL)==symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)magic)
         {
            ticket   = t;
            isBuy    = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
            entry    = PositionGetDouble(POSITION_PRICE_OPEN);
            sl       = PositionGetDouble(POSITION_SL);
            tp       = PositionGetDouble(POSITION_TP);
            timeOpen = (datetime)PositionGetInteger(POSITION_TIME);
            return true;
         }
      }
   }
   return false;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: BarsSince
// Co robi: Zwraca liczbę zamkniętych świec od chwili 't' licząc po candleHistory.
// Woła: ArraySize.
// Używa: candleHistory[].
// Zwraca: liczba barów (int).
// -------------------------------------------------------------------
int BarsSince(datetime t)
{
   // policz ile świec zamknięto od czasu t
   for(int i=1;i<ArraySize(candleHistory);++i)
      if(candleHistory[i].time<=t) return i-1;
   return 0;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeMoveToBreakeven
// Co robi: Warunkowo przesuwa SL do BE wg globali (UseBreakeven, BE_Trigger_R, BE_OffsetPoints).
// Woła: SymbolInfoDouble, PositionGetDouble, tradeExit.PositionModify, MathAbs.
// Używa: UseBreakeven, BE_Trigger_R, BE_OffsetPoints, _Symbol, tradeExit.
// Zwraca: void (aktualizuje &sl).
// UWAGA: zakłada, że odpowiednia pozycja jest już wybrana (PositionSelectByTicket wcześniej).
// -------------------------------------------------------------------
void MaybeMoveToBreakeven(ulong ticket, bool isBuy, double entry, double &sl)
{
   if(!UseBreakeven) return;
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double move  = MathAbs(price - entry);
   double risk  = MathAbs(entry - sl);
   if(risk<=0) return;

   double rNow = move / risk;
   if(rNow >= BE_Trigger_R)
   {
      double be = isBuy ? (entry + BE_OffsetPoints*point) : (entry - BE_OffsetPoints*point);
      if((isBuy && (sl<be)) || (!isBuy && (sl>be)))
      {
         tradeExit.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
         sl = be;
      }
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybePartialTP
// Co robi: Jednorazowe częściowe wyjście wg globali (UsePartialTP, PartialTP_R, PartialTP_Percent).
// Woła: PartialAlreadyDone, SymbolInfoDouble, PositionGetDouble, MathAbs/MathFloor/MathMax,
//       tradeExit.PositionClosePartial, MarkPartialDone.
// Używa: _Symbol, tradeExit, g_partialDoneTickets.
// Zwraca: void.
// UWAGA: zakłada wcześniejsze PositionSelectByTicket dla poprawnego PositionGetDouble().
// -------------------------------------------------------------------
void MaybePartialTP(ulong ticket, bool isBuy, double entry, double sl)
{
   if(!UsePartialTP) return;
   if(PartialAlreadyDone(ticket)) return; // jednorazowo

   double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double move  = MathAbs(price - entry);
   double risk  = MathAbs(entry - sl);
   if(risk <= 0) return;

   double rNow = move / risk;
   if(rNow >= PartialTP_R)
   {
      double volume = PositionGetDouble(POSITION_VOLUME);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double closeVol = MathMax(minLot, MathFloor(volume*PartialTP_Percent/step)*step);

      if(closeVol > 0 && closeVol < volume)
      {
         if(tradeExit.PositionClosePartial(ticket, closeVol))
            MarkPartialDone(ticket);
      }
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeTrail
// Co robi: Trailing stop wg globalnych ustawień (TRAIL_ATR / TRAIL_CANDLE / TRAIL_STEP).
// Woła: SymbolInfoDouble, PositionGetDouble, GetATR, MathFloor, tradeExit.PositionModify.
// Używa: UseTrailing, ATR_Period, ATR_Multiplier, TrailStepEveryPoints, TrailStepLockPoints,
//        candleHistory[], _Symbol, tradeExit.
// Zwraca: void (aktualizuje &sl).
// -------------------------------------------------------------------
void MaybeTrail(ulong ticket, bool isBuy, double &sl)
{
   if(UseTrailing==TRAIL_NONE) return;
   double newSL = sl;

   if(UseTrailing==TRAIL_ATR)
   {
      double atr = GetATR(ATR_Period, 1);
      if(atr<=0) return;
      double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double candidate = isBuy ? price - ATR_Multiplier*atr : price + ATR_Multiplier*atr;
      if( (isBuy  && candidate>sl) || (!isBuy && candidate<sl) )
         newSL = candidate;
   }
   else if(UseTrailing==TRAIL_CANDLE)
   {
      // po zamknięciu każdej świecy: SL za minimum/maksimum poprzedniej świecy ± buffer 5 punktów
      double buffer = 5*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      double base   = isBuy ? candleHistory[2].low - buffer : candleHistory[2].high + buffer;
      if( (isBuy && base>sl) || (!isBuy && base<sl) )
         newSL = base;
   }
   else if(UseTrailing==TRAIL_STEP)
   {
      double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double advance = MathFloor(MathAbs(price - entry)/(TrailStepEveryPoints*point)) * TrailStepLockPoints*point;
      double base    = isBuy ? (entry + advance) : (entry - advance);
      if( (isBuy && base>sl) || (!isBuy && base<sl) )
         newSL = base;
   }

   if(newSL!=sl)
   {
      tradeExit.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      sl = newSL;
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeOppositeDIExit
// Co robi: „Twarde” wyjście na podstawie przeciwnych wskazań DI/ADX wg globali.
// Woła: GetCustomADXAt, GetCustomPlusDIAt, GetCustomMinusDIAt, MathAbs.
// Używa: UseOppositeDIExit, ExitAdxMin, ExitDiMin, ExitDiDiff.
// Zwraca: true (wyjść) / false (nie wychodzić).
// -------------------------------------------------------------------
bool MaybeOppositeDIExit(bool isBuy)
{
   if(!UseOppositeDIExit) return false;
   int i = 1;
   double adx = GetCustomADXAt(i);
   double plusDI = GetCustomPlusDIAt(i);
   double minusDI= GetCustomMinusDIAt(i);
   double diff   = MathAbs(plusDI - minusDI);

   if(adx<ExitAdxMin) return false;
   if(plusDI<ExitDiMin && minusDI<ExitDiMin) return false;

   // Wyjście gdy DI stanowczo odwrócił się przeciwko
   if( isBuy && (minusDI>plusDI) && diff>=ExitDiDiff ) return true;
   if(!isBuy && (plusDI>minusDI)  && diff>=ExitDiDiff ) return true;
   return false;
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeTimeStop
// Co robi: Sprawdza limit czasu w pozycji (time-stop) wg globali UseTimeStop/MaxBarsInTrade.
// Woła: BarsSince.
// Używa: UseTimeStop, MaxBarsInTrade.
// Zwraca: true/false.
// -------------------------------------------------------------------
bool MaybeTimeStop(datetime openTime)
{
   if(!UseTimeStop) return false;
   int bars = BarsSince(openTime);
   return (bars >= MaxBarsInTrade);
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeSessionClose
// Co robi: Hak pod „zamknij przy zmianie sesji” (na razie tylko zwraca false).
// Woła: (brak).
// Używa: UseSessionCloseExit.
// Zwraca: false.
// -------------------------------------------------------------------
bool MaybeSessionClose()
{
   if(!UseSessionCloseExit) return false;
   // Prosto: zamknij przy zmianie sesji (wywołuj po detekcji zmiany sesji)
   // Zakładamy, że logika zmiany sesji jest gdzie indziej – tutaj tylko hook.
   return false;
}

// ---- PUBLIC API ----

// -------------------------------------------------------------------
// OPIS FUNKCJI: ManageOpenPositions
// Co robi: Główna pętla zarządzania wyjściem dla wszystkich pozycji z danym magic number.
//          Kolejność: BE → Partial → Trailing → wyjścia twarde (DI/time-stop).
// Woła: PositionsTotal, PositionGetTicket, PositionSelectByTicket, PositionGet*,
//       EnsureBindingForPosition, FindBinding, CopyExitParams,
//       MaybeMoveToBreakevenWithParams, MaybePartialTPWithParams, MaybeTrailWithParams,
//       MaybeOppositeDIExitWithParams, BarsSince, tradeExit.PositionClose.
// Używa: UseExitManager, _Symbol, tradeExit, g_exitBindings[].
// Zwraca: void.
// -------------------------------------------------------------------
void ManageOpenPositions(ulong magic)
{
   if(!UseExitManager) return;

   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)magic) continue;

      bool isBuy = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      EnsureBindingForPosition(ticket, isBuy);
      int b = FindBinding(ticket);
      if(b<0) continue; // ochronnie

      ExitParams p;                                      // deklaracja bez inicjalizacji
      CopyExitParams(p, g_exitBindings[b].params);       // bezpieczna kopia pól (z ExitPolicy.mqh)


      // kolejność: BE -> partial -> trailing -> wyjścia twarde
      MaybeMoveToBreakevenWithParams(ticket, isBuy, entry, sl, p);
      MaybePartialTPWithParams(ticket, isBuy, entry, sl, p);
      MaybeTrailWithParams(ticket, isBuy, sl, p);

      // twarde
      if( MaybeOppositeDIExitWithParams(isBuy, p) ||
          (p.useTimeStop && BarsSince(openTime) >= p.maxBars) )
      {
         tradeExit.PositionClose(ticket);
      }
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeMoveToBreakevenWithParams
// Co robi: Przesuwa SL do BE na podstawie ExitParams (zamiast globali).
// Woła: SymbolInfoDouble, PositionGetDouble, tradeExit.PositionModify, MathAbs.
// Używa: _Symbol, tradeExit.
// Zwraca: void (aktualizuje &sl).
// UWAGA: zakłada wcześniejsze PositionSelectByTicket.
// -------------------------------------------------------------------
void MaybeMoveToBreakevenWithParams(ulong ticket, bool isBuy, double entry, double &sl, const ExitParams &p) {
   if(!p.useBE) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double move  = MathAbs(price - entry);
   double risk  = MathAbs(entry - sl);
   if(risk<=0) return;

   double rNow = move / risk;
   if(rNow >= p.beR) {
      double be = isBuy ? (entry + p.beOffsetPts*point) : (entry - p.beOffsetPts*point);
      if( (isBuy && sl < be) || (!isBuy && sl > be) ) {
         tradeExit.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
         sl = be;
      }
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybePartialTPWithParams
// Co robi: Częściowe wyjście wg ExitParams (procent, próg R).
// Woła: SymbolInfoDouble, PositionGetDouble, MathAbs/MathFloor/MathMax, tradeExit.PositionClosePartial.
// Używa: _Symbol, tradeExit.
// Zwraca: void.
// UWAGA: zakłada wcześniejsze PositionSelectByTicket.
// -------------------------------------------------------------------
void MaybePartialTPWithParams(ulong ticket, bool isBuy, double entry, double sl, const ExitParams &p) {
   if(!p.usePartial) return;
   double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double move  = MathAbs(price - entry);
   double risk  = MathAbs(entry - sl);
   if(risk<=0) return;
   double rNow = move / risk;
   if(rNow >= p.partialR) {
      double volume = PositionGetDouble(POSITION_VOLUME);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double closeVol = MathMax(minLot, MathFloor(volume*p.partialPct/step)*step);
      if(closeVol>0 && closeVol<volume) tradeExit.PositionClosePartial(ticket, closeVol);
      // jednorazowość można trzymać jak wcześniej po ticketach, jeśli chcesz
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeTrailWithParams
// Co robi: Trailing wg ExitParams (TRAIL_ATR / TRAIL_CANDLE / TRAIL_STEP).
//          W trybie ATR używa RD_ATR(atrPeriod,shift) z analizatora.
// Woła: RD_ATR, SymbolInfoDouble, PositionGetDouble, MathFloor, ArraySize, tradeExit.PositionModify.
// Używa: _Symbol, candleHistory[], tradeExit.
// Zwraca: void (aktualizuje &sl).
// UWAGA: zakłada wcześniejsze PositionSelectByTicket.
// -------------------------------------------------------------------
void MaybeTrailWithParams(ulong ticket, bool isBuy, double &sl, const ExitParams &p)
{
   if(p.trail==TRAIL_NONE) return;

   double newSL = sl;  // lokalny kandydat (to naprawia „undeclared identifier”)

   if(p.trail==TRAIL_ATR)
   {
      double atr = RD_ATR(p.atrPeriod, 1);
      if(atr > 0.0)
      {
         double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double candidate = isBuy ? (price - p.atrMult * atr)
                                  : (price + p.atrMult * atr);
         if( (isBuy && candidate > newSL) || (!isBuy && candidate < newSL) )
            newSL = candidate;
      }
   }
   else if(p.trail==TRAIL_CANDLE)
   {
      if(ArraySize(candleHistory) > 2)
      {
         double buffer = 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double base   = isBuy ? (candleHistory[2].low  - buffer)
                               : (candleHistory[2].high + buffer);
         if( (isBuy && base > newSL) || (!isBuy && base < newSL) )
            newSL = base;
      }
   }
   else if(p.trail==TRAIL_STEP)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);

      double steps   = MathFloor(MathAbs(price - entry) / (p.stepEveryPts * point));
      double advance = steps * (p.stepLockPts * point);
      double base    = isBuy ? (entry + advance) : (entry - advance);

      if( (isBuy && base > newSL) || (!isBuy && base < newSL) )
         newSL = base;
   }

   if(newSL != sl)
   {
      tradeExit.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      sl = newSL;
   }
}

// -------------------------------------------------------------------
// OPIS FUNKCJI: MaybeOppositeDIExitWithParams
// Co robi: „Twarde” wyjście DI/ADX wg progów w ExitParams.
// Woła: GetCustomADXAt, GetCustomPlusDIAt, GetCustomMinusDIAt, MathAbs.
// Używa: (brak globali – tylko parametry p).
// Zwraca: true/false.
// -------------------------------------------------------------------
bool MaybeOppositeDIExitWithParams(bool isBuy, const ExitParams &p) {
   if(!p.useDIExit) return false;
   int i=1;
   double adx=GetCustomADXAt(i), pdi=GetCustomPlusDIAt(i), mdi=GetCustomMinusDIAt(i);
   double d=MathAbs(pdi-mdi);
   if(adx<p.adxMin) return false;
   if(pdi<p.diMin && mdi<p.diMin) return false;
   if( isBuy && (mdi>pdi) && d>=p.diDiff ) return true;
   if(!isBuy && (pdi>mdi) && d>=p.diDiff ) return true;
   return false;
}


#endif
