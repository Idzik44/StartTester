//+------------------------------------------------------------------+
//| PositionSizeManager11.mqh                                        |
//| Zarządzanie wielkością pozycji w oparciu o stały lot lub procent |
//+------------------------------------------------------------------+
#ifndef __POSITIONSIZEMANAGER_MQH__
#define __POSITIONSIZEMANAGER_MQH__

#property strict

#include <Trade\Trade.mqh>

#include <StartTester/Zmienne11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>
#include <StartTester/PeaksEnded11.mqh>
#include <StartTester/trenddetector11.mqh>

CTrade trade; // Instancja klasy CTrade


// ─────────────────────────────────────────────────────────────
// Funkcja: CalculateLotSize
// Opis:    Wylicza wielkość pozycji w lotach – jako stała wartość (CalculationMode=0)
//          albo jako procent ryzyka od kapitału (CalculationMode=1). Gdy SL w punktach
//          niepodany, odległość SL liczona jest z różnicy między marketPrice a stopLossPrice.
//          Dodatkowo dopasowuje wynik do ograniczeń brokera: VOLUME_STEP/MIN/MAX.
// Wywołuje: AccountInfoDouble(ACCOUNT_MARGIN_FREE), SymbolInfoDouble(), SymbolInfoInteger(), NormalizeDouble().
// Globalne/extern: _Symbol, inputAccountRiskCapital (z Zmienne11.mqh), _Digits.
// Zwraca:  lotSize znormalizowany do 2 miejsc po przecinku.
// ─────────────────────────────────────────────────────────────
double CalculateLotSize(
    double stopLossDistancePoints,
    double stopLossPrice,
    double marketPrice,
    double FixedLot,
    int CalculationMode,
    double AccountRiskCapital,
    double RiskPercentage)
{
    if (marketPrice <= 0.0)
        return 0.0;

    double lotSize = 0.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if (tickValue <= 0.0 || tickSize <= 0.0)
        return 0.0;

    // Użyj inputAccountRiskCapital jeśli podano, w przeciwnym razie użyj dostępnego marginesu
    double riskCapitalToUse = (inputAccountRiskCapital > 0.0)
                              ? inputAccountRiskCapital
                              : AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    if (stopLossPrice == 0.0)
    {
        lotSize = FixedLot;
    }
    else if (CalculationMode == 0) // Stała wielkość lota
    {
        lotSize = FixedLot;
    }
    else if (CalculationMode == 1) // Procent ryzyka
    {
        double riskAmount = riskCapitalToUse * RiskPercentage / 100.0;

        if (stopLossDistancePoints <= 0.0)
        {
            stopLossDistancePoints = MathAbs(marketPrice - stopLossPrice) / tickSize;

            if (stopLossDistancePoints <= 5) // Minimalny SL
                return 0.0;
        }

        double lossPerLot = stopLossDistancePoints * tickValue;
        if (lossPerLot > 0.0)
        {
            lotSize = riskAmount / lossPerLot;
        }
        else
        {
            return 0.0;
        }
    }

    // 🔒 Dopasowanie do ograniczeń brokera (bez zmiany logiki risk modelu)
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if (volStep > 0.0)
        lotSize = MathFloor(lotSize / volStep) * volStep; // zaokrąglenie w dół do kroku

    if (volMin > 0.0 && lotSize < volMin)
        lotSize = volMin;

    if (volMax > 0.0 && lotSize > volMax)
        lotSize = volMax;

    return NormalizeDouble(lotSize, 2);
}



