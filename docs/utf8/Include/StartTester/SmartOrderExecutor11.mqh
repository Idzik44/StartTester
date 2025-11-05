//+------------------------------------------------------------------+
//|                                      SmartOrderExecutor11.mqh    |
//| Składanie zleceń dla sygnałów impulsowych (pending/rynek)        |
//+------------------------------------------------------------------+
#property strict
#ifndef __SMART_ORDER_EXECUTOR_MQH__
#define __SMART_ORDER_EXECUTOR_MQH__

#include <Trade\Trade.mqh>
#include <StartTester/Zmienne11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>

// Overload per-regime (parametry SL/TP jawnie)
void ExecuteImpulseTrade(bool isBuy,
                         double adjustedPrice,
                         datetime candleTime,
                         int UseSLMethod,
                         ulong magicNumber,
                         double slMultiplier,
                         double slPoints,
                         double tpMultiplier)
{
    RefreshOrderAndPositionData();

    if (HasAnyOpenOrPendingOrder(magicNumber))
    {
        if (DebugOrders)
            PrintFormat("⚠️ [ORD] Istnieje już pozycja/zlecenie dla magic=%I64u – pomijam.", magicNumber);
        return;
    }

    int tfSec = PeriodSeconds(_Period);
    if (tfSec <= 0) tfSec = 60;
    datetime expiryTime = TimeCurrent() + tfSec;

    double stopLossPrice = 0.0, takeProfitPrice = 0.0;
    CalculateSLAndTP(stopLossPrice, takeProfitPrice,
                     UseSLMethod, adjustedPrice, isBuy,
                     slMultiplier, slPoints, tpMultiplier);

    double lotSize = CalculateLotSize(
        0.0, stopLossPrice, adjustedPrice,
        inputFixedLot, inputCalculationMode,
        inputAccountRiskCapital, inputRiskPercentage);

    if (lotSize <= 0.0 || adjustedPrice <= 0.0)
    {
        Print("⛔ [ORD] Błędny lot lub cena – przerwano.");
        return;
    }

    if (!Enable_LiveTrading)
    {
        if (DebugOrders)
            PrintFormat("🧪 [DRY-RUN] %sStop lot=%.2f @ %.5f | SL=%.5f | TP=%.5f | exp=%s | magic=%I64u | meth=%d slM=%.3f slP=%.1f tpM=%.2f",
                        isBuy ? "Buy" : "Sell", lotSize, adjustedPrice,
                        stopLossPrice, takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS),
                        magicNumber, UseSLMethod, slMultiplier, slPoints, tpMultiplier);
        return;
    }

    // REAL
    trade.SetExpertMagicNumber(magicNumber);
    bool success = isBuy
        ? trade.BuyStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime)
        : trade.SellStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime);

    if (success)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] Pending %sStop @ %.5f | SL=%.5f | TP=%.5f | exp=%s | lot=%.2f | magic=%I64u | meth=%d",
                        isBuy ? "Buy" : "Sell", adjustedPrice, stopLossPrice, takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS), lotSize, magicNumber, UseSLMethod);
        return;
    }

    // Fallback: rynek
    double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool mktOK = isBuy
        ? trade.Buy(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice)
        : trade.Sell(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice);

    if (mktOK)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] RYNEK %s @ %.5f | SL=%.5f | TP=%.5f | lot=%.2f | magic=%I64u | meth=%d",
                        isBuy ? "BUY" : "SELL", marketPrice, stopLossPrice, takeProfitPrice, lotSize, magicNumber, UseSLMethod);
    }
    else
    {
        PrintFormat("❌ [ORD] Nie udało się ustawić ani pendinga, ani rynku (%s).", isBuy ? "BUY" : "SELL");
    }
}

// Wariant legacy – korzysta z globalnych inputów SL/TP
void ExecuteImpulseTrade(bool isBuy,
                         double adjustedPrice,
                         datetime candleTime,
                         int UseSLMethod,
                         ulong magicNumber)
{
    RefreshOrderAndPositionData();

    if (HasAnyOpenOrPendingOrder(magicNumber))
    {
        if (DebugOrders)
            PrintFormat("⚠️ [ORD] Istnieje już pozycja/zlecenie dla magic=%I64u – pomijam.", magicNumber);
        return;
    }

    int tfSec = PeriodSeconds(_Period);
    if (tfSec <= 0) tfSec = 60;
    datetime expiryTime = TimeCurrent() + tfSec;

    double stopLossPrice = 0.0, takeProfitPrice = 0.0;
    CalculateSLAndTP(stopLossPrice, takeProfitPrice,
                     UseSLMethod, adjustedPrice, isBuy,
                     inputSLMultiplier, inputSLPoints, inputTPMultiplier);

    double lotSize = CalculateLotSize(
        0.0, stopLossPrice, adjustedPrice,
        inputFixedLot, inputCalculationMode,
        inputAccountRiskCapital, inputRiskPercentage);

    if (lotSize <= 0.0 || adjustedPrice <= 0.0)
    {
        Print("⛔ [ORD] Błędny lot lub cena – przerwano.");
        return;
    }

    if (!Enable_LiveTrading)
    {
        if (DebugOrders)
            PrintFormat("🧪 [DRY-RUN] %sStop lot=%.2f @ %.5f | SL=%.5f | TP=%.5f | exp=%s | magic=%I64u (legacy inputs)",
                        isBuy ? "Buy" : "Sell", lotSize, adjustedPrice, stopLossPrice, takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS), magicNumber);
        return;
    }

    trade.SetExpertMagicNumber(magicNumber);
    bool success = isBuy
        ? trade.BuyStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime)
        : trade.SellStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime);

    if (success)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] Pending %sStop @ %.5f | SL=%.5f | TP=%.5f | exp=%s | lot=%.2f | magic=%I64u (legacy inputs)",
                        isBuy ? "Buy" : "Sell", adjustedPrice, stopLossPrice, takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS), lotSize, magicNumber);
        return;
    }

    double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool mktOK = isBuy
        ? trade.Buy(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice)
        : trade.Sell(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice);

    if (mktOK)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] RYNEK %s @ %.5f | SL=%.5f | TP=%.5f | lot=%.2f | magic=%I64u (legacy inputs)",
                        isBuy ? "BUY" : "SELL", marketPrice, stopLossPrice, takeProfitPrice, lotSize, magicNumber);
    }
    else
    {
        PrintFormat("❌ [ORD] Nie udało się ustawić ani pendinga, ani rynku (%s).", isBuy ? "BUY" : "SELL");
    }
}

#endif // __SMART_ORDER_EXECUTOR_MQH__
