//+------------------------------------------------------------------+
//|                                      SmartOrderExecutor11.mqh    |
//| Pomocnicza funkcja do składania zleceń impulsowych               |
//+------------------------------------------------------------------+
#property strict

#ifndef __SMART_ORDER_EXECUTOR_MQH__
#define __SMART_ORDER_EXECUTOR_MQH__

#include <Trade\Trade.mqh>
#include <StartTester/Zmienne11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/BuySellFunction11.mqh>
#include <StartTester/ExitEngine.mqh>   // [EXITENGINE] meta-kontroler wyjść

// Główna funkcja do składania zleceń 
void ExecuteImpulseTrade(bool isBuy,
                         double adjustedPrice,
                         datetime candleTime,
                         int UseSLMethod,
                         ulong magicNumber)
{
    // odśwież lokalne bufory zleceń/pozycji
    RefreshOrderAndPositionData();

    // antyduplikat: jeśli jest już pozycja lub oczekujące z tym magic -> wyjdź
    if (HasAnyOpenOrPendingOrder(magicNumber))
    {
        if (DebugOrders)
            PrintFormat("⚠️ [ORD] Istnieje już pozycja/zlecenie dla magic=%I64u – pomijam nowy sygnał.", magicNumber);
        return;
    }

    // ustaw czas wygaśnięcia pendinga = jedna świeca bieżącego TF
    datetime expiryTime = TimeCurrent() + _Period;

    // wylicz SL/TP
    double stopLossPrice = 0.0, takeProfitPrice = 0.0;
    CalculateSLAndTP(stopLossPrice, takeProfitPrice,
                     UseSLMethod, adjustedPrice, isBuy,
                     inputSLMultiplier, inputSLPoints, inputTPMultiplier);

    // lot wg ryzyka
    double lotSize = CalculateLotSize(
        0.0, stopLossPrice, adjustedPrice,
        inputFixedLot, inputCalculationMode,
        inputAccountRiskCapital, inputRiskPercentage);

    if (lotSize <= 0.0 || adjustedPrice <= 0.0)
    {
        Print("⛔ [ORD] Błędny lot lub cena – przerwano.");
        return;
    }

    // ======= TRYB DRY-RUN (Etap 3A): nie składaj zleceń, tylko zaloguj co by się stało =======
    if (!Enable_LiveTrading)
    {
        if (DebugOrders)
        {
            PrintFormat("🧪 [DRY-RUN] %sStop lot=%.2f @ %.5f | SL=%.5f | TP=%.5f | expiry=%s | magic=%I64u",
                        isBuy ? "Buy" : "Sell",
                        lotSize,
                        adjustedPrice,
                        stopLossPrice,
                        takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS),
                        magicNumber);
        }
        // W DRY-RUN nie wiążemy polityki wyjścia i nie składamy zleceń.
        return;
    }
    // ==========================================================================================

    // REAL TRADING (Etap 3B+)
    trade.SetExpertMagicNumber(magicNumber);

    bool success = false;
    if (isBuy)
        success = trade.BuyStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime);
    else
        success = trade.SellStop(lotSize, adjustedPrice, _Symbol, stopLossPrice, takeProfitPrice, ORDER_TIME_SPECIFIED, expiryTime);

    if (success)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] Pending %sStop ustawiony @ %.5f | SL=%.5f | TP=%.5f | exp=%s | lot=%.2f | magic=%I64u",
                        isBuy ? "Buy" : "Sell",
                        adjustedPrice, stopLossPrice, takeProfitPrice,
                        TimeToString(expiryTime, TIME_DATE|TIME_SECONDS),
                        lotSize, magicNumber);

        // Powiąż politykę wyjścia tylko jeśli włączone
        if (Enable_BindExitEngine)
            BindPolicyForSymbolPosition(_Symbol);
        return;
    }

    // fallback: jeśli pending się nie udał – spróbuj rynek
    double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool mktOK = false;
    if (isBuy)
        mktOK = trade.Buy(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice);
    else
        mktOK = trade.Sell(lotSize, _Symbol, marketPrice, stopLossPrice, takeProfitPrice);

    if (mktOK)
    {
        if (DebugOrders)
            PrintFormat("✅ [ORD] RYNEK %s @ %.5f | SL=%.5f | TP=%.5f | lot=%.2f | magic=%I64u",
                        isBuy ? "BUY" : "SELL", marketPrice, stopLossPrice, takeProfitPrice, lotSize, magicNumber);

        if (Enable_BindExitEngine)
            BindPolicyForSymbolPosition(_Symbol);
    }
    else
    {
        PrintFormat("❌ [ORD] Nie udało się ustawić ani pendinga, ani rynku (%s).",
                    isBuy ? "BUY" : "SELL");
    }
}


#endif
