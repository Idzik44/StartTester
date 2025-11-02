//+------------------------------------------------------------------+
//|                                            BuySellFunction11.mqh |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict

#include <StartTester/CandleAndTranactionData11.mqh>      // activeOrdersAndPositions[], RefreshOrderAndPositionData(), OrderPositionData itp.
#include <StartTester/Zmienne11.mqh>                       // parametry input: inputSLMultiplier, inputSLPoints, inputTPMultiplier, inputFixedLot, itp.
#include <StartTester/Position_Size11.mqh>                 // CalculateSLAndTP(), CalculateLotSize(), CTrade trade

#ifndef __BUYSELLFUNCTION_MQH__
#define __BUYSELLFUNCTION_MQH__

// -------------------------------------------------------------------
// OPIS: ZMIENNE / OBIEKTY UŻYWANE W TYM PLIKU
// - trade (CTrade)            : obiekt składania zleceń (z Position_Size11.mqh)
// - activeOrdersAndPositions[]: lista zleceń/pozycji (z CandleAndTranactionData11.mqh; odświeżana przez RefreshOrderAndPositionData())
// - Parametry wejściowe (Zmienne11.mqh):
//     inputSLMultiplier, inputSLPoints, inputTPMultiplier,
//     inputExecuteMarginPoints, inputFixedLot, inputCalculationMode,
//     inputAccountRiskCapital, inputRiskPercentage
// - Symbole/stałe MQL5: _Symbol, SYMBOL_POINT, SYMBOL_ASK, SYMBOL_BID, ORDER_TIME_GTC,
//                       ORDER_TYPE_* (BUY/SELL/BUY_STOP/SELL_STOP/BUY_LIMIT/SELL_LIMIT),
//                       POSITION_TYPE_* (BUY/SELL)
// -------------------------------------------------------------------


// ====================================================================
// OPIS FUNKCJI: HasPendingOrOpenOrders
// Co robi:
//   Sprawdza, czy istnieje już zlecenie lub pozycja po zadanej „stronie rynku”
//   (BUY lub SELL) dla bieżącego symbolu i magicNumber. Parametr orderType może
//   wskazywać BUY/SELL lub odpowiednie STOP/LIMIT (albo typ pozycji), a funkcja
//   potraktuje go jako „grupę kierunkową”.
// Woła:
//   - RefreshOrderAndPositionData() (odświeżenie bufora aktywnych zleceń/pozycji).
// Używa:
//   - activeOrdersAndPositions[] (odczyt),
//   - _Symbol (odczyt).
// Zwraca: true, jeśli znaleziono pasujący rekord; w przeciwnym razie false.
// ====================================================================
bool HasPendingOrOpenOrders(int orderType, ulong magicNumber)
{
   RefreshOrderAndPositionData();  // zawsze aktualizujemy dane tylko przy sprawdzaniu

   // „strona rynku” wynikająca z orderType:
   bool checkBuySide  = (orderType == ORDER_TYPE_BUY
                      || orderType == ORDER_TYPE_BUY_STOP
                      || orderType == ORDER_TYPE_BUY_LIMIT
                      || orderType == POSITION_TYPE_BUY);   // dopuszczamy też typ pozycji
   bool checkSellSide = (orderType == ORDER_TYPE_SELL
                      || orderType == ORDER_TYPE_SELL_STOP
                      || orderType == ORDER_TYPE_SELL_LIMIT
                      || orderType == POSITION_TYPE_SELL);

   for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
   {
      OrderPositionData opd = activeOrdersAndPositions[i];

      // Strona rynku pochodząca z rekordu:
      bool opdIsBuySide  = (opd.type == ORDER_TYPE_BUY  || opd.type == ORDER_TYPE_BUY_STOP  || opd.type == ORDER_TYPE_BUY_LIMIT  || opd.type == POSITION_TYPE_BUY);
      bool opdIsSellSide = (opd.type == ORDER_TYPE_SELL || opd.type == ORDER_TYPE_SELL_STOP || opd.type == ORDER_TYPE_SELL_LIMIT || opd.type == POSITION_TYPE_SELL);

      if (((checkBuySide  && opdIsBuySide) ||
           (checkSellSide && opdIsSellSide)) &&
          opd.symbol == _Symbol && opd.magic == magicNumber)
      {
         return true;
      }
   }
   return false;
}


