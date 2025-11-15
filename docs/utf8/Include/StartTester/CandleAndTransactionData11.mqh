//+------------------------------------------------------------------+
//| CandleAndTransactionData11.mqh                                   |
//| Przechowuje dane świec i dane transakcyjne                       |
//+------------------------------------------------------------------+
#property strict

#ifndef __CANDLE_AND_TRANSACTION_DATA_MQH__
#define __CANDLE_AND_TRANSACTION_DATA_MQH__

#include <StartTester/Zmienne11.mqh>   // numCandlesToCheck, inputRSIPeriod itp.

// -------------------------------------------------------------------
// OPIS: ZMIENNE / TYPY W TYM PLIKU
// - MqlRates candleHistory[] : bufor świec (series: 0=najnowsza). Rozmiar faktycznie
//                              zależy od numCandlesToCheck (uzupełniany w RefreshCandleHistory).
// - struct OrderPositionData : rekord danych zlecenia/pozycji (wspólny format).
// - OrderPositionData activeOrdersAndPositions[] : tablica aktywnych zleceń/pozycji bieżącego symbolu.
// - int rsiHandle            : uchwyt wskaźnika RSI (INVALID_HANDLE jeśli nieutworzony).
// - double customADX[], customPlusDI[], customMinusDI[] : bufory wyliczeń ADX/+DI/-DI.
// -------------------------------------------------------------------

// Bufor świec – rozmiar zależny od 'numCandlesToCheck' (uzupełnia RefreshCandleHistory)
MqlRates candleHistory[];

//------------------------------------------------------------------+
// OPIS FUNKCJI: RefreshCandleHistory
// Co robi:
//   Ustawia candleHistory jako series (0=najnowsza) i kopiuje najnowsze
//   'numCandlesToCheck' świec z bieżącego symbolu/timeframe’u.
//   Ostrzega, gdy skopiowanych świec jest mniej niż 50.
// Woła: ArraySetAsSeries, CopyRates, Print.
// Używa: candleHistory[] (zapis), _Symbol, PERIOD_CURRENT, numCandlesToCheck.
// Zwraca: void.
//------------------------------------------------------------------+
void RefreshCandleHistory()
{
   ArraySetAsSeries(candleHistory, true);  // indeks 0 = najnowsza świeca (niedokończona)

   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, numCandlesToCheck, candleHistory);

   if (copied < 50)
   {
      Print("⛔ Za mało danych świec do analizy: tylko ", copied);
   }
}



//------------------------------------------------------------------+
// OPIS FUNKCJI: FindIndexByTime
// Co robi:
//   Dla czasu 't' zwraca indeks świecy, której przedział [start, start+tf)
//   obejmuje 't' (zależnie od bieżącego _Period).
// Woła: PeriodSeconds, ArraySize.
// Używa: candleHistory[] (odczyt), _Period (odczyt).
// Zwraca: indeks >=0 lub -1, gdy brak dopasowania.
//------------------------------------------------------------------+
int FindIndexByTime(datetime t)
{
    int tfSec = PeriodSeconds(_Period);

    for (int i = 0; i < ArraySize(candleHistory); i++)
    {
        datetime candleStart = candleHistory[i].time;
        datetime candleEnd = candleStart + tfSec;

        if (t >= candleStart && t < candleEnd)
            return i;
    }

    return -1;  // nie znaleziono
}

//+------------------------------------------------------------------+
//| Struktura przechowująca zlecenia i pozycje                       |
//+------------------------------------------------------------------+
struct OrderPositionData {
   ulong ticket;
   int type;           // ORDER_TYPE_* (dla zleceń) lub POSITION_TYPE_* (dla pozycji)
   double price;
   double sl;
   double tp;
   string symbol;
   long magic;
   bool isPending;
   bool isOpen;
   datetime openTime;

   // Konstruktor domyślny
   OrderPositionData() {
      ticket = 0;
      type = -1;
      price = 0;
      sl = 0;
      tp = 0;
      symbol = "";
      magic = -1;
      isPending = false;
      isOpen = false;
      openTime = 0;
   }

   // Konstruktor kopiujący
   OrderPositionData(const OrderPositionData &src) {
      ticket = src.ticket;
      type = src.type;
      price = src.price;
      sl = src.sl;
      tp = src.tp;
      symbol = src.symbol;
      magic = src.magic;
      isPending = src.isPending;
      isOpen = src.isOpen;
      openTime = src.openTime;
   }
};


// Globalna tablica do przechowywania aktywnych zleceń/pozycji
OrderPositionData activeOrdersAndPositions[];

