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

//datetime lastCandleTime = 0;     // Zmienna przechowująca czas ostatniej świecy

double minLow = 0;        // Minimalna cena w sekwencji
double maxHigh = 0;       // Maksymalna cena w sekwencji


// ====================================================================
// OPIS FUNKCJI: CalculateAverageCandleHeight
// Co robi:
//   Liczy średnią wysokość świecy (high-low) z ostatnich N świec.
//   Ustawia globalne: avgCandleHeight oraz threshold (kopiuje userThreshold).
// Woła:
//   Wbudowane: MathMin, ArraySize, Print.
//   Funkcje użytkownika: brak.
// Używane zmienne globalne:
//   - avgCandleHeight (zapis),
//   - threshold (zapis).
// Używane extern/input:
//   - candleHistory (MqlRates[]) z CandleAndTranactionData11.mqh (odczyt),
//   - userThreshold (double) z Zmienne11.mqh (odczyt).
// Zwraca:
//   Średnią wysokość świecy (double). Zabezpieczenie na brak danych: 0.00001.
// ====================================================================
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
   

// ====================================================================
// OPIS FUNKCJI: CalculateLastCandleHeight
// Co robi:
//   Dla świecy o indeksie [1] wyznacza:
//   - pełną wysokość świecy (high-low) oraz % względem avgCandleHeight,
//   - wysokość korpusu |open-close| oraz % względem avgCandleHeight,
//   - PercentOfAvg = % (zaokrąglony) wysokości świecy względem średniej.
// Woła:
//   Wbudowane: MathAbs.
//   Funkcje użytkownika: brak.
// Używane zmienne globalne (odczyt/zapis):
//   - avgCandleHeight (odczyt),
//   - CandleHeight, CandlePercentage, CandleHeightOC, CandlePercentageOC, PercentOfAvg (zapis).
// Używane extern/input:
//   - candleHistory[1] (MqlRates) z CandleAndTranactionData11.mqh (odczyt).
// Zwraca:
//   void (wyniki w zmiennych globalnych).
// ====================================================================
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

// ====================================================================
// OPIS FUNKCJI: CalculateAverageVolume
// Co robi:
//   Liczy średni tick_volume z ostatnich 'volumeCandles' świec.
// Woła:
//   Wbudowane: MathMin, ArraySize.
//   Funkcje użytkownika: brak.
// Używane zmienne globalne:
//   (brak – funkcja działa na danych wejściowych i zwraca wynik)
// Używane extern/input:
//   - candleHistory (MqlRates[]) z CandleAndTranactionData11.mqh (odczyt .tick_volume).
// Zwraca:
//   Średni tick_volume (double); 0.0 gdy brak świec do analizy.
// ====================================================================
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

// ====================================================================
// OPIS FUNKCJI: IsValidBreakoutCandle
// Co robi:
//   Waliduje świecę jako „wybicie” jeśli spełnia jednocześnie dwa warunki:
//   1) candleHeight > avgCandleHeight * sizeMultiplierLocal,
//   2) volume       > avgVolumeLocal  * volumeMultiplierLocal,
//   gdzie avgVolumeLocal = CalculateAverageVolume(volumeBarsLocal).
// Woła:
//   - CalculateAverageVolume(volumeBarsLocal).
// Używane zmienne globalne (odczyt):
//   - avgCandleHeight.
// Używane extern/input:
//   - candleHistory[index] (MqlRates) z CandleAndTranactionData11.mqh (odczyt).
// Zwraca:
//   true/false – czy świeca spełnia kryteria wybicia wielkością i wolumenem.
// ====================================================================
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