// ====================================================================
// OPIS FUNKCJI: PlaceBuyStop
// Co robi:
//   Składa zlecenie oczekujące BUY STOP. Oblicza SL/TP i wolumen (lot),
//   dodaje margines wykonania do ceny, wymaga poprawnego SL (spójnie z rynkowymi).
// Woła:
//   - HasPendingOrOpenOrders(...),
//   - CalculateSLAndTP(...), CalculateLotSize(...),
//   - SymbolInfoDouble(...), trade.SetExpertMagicNumber(...), trade.BuyStop(...).
// Używa:
//   - parametry input (Zmienne11.mqh), _Symbol, SYMBOL_POINT, ORDER_TIME_GTC.
// Zwraca: true po sukcesie; false w razie konfliktu/błędu/walidacji.
// ====================================================================
bool PlaceBuyStop(double price, int UseSLMethod, ulong magicNumber)
{
   if (HasPendingOrOpenOrders(ORDER_TYPE_BUY_STOP, magicNumber))
   {
      return false;
   }

   double stopLossPrice = 0.0, takeProfitPrice = 0.0;
   CalculateSLAndTP(stopLossPrice, takeProfitPrice, UseSLMethod, price, true, inputSLMultiplier,inputSLPoints,inputTPMultiplier);

   double adjustedPrice = price + inputExecuteMarginPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lotSize = CalculateLotSize(0.0, stopLossPrice, adjustedPrice, inputFixedLot, inputCalculationMode, inputAccountRiskCapital,inputRiskPercentage);

   // Spójnie z rynkowymi — wymagamy sensownego SL:
   if (lotSize <= 0.0 || adjustedPrice <= 0.0 || stopLossPrice == 0.0)
      return false;

   trade.SetExpertMagicNumber(magicNumber);

   if (!trade.BuyStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_GTC, 0))
   {
      return false;
   }
   return true;
}


// ====================================================================
// OPIS FUNKCJI: PlaceSellStop
// Co robi:
//   Składa zlecenie oczekujące SELL STOP. Oblicza SL/TP i wolumen (lot),
//   odejmuje margines wykonania od ceny, wymaga poprawnego SL (spójnie z rynkowymi).
// Woła:
//   - HasPendingOrOpenOrders(...),
//   - CalculateSLAndTP(...), CalculateLotSize(...),
//   - SymbolInfoDouble(...), trade.SetExpertMagicNumber(...), trade.SellStop(...).
// Używa:
//   - parametry input (Zmienne11.mqh), _Symbol, SYMBOL_POINT, ORDER_TIME_GTC.
// Zwraca: true po sukcesie; false w razie konfliktu/błędu/walidacji.
// ====================================================================
bool PlaceSellStop(double price, int UseSLMethod, ulong magicNumber)
{
   if (HasPendingOrOpenOrders(ORDER_TYPE_SELL_STOP, magicNumber))
   {
      return false;
   }

   double stopLossPrice = 0.0, takeProfitPrice = 0.0;
   CalculateSLAndTP(stopLossPrice, takeProfitPrice, UseSLMethod, price, false, inputSLMultiplier,inputSLPoints,inputTPMultiplier);

   double adjustedPrice = price - inputExecuteMarginPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lotSize = CalculateLotSize(0.0, stopLossPrice, adjustedPrice, inputFixedLot, inputCalculationMode, inputAccountRiskCapital,inputRiskPercentage);

   // Spójnie z rynkowymi — wymagamy sensownego SL:
   if (lotSize <= 0.0 || adjustedPrice <= 0.0 || stopLossPrice == 0.0)
      return false;

   trade.SetExpertMagicNumber(magicNumber);

   if (!trade.SellStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_GTC, 0))
   {
      return false;
   }
   return true;
}


