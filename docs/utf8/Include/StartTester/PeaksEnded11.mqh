//+----------------------------------------------------------------------+
//| PeaksEnded.mqh                                                       |
//| Plik zawierający logikę pobierania peaksów oraz tablicę peak         |
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
//| FindPeak                                                         |
//| Opis:    Wyszukuje indeks świecy z lokalnym ekstremum (szczyt/dołek)
//|          startując od startBar i iteracyjnie zacieśniając okno,
//|          aż do stabilizacji (zbieżności) znalezionego indeksu.
//| Wywołuje: FindNextPeak (w pętli).
//| Globals:  pośrednio używa _Symbol/PERIOD_CURRENT przez FindNextPeak.
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
//| FindNextPeak                                                     |
//| Opis:    Zwraca indeks następnego lokalnego maksimum/minimum w
//|          oknie [startBar, startBar+count). Parametr `mode` to
//|          MODE_HIGH/MODE_LOW i jest bezpośrednio rzutowany na
//|          ENUM_SERIESMODE zgodnie z sygnaturą MQL5.
//| Wywołuje: iHighest, iLowest (platforma).
//| Globals:  _Symbol, PERIOD_CURRENT (platforma MQL5).
//+------------------------------------------------------------------+
int FindNextPeak(int mode, int count, int startBar) {
    if (startBar < 0) {
        count += startBar;
        startBar = 0;
    }

    // Rzutowanie bez zmiany logiki: MODE_HIGH/MODE_LOW -> ENUM_SERIESMODE
    const ENUM_SERIESMODE series = (ENUM_SERIESMODE)mode;

    return (mode == MODE_HIGH
            ? iHighest(_Symbol, PERIOD_CURRENT, series, count, startBar)
            : iLowest (_Symbol, PERIOD_CURRENT, series, count, startBar));
}

//+------------------------------------------------------------------+
//| Peaks                                                            |
//| Opis:    Wypełnia tablice Highs[20] i Lows[20] indeksami pików
//|          (szczyty/dołki), a następnie uzupełnia value/time i
//|          oznacza isValid=true dla znalezionych rekordów.
//| Wywołuje: FindPeak, iHigh, iLow, iTime (platforma).
//| Globals:  Inpshoulder (czyta), Highs/Lows (zapisuje), _Symbol/PERIOD_CURRENT.
//+------------------------------------------------------------------+
void Peaks() {
    for (int i = 0; i < 20; i++) {
        if (i == 0) {
            Highs[i].index = FindPeak(MODE_HIGH, Inpshoulder, 0);
            Lows[i].index  = FindPeak(MODE_LOW,  Inpshoulder, 0);
        } else {
            Highs[i].index = FindPeak(MODE_HIGH, Inpshoulder, Highs[i - 1].index + 1);
            Lows[i].index  = FindPeak(MODE_LOW,  Inpshoulder, Lows[i - 1].index + 1);
        }

        // Jeśli indeks poprawny, pobierz dane o świecy
        if (Highs[i].index >= 0) {
            Highs[i].value   = iHigh(_Symbol, PERIOD_CURRENT, Highs[i].index);
            Highs[i].time    = iTime(_Symbol, PERIOD_CURRENT, Highs[i].index);
            Highs[i].isValid = true;
        }

        if (Lows[i].index >= 0) {
            Lows[i].value   = iLow(_Symbol, PERIOD_CURRENT, Lows[i].index);
            Lows[i].time    = iTime(_Symbol, PERIOD_CURRENT, Lows[i].index);
            Lows[i].isValid = true;
        }
    }
}

//+------------------------------------------------------------------+
//| FilterPeaks                                                      |
//| Opis:    Weryfikuje ważność wykrytych ekstremów na podstawie
//|          późniejszych barów. Dla szczytów/dołków używa rzeczywistych
//|          maksimów/minimów świec (iHigh/iLow) oraz prevClose do
//|          potwierdzenia naruszenia poziomu. Gdy warunek naruszenia
//|          spełniony — isValid=false i przejście do kolejnego piku.
//| Wywołuje: iHigh, iLow, iClose (platforma).
//| Globals:  Highs/Lows (czyta/modyfikuje), _Symbol/PERIOD_CURRENT.
//+------------------------------------------------------------------+
void FilterPeaks() {
    for (int i = 0; i < 10; i++) {
        // --- Filtrowanie szczytów ---
        if (Highs[i].index > 1) {
            for (int j = Highs[i].index - 1; j > 0; j--) {
                double high      = iHigh(_Symbol, PERIOD_CURRENT, j);
                double low       = iLow (_Symbol, PERIOD_CURRENT, j);
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
                double high      = iHigh(_Symbol, PERIOD_CURRENT, j);
                double low       = iLow (_Symbol, PERIOD_CURRENT, j);
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
