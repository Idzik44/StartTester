//+------------------------------------------------------------------+
//|                                                     Zmienne11.mqh|
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict


// --- WSPÓLNY STAN (dla detektora i optymalizatora)
extern int impulseCandlesSinceLastDetection;   // licznik świec bez impulsu (definicja w innym module)

// ── Metody Handlu
input group "Metody Handlu"

// ── Ustawienia wybicia z prostokąta
input group "Ustawienia wybicia z prostokąta"
input double userThreshold = 70.0;           // Próg
input int    numCandlesToCheck = 300;        // Liczba świec do sprawdzenia
input int    userDefinedCandleCount = 5;     // Świece w formacji
input int    inputUserDefinedVolumeSessionCount = 1;
input int    inputUserDefinedRangeSessionCount  = 1;
input double VolumeThresholdPct = 150.0;     // min. % średniego wolumenu
input double RangeThresholdPct  = 50.0;      // max. % średniego zakresu świecy

// ── Średnia świeca i wolumen
input group "Średnia świeca i wolumen"
input int volumeCheckCandles = 100;          // liczba świec do analizy wolumenu

// ── Słabe wybicie
input double WeakBreakoutMaxVolumePercent = 80.0;
input double WeakBreakoutMinRangePercent = 120.0;

// ── Metody Wyjścia
input group " Metody Wyjścia"
input int hourToClose = 0;               // Godzina, o której zamykamy pozycje
input int candleCountToWait = 0;         // Liczba świec do odczekania przed anulowaniem zleceń

// ── Magic Numbers
input group  "MagicNumber "
input ulong inputMagicNumber            = 123456;  // Magic Number zleceń (ogólny)
input ulong inputMagicNumberSRBrakeOut  = 234567;  // MN dla S/R BrakeOut
input ulong inputMagicnumberBoxBrakeOut = 345678;  // MN dla Box BrakeOut
input ulong inputImpulseMagicNumber     = 456789;  // MN dla Impulsu

// ── RSI StopLoss
input group "RSI StopLoss"
input int    inputRSIPeriod           = 14;  // Okres RSI
input int    inputRsiSlCandleToWait   = 4;   // Ilość świec do uruchomienia RSI SL
input double inputRsiLevelOverbought  = 70;  // Poziom wykupienia
input double inputRsiLevelOversold    = 30;  // Poziom wyprzedania
input double inputRsiSlLevel          = 50;  // Poziom SL RSI

// ── H/L Trailing Stop
input group "H/L Trailing Stop"
input bool inputTrailingStop = false; // Trailing Stop H/L

// ── Kalkulator wielkości pozycji
input group " Kalkulator wielkości pozycji"
input int    inputCalculationMode   = 0;     // 0 = Fixed Lot, 1 = Procent ryzyka
input double inputFixedLot          = 0.01;  // Stała wielkość lotu
input double inputRiskPercentage    = 3.0;   // Procent kapitału na ryzyko
input double inputAccountRiskCapital= 300.0; // Kwota ryzykowana (waluta konta)

// ── SL i TP
input group "SL i TP "
input int    inputUseSLMethod   = 3;     // 0=peaks, 1=range multiplier, 2=points, 3=50 pts nad/pod świecą sygnałową
input double inputSLMultiplier  = 0;     // Mnożnik dla Stop Loss (dla metody 1)
input double inputSLPoints      = 50;    // Stop Loss w punktach (dla metody 2)
input double inputTPMultiplier  = 2;     // Mnożnik dla Take Profit
input int    inputExecuteMarginPoints = 2;  // Margines otwierania pozycji
input int inputSL_RangeBars = 50;   // ile ostatnich zamkniętych świec liczyć do konsolidacyjnego

// ── EMA/SMA
input group "EMA SMA"
input int inputMaValue = 50;              // Okres EMA/SMA

// ── Cluster Detector
input group "Cluster Detector"
input bool UseATRFilter   = false;
input bool UseVolumeFilter= false;
input bool UseStdDevFilter= false;

// ── Globalne parametry wyjść (domyślne)
input group "Globalne parametry wyjść (domyślne)"
input int    Exit_ATR_Period     = 14;
input double Exit_ATR_K_Default  = 2.6;
input int    Exit_Swing_N_Default= 8;   // liczba świec do lokalnych max/min
input int    Exit_Swing_OffsetPts= 8;   // bufor w punktach

// ── Eksploracja polityk (epsilon-greedy)
input group "Eksploracja polityk przy doborze (epsilon-greedy)"
input double Exit_EpsilonGreedy = 0.10; // 10% próbuj alternatyw

// ── Regime/ExitEngine – parametry kalibracyjne
input int    Regime_ADXWeak      = 16;
input int    Regime_ADXStrong    = 20;
input int    Regime_DIDiffTrend  = 20;
input double Regime_ZRangeLow    = 0.50;
input double Regime_ZRangeHigh   = 1.50;
input int    Regime_SmoothBars   = 3;
input int    Regime_DrawBars     = 1;
input bool   Regime_DrawOverlay  = true;
input bool   Regime_DrawHUD      = true;
input bool   Regime_DebugPrint   = true;

