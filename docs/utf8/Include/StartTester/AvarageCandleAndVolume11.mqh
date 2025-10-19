//+----------------------------------------------------------------------+
//| AvarageCandleAndVolume.mqh                                           |
//| Plik zawierający logikę obliczania średniej świecy i volumenu        |
//+----------------------------------------------------------------------+

#property strict

#ifndef __AVARAGECANDLE_MQH__
#define __AVARAGECANDLE_MQH__

#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>



double avgCandleHeight;     // Zmienna przechowująca średnią wysokość świecy
double threshold;           // Próg dla świec (procent od średniej)
int currentCandleCount = 0; // Liczba świec w bieżącej sekwencji

//datetime lastCandleTime = 0;     // Zmienna przechowująca czas ostatniej świecy
datetime sequenceStartTime = 0;  // Zmienna przechowująca czas rozpoczęcia sekwencji
datetime sequenceEndTime = 0;    // Zmienna przechowująca ostatni element w sekwencji

double minLow = 0;        // Minimalna cena w sekwencji
double maxHigh = 0;       // Maksymalna cena w sekwencji


double CalculateAverageCandleHeight(int candleToCheck)
{
    double totalHeight = 0;
    int candlesToAnalyze = MathMin(ArraySize(candleHistory), candleToCheck);

    if (candlesToAnalyze == 0) {
        Print("[ERROR] Brak świec do analizy w CalculateAverageCandleHeight");
        return 0.00001; // zapobiega dzieleniu przez zero, minimalna wartość
    }

    for (int i = 0; i < candlesToAnalyze; i++)
    {
        totalHeight += candleHistory[i].high - candleHistory[i].low;
    }

    avgCandleHeight = totalHeight / candlesToAnalyze;
    threshold = userThreshold;

    return avgCandleHeight;
}


// Zmienne dla funkcji CalculateLastCandleHeight
   double CandleHeight;
   double CandlePercentage;
   double CandleHeightOC;
   double CandlePercentageOC;
   int PercentOfAvg;
   

void CalculateLastCandleHeight()
{
   double openPrice  = candleHistory[1].open;
   double closePrice = candleHistory[1].close;
   double highPrice  = candleHistory[1].high;
   double lowPrice   = candleHistory[1].low;
   datetime time     = candleHistory[1].time;

   CandleHeight       = highPrice - lowPrice;
   CandlePercentage   = (CandleHeight / avgCandleHeight) * 100;
   CandleHeightOC     = MathAbs(openPrice - closePrice);
   CandlePercentageOC = (CandleHeightOC / avgCandleHeight) * 100;
   PercentOfAvg       = (avgCandleHeight > 0) ? int((CandleHeight / avgCandleHeight) * 100) : 0;
}

// Funkcja do sprawdzania sekwencji małych świec
bool sequenceActive = false;      // Czy aktualnie trwa sekwencja
bool sequenceCompleted = false;  // Czy sekwencja została zakończona

// Oblicz średni wolumen z ostatnich X świec
double CalculateAverageVolume(int volumeCandles)
{
    double totalVolume = 0;
    int barsToCheck = MathMin(ArraySize(candleHistory), volumeCandles);

    for (int i = 0; i < barsToCheck; i++)
    {
        totalVolume += (double)candleHistory[i].tick_volume;
    }

    return (barsToCheck > 0) ? (totalVolume / barsToCheck) : 0.0;
}

bool IsValidBreakoutCandle(int index,
                           double sizeMultiplierLocal,
                           double volumeMultiplierLocal,
                           int volumeBarsLocal)
{
    if (index < 0 || index >= ArraySize(candleHistory))
        return false;

    MqlRates candle = candleHistory[index];
    double candleHeight = candle.high - candle.low;
    double volume = (double)candle.tick_volume;

    double avgVolumeLocal = CalculateAverageVolume(volumeBarsLocal);
    bool isBigCandle = candleHeight > avgCandleHeight * sizeMultiplierLocal;
    bool isHighVolume = volume > avgVolumeLocal * volumeMultiplierLocal;

    return isBigCandle && isHighVolume;
}



#endif
