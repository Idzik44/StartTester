//+------------------------------------------------------------------+
//|                                            BuySellFunction11.mqh |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict


#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/Zmienne11.mqh>
#include <StartTester/Position_Size11.mqh>

#ifndef __BUYSELLFUNCTION_MQH__
#define __BUYSELLFUNCTION_MQH__

//Ctrade trade jest w PositionSize

// Sprawdzanie zleceń oczekujących i otwartych pozycji
bool HasPendingOrOpenOrders(int orderType, ulong magicNumber)
{
   RefreshOrderAndPositionData();  // zawsze aktualizujemy dane tylko przy sprawdzaniu

   for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
   {
      OrderPositionData opd = activeOrdersAndPositions[i];

      // Sprawdź typ pozycji lub zlecenia odpowiadający kierunkowi
      bool isBuyType  = (orderType == ORDER_TYPE_BUY  && (opd.type == ORDER_TYPE_BUY  || opd.type == POSITION_TYPE_BUY));
      bool isSellType = (orderType == ORDER_TYPE_SELL && (opd.type == ORDER_TYPE_SELL || opd.type == POSITION_TYPE_SELL));

      if ((isBuyType || isSellType) && opd.symbol == _Symbol && opd.magic == magicNumber)
      {
         return true;
      }
   }
   return false;
}



// Składanie zleceń oczekujących kupna
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
   if (lotSize <= 0.0 || adjustedPrice <= 0.0)
      return false;

   trade.SetExpertMagicNumber(magicNumber);

   if (!trade.BuyStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_GTC, 0))
   {
      return false;
   }
   return true;
}


// Składanie zleceń oczekujących sprzedaży
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
   if (lotSize <= 0.0 || adjustedPrice <= 0.0)
      return false;

   trade.SetExpertMagicNumber(magicNumber);

   if (!trade.SellStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_GTC, 0))
   {
      return false;
   }
   return true;
}


// Składanie zleceń kupna po cenie rynkowej
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