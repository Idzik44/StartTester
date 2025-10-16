//+------------------------------------------------------------------+
//| StartTester11.mq5                                                |
//| Główny plik uruchomieniowy                                       |
//+------------------------------------------------------------------+

#property strict

#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/PeaksEnded11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>
#include <StartTester/DrawingTools11.mqh>
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
void   Regime_Summary(int bars);
void   Detector_StageAudit(const int lookbackBars);
void   DetectLivePatternAndDraw();
void   TestHarness_OnClosedBar();
bool   CheckImpulseConditions(int i, bool &isBuy);
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
int OnInit()
{
   MathSrand((int)TimeLocal()); // dla epsilon-greedy
   
   RefreshCandleHistory();
   ComputeCustomADX(14); 
   ResetSessionStats();
   AnalyzeInitialSessionRangesAndVolumes();

   ForceOptimizeParametersHistorical();
   DetectHistoricalImpulsesWithProfitCheck();
 //  DetectHistoricalPatternsAndDraw();
   hasDrawnHistorical = true;

   detector.DetectAndDrawHistoricalClusters();

   DumpZStats_Range(2000);
   DumpZStats_Volume(2000);
   

   
   if (MA_Opt_Enable) {
   Print("🧪 [MA-OPT] Start grid-search MA per-regime…");
   OptimizeMAPeriodsAllRegimes(MA_Opt_ScanBars);
   Print("🏁 [MA-OPT] Gotowe (zobacz logi i rysunki 2×MA).");
}

 
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Odśwież dane świec i sprawdź, czy pojawiła się nowa świeca
   RefreshCandleHistory();
   //Zamykacz na wiele sposobów
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

      MarketDirection maDir = DetectTrendByMA();
      MarketDirection adxDir = DetectTrendByADX();

      CalculateAverageCandleHeight(numCandlesToCheck);
      CalculateLastCandleHeight();
      CheckSmallCandleSequence(userThreshold, userDefinedCandleCount);

      Peaks();
      FilterPeaks();
      DetectTrendByStructure();
      DrawPeaksAndLows();
      CheckTrendLines();

      DrawCandleSizeLabel(
         candleHistory[1].time,
         candleHistory[1].open,
         candleHistory[1].close,
         candleHistory[1].high,
         candleHistory[1].low,
         avgCandleHeight,
         inputCandleSizeDrav);

      // ✅ Detekcja impulsu dokładnie po zamknięciu świecy
      DetectLivePatternAndDraw();

      // 📈 Ewentualna optymalizacja
      MaybeOptimizeParametersHistorical();
      TestHarness_OnClosedBar();
      
      // wizualizacja reżimów do kalibracji
 //     RegimeViz_DrawOverlay(200, true);   // 200 ostatnich świec, z etykietą

      // audyt reżimów (podsumowanie rozkładu)
      Regime_Summary(300);

      // audyt etapów detektora (time → Z → ADX/DI → MA → PASS)
      Detector_StageAudit(300);

      // --- 3A HARNESS: wymusza wywołanie execute po PASS detektora ---
      static datetime __last3Abar = 0;
      datetime t1 = candleHistory[1].time;
      if (t1 != __last3Abar) {
         __last3Abar = t1;

         // komunikat kontrolny (zobaczysz go co bar — wiesz, że blok działa)
         PrintFormat("[3A][BAR] %s — start harness", TimeToString(t1, TIME_DATE|TIME_MINUTES));

         if (Enable_Detector_Live) {
            int  i = 1;
            bool isBuy = false;
            // pokaż progi i wartości (łatwiej debugować)
            double zr = MathAbs(GetStandardizedRange(i));
            double zv = MathAbs(GetStandardizedVolume(i));
            int reg   = DetectRegimeKey(i); if (reg<0 || reg>=NUM_REGIMES) reg=0;
            double thrZR = IMP_ZR_MIN_PD * DET_ZR_Mult_PD * __GetMultFromCsv(DET_ZR_Mults_PD, reg, 1.0);
            double thrZV = IMP_ZR_MIN_PD * DET_ZV_Mult_PD * __GetMultFromCsv(DET_ZV_Mults_PD, reg, 1.0);
            double adx = GetCustomADXAt(i); double pdi = GetCustomPlusDIAt(i); double mdi = GetCustomMinusDIAt(i);
            if (adx<0||pdi<0||mdi<0){ ComputeCustomADX(14); adx=GetCustomADXAt(i); pdi=GetCustomPlusDIAt(i); mdi=GetCustomMinusDIAt(i); }
            double diff = MathAbs(pdi-mdi);

            PrintFormat("[3A][CHK] reg=%d | Zr=%.2f (>=%.2f) | Zv=%.2f (>=%.2f) | ADX=%.1f (>=%.1f) | DI_diff=%.1f (>=%.1f) | MA=%s | TIME=%s",
                        reg, zr, thrZR, zv, thrZV, adx, (double)impulseAdxThreshold, diff, (double)impulseMinDiffDI,
                        (UsePerRegimeMA ? "ON" : "OFF"),
                        (UseSessionTimeFilter ? "ON" : "OFF"));


            if (CheckImpulseConditions(i, isBuy)) {
               // liczymy breakout i wywołujemy ExecuteImpulseTrade (DRY-RUN zaloguje plan)
               double breakout = isBuy ? candleHistory[i].high : candleHistory[i].low;
               double adj      = isBuy ? (breakout + inputExecuteMarginPoints * _Point)
                                       : (breakout - inputExecuteMarginPoints * _Point);

               PrintFormat("[3A][PASS] %s | breakout=%.5f -> adj=%.5f",
                           isBuy ? "BUY" : "SELL", breakout, adj);

               ExecuteImpulseTrade(isBuy, adj, t1, inputUseSLMethod, inputMagicNumber);
            } else {
               Print("[3A][NO-PASS] Detektor nie przeszedł (patrz [3A][CHK])");
            }
         } else {
            Print("[3A] Enable_Detector_Live=false — nic nie testuję na tym barze.");
         }
      }
   }

   // 🕐 Funkcje co tick
//   ApplyTrailingStop(inputMagicNumber);
//   ClosePositionsByRSI(inputImpulseMagicNumber, inputRsiLevelOverbought, inputRsiLevelOversold, inputRsiSlLevel);
//   ApplyCandleBasedTrailingStop(inputMagicNumber);
//   CancelOldPendingOrders(5,inputImpulseMagicNumber);
}

//+------------------------------------------------------------------+
//| OnDeinit – usuwanie obiektów z wykresu                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
 /*  ReleaseRSI();

   if (handleEMA != INVALID_HANDLE) IndicatorRelease(handleEMA);
   if (handleSMA != INVALID_HANDLE) IndicatorRelease(handleSMA);

   // Usuń wszystkie obiekty narysowane przez EA
   int total = ObjectsTotal(0, 0);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if (StringFind(name, "Live_") == 0 || StringFind(name, "Hist_") == 0 || StringFind(name, "RECT") == 0)
         ObjectDelete(0, name);
   }

   Print("🧹 Wszystkie obiekty usunięte.");
 */
}
