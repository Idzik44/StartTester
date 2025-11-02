//+------------------------------------------------------------------+
//| StartTester11.mq5                                                |
//| Główny plik uruchomieniowy                                       |
//+------------------------------------------------------------------+
#property strict

#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/PeaksEnded11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>
#include <StartTester/Position_Size11.mqh>
#include <StartTester/trenddetector11.mqh>
#include <StartTester/BuySellFunction11.mqh>
#include <StartTester/RegimeThresholds.mqh>
#include <StartTester/ClusterDetector11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>
#include <StartTester/PatternOptymalizer11.mqh>
#include <StartTester/PatternDetector11.mqh>
#include <StartTester/ExitEngine.mqh>
#include <StartTester/RegimeVisualizer.mqh>

// ─────────────────────────────────────────────────────────────
// PROTOTYPY (bez wartości domyślnych)

// Opis: Loguje statystyki reżimów dla ostatnich 'bars' słupków (diagnostyka).
// Wywołuje (w implementacji): DetectRegimeKey, GetStandardizedRange/Volume, PrintFormat.
// Używa globalnych (pośrednio): candleHistory[], NUM_REGIMES, DebugRegime.
// Definicja: PatternDetector11.mqh.
void   Regime_Summary(int bars);

// Opis: Audyt etapów detektora na oknie 'lookbackBars' (ile barów przechodzi kolejne filtry).
// Wywołuje (w implementacji): PassesSessionTimeFilter, GetStandardizedRange/Volume, GetCustomADXAt/ComputeCustomADX,
//                              __GetMultFromCsv, CheckImpulseConditions, PrintFormat.
// Używa globalnych (pośrednio): candleHistory[], progi IMP_*/DET_* i ustawienia filtrów.
// Definicja: PatternDetector11.mqh.
void   Detector_StageAudit(const int lookbackBars);

// Opis: Detekcja impulsu na świecy 1 po zamknięciu baru, rysowanie strzałek, przygotowanie wejścia.
// Wywołuje (w implementacji): CheckImpulseConditions, DrawTradeArrow/DrawSignalArrow, ExecuteImpulseTrade.
// Używa globalnych (pośrednio): candleHistory[], input* dla SL/TP/marginesów, ustawienia sesji.
// Definicja: PatternDetector11.mqh.
void   DetectLivePatternAndDraw();

// Opis: Tryb testowy wywoływany po zamknięciu świecy; rysuje MA, wykonuje testy wg bieżącego trybu.
// Wywołuje (w implementacji): PD_DrawUnifiedRegimeMA, SessionAnalyzer_DumpSnapshot, Regime_LogBar, DetectLivePatternAndDraw.
// Używa globalnych (pośrednio): ustawienia TEST_* i Debug*.
// Definicja: PatternDetector11.mqh.
void   TestHarness_OnClosedBar();

// Opis: Sprawdza warunki impulsu na barze i (Z-score zasięgu/wolumenu, ADX/DI, MA, filtr czasu).
// Wywołuje (w implementacji): PassesSessionTimeFilter, DetectRegimeKey, GetStandardizedRange/Volume, GetCustomADXAt/ComputeCustomADX,
//                              __GetMultFromCsv, __ComputeMASideTwoClose.
// Używa globalnych (pośrednio): progi IMP_*/DET_*, impulseAdxThreshold, impulseMinDiffDI, UseSessionTimeFilter.
// Definicja: PatternDetector11.mqh.
bool   CheckImpulseConditions(int i, bool &isBuy);

// Opis: Zwraca mnożnik z CSV (split po przecinku) dla indeksu idx (fallback na defVal).
// Wywołuje (w implementacji): StringSplit, StringTrimLeft/Right, StringToDouble.
// Używa globalnych: brak.
// Definicja: PatternDetector11.mqh.
double __GetMultFromCsv(const string csv, int idx, double defVal);

// Zmienne globalne
bool hasDrawnHistorical = true;
ClusterDetector detector;
datetime lastProcessedCandleTime = 0;