//+------------------------------------------------------------------+
// OPIS FUNKCJI: HasAnyOpenOrPendingOrder
// Co robi:
//   Odświeża listę i sprawdza, czy istnieje cokolwiek (pending/open)
//   dla bieżącego symbolu i wskazanego magicNumber.
// Woła: RefreshOrderAndPositionData().
// Używa: activeOrdersAndPositions[] (po odświeżeniu), _Symbol.
// Zwraca: true/false.
//+------------------------------------------------------------------+
bool HasAnyOpenOrPendingOrder(ulong magicNumber)
{
   RefreshOrderAndPositionData();

   for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
   {
      OrderPositionData opd = activeOrdersAndPositions[i];
      if ((opd.isOpen || opd.isPending) && opd.symbol == _Symbol && opd.magic == magicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// OPIS FUNKCJI: HasPendingOrOpenOrders (kierunkowa)
// Co robi:
//   Odświeża listę i sprawdza, czy istnieje cokolwiek po podanej „stronie”
//   rynku (BUY lub SELL – w tym STOP/LIMIT/pozycje) dla bieżącego symbolu
//   i magicNumber.
// Woła: RefreshOrderAndPositionData().
// Używa: activeOrdersAndPositions[], _Symbol.
// Zwraca: true/false.
//+------------------------------------------------------------------+
bool HasPendingOrOpenOrders(int orderType, ulong magicNumber)
{
   RefreshOrderAndPositionData();

   bool checkBuySide  = (orderType == ORDER_TYPE_BUY
                      || orderType == ORDER_TYPE_BUY_STOP
                      || orderType == ORDER_TYPE_BUY_LIMIT
                      || orderType == POSITION_TYPE_BUY);

   bool checkSellSide = (orderType == ORDER_TYPE_SELL
                      || orderType == ORDER_TYPE_SELL_STOP
                      || orderType == ORDER_TYPE_SELL_LIMIT
                      || orderType == POSITION_TYPE_SELL);

   for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
   {
      OrderPositionData opd = activeOrdersAndPositions[i];
      if (opd.symbol != _Symbol || opd.magic != magicNumber) continue;

      bool opdIsBuySide  = (opd.type == ORDER_TYPE_BUY  || opd.type == ORDER_TYPE_BUY_STOP  || opd.type == ORDER_TYPE_BUY_LIMIT  || opd.type == POSITION_TYPE_BUY);
      bool opdIsSellSide = (opd.type == ORDER_TYPE_SELL || opd.type == ORDER_TYPE_SELL_STOP || opd.type == ORDER_TYPE_SELL_LIMIT || opd.type == POSITION_TYPE_SELL);

      if ((checkBuySide  && opdIsBuySide) ||
          (checkSellSide && opdIsSellSide))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// OPIS FUNKCJI: RefreshOrderAndPositionData
// Co robi:
//   Czyści i ponownie wypełnia activeOrdersAndPositions[] rekordami:
//   - Zlecenia oczekujące (ORDER_*) dla bieżącego symbolu,
//   - Pozycje otwarte (POSITION_*) dla bieżącego symbolu.
//   Dla zleceń openTime = ORDER_TIME_SETUP, dla pozycji openTime = POSITION_TIME.
//   Na końcu dla każdego rekordu wywołuje DebugPrintOrderData(opd) (log zakomentowany).
// Woła: ArrayResize, OrdersTotal/OrderGet*/OrderSelect, PositionsTotal/PositionGet*/PositionSelectByTicket.
// Używa: _Symbol, activeOrdersAndPositions[].
// Zwraca: void.
//+------------------------------------------------------------------+
void RefreshOrderAndPositionData() {
   ArrayResize(activeOrdersAndPositions, 0); // Wyczyść poprzednie dane
   int count = 0;

   // Zlecenia oczekujące
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0 && OrderSelect(ticket)) {
         if (OrderGetString(ORDER_SYMBOL) == _Symbol) {
            OrderPositionData opd;
            opd.ticket    = ticket;
            opd.type      = (int)OrderGetInteger(ORDER_TYPE); // ENUM_ORDER_TYPE
            opd.price     = OrderGetDouble(ORDER_PRICE_OPEN);
            opd.sl        = OrderGetDouble(ORDER_SL);
            opd.tp        = OrderGetDouble(ORDER_TP);
            opd.symbol    = OrderGetString(ORDER_SYMBOL);
            opd.magic     = OrderGetInteger(ORDER_MAGIC);
            opd.isPending = true;
            opd.isOpen    = false;
            opd.openTime  = (datetime)OrderGetInteger(ORDER_TIME_SETUP);  // czas ustawienia zlecenia

            ArrayResize(activeOrdersAndPositions, count + 1);
            activeOrdersAndPositions[count] = opd;
            DebugPrintOrderData(opd);
            count++;
         }
      }
   }

   // Pozycje otwarte
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0 && PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) == _Symbol) {
            OrderPositionData opd;
            opd.ticket    = ticket;
            opd.type      = (int)PositionGetInteger(POSITION_TYPE); // ENUM_POSITION_TYPE
            opd.price     = PositionGetDouble(POSITION_PRICE_OPEN);
            opd.sl        = PositionGetDouble(POSITION_SL);
            opd.tp        = PositionGetDouble(POSITION_TP);
            opd.symbol    = PositionGetString(POSITION_SYMBOL);
            opd.magic     = PositionGetInteger(POSITION_MAGIC);
            opd.isPending = false;
            opd.isOpen    = true;
            opd.openTime  = (datetime)PositionGetInteger(POSITION_TIME);  // czas otwarcia pozycji

            ArrayResize(activeOrdersAndPositions, count + 1);
            activeOrdersAndPositions[count] = opd;
            DebugPrintOrderData(opd);
            count++;
         }
      }
   }
}