// ── MNOŻNIKI DETEKTORA (runtime tuning)
input double DET_ZR_Mult    = 1.00;
input double DET_ZV_Mult    = 1.00;

// ── DETEKCJA / REGIME (per-regime CSV)
input string DET_ZR_Mults_PD = "1, 1, 1, 0.9, 0.9, 0.85, 1, 1, 1";
input string DET_ZV_Mults_PD = "1, 1, 1, 0.9, 0.9, 0.85, 1, 1, 1";

// EXIT per regime: metoda i parametry SL/TP definiowane inputami (CSV)
// 0 = High/Low (szczyty/dołki z PeaksEnded), 1 = Konsolidacja (range*SLMult),
// 2 = Stałe punkty (SLPoints), 3 = Świeca sygnałowa ± SLPoints
input string Exit_Method_ByRegime_CSV   = "1,1,2,3";
input string Exit_SLPoints_ByRegime_CSV = "50,50,100,100";
input string Exit_SLMult_ByRegime_CSV   = "0.5,0.8,0.0,0.0";
input string Exit_TPMult_ByRegime_CSV   = "2.0,1.5,1.2,1.0";

// ── Pending expiry
input int    inputPendingExpiryBars = 3;

// ── Anty-duplikat
input bool   inputOneSignalPerBarPerDirection = true;

// ── Backtest — koszty
input int    inputSimSpreadPoints   = 0;
input int    inputSimSlippagePoints = 0;

// ── Filtr czasu sesji
input bool UseSessionTimeFilter       = false;
input int  BlockFirstMinutesOfSession = 10;
input int  BlockLastMinutesOfSession  = 10;
input int  BlockLastMinutesOfDay      = 15;


// ── TRYB TESTOWY / GATING
enum TestStage
{
   TEST_SESSION_ONLY = 0,
   TEST_REGIME_ONLY  = 1,
   TEST_ENTRY_NO_EXIT= 2,
   TEST_FILTER_TUNE  = 3,
   TEST_FULL         = 4
};
input TestStage Test_Mode = TEST_REGIME_ONLY;

// ── Globalne przełączniki modułów
input bool Enable_LiveTrading     = true;
input bool Enable_BindExitEngine  = false;
input bool Enable_Detector_Live   = true;
// input bool Enable_Auto_MA_PerRegime = false;

// ── LOGI: Sesje
input bool DebugSessionAnalyzer         = false;
input bool DebugSessionAnalyzer_OnceBar = false;

// ── LOGI: Regime / Detektor
input bool DebugRegime         = false;
input bool DebugRegime_OnceBar = false;

// ── LOGI: Zamówienia
input bool DebugOrders = true;


// ── Parametry detektora (lokalne, _PD)
input double IMP_ZR_MIN_PD  = 0.68;
input double IMP_ZV_MIN_PD  = 0.62;
input double DET_ZR_Mult_PD = 0.8;
input double DET_ZV_Mult_PD = 0.8;

// ── miękki filtr MA (G-soft)
input bool   DET_MA_Soft           = true;
input double DET_MA_Soft_Tolerance = 0.02;

// ── progi ADX/DI per-regime (CSV-mnożniki)
input string DET_ADX_Mults_PD = "0.95,1,1,1.05,1.1,1,0.9,0.95,1";
input string DET_DI_Mults_PD  = "0.95,1,1,1.05,1.1,1,0.9,0.95,1";

// ── Debug filtrowania czasu sesji
input bool DebugTimeFilter          = true;
input bool TimeFilterLogOnlyLiveBar = false;
input bool TimeFilterLogOncePerBar  = false;

input bool DebugPatternEval     = false;
input bool DebugPatternImpulse  = true;
input bool DebugPatternBacktest = false;
input bool DebugOptimizer        = false;

// ── Z-score (rolling fallback)
input int Z_Window  = 200;
input int Z_MinBars = 50;

// ── Kierunek wg MA + potwierdzenie 2 zamknięciami
input bool UseMA_SideDirection   = true;
input bool UseMA_TwoCloseConfirm = true;

// ── Kalibrator Regime
input bool Regime_CalibrationMode = true;

// ─────────────────────────────────────────────────────────────
// Wejścia globalne (przeniesione z StartTester11.mq5)

input int  inputADX_Period        = 14;    // okres ADX dla ComputeCustomADX()
input int  inputRegimeAuditBars   = 300;   // okno audytu (Regime_Summary / Detector_StageAudit)
input int  inputZDumpBars         = 2000;  // liczba barów do zrzutu Z-score na starcie
input bool inputEnable_3A_Harness = true;  // włącz/wyłącz 3A-harness (logi DRY-RUN execute)