// Zmienne extern z funkcji wykrywania trendu
extern bool BuyOnly;
extern bool SellOnly;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
// Opis: Inicjalizacja EA. Odświeża bufory cenowe i wskaźniki, uruchamia diagnostykę,
//       wykonuje wykrycie klastrów historycznych oraz wymusza wstępną optymalizację wyjść.
// Wywołuje: MathSrand/TimeLocal, RefreshCandleHistory, ComputeCustomADX, ResetSessionStats,
//           AnalyzeInitialSessionRangesAndVolumes, ForceOptimizeParametersHistorical,
//           DetectHistoricalImpulsesWithProfitCheck, detector.Enable*Filter, detector.DetectAndDrawHistoricalClusters,
//           DumpZStats_Range, DumpZStats_Volume.
// Używa globalnych: hasDrawnHistorical (ustawia), detector, UseATRFilter/UseVolumeFilter/UseStdDevFilter (inputy).
int OnInit()
{
   MathSrand((int)TimeLocal()); // dla epsilon-greedy

   // Bufory i wskaźniki
   RefreshCandleHistory();
   ComputeCustomADX(14);
   ResetSessionStats();
   AnalyzeInitialSessionRangesAndVolumes();

   // Optymalizacje/diagnostyka na starcie
   ForceOptimizeParametersHistorical();
   DetectHistoricalImpulsesWithProfitCheck();
   hasDrawnHistorical = true;

   // Cluster Detector: history + podpięcie filtrów z inputów
   detector.EnableATRFilter(UseATRFilter);
   detector.EnableVolumeFilter(UseVolumeFilter);
   detector.EnableStdDevFilter(UseStdDevFilter);
   detector.DetectAndDrawHistoricalClusters();

   // Zrzuty Z-score (diagnostyka)
   DumpZStats_Range(2000);
   DumpZStats_Volume(2000);


   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
// Opis: Główna pętla. Reaguje na zamknięcie świecy: aktualizuje dane/ADX/volumen,
//       wykonuje analizy trendu/peaks, detekcję impulsu i ewentualne wejście,
//       okresowo optymalizuje parametry oraz loguje audyty reżimów. Zawiera też
//       wewnętrzny „3A harness” do jawnego uruchamiania ExecuteImpulseTrade po PASS.
// Wywołuje: RefreshCandleHistory, ManageOpenPositions, RefreshOrderAndPositionData,
//           ComputeCustomADX, UpdateLiveSessionVolume, DetectTrendByMA/DetectTrendByADX,
//           CalculateAverageCandleHeight, CalculateLastCandleHeight,
//           Peaks, FilterPeaks, DetectTrendByStructure,
//           DetectLivePatternAndDraw, MaybeOptimizeParametersHistorical, TestHarness_OnClosedBar,
//           Regime_Summary, Detector_StageAudit,
//           (w harness) GetStandardizedRange/Volume, DetectRegimeKey, __GetMultFromCsv,
//           GetCustomADXAt/ComputeCustomADX, CheckImpulseConditions, ExecuteImpulseTrade.
// Używa globalnych: lastProcessedCandleTime, candleHistory[], Enable_Detector_Live, numCandlesToCheck,
//                   parametry detektora (IMP_*, DET_*), impulseAdxThreshold, impulseMinDiffDI,
//                   UseSessionTimeFilter, inputExecuteMarginPoints, inputUseSLMethod, inputMagicNumber.
void OnTick()
{
   // Odśwież dane świec i sprawdź, czy pojawiła się nowa świeca
   RefreshCandleHistory();

   // Zarządzanie pozycjami (ExitEngine)
   ManageOpenPositions();

   datetime closedCandleTime = candleHistory[1].time;
   if (closedCandleTime != lastProcessedCandleTime)
   {
      lastProcessedCandleTime = closedCandleTime;
      Print("🔍 Nowa świeca zamknięta: ", TimeToString(closedCandleTime));

      // 🔄 Odśwież dane
      RefreshOrderAndPositionData();
      ComputeCustomADX(14);
      UpdateLiveSessionVolume();

      // Kierunki/analizy pomocnicze
      MarketDirection maDir  = DetectTrendByMA();
      MarketDirection adxDir = DetectTrendByADX();

      CalculateAverageCandleHeight(numCandlesToCheck);
      CalculateLastCandleHeight();

      Peaks();
      FilterPeaks();
      DetectTrendByStructure();
      


      // ✅ Detekcja impulsu dokładnie po zamknięciu świecy
      DetectLivePatternAndDraw();

      // 📈 Ewentualna optymalizacja
      MaybeOptimizeParametersHistorical();
      TestHarness_OnClosedBar();

      // Audyty/diagnostyka reżimów
      Regime_Summary(300);
      Detector_StageAudit(300);

      // --- 3A HARNESS: wymusza wywołanie execute po PASS detektora ---
      static datetime __last3Abar = 0;
      datetime t1 = candleHistory[1].time;
      if (t1 != __last3Abar)
      {
         __last3Abar = t1;
         PrintFormat("[3A][BAR] %s — start harness", TimeToString(t1, TIME_DATE | TIME_MINUTES));

         if (Enable_Detector_Live)
         {
            int  i = 1;
            bool isBuy = false;

            // pokaż progi i wartości (łatwiej debugować)
            double zr = MathAbs(GetStandardizedRange(i));
            double zv = MathAbs(GetStandardizedVolume(i));
            int reg   = DetectRegimeKey(i); if (reg < 0 || reg >= NUM_REGIMES) reg = 0;

            // ✅ POPRAWA: thrZV od IMP_ZV_MIN_PD (wcześniej literówka)
            double thrZR = IMP_ZR_MIN_PD * DET_ZR_Mult_PD * __GetMultFromCsv(DET_ZR_Mults_PD, reg, 1.0);
            double thrZV = IMP_ZV_MIN_PD * DET_ZV_Mult_PD * __GetMultFromCsv(DET_ZV_Mults_PD, reg, 1.0);

            double adx = GetCustomADXAt(i);
            double pdi = GetCustomPlusDIAt(i);
            double mdi = GetCustomMinusDIAt(i);
            if (adx < 0 || pdi < 0 || mdi < 0)
            { 
               ComputeCustomADX(14);
               adx = GetCustomADXAt(i); pdi = GetCustomPlusDIAt(i); mdi = GetCustomMinusDIAt(i);
            }
            double diff = MathAbs(pdi - mdi);

            PrintFormat("[3A][CHK] reg=%d | Zr=%.2f (>=%.2f) | Zv=%.2f (>=%.2f) | ADX=%.1f (>=%.1f) | DI_diff=%.1f (>=%.1f) | MA=%s | TIME=%s",
                        reg, zr, thrZR, zv, thrZV, adx, (double)impulseAdxThreshold, diff, (double)impulseMinDiffDI,
                        "ON",  // Unified 2×MA aktywne – bez przełącznika
                        (UseSessionTimeFilter ? "ON" : "OFF"));


            if (CheckImpulseConditions(i, isBuy))
            {
               // liczymy breakout i wywołujemy ExecuteImpulseTrade (DRY-RUN zaloguje plan)
               double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
               double adj      = isBuy ? (breakout + inputExecuteMarginPoints * _Point)
                                       : (breakout - inputExecuteMarginPoints * _Point);

               PrintFormat("[3A][PASS] %s | breakout=%.5f -> adj=%.5f",
                           isBuy ? "BUY" : "SELL", breakout, adj);

               ExecuteImpulseTrade(isBuy, adj, t1, inputUseSLMethod, inputMagicNumber);
            }
            else
            {
               Print("[3A][NO-PASS] Detektor nie przeszedł (patrz [3A][CHK])");
            }
         }
         else
         {
            Print("[3A] Enable_Detector_Live=false — nic nie testuję na tym barze.");
         }
      }
   }

   // 🕐 Funkcje co tick (opcjonalne hooki; obecnie wyłączone w tym buildzie)
   // ApplyTrailingStop(inputMagicNumber);
   // ClosePositionsByRSI(inputImpulseMagicNumber, inputRsiLevelOverbought, inputRsiLevelOversold, inputRsiSlLevel);
   // ApplyCandleBasedTrailingStop(inputMagicNumber);
   // CancelOldPendingOrders(5, inputImpulseMagicNumber);
}

//+------------------------------------------------------------------+
//| OnDeinit – cleanup (opcjonalnie)                                 |
//+------------------------------------------------------------------+
// Opis: Sprzątanie przy wyłączaniu EA/odpinaniu od wykresu.
// Wywołuje: (brak, aktualnie puste).
// Używa globalnych: (brak).
void OnDeinit(const int reason)
{
   
}
