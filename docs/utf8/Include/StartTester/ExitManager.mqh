//+------------------------------------------------------------------+
//|                        ExitManager.mqh                           |
//| Zaawansowane zarządzanie wyjściem: BE, trailing, partial, time  |
//+------------------------------------------------------------------+
#property strict

#ifndef __EXIT_MANAGER_MQH__
#define __EXIT_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
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

// mapa: ticket -> policy
struct ExitBinding {
   ulong ticket;
   ExitParams params;
   MarketRegime regime;
   bool initialized;
};
ExitBinding g_exitBindings[];

// Opis: Szuka istniejącego wiązania ticket→ExitParams/Regime.
// Wywołania: (brak).
// Globalne: g_exitBindings (tablica).
int FindBinding(ulong ticket) {
   for(int i=ArraySize(g_exitBindings)-1;i>=0;--i)
      if(g_exitBindings[i].ticket==ticket) return i;
   return -1;
}

// Opis: Zapewnia (tworzy/aktualizuje) wiązanie dla pozycji. Klasyfikuje reżim, ładuje najlepsze parametry,
//       wyłącza partial jeśli wolumen nie pozwala.
// Wywołania: FindBinding, GetRegimeFeatures, ClassifyRegime, LoadBestExitForRegime, CanPartialByLot,
//            ArrayResize, CopyExitParams.
// Globalne: g_exitBindings[], candleHistory (pośrednio przez klasyfikację reżimu).
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

// Opis: Sprawdza, czy dla ticket wykonano już częściowe wyjście (jednorazowość).
// Wywołania: (brak).
// Globalne: g_partialDoneTickets.
bool PartialAlreadyDone(ulong ticket) {
   for (int i = ArraySize(g_partialDoneTickets) - 1; i >= 0; --i)
      if (g_partialDoneTickets[i] == ticket) return true;
   return false;
}

// Opis: Oznacza ticket jako obsłużony (partial TP wykonany).
// Wywołania: ArrayResize.
// Globalne: g_partialDoneTickets.
void MarkPartialDone(ulong ticket) {
   int n = ArraySize(g_partialDoneTickets);
   ArrayResize(g_partialDoneTickets, n + 1);
   g_partialDoneTickets[n] = ticket;
}

// Opis: Prosty ATR liczony lokalnie z candleHistory (średnia TR z ostatnich 'period' barów od 'index').
// Wywołania: ArraySize, MathAbs, MathMax.
// Globalne: candleHistory (MqlRates[]).
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

// Opis: Wyszukuje pozycję po magicu i symbolu; zwraca podstawowe parametry pozycji.
// Wywołania: PositionsTotal, PositionGetTicket, PositionSelectByTicket, PositionGetString/Integer/Double.
// Globalne: (brak).
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

// Opis: Zwraca liczbę zamkniętych świec od chwili 't' (licząc po candleHistory).
// Wywołania: ArraySize.
// Globalne: candleHistory.
int BarsSince(datetime t)
{
   // policz ile świec zamknięto od czasu t
   for(int i=1;i<ArraySize(candleHistory);++i)
      if(candleHistory[i].time<=t) return i-1;
   return 0;
}

// Opis: Warunkowe przesunięcie SL do BE wg konfiguracji globalnej (UseBreakeven, BE_Trigger_R, BE_OffsetPoints).
// Wywołania: SymbolInfoDouble, PositionGetDouble, tradeExit.PositionModify, MathAbs.
// Globalne: UseBreakeven, BE_Trigger_R, BE_OffsetPoints, _Symbol, tradeExit.
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

// Opis: Warunkowe częściowe wyjście wg konfiguracji globalnej (UsePartialTP, PartialTP_R, PartialTP_Percent).
//       Jednorazowe na ticket (PartialAlreadyDone/MarkPartialDone).
// Wywołania: PartialAlreadyDone, SymbolInfoDouble, PositionGetDouble, MathAbs/MathFloor/MathMax,
//            tradeExit.PositionClosePartial, MarkPartialDone.
// Globalne: UsePartialTP, PartialTP_R, PartialTP_Percent, _Symbol, tradeExit.
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

