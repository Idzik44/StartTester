//+------------------------------------------------------------------+ 
//| StartTester11.mq5                                                |
//| Główny plik uruchomieniowy                                       |
//+------------------------------------------------------------------+
#property strict

// ─────────────────────────────────────────────────────────────
// INCLUDE
#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/PeaksEnded11.mqh>
//#include <StartTester/Position_Size11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>
#include <StartTester/PatternOptymalizer11.mqh>     
#include <StartTester/PatternDetector11.mqh>
#include <StartTester/RegimeVisualizer.mqh>

// ─────────────────────────────────────────────────────────────
// ZMIENNE
// Opis: Pamięta czas ostatniej świecy zamkniętej (index 1), aby
//       wywoływać logikę "na zamknięciu świecy" tylko raz.
// Używane przez: OnTick (odczyt/zapis)
datetime lastProcessedCandleTime = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//| Opis: Inicjalizacja EA. Ładuje bufory świec, ustawia deterministyczny
//|       seed RNG na bazie czasu świecy [1], oblicza ADX, resetuje statystyki
//|       sesji, analizuje wstępne zakresy/wolumeny, uruchamia bezpieczną
//|       optymalizację parametrów formacji (bez optymalizacji wyjść) i zrzuca
//|       diagnostykę Z-score dla zakresu i wolumenu.
//| Wywołuje:
//|   - RefreshCandleHistory()
//|   - ComputeCustomADX(inputADX_Period)
//|   - ResetSessionStats()
//|   - AnalyzeInitialSessionRangesAndVolumes()
//|   - ForceOptimizeParametersHistorical()
//|   - DumpZStats_Range(inputZDumpBars)
//|   - DumpZStats_Volume(inputZDumpBars)
//| Korzysta z globalnych/extern:
//|   - candleHistory[] (z CandleAndTranactionData11.mqh)
//|   - inputADX_Period, inputZDumpBars (z Zmienne11.mqh)
//| Zwraca: INIT_SUCCEEDED lub błąd inicjalizacji
//+------------------------------------------------------------------+
int OnInit()
{
   // Najpierw załaduj dane, potem seed RNG na bazie świecy [1] (deterministyczny).
   RefreshCandleHistory();
   if (ArraySize(candleHistory) < 2)
   {
      Print("[Init] Zbyt mało świec w bufferze (", ArraySize(candleHistory), ").");
      return INIT_SUCCEEDED;
   }

   // ✅ Deterministyczny seed zamiast TimeLocal(): powtarzalne testy.
   MathSrand((int)candleHistory[1].time);

   ComputeCustomADX(inputADX_Period);
   ResetSessionStats();
   AnalyzeInitialSessionRangesAndVolumes();

   // Startowe „bezpieczne” procedury (bez optymalizacji wyjść!)
   ForceOptimizeParametersHistorical();

   DumpZStats_Range(inputZDumpBars);
   DumpZStats_Volume(inputZDumpBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//| Opis: Główna pętla zdarzeń. Odświeża bufory danych i – tylko
//|       gdy pojawi się NOWA świeca zamknięta (index 1) – uruchamia
//|       sekwencję: aktualizacja zleceń/pozycji, ADX, wolumen sesji,
//|       detektor szczytów, filtr szczytów, wykrywanie formacji
//|       z rysowaniem, ewentualną periodyczną optymalizację (bez
//|       optymalizacji wyjść), podsumowanie reżimu i audyt etapów.
//| Wywołuje:
//|   - RefreshCandleHistory()
//|   - RefreshOrderAndPositionData()
//|   - ComputeCustomADX(inputADX_Period)
//|   - UpdateLiveSessionVolume()
//|   - Peaks()
//|   - FilterPeaks()
//|   - DetectLivePatternAndDraw()
//|   - MaybeOptimizeParametersHistorical()
//|   - Regime_Summary(inputRegimeAuditBars)
//|   - Detector_StageAudit(inputRegimeAuditBars)
//| Korzysta z globalnych/extern:
//|   - candleHistory[]
//|   - lastProcessedCandleTime (odczyt/zapis)
//|   - inputADX_Period, inputRegimeAuditBars (z Zmienne11.mqh)
//| Uwagi: Logika uruchamiana tylko po zmianie czasu świecy [1].
//+------------------------------------------------------------------+
void OnTick()
{
   RefreshCandleHistory();

   if (ArraySize(candleHistory) < 2) return;

   datetime closedCandleTime = candleHistory[1].time;
   if (closedCandleTime != lastProcessedCandleTime)
   {
      lastProcessedCandleTime = closedCandleTime;
      Print("🔍 Nowa świeca zamknięta: ", TimeToString(closedCandleTime));

      RefreshOrderAndPositionData();
      ComputeCustomADX(inputADX_Period);
      UpdateLiveSessionVolume();

      Peaks();
      FilterPeaks();

      // Wejścia + rysunki (wyjścia per-regime z CSV w SmartOrderExecutor)
      DetectLivePatternAndDraw();

      // Okresowa diagnostyka/kalibracja
      MaybeOptimizeParametersHistorical();

      Regime_Summary(inputRegimeAuditBars);
      Detector_StageAudit(inputRegimeAuditBars);
   }

   // Hooki co-tick (opcjonalne, pozostawione zakomentowane)
   // ApplyTrailingStop(...);                        // jeśli kiedyś wróci inny trailing
   // ClosePositionsByRSI(...);
   // ApplyCandleBasedTrailingStop(...);
   // CancelOldPendingOrders(...);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//| Opis: Sprzątanie przy wyłączaniu EA. Minimalne, bezinwazyjne
//|       zakończenie: log powodu, reset strażnika świecy, redraw.
//|       (Nie usuwamy obiektów z wykresu globalnie, by nie naruszyć
//|       cudzych elementów; moduły powinny czyścić się wewnętrznie.)
//| Wywołuje:
//|   - ChartRedraw(0)
//| Korzysta z globalnych/extern:
//|   - lastProcessedCandleTime (zapis)
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("[Deinit] Powód: ", IntegerToString(reason));
   lastProcessedCandleTime = 0;
   ChartRedraw(0);
}
