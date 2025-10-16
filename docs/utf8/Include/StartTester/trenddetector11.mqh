//+------------------------------------------------------------------+
//| trenddetector11.mqh                                              |
//| plik zawierający logikę wykrywania trendu                        |
//+------------------------------------------------------------------+
#property strict

#ifndef __TRENDDETECTOR_MQH__
#define __TRENDDETECTOR_MQH__

#include <strings/String.mqh>
#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>
#include <StartTester/PeaksEnded11.mqh>
#include <StartTester/DrawingTools11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/BuySellFunction11.mqh>

// ─────────────────────────────────────────────────────────────
// Ustawienia okresów MA wykorzystywanych w DetectTrendByMA()
input int TD_EMA_Period = 20;
input int TD_SMA_Period = 50;

// ─────────────────────────────────────────────────────────────
// Własne liczenie MA na CLOSE (bez iMA)

// sprawdza czy mamy okno [shift .. shift+period-1] w candleHistory
bool TD__HasWindow(const int shift, const int period)
{
   const int total = ArraySize(candleHistory);
   if (period <= 0) return false;
   if (shift < 1)   return false;                 // 1 = ostatnia zamknięta świeca
   if (shift + period - 1 >= total) return false; // potrzebujemy historii aż do najstarszego punktu okna
   return true;
}

// proste SMA na CLOSE
double TD__SMA_Close(const int shift, const int period)
{
   if (!TD__HasWindow(shift, period)) return 0.0;
   double s = 0.0;
   for (int k = shift; k < shift + period; ++k)
      s += candleHistory[k].close;
   return s / period;
}

// EMA na CLOSE z zasianiem SMA z najstarszej części okna
// seed na indeksie seedIdx = shift + period - 1, potem schodzimy do "shift"
double TD__EMA_Close(const int shift, const int period)
{
   if (!TD__HasWindow(shift, period)) return 0.0;

   const int seedIdx = shift + period - 1;
   double ema = TD__SMA_Close(seedIdx - period + 1, period);
   if (ema == 0.0) return 0.0;

   const double alpha = 2.0 / (period + 1.0);
   for (int i = seedIdx - 1; i >= shift; --i)
      ema = alpha * candleHistory[i].close + (1.0 - alpha) * ema;

   return ema;
}

// ─────────────────────────────────────────────────────────────
// Funkcja wykrywająca trend
// Określenie typu trendu
enum TrendType { TREND_UP, TREND_DOWN, TREND_RANGE };
TrendType currentTrend = TREND_RANGE;

// Zmienna kierunkowa – wynik analizy trendu
bool BuyOnly = false;
bool SellOnly = false;

// Główna funkcja wykrywająca trend na podstawie struktury rynku (szczyty i dołki)
void DetectTrendByStructure()
{
    int validHighsCount = 0;
    int validLowsCount  = 0;

    double hh1 = -1, hh2 = -1;  // dwa ostatnie ważne szczyty
    double ll1 = -1, ll2 = -1;  // dwa ostatnie ważne dołki

    // Szukanie dwóch ostatnich ważnych szczytów (Highs)
    for (int i = 1; i < ArraySize(Highs); i++)
    {
        if (Highs[i].isValid)
        {
            hh2 = hh1;
            hh1 = Highs[i].value;
            validHighsCount++;
            if (validHighsCount == 2) break;
        }
    }

    // Szukanie dwóch ostatnich ważnych dołków (Lows)
    for (int i = 1; i < ArraySize(Lows); i++)
    {
        if (Lows[i].isValid)
        {
            ll2 = ll1;
            ll1 = Lows[i].value;
            validLowsCount++;
            if (validLowsCount == 2) break;
        }
    }

    if (validHighsCount == 2 && validLowsCount == 2)
    {
        bool isUp   = (hh1 > hh2 && ll1 > ll2);
        bool isDown = (hh1 < hh2 && ll1 < ll2);

        if (isUp)        currentTrend = TREND_UP;
        else if (isDown) currentTrend = TREND_DOWN;
        else             currentTrend = TREND_RANGE;
    }
    else
    {
        currentTrend = TREND_RANGE;
    }

    BuyOnly  = (currentTrend == TREND_UP);
    SellOnly = (currentTrend == TREND_DOWN);
}