// ─────────────────────────────────────────────────────────────
// Funkcja: CalculateSLAndTP
// Opis:    Ustala poziomy SL/TP wg wybranej metody:
//          (0) po ostatnich ważnych szczytach/dołkach (Highs/Lows),
//          (1) konsolidacja: entry ± range*SLMultiplier,
//          (2) stałe SLPoints,
//          (3) świeca sygnałowa (candleHistory[1]) ± SLPoints.
//          Następnie wylicza TP jako wielokrotność odległości SL od ceny wejścia (TPMultiplier).
// Wywołuje: SymbolInfoDouble(), SymbolInfoInteger(), Print(), NormalizeDouble().
// Globalne/extern: _Symbol, _Digits, Highs[], Lows[] (z PeaksEnded11.mqh),
//                  candleHistory[], maxHigh, minLow (z modułów danych), _Period.
// Zwraca:  przez referencje: stopLossPrice, takeProfitPrice.
// ─────────────────────────────────────────────────────────────
void CalculateSLAndTP(
    double &stopLossPrice,
    double &takeProfitPrice,
    int UseSLMethod,
    double entryPrice,
    bool isBuy,
    double SLMultiplier,
    double SLPoints,
    double TPMultiplier)
{
    double range = maxHigh - minLow;

    if (range <= 0)
    {
        stopLossPrice = 0;
        takeProfitPrice = 0;
        return;
    }

    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minStopDistance = stopLevel * point;

    if (UseSLMethod == 0) // Metoda szczytów/dołków
    {
        stopLossPrice = 0;

        if (isBuy)
        {
            for (int i = 1; i < ArraySize(Lows); i++)
            {
                if (!Lows[i].isValid) continue;

                double low = Lows[i].value;
                if (low < entryPrice && (entryPrice - low) >= minStopDistance)
                {
                    stopLossPrice = NormalizeDouble(low, _Digits);
                    break;
                }
            }
        }
        else // SELL
        {
            for (int i = 1; i < ArraySize(Highs); i++)
            {
                if (!Highs[i].isValid) continue;

                double high = Highs[i].value;
                if (high > entryPrice && (high - entryPrice) >= minStopDistance)
                {
                    stopLossPrice = NormalizeDouble(high, _Digits);
                    break;
                }
            }
        }
    }
    else if (UseSLMethod == 1) // Metoda konsolidacji
    {
        stopLossPrice = (SLMultiplier == 0) ? 0 :
                        (isBuy ? NormalizeDouble(entryPrice - range * SLMultiplier, _Digits)
                               : NormalizeDouble(entryPrice + range * SLMultiplier, _Digits));
    }
    else if (UseSLMethod == 2) // SL w punktach
    {
        if (SLPoints > 0)
        {
            double slDistance = SLPoints * point;
            stopLossPrice = isBuy ? NormalizeDouble(entryPrice - slDistance, _Digits)
                                  : NormalizeDouble(entryPrice + slDistance, _Digits);
        }
        else
        {
            stopLossPrice = 0;
        }
    }
    else if (UseSLMethod == 3) // SL na podstawie świecy sygnałowej ± SLPoints
    {
        if (ArraySize(candleHistory) < 2)
        {
            Print("⚠️ Brak świecy sygnałowej do SLMethod 3");
            stopLossPrice = 0;
        }
        else
        {
            MqlRates signalCandle = candleHistory[1];
            double slDistance = SLPoints * point;

            stopLossPrice = isBuy
                            ? NormalizeDouble(signalCandle.low - slDistance, _Digits)
                            : NormalizeDouble(signalCandle.high + slDistance, _Digits);

            // Weryfikacja minimalnego dystansu od entry
            double distance = MathAbs(entryPrice - stopLossPrice);
            if (distance < minStopDistance)
            {
                Print("⛔ SL zbyt blisko ceny wejścia – metoda 3");
                stopLossPrice = 0;
            }
        }
    }

    // TP jako wielokrotność odległości SL od ceny wejścia
    if (stopLossPrice > 0 && TPMultiplier > 0)
    {
        double slDistance = isBuy ? (entryPrice - stopLossPrice) : (stopLossPrice - entryPrice);
        takeProfitPrice = isBuy
                          ? NormalizeDouble(entryPrice + slDistance * TPMultiplier, _Digits)
                          : NormalizeDouble(entryPrice - slDistance * TPMultiplier, _Digits);
    }
    else
    {
        takeProfitPrice = 0;
    }
}