//+------------------------------------------------------------------+
// OPIS FUNKCJI: DebugPrintOrderData
// Co robi:
//   Buduje (i po odkomentowaniu PrintFormat wypisuje) sformatowany log rekordu.
//   Poprawne mapowanie enumów: dla pending → ENUM_ORDER_TYPE, dla open → ENUM_POSITION_TYPE.
// Woła: EnumToString, TimeToString, (opcjonalnie) PrintFormat.
// Używa: tylko parametrów funkcji.
// Zwraca: void.
//+------------------------------------------------------------------+
void DebugPrintOrderData(const OrderPositionData &opd) {
   string typeStr = opd.isPending ? "Pending" : (opd.isOpen ? "Open" : "Unknown");
   string typeName;

   if (opd.isPending)
      typeName = EnumToString((ENUM_ORDER_TYPE)opd.type);
   else if (opd.isOpen)
      typeName = EnumToString((ENUM_POSITION_TYPE)opd.type);
   else
      typeName = "Unknown";

   string timeStr = TimeToString(opd.openTime, TIME_DATE | TIME_MINUTES);

 /*  PrintFormat("Ticket: %I64u | Kind: %s | Type: %s | Symbol: %s | Price: %.5f | SL: %.5f | TP: %.5f | Magic: %d | Time: %s",
               opd.ticket, typeStr, typeName, opd.symbol, opd.price, opd.sl, opd.tp, opd.magic, timeStr); */
}

//+------------------------------------------------------------------+
//| RSI – inicjalizacja i zwalnianie uchwytu                         |
//+------------------------------------------------------------------+
int rsiHandle = INVALID_HANDLE;

//------------------------------------------------------------------+
// OPIS FUNKCJI: InitRSI
// Co robi: Jeśli inputRSIPeriod > 0 i uchwyt nie istnieje, tworzy RSI dla bieżącego symbolu/timeframe’u.
// Woła: iRSI, Print.
// Używa: inputRSIPeriod, rsiHandle, _Symbol, PERIOD_CURRENT.
// Zwraca: void.
//------------------------------------------------------------------+
void InitRSI()
{
    if (inputRSIPeriod == 0)
        return;

    if (rsiHandle != INVALID_HANDLE)
        return;

    rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, inputRSIPeriod, PRICE_CLOSE);
    if (rsiHandle == INVALID_HANDLE)
        Print("[ERROR] Failed to create RSI handle");
}

//------------------------------------------------------------------+
// OPIS FUNKCJI: ReleaseRSI
// Co robi: Zwalnia uchwyt RSI (jeśli istnieje) i resetuje do INVALID_HANDLE.
// Woła: IndicatorRelease.
// Używa: rsiHandle.
// Zwraca: void.
//------------------------------------------------------------------+
void ReleaseRSI()
{
    if (rsiHandle != INVALID_HANDLE)
    {
        IndicatorRelease(rsiHandle);
        rsiHandle = INVALID_HANDLE;
    }
}

//+--------------------------------------------------------------+
//| ADX – bufory i obliczenia                                   |
//+--------------------------------------------------------------+
double customADX[];
double customPlusDI[];
double customMinusDI[];