// Opis: Trailing stop wg ustawionego trybu: ATR / CANDLE / STEP (globalne UseTrailing, ATR_Period, ATR_Multiplier,
//       TrailStepEveryPoints, TrailStepLockPoints). Modyfikuje SL, jeśli kandydat poprawia pozycję.
// Wywołania: SymbolInfoDouble, PositionGetDouble, GetATR, MathFloor, tradeExit.PositionModify.
// Globalne: UseTrailing, ATR_Period, ATR_Multiplier, TrailStepEveryPoints, TrailStepLockPoints, _Symbol, candleHistory, tradeExit.
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

// Opis: „Twarde” wyjście na podstawie przeciwnych wskazań DI/ADX (globalne progi ExitAdxMin/ExitDiMin/ExitDiDiff).
// Wywołania: GetCustomADXAt, GetCustomPlusDIAt, GetCustomMinusDIAt, MathAbs.
// Globalne: UseOppositeDIExit, ExitAdxMin, ExitDiMin, ExitDiDiff.
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

// Opis: Sprawdza limit czasu w pozycji (time-stop) według globali UseTimeStop/MaxBarsInTrade.
// Wywołania: BarsSince.
// Globalne: UseTimeStop, MaxBarsInTrade.
bool MaybeTimeStop(datetime openTime)
{
   if(!UseTimeStop) return false;
   int bars = BarsSince(openTime);
   return (bars >= MaxBarsInTrade);
}

// Opis: Hak pod „zamknij przy zmianie sesji” (na razie zawsze false; sterowane UseSessionCloseExit).
// Wywołania: (brak).
// Globalne: UseSessionCloseExit.
bool MaybeSessionClose()
{
   if(!UseSessionCloseExit) return false;
   // Prosto: zamknij przy zmianie sesji (wywołuj po detekcji zmiany sesji)
   // Zakładamy, że logika zmiany sesji jest gdzie indziej – tutaj tylko hook.
   return false;
}

// ---- PUBLIC API ----
// Opis: Główna pętla zarządzania wyjściem dla wszystkich pozycji z danym magic number.
//       Kolejność: BE → Partial → Trailing → wyjścia twarde (DI/time-stop).
// Wywołania: PositionsTotal, PositionGetTicket, PositionSelectByTicket, PositionGet*, EnsureBindingForPosition,
//            FindBinding, CopyExitParams, MaybeMoveToBreakevenWithParams, MaybePartialTPWithParams,
//            MaybeTrailWithParams, MaybeOppositeDIExitWithParams, BarsSince, tradeExit.PositionClose.
// Globalne: UseExitManager, _Symbol, tradeExit, g_exitBindings[].
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

// Opis: Wersja BE na podstawie parametrów ExitParams (zamiast globali).
// Wywołania: SymbolInfoDouble, PositionGetDouble, tradeExit.PositionModify, MathAbs.
// Globalne: _Symbol, tradeExit.
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

// Opis: Wersja partial TP na podstawie ExitParams (zamiast globali).
// Wywołania: SymbolInfoDouble, PositionGetDouble, MathAbs/MathFloor/MathMax, tradeExit.PositionClosePartial.
// Globalne: _Symbol, tradeExit.
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

// Opis: Wersja trailing stop na podstawie ExitParams (TRAIL_ATR / TRAIL_CANDLE / TRAIL_STEP).
//       Używa RD_ATR(...) zewnętrznie (Regime/Range analyzer) dla trybu ATR.
// Wywołania: RD_ATR, SymbolInfoDouble, PositionGetDouble, MathFloor, ArraySize, tradeExit.PositionModify.
// Globalne: _Symbol, candleHistory, tradeExit.
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

// Opis: „Twarde” wyjście DI/ADX na bazie ExitParams (progi z pól p).
// Wywołania: GetCustomADXAt, GetCustomPlusDIAt, GetCustomMinusDIAt, MathAbs.
// Globalne: (brak — korzysta wyłącznie z parametrów wejściowych).
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