// ─────────────────────────────────────────────────────────────
// Funkcja: CheckClosingConditions
// Opis:    Realizuje warunki zamykania pozycji:
//          (a) o określonej godzinie (hourToClose), lub
//          (b) po odczekaniu zadanej liczby świec od otwarcia (candleCountToWait).
//          Przegląda aktywne pozycje/zlecenia i decyduje o CloseOrdersAndPositions().
// Wywołuje: TimeCurrent(), TimeToStruct(), CloseOrdersAndPositions(), PeriodSeconds().
// Globalne/extern: hourToClose, candleCountToWait, inputMagicNumber,
//                  activeOrdersAndPositions[], _Symbol, _Period.
// ─────────────────────────────────────────────────────────────
void CheckClosingConditions()
{
    static datetime lastCloseTime = 0;       // Czas ostatniego zamknięcia
    static datetime positionOpenTime = 0;    // Czas otwarcia pozycji
    static bool positionDetected = false;    // Flaga wykrycia otwartej pozycji

    datetime currentTime = TimeCurrent();
    MqlDateTime currentDateTime;
    TimeToStruct(currentTime, currentDateTime);

    // Sprawdź, czy zamykanie o określonej godzinie jest aktywne
    if (hourToClose > 0 && currentDateTime.hour == hourToClose && lastCloseTime != currentTime)
    {
        lastCloseTime = currentTime;
        CloseOrdersAndPositions(); // Wywołanie funkcji zamykającej
        Print("Zamknięto po upływie ustalonego czasu");
    }

    // Sprawdź, czy istnieje otwarta pozycja dla danego symbolu i magic number
    positionDetected = false;
    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];
        if (opd.isOpen && opd.symbol == _Symbol && opd.magic == inputMagicNumber)
        {
            positionDetected = true;
            break;
        }
    }

    if (positionDetected)
    {
        // Inicjalizacja czasu otwarcia pozycji
        if (positionOpenTime == 0)
        {
            positionOpenTime = currentTime;
        }

        // Sprawdź, czy zamykanie na podstawie liczby świec jest aktywne
        if (candleCountToWait > 0)
        {
            int periodSeconds = PeriodSeconds(_Period);
            datetime closingTime = positionOpenTime + (candleCountToWait * periodSeconds);

            if (currentTime >= closingTime)
            {
                positionOpenTime = 0; // Zresetuj czas otwarcia pozycji
                Print("Upłynął wymagany czas na podstawie liczby świec.");
                CloseOrdersAndPositions();
            }
        }
    }
    else
    {
        // Resetuj czas otwarcia, jeśli nie ma aktywnej pozycji
        positionOpenTime = 0;
    }
}


// ─────────────────────────────────────────────────────────────
// (flaga) PrintCancelOldPendingOrders – steruje logowaniem w CancelOldPendingOrders
// ─────────────────────────────────────────────────────────────
bool PrintCancelOldPendingOrders = false;