// ====================================================================
// OPIS FUNKCJI: PlaceBuy
// Co robi:
//   Składa zlecenie rynkowe BUY z wyliczeniem SL/TP i lota. Wcześniej
//   sprawdza konflikt z istniejącymi zleceniami/pozycjami w tym kierunku.
// Woła:
//   - HasPendingOrOpenOrders(...), SymbolInfoDouble(...),
//   - CalculateSLAndTP(...), CalculateLotSize(...),
//   - trade.SetExpertMagicNumber(...), trade.Buy(...).
// Używa: _Symbol, SYMBOL_ASK i parametry wejściowe (z argumentów).
// Zwraca: true po sukcesie; false w razie błędu/walidacji.
// ====================================================================
bool PlaceBuy(
    int UseSLMethod,
    ulong magicNumber,
    double SLMultiplier,
    double SLPoints,
    double TPMultiplier,
    double FixedLot,
    int CalculationMode,
    double AccountRiskCapital,
    double RiskPercentage)
{
    if (HasPendingOrOpenOrders(ORDER_TYPE_BUY, magicNumber))
        return false;

    double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (askPrice == 0.0)
        return false;

    double stopLossPrice, takeProfitPrice;
    CalculateSLAndTP(
        stopLossPrice, takeProfitPrice, UseSLMethod, askPrice, true,
        SLMultiplier, SLPoints, TPMultiplier);

    double lotSize = CalculateLotSize(
        0.0, stopLossPrice, askPrice,
        FixedLot, CalculationMode, AccountRiskCapital, RiskPercentage);

    if (lotSize <= 0.0 || stopLossPrice == 0)
        return false;

    trade.SetExpertMagicNumber(magicNumber);

    if (!trade.Buy(lotSize, _Symbol, askPrice, stopLossPrice, takeProfitPrice))
        return false;

    return true;
}


// ====================================================================
// OPIS FUNKCJI: PlaceSell
// Co robi:
//   Składa zlecenie rynkowe SELL z wyliczeniem SL/TP i lota. Wcześniej
//   odświeża bufor danych oraz sprawdza konflikt z istniejącymi zleceniami/pozycjami.
// Woła:
//   - RefreshOrderAndPositionData(), HasPendingOrOpenOrders(...),
//   - SymbolInfoDouble(...), CalculateSLAndTP(...), CalculateLotSize(...),
//   - trade.SetExpertMagicNumber(...), trade.Sell(...).
// Używa: _Symbol, SYMBOL_BID i parametry wejściowe (z argumentów).
// Zwraca: true po sukcesie; false w razie błędu/walidacji.
// ====================================================================
bool PlaceSell(
    int UseSLMethod,
    ulong magicNumber,
    double SLMultiplier,
    double SLPoints,
    double TPMultiplier,
    double FixedLot,
    int CalculationMode,
    double AccountRiskCapital,
    double RiskPercentage)
{
    RefreshOrderAndPositionData();

    if (HasPendingOrOpenOrders(ORDER_TYPE_SELL, magicNumber))
        return false;

    double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (bidPrice == 0.0)
        return false;

    double stopLossPrice, takeProfitPrice;
    CalculateSLAndTP(
        stopLossPrice, takeProfitPrice, UseSLMethod, bidPrice, false,
        SLMultiplier, SLPoints, TPMultiplier);

    double lotSize = CalculateLotSize(
        0.0, stopLossPrice, bidPrice,
        FixedLot, CalculationMode, AccountRiskCapital, RiskPercentage);

    if (lotSize <= 0.0 || stopLossPrice == 0)
        return false;

    trade.SetExpertMagicNumber(magicNumber);

    if (!trade.Sell(lotSize, _Symbol, bidPrice, stopLossPrice, takeProfitPrice))
        return false;

    return true;
}

#endif