// Naruszenie S/R
bool isAboveResistance = false;
bool isBelowSupport    = false;
bool isTouchingResistance = false;
bool isTouchingSupport    = false;

double resistancePrice = 0;
double supportPrice    = 0;

void CheckTrendLines()
{
    // Reset flag
    isAboveResistance   = false;
    isBelowSupport      = false;
    isTouchingResistance= false;
    isTouchingSupport   = false;

    for (int i = 0; i < ArraySize(SupportResistanceLevels); i++)
    {
        SupportResistanceLevel level = SupportResistanceLevels[i];

        if (level.type == LEVEL_RESISTANCE)
        {
            resistancePrice = level.price;

            if (candleHistory[1].open < resistancePrice && candleHistory[1].close > resistancePrice)
                isAboveResistance = true;

            if (candleHistory[1].open < resistancePrice &&
                candleHistory[1].high >= resistancePrice &&
                candleHistory[1].close <= resistancePrice &&
                candleHistory[1].close > candleHistory[1].open)
                isTouchingResistance = true;
        }

        if (level.type == LEVEL_SUPPORT)
        {
            supportPrice = level.price;

            if (candleHistory[1].open > supportPrice && candleHistory[1].close < supportPrice)
                isBelowSupport = true;

            if (candleHistory[1].open > supportPrice &&
                candleHistory[1].low  <= supportPrice &&
                candleHistory[1].close >  supportPrice &&
                candleHistory[1].close <  candleHistory[1].open)
                isTouchingSupport = true;
        }
    }
}

// Sprawdza duże wybicia dla sell
bool IsCloseTouchedByCandleSell(int startIndex, int endIndex)
{
    if (startIndex >= endIndex || startIndex < 1) return false;

    double closeLevel = iClose(_Symbol, PERIOD_CURRENT, 1);

    for (int i = startIndex; i <= endIndex; i++)
    {
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        if (low <= closeLevel) return true;
    }
    return false;
}

// Sprawdza duże wybicia dla buy
bool IsCloseTouchedByCandleBuy(int startIndex, int endIndex)
{
    if (startIndex >= endIndex || startIndex < 1) return false;

    double closeLevel = iClose(_Symbol, PERIOD_CURRENT, 1);

    for (int i = startIndex; i <= endIndex; i++)
    {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        if (high >= closeLevel) return true;
    }
    return false;
}

// Szuka trendu EMA i SMA (bez iMA – liczymy własne EMA/SMA z candleHistory)
enum MarketDirection {
   MARKET_FLAT,
   MARKET_UP,
   MARKET_DOWN
};

MarketDirection currentDirection = MARKET_FLAT;
bool waitingForConfirmation = false;

MarketDirection DetectTrendByMA()
{
   // potrzebujemy co najmniej max(TD_EMA_Period, TD_SMA_Period) + 2 świec
   const int total = ArraySize(candleHistory);
   const int need  = MathMax(TD_EMA_Period, TD_SMA_Period) + 2;
   if (total < need) return currentDirection;

   // bieżąca i poprzednia wartość EMA/SMA na CLOSE
   double emaNow  = TD__EMA_Close(1, TD_EMA_Period);
   double emaPrev = TD__EMA_Close(2, TD_EMA_Period);
   double smaNow  = TD__SMA_Close(1, TD_SMA_Period);
   double smaPrev = TD__SMA_Close(2, TD_SMA_Period);

   if (emaNow==0.0 || emaPrev==0.0 || smaNow==0.0 || smaPrev==0.0)
      return currentDirection;

   double close1 = candleHistory[1].close;

   if (!waitingForConfirmation)
   {
      if (emaPrev < smaPrev && emaNow > smaNow)
      {
         waitingForConfirmation = true;
         currentDirection = MARKET_FLAT;
      }
      else if (emaPrev > smaPrev && emaNow < smaNow)
      {
         waitingForConfirmation = true;
         currentDirection = MARKET_FLAT;
      }
   }
   else
   {
      if (close1 > emaPrev && close1 > smaPrev)
      {
         waitingForConfirmation = false;
         currentDirection = MARKET_UP;
         // DrawDirectionArrow(candleHistory[1].time, close1, currentDirection, clrLime);
      }
      else if (close1 < emaPrev && close1 < smaPrev)
      {
         waitingForConfirmation = false;
         currentDirection = MARKET_DOWN;
         // DrawDirectionArrow(candleHistory[1].time, close1, currentDirection, clrRed);
      }
   }

   return currentDirection;
}