// ─────────────────────────────────────────────────────────────
// Funkcja: CancelOldPendingOrders
// Tematyka: porządkowanie starych zleceń oczekujących.
// Opis:    Odświeża stan zleceń/pozycji, dla bieżącej zamkniętej świecy (candleHistory[1])
//          wyznacza jej indeks i dla zleceń oczekujących (z danym magicNumber i symbolem)
//          sprawdza ich „wiek” w świecach. Jeśli ≥ maxBarsToWait – usuwa zlecenie.
// Wywołuje: RefreshOrderAndPositionData(), FindIndexByTime(), OrderSelect(), trade.OrderDelete().
// Globalne/extern: candleHistory[], activeOrdersAndPositions[], _Symbol,
//                  PrintCancelOldPendingOrders (lokalna flaga).
// ─────────────────────────────────────────────────────────────
void CancelOldPendingOrders(int maxBarsToWait, ulong magicNumber)
{
    RefreshOrderAndPositionData();
    
    datetime currentCandleTime = candleHistory[1].time;  // Świeca zamknięta
    int currentIndex = FindIndexByTime(currentCandleTime);
    if (currentIndex == -1)
    {
        if (PrintCancelOldPendingOrders)
            Print("⚠️ Nie znaleziono indeksu dla bieżącej świecy (index = -1)");
        return;
    }

    int cancelCount = 0;

    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];

        if (!opd.isPending || opd.magic != magicNumber || opd.symbol != _Symbol)
            continue;

        // 🔍 Debug: podstawowe informacje o zleceniu
        if (PrintCancelOldPendingOrders)
            PrintFormat("🧪 DEBUG: isPending=%d, type=%d, magic=%d, ticket=%d",
                        opd.isPending, opd.type, opd.magic, opd.ticket);

        int placedAtIndex = FindIndexByTime(opd.openTime);
        if (placedAtIndex == -1)
        {
            if (PrintCancelOldPendingOrders)
                PrintFormat("❌ Nie znaleziono indeksu świecy dla openTime=%s", TimeToString(opd.openTime));
            continue;
        }

        int barsPassed = placedAtIndex - currentIndex;

        // 🔍 Debug: porównanie czasu
        if (PrintCancelOldPendingOrders)
            PrintFormat("⏱️ Zlecenie oczekujące %d: openTime=%s (i=%d) vs now=%s (i=%d) → barsPassed=%d",
                        opd.ticket,
                        TimeToString(opd.openTime), placedAtIndex,
                        TimeToString(currentCandleTime), currentIndex,
                        barsPassed);

        if (barsPassed >= maxBarsToWait)
        {
            if (OrderSelect(opd.ticket))
            {
                trade.SetExpertMagicNumber(magicNumber);
                if (trade.OrderDelete(opd.ticket))
                {
                    cancelCount++;
                    if (PrintCancelOldPendingOrders)
                        PrintFormat("🧹 Usunięto stare zlecenie oczekujące: ticket=%d (wiek: %d świec)", opd.ticket, barsPassed);
                }
                else
                {
                    if (PrintCancelOldPendingOrders)
                        PrintFormat("❌ Błąd przy usuwaniu zlecenia %d | code=%d", opd.ticket, GetLastError());
                }
            }
            else
            {
                if (PrintCancelOldPendingOrders)
                    PrintFormat("❌ OrderSelect nie powiodło się dla ticket=%d", opd.ticket);
            }
        }
    }

    if (cancelCount > 0)
        PrintFormat("✅ Usunięto %d przeterminowanych zleceń oczekujących.", cancelCount);
}


