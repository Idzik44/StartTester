//+------------------------------------------------------------------+
//| CandleAndTransactionData11.mqh                                     |
//| Przechowuje dane świec i dane transakcyjne                       |
//+------------------------------------------------------------------+
#property strict


#ifndef __CANDLE_AND_TRANSACTION_DATA_MQH__
#define __CANDLE_AND_TRANSACTION_DATA_MQH__

#include <StartTester/Zmienne11.mqh>

// Historia 300 świec (od indeksu 0 = najnowsza, do 299 = najstarsza)
MqlRates candleHistory[];

// Odświeżanie danych historycznych świec
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
// Znajdź indeks świecy w candleHistory po dacie                    |
//------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Znajdź indeks świecy w candleHistory[] po czasie otwarcia       |
//+------------------------------------------------------------------+
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

//------------------------------------------------------------------+
// Wyświetl porównanie indeksów dla testu synchronizacji            |
//------------------------------------------------------------------+
void CommentCandleBarIndices()
{
   int idxHist1 = FindIndexByTime(candleHistory[1].time);

 /*  Comment(
      "Sprawdzenie indeksów wg czasu:\n",
      "candleHistory[1] → indeks: ", idxHist1
   );*/
}

//+------------------------------------------------------------------+
//| Struktura przechowująca zlecenia i pozycje                       |
//+------------------------------------------------------------------+
struct OrderPositionData {
   ulong ticket;
   int type;           // ORDER_TYPE_*, POSITION_TYPE_*
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
//| Sprawdź czy istnieje aktywne zlecenie lub pozycja dla symbolu  |
//| i magicznego numeru (bez względu na kierunek)                   |
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
//| Odświeżanie listy aktywnych zleceń i pozycji                     |
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
            opd.type      = (int)OrderGetInteger(ORDER_TYPE);
            opd.price     = OrderGetDouble(ORDER_PRICE_OPEN);
            opd.sl        = OrderGetDouble(ORDER_SL);
            opd.tp        = OrderGetDouble(ORDER_TP);
            opd.symbol    = OrderGetString(ORDER_SYMBOL);
            opd.magic     = OrderGetInteger(ORDER_MAGIC);
            opd.isPending = true;
            opd.isOpen    = false;
            opd.openTime  = (datetime)OrderGetInteger(ORDER_TIME_SETUP);  // ✅ Poprawka tutaj

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
            opd.type      = (int)PositionGetInteger(POSITION_TYPE);
            opd.price     = PositionGetDouble(POSITION_PRICE_OPEN);
            opd.sl        = PositionGetDouble(POSITION_SL);
            opd.tp        = PositionGetDouble(POSITION_TP);
            opd.symbol    = PositionGetString(POSITION_SYMBOL);
            opd.magic     = PositionGetInteger(POSITION_MAGIC);
            opd.isPending = false;
            opd.isOpen    = true;
            opd.openTime  = (datetime)PositionGetInteger(POSITION_TIME);  // ✅ To zostaje

            ArrayResize(activeOrdersAndPositions, count + 1);
            activeOrdersAndPositions[count] = opd;
            DebugPrintOrderData(opd);
            count++;
         }
      }
   }
}


void DebugPrintOrderData(const OrderPositionData &opd) {
   string typeStr = opd.isPending ? "Pending" : (opd.isOpen ? "Open" : "Unknown");
   string typeName = EnumToString((ENUM_ORDER_TYPE)opd.type);
   string timeStr = TimeToString(opd.openTime, TIME_DATE | TIME_MINUTES);

 /*  PrintFormat("Ticket: %I64u | Type: %s (%s) | Symbol: %s | Price: %.5f | SL: %.5f | TP: %.5f | Magic: %d | Time: %s",
               opd.ticket,
               typeStr,
               typeName,
               opd.symbol,
               opd.price,
               opd.sl,
               opd.tp,
               opd.magic,
               timeStr);          */
}

//+------------------------------------------------------------------+
//| RSI                                                              |
//+------------------------------------------------------------------+

int rsiHandle = INVALID_HANDLE;

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