// Szuka trendu dla ADX
MarketDirection currentDirectionADX = MARKET_FLAT;

MarketDirection DetectTrendByADX()
{
   if (ArraySize(candleHistory) < 2) return currentDirectionADX;

   int index = 1; // świeca zamknięta
   double adx     = GetCustomADXAt(index);
   double plusDI  = GetCustomPlusDIAt(index);
   double minusDI = GetCustomMinusDIAt(index);
   double diff    = MathAbs(plusDI - minusDI);

   datetime time  = candleHistory[index].time;
   double close   = candleHistory[index].close;

   double adxThreshold = inputAdxThreshold;
   double diThreshold  = inputDiThreshold;
   double minDiff      = inputMinDiff;

   MarketDirection newDirection = MARKET_FLAT;

   if (adx >= adxThreshold && plusDI >= diThreshold && (plusDI - minusDI) >= minDiff)
      newDirection = MARKET_UP;
   else if (adx >= adxThreshold && minusDI >= diThreshold && (minusDI - plusDI) >= minDiff)
      newDirection = MARKET_DOWN;

   if (newDirection != currentDirectionADX && newDirection != MARKET_FLAT)
   {
      currentDirectionADX = newDirection;
      // DrawDirectionArrow(time, close, currentDirectionADX, (newDirection == MARKET_UP ? clrLightGreen : clrSalmon));
   }

   return currentDirectionADX;
}

// Globalne zmienne
MarketDirection lastTradeDirectionBuy  = MARKET_FLAT;
MarketDirection lastTradeDirectionSell = MARKET_FLAT;

bool canTradeBuyWasFalse  = true;
bool canTradeSellWasFalse = true;

bool signalBuyPending  = false;
bool signalSellPending = false;

// Główna funkcja handlowa
bool CanTrade(MarketDirection &dir,
              double sizeMultiplier,
              double volumeMultiplier,
              int volumeBars)
{
   MarketDirection maDir  = DetectTrendByMA();
   MarketDirection adxDir = DetectTrendByADX();

   MarketDirection consensus = (maDir == adxDir) ? maDir : MARKET_FLAT;
   dir = consensus;

   if (consensus == MARKET_FLAT)
   {
      canTradeBuyWasFalse  = true;
      canTradeSellWasFalse = true;
      signalBuyPending     = false;
      signalSellPending    = false;
      return false;
   }

   // BUY
   if (consensus == MARKET_UP)
   {
      bool breakoutConfirmed = IsValidBreakoutCandle(1, sizeMultiplier, volumeMultiplier, volumeBars);
      bool momentumConfirmed = IsCloseTouchedByCandleBuy(1, 50);

      if ((canTradeBuyWasFalse || lastTradeDirectionBuy != MARKET_UP) && breakoutConfirmed && momentumConfirmed)
      {
         canTradeBuyWasFalse   = false;
         lastTradeDirectionBuy = MARKET_UP;
         signalBuyPending      = true;
         return true;
      }

      if (signalBuyPending && breakoutConfirmed && momentumConfirmed)
      {
         signalBuyPending = false;
         return true;
      }

      return false;
   }

   // SELL
   if (consensus == MARKET_DOWN)
   {
      bool breakoutConfirmed = IsValidBreakoutCandle(1, sizeMultiplier, volumeMultiplier, volumeBars);
      bool momentumConfirmed = IsCloseTouchedByCandleSell(1, 50);

      if ((canTradeSellWasFalse || lastTradeDirectionSell != MARKET_DOWN) && breakoutConfirmed && momentumConfirmed)
      {
         canTradeSellWasFalse    = false;
         lastTradeDirectionSell  = MARKET_DOWN;
         signalSellPending       = true;
         return true;
      }

      if (signalSellPending && breakoutConfirmed && momentumConfirmed)
      {
         signalSellPending = false;
         return true;
      }

      return false;
   }

   return false;
}

#endif  // __TRENDDETECTOR_MQH__