// ─────────────────────────────────────────────────────────────
// Funkcja: CloseOrdersAndPositions
// Opis:    Dla aktualnego symbolu i zdefiniowanego inputMagicNumber
//          zamyka wszystkie otwarte pozycje i usuwa zlecenia oczekujące.
// Wywołuje: trade.PositionClose(), trade.OrderDelete(), PrintFormat().
// Globalne/extern: activeOrdersAndPositions[], _Symbol, inputMagicNumber.
// ─────────────────────────────────────────────────────────────
void CloseOrdersAndPositions()
{
    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];

        // Tylko dla tego samego symbolu i magic number
        if (opd.symbol != _Symbol || opd.magic != inputMagicNumber)
            continue;

        // Zamknięcie otwartych pozycji
        if (opd.isOpen)
        {
            if (!trade.PositionClose(opd.symbol))
            {
                PrintFormat("Błąd przy zamykaniu pozycji: %s, ticket=%d, error=%d", opd.symbol, opd.ticket, GetLastError());
            }
            else
            {
                PrintFormat("Zamknięto pozycję dla symbolu: %s, ticket=%d", opd.symbol, opd.ticket);
            }
        }

        // Anulowanie oczekujących zleceń
        if (opd.isPending)
        {
            if (!trade.OrderDelete(opd.ticket))
            {
                PrintFormat("Błąd przy anulowaniu zlecenia oczekującego: ticket=%d, error=%d", opd.ticket, GetLastError());
            }
            else
            {
                PrintFormat("Anulowano zlecenie oczekujące: ticket=%d", opd.ticket);
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────
// Funkcja: ClosePositionsByRSI
// Opis:    Dla pozycji z danym magicNumber i symbolem – na podstawie sygnałów RSI
//          (przecięcia poziomów wykupienia/wyprzedania oraz poziomu „SL RSI”)
//          zamyka pozycje po odczekaniu minimalnej liczby świec (inputRsiSlCandleToWait).
//          [Poprawka]: Używa trade.PositionClose(opd.symbol) (spójnie z resztą pliku).
// Wywołuje: CopyBuffer(rsiHandle), trade.PositionClose(), RefreshOrderAndPositionData().
// Globalne/extern: rsiHandle, inputRSIPeriod, inputRsiSlCandleToWait,
//                  activeOrdersAndPositions[], _Symbol, PERIOD_CURRENT.
// ─────────────────────────────────────────────────────────────
void ClosePositionsByRSI(ulong magicNumber, double rsiLevelOverbought, double rsiLevelOversold, double rsiSlLevel) 
{
    if (inputRSIPeriod == 0)
        return;

    if (rsiHandle == INVALID_HANDLE)
    {
        Print("[ERROR RSI] RSI handle not initialized");
        return;
    }

    double buffer[2];
    if (CopyBuffer(rsiHandle, 0, 0, 2, buffer) != 2)
    {
        Print("[ERROR RSI] Cannot get RSI values");
        return;
    }

    double lastRSI = buffer[0];
    double prevRSI = buffer[1];
    
    PrintFormat("🔁 RSI check: prevRSI = %.2f, lastRSI = %.2f", prevRSI, lastRSI);

    RefreshOrderAndPositionData();
    datetime currentTime = TimeCurrent();
    int tfSeconds = PeriodSeconds(PERIOD_CURRENT);

    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];

        if (!opd.isOpen || opd.magic != magicNumber || opd.symbol != _Symbol)
            continue;

        int barsSinceOpen = (int)((currentTime - opd.openTime) / tfSeconds);
        bool allowReversalClose = barsSinceOpen >= inputRsiSlCandleToWait;

        if (opd.type == POSITION_TYPE_BUY)
        {
            bool reversalClose = (prevRSI >= rsiLevelOverbought && lastRSI <= rsiLevelOverbought);
            bool slClose = (lastRSI <= rsiSlLevel);

            if ((allowReversalClose && reversalClose) || slClose)
            {
                if (trade.PositionClose(opd.symbol))
                    PrintFormat("[INFO RSI] Closed BUY position (ticket: %d)", opd.ticket);
            }
        }

        if (opd.type == POSITION_TYPE_SELL)
        {
            bool reversalClose = (prevRSI <= rsiLevelOversold && lastRSI >= rsiLevelOversold);
            bool slClose = (lastRSI >= rsiSlLevel);

            if ((allowReversalClose && reversalClose) || slClose)
            {
                if (trade.PositionClose(opd.symbol))
                    PrintFormat("[INFO RSI] Closed SELL position (ticket: %d)", opd.ticket);
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────
// Funkcja: ApplyTrailingStop
// Opis:    Prosty trailing stop oparty o lokalne ekstremum (Highs[2]/Lows[2])
//          i minimalny bufor (50 „pipsów” = 50 * _Point). Dla BUY podnosi SL
//          pod Low[2], dla SELL opuszcza SL nad High[2], gdy cena oddaliła się
//          o bufor. [Poprawka]: sprawdza dostępność i ważność Highs[2]/Lows[2].
// Wywołuje: SymbolInfoDouble(), ModifyStopLoss().
// Globalne/extern: inputTrailingStop, activeOrdersAndPositions[], Highs[], Lows[], _Symbol.
// ─────────────────────────────────────────────────────────────
void ApplyTrailingStop(ulong magicNumber)
{
    if (!inputTrailingStop)
        return; // Trailing Stop wyłączony

    // ── Safety: upewnij się, że mamy wystarczającą liczbę ekstremów i są ważne
    bool lowsReady  = (ArraySize(Lows)  > 2 && Lows[2].isValid);
    bool highsReady = (ArraySize(Highs) > 2 && Highs[2].isValid);

    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];

        if (!opd.isOpen || opd.magic != magicNumber || opd.symbol != _Symbol)
            continue;

        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 50; // 50 pipsów

        // Pozycja DŁUGA
        if (opd.type == POSITION_TYPE_BUY && lowsReady)
        {
            double low2 = Lows[2].value;
            if (opd.sl < low2)
            {
                if (currentPrice >= low2 + pipValue)
                {
                    ModifyStopLoss(opd.ticket, low2);
                }
            }
        }
        // Pozycja KRÓTKA
        else if (opd.type == POSITION_TYPE_SELL && highsReady)
        {
            double high2 = Highs[2].value;
            if (opd.sl > high2)
            {
                if (currentPrice <= high2 - pipValue)
                {
                    ModifyStopLoss(opd.ticket, high2);
                }
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────
// Funkcja: ApplyCandleBasedTrailingStop
// Opis:    Trailing stop „świecowy”. Na zamknięciu każdej świecy (candleHistory[1])
//          przesuwa SL pod (dla BUY) lub nad (dla SELL) świecę, z niewielkim buforem.
//          [Poprawka]: dodatkowe zabezpieczenia na dostępność danych.
// Wywołuje: ModifyStopLoss(), SymbolInfoDouble().
// Globalne/extern: candleHistory[], activeOrdersAndPositions[], _Digits, _Symbol.
// ─────────────────────────────────────────────────────────────
void ApplyCandleBasedTrailingStop(ulong magicNumber)
{
    static datetime lastTrailingCandleTime = 0;

    if (ArraySize(candleHistory) < 2) return;

    MqlRates closedCandle = candleHistory[1];  // świeca, która właśnie się zamknęła

    // Sprawdź, czy to nowa świeca
    if (closedCandle.time <= lastTrailingCandleTime)
        return;

    lastTrailingCandleTime = closedCandle.time;

    double bufferPoints = 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    for (int i = 0; i < ArraySize(activeOrdersAndPositions); i++)
    {
        OrderPositionData opd = activeOrdersAndPositions[i];

        if (!opd.isOpen || opd.magic != magicNumber || opd.symbol != _Symbol)
            continue;

        double newSL = 0;

        if (opd.type == POSITION_TYPE_BUY)
        {
            double low = closedCandle.low;
            newSL = NormalizeDouble(low - bufferPoints, _Digits);

            if (newSL > opd.sl)  // tylko jeśli SL się podnosi
                ModifyStopLoss(opd.ticket, newSL);
        }
        else if (opd.type == POSITION_TYPE_SELL)
        {
            double high = closedCandle.high;
            newSL = NormalizeDouble(high + bufferPoints, _Digits);

            if (newSL < opd.sl)  // tylko jeśli SL się obniża
                ModifyStopLoss(opd.ticket, newSL);
        }
    }
}


// ─────────────────────────────────────────────────────────────
// Funkcja: ModifyStopLoss
// Opis:    Modyfikuje SL pozycji wskazanej ticketem przez wysłanie
//          żądania TRADE_ACTION_SLTP. TP pobierany z pozycji (PositionSelectByTicket + POSITION_TP).
//          [Poprawka]: jawne PositionSelectByTicket(ticket) przed pobraniem TP.
// Wywołuje: OrderSend(), PositionSelectByTicket(), PositionGetDouble(), Print().
// Globalne/extern: brak bezpośrednich własnych (korzysta z API handlowego MQL5).
// Zwraca:  void.
// ─────────────────────────────────────────────────────────────
void ModifyStopLoss(ulong ticket, double newSL)
{
    double tpCurrent = 0.0;
    if (PositionSelectByTicket(ticket))
        tpCurrent = PositionGetDouble(POSITION_TP); // TP z właściwej pozycji

    MqlTradeRequest request;
    MqlTradeResult  result;
    ZeroMemory(request);

    request.action   = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl       = newSL;
    request.tp       = tpCurrent;

    if (!OrderSend(request, result))
    {
        Print("[ERROR] Nie udało się zmodyfikować SL dla pozycji ", ticket);
    }
    else
    {
        Print("[INFO] Zmodyfikowano SL dla pozycji ", ticket, " na ", newSL);
    }
}

#endif