void ReleaseRSI()
{
    if (rsiHandle != INVALID_HANDLE)
    {
        IndicatorRelease(rsiHandle);
        rsiHandle = INVALID_HANDLE;
    }
}
//+--------------------------------------------------------------+
//                   EMA i SMA                                   |
//+--------------------------------------------------------------+
/*
int handleEMA;
int handleSMA;

double emaBuffer[];
double smaBuffer[];

// Inicjalizacja
bool InitMovingAverages(string symbol, ENUM_TIMEFRAMES timeframe) {
   handleEMA = iMA(symbol, timeframe, inputMaValue, 0, MODE_EMA, PRICE_CLOSE);
   handleSMA = iMA(symbol, timeframe, inputMaValue, 0, MODE_SMA, PRICE_CLOSE);
   return (handleEMA != INVALID_HANDLE && handleSMA != INVALID_HANDLE);
}

// Aktualizacja danych
bool UpdateMovingAverages() {
   if(!CopyBuffer(handleEMA, 0, 0, 3, emaBuffer) || 
      !CopyBuffer(handleSMA, 0, 0, 3, smaBuffer)) {
      Print("Failed to update moving averages");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Sprawdzenie położenia względem EMA i SMA                                |
//+------------------------------------------------------------------+
bool PassesMaCloseFilter(bool isBuy)
{
   if (ArraySize(emaBuffer) < 2 || ArraySize(smaBuffer) < 2 || ArraySize(candleHistory) < 2)
      return false;

   double close = candleHistory[1].close;
   double ema   = emaBuffer[1];
   double sma   = smaBuffer[1];

   if (isBuy)
      return (close > ema && close > sma);
   else
      return (close < ema && close < sma);
}
*/
//+--------------------------------------------------------------+
//                         ADX                                   |
//+--------------------------------------------------------------+

double customADX[];
double customPlusDI[];
double customMinusDI[];

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
      double prevLow = candleHistory[i + 1].low;
      double prevClose = candleHistory[i + 1].close;

      double high = candleHistory[i].high;
      double low = candleHistory[i].low;

      double upMove = high - prevHigh;
      double downMove = prevLow - low;

      double plusDM = (upMove > downMove && upMove > 0) ? upMove : 0;
      double minusDM = (downMove > upMove && downMove > 0) ? downMove : 0;

      double tr1 = high - low;
      double tr2 = MathAbs(high - prevClose);
      double tr3 = MathAbs(low - prevClose);
      double trueRange = MathMax(tr1, MathMax(tr2, tr3));

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

         double up = h - prevH;
         double down = prevL - l;
         sumPlusDM += (up > down && up > 0) ? up : 0;
         sumMinusDM += (down > up && down > 0) ? down : 0;

         double trA = h - l;
         double trB = MathAbs(h - prevC);
         double trC = MathAbs(l - prevC);
         sumTR += MathMax(trA, MathMax(trB, trC));
      }

      if (sumTR == 0) continue;

      double plusDI = 100.0 * sumPlusDM / sumTR;
      double minusDI = 100.0 * sumMinusDM / sumTR;
      double dx = 100.0 * MathAbs(plusDI - minusDI) / (plusDI + minusDI);

      double adx = 0;
      for (int j = 0; j < period && (i + j) < total; j++)
      {
         int idx = i + j;
         double pDI = customPlusDI[idx];
         double mDI = customMinusDI[idx];
         if ((pDI + mDI) == 0) continue;
         adx += 100.0 * MathAbs(pDI - mDI) / (pDI + mDI);
      }
      adx /= period;

      customADX[i] = adx;
      customPlusDI[i] = plusDI;
      customMinusDI[i] = minusDI;
   }

//   Print("✅ Własne ADX obliczone.");
}

double GetCustomADXAt(int i) {
   if (i < 0 || i >= ArraySize(customADX)) return -1;
   return customADX[i];
}

double GetCustomPlusDIAt(int i) {
   if (i < 0 || i >= ArraySize(customPlusDI)) return -1;
   return customPlusDI[i];
}

double GetCustomMinusDIAt(int i) {
   if (i < 0 || i >= ArraySize(customMinusDI)) return -1;
   return customMinusDI[i];
}


#endif