//------------------------------------------------------------------+
// OPIS FUNKCJI: ComputeCustomADX
// Co robi:
//   Liczy customPlusDI/customMinusDI oraz customADX dla zadanego 'period'.
//   Najpierw oblicza DI i zapisuje do buforów, następnie liczy średni DX
//   (ADX) po oknie – korzystając już z aktualnego elementu.
// Woła: ArraySize/Resize/Initialize, MathAbs, MathMax.
// Używa: candleHistory[] (odczyt), custom* bufory (zapis).
// Zwraca: void.
//------------------------------------------------------------------+
void ComputeCustomADX(int period = 14)
{
   int total = ArraySize(candleHistory);
   ArrayResize(customADX, total);
   ArrayResize(customPlusDI, total);
   ArrayResize(customMinusDI, total);
   ArrayInitialize(customADX, 0);
   ArrayInitialize(customPlusDI, 0);
   ArrayInitialize(customMinusDI, 0);

   for (int i = total - period - 1; i >= 1; i--)
   {
      double prevHigh = candleHistory[i + 1].high;
      double prevLow  = candleHistory[i + 1].low;
      double prevClose= candleHistory[i + 1].close;

      double high = candleHistory[i].high;
      double low  = candleHistory[i].low;

      double upMove   = high - prevHigh;
      double downMove = prevLow - low;

      double plusDM  = (upMove > downMove && upMove > 0) ? upMove : 0;
      double minusDM = (downMove > upMove && downMove > 0) ? downMove : 0;

      // Sumowania DM/TR po 'period'
      double sumTR = 0, sumPlusDM = 0, sumMinusDM = 0;
      for (int j = 0; j < period; j++)
      {
         int idx = i + j;
         if (idx + 1 >= total) continue;

         double prevH = candleHistory[idx + 1].high;
         double prevL = candleHistory[idx + 1].low;
         double prevC = candleHistory[idx + 1].close;
         double h = candleHistory[idx].high;
         double l = candleHistory[idx].low;

         double up   = h - prevH;
         double down = prevL - l;
         sumPlusDM  += (up > down && up > 0) ? up : 0;
         sumMinusDM += (down > up && down > 0) ? down : 0;

         double trA = h - l;
         double trB = MathAbs(h - prevC);
         double trC = MathAbs(l - prevC);
         sumTR += MathMax(trA, MathMax(trB, trC));
      }

      if (sumTR == 0) continue;

      double plusDI  = 100.0 * sumPlusDM  / sumTR;
      double minusDI = 100.0 * sumMinusDM / sumTR;

      // Zapisz DI dla bieżącego i
      customPlusDI[i]  = plusDI;
      customMinusDI[i] = minusDI;

      // Policz średni DX (ADX) po oknie [i .. i+period)
      double adxSum = 0.0;
      int    adxCnt = 0;
      for (int j = 0; j < period && (i + j) < total; j++)
      {
         int idx = i + j;
         double pDI = customPlusDI[idx];
         double mDI = customMinusDI[idx];
         if ((pDI + mDI) == 0) continue;
         adxSum += 100.0 * MathAbs(pDI - mDI) / (pDI + mDI);
         adxCnt++;
      }
      double adx = (adxCnt > 0) ? (adxSum / adxCnt) : 0.0;

      customADX[i] = adx;
   }

//   Print("✅ Własne ADX obliczone.");
}

//------------------------------------------------------------------+
// OPIS FUNKCJI: GetCustomADXAt
// Co robi: Zwraca customADX[i] lub -1, jeśli i poza zakresem.
// Zwraca: double.
//------------------------------------------------------------------+
double GetCustomADXAt(int i) {
   if (i < 0 || i >= ArraySize(customADX)) return -1;
   return customADX[i];
}

//------------------------------------------------------------------+
// OPIS FUNKCJI: GetCustomPlusDIAt
// Co robi: Zwraca customPlusDI[i] lub -1, jeśli i poza zakresem.
// Zwraca: double.
//------------------------------------------------------------------+
double GetCustomPlusDIAt(int i) {
   if (i < 0 || i >= ArraySize(customPlusDI)) return -1;
   return customPlusDI[i];
}

//------------------------------------------------------------------+
// OPIS FUNKCJI: GetCustomMinusDIAt
// Co robi: Zwraca customMinusDI[i] lub -1, jeśli i poza zakresem.
// Zwraca: double.
//------------------------------------------------------------------+
double GetCustomMinusDIAt(int i) {
   if (i < 0 || i >= ArraySize(customMinusDI)) return -1;
   return customMinusDI[i];
}

#endif
