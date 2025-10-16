//+----------------------------------------------------------------------+
//| PeaksEnded.mqh                                                       |
//| Plik zawierający logikę  pobierania peaksów oraz tablicę peak        |
//+----------------------------------------------------------------------+
#ifndef __PEAK_MQH__
#define __PEAK_MQH__

#property strict


#include <StartTester/CandleAndTranactionData11.mqh>

//+------------------------------------------------------------------+
//| Struktura przechowująca informacje o ekstremum                   |
//+------------------------------------------------------------------+
struct Peak {
    int index;          // Indeks świecy
    double value;       // Cena szczytu/dołka
    bool isValid;       // Czy poziom jest nadal ważny?
    datetime time;      // Czas świecy

};

int Inpshoulder = 3;

Peak Highs[20];   // Tablica szczytów
Peak Lows[20];    // Tablica dołków

//+------------------------------------------------------------------+
//| Znajdowanie szczytu lub dołka                                    |
//+------------------------------------------------------------------+
int FindPeak(int mode, int count, int startBar) {
    if (mode != MODE_HIGH && mode != MODE_LOW) return -1;

    int currentBar = startBar;
    int foundBar = FindNextPeak(mode, count * 2 + 1, currentBar - count);
    while (foundBar != currentBar) {
        currentBar = FindNextPeak(mode, count, currentBar + 1);
        foundBar = FindNextPeak(mode, count * 2 + 1, currentBar - count);
    }
    return currentBar;
}

//+------------------------------------------------------------------+
//| Znajdowanie kolejnego ekstremum                                  |
//+------------------------------------------------------------------+
int FindNextPeak(int mode, int count, int startBar) {
    if (startBar < 0) {
        count += startBar;
        startBar = 0;
    }
    return (mode == MODE_HIGH ?
            iHighest(_Symbol, PERIOD_CURRENT, (ENUM_SERIESMODE)mode, count, startBar) :
            iLowest(_Symbol, PERIOD_CURRENT, (ENUM_SERIESMODE)mode, count, startBar));
}

//+------------------------------------------------------------------+
//| Wypełnienie tablic Highs i Lows                                  |
//+------------------------------------------------------------------+
void Peaks() {
    for (int i = 0; i < 20; i++) {
        if (i == 0) {
            Highs[i].index = FindPeak(MODE_HIGH, Inpshoulder, 0);
            Lows[i].index = FindPeak(MODE_LOW, Inpshoulder, 0);
        } else {
            Highs[i].index = FindPeak(MODE_HIGH, Inpshoulder, Highs[i - 1].index + 1);
            Lows[i].index = FindPeak(MODE_LOW, Inpshoulder, Lows[i - 1].index + 1);
        }

        // Jeśli indeks poprawny, pobierz dane o świecy
        if (Highs[i].index >= 0) {
            Highs[i].value = iHigh(_Symbol, PERIOD_CURRENT, Highs[i].index);
            Highs[i].time = iTime(_Symbol, PERIOD_CURRENT, Highs[i].index);
            Highs[i].isValid = true;

        }

        if (Lows[i].index >= 0) {
            Lows[i].value = iLow(_Symbol, PERIOD_CURRENT, Lows[i].index);
            Lows[i].time = iTime(_Symbol, PERIOD_CURRENT, Lows[i].index);
            Lows[i].isValid = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Filtrowanie ekstremów na podstawie późniejszego ruchu ceny       |
//+------------------------------------------------------------------+
void FilterPeaks() {
    for (int i = 0; i < 10; i++) {
        // --- Filtrowanie szczytów ---
        if (Highs[i].index > 1) {
            for (int j = Highs[i].index - 1; j > 0; j--) {
                double high = iOpen(_Symbol, PERIOD_CURRENT, j);
                double low = iClose(_Symbol, PERIOD_CURRENT, j);
                double prevClose = iClose(_Symbol, PERIOD_CURRENT, j - 1);

                if ((low <= Highs[i].value && high <= Highs[i].value) &&
                    (prevClose > Highs[i].value)) {
                    Highs[i].isValid = false;
                    break;
                }
            }
        }

        // --- Filtrowanie dołków ---
        if (Lows[i].index > 1) {
            for (int j = Lows[i].index - 1; j > 0; j--) {
                double high = iOpen(_Symbol, PERIOD_CURRENT, j);
                double low = iClose(_Symbol, PERIOD_CURRENT, j);
                double prevClose = iClose(_Symbol, PERIOD_CURRENT, j - 1);

                if ((low >= Lows[i].value && high >= Lows[i].value) &&
                    (prevClose < Lows[i].value)) {
                    Lows[i].isValid = false;
                    break;
                }
            }
        }
    }
}

#endif // __PEAK_MQH__
