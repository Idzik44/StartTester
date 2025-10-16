//+------------------------------------------------------------------+
//|                                                      Zmienne11.m |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict


// --- WSPÓLNY STAN (dla detektora i optymalizatora)
extern int impulseCandlesSinceLastDetection;   // licznik świec bez impulsu

input group "Rysowanie"
input bool inputCandleSizeDrav = false; //Rysowanie wielkości swiec
input bool inputRectangleDrav = false;  //Rysowanie prostokątów
input bool inputSRLineDrav = false;      //RysowanieS/R

input group "Metody Handlu"


input group "Ustawienia wybicia z prostokąta"
input double userThreshold = 70.0;  // Próg
input int numCandlesToCheck = 300; // Liczba świec do sprawdzenia
input int userDefinedCandleCount = 5; // Świece w formacji
input int inputUserDefinedVolumeSessionCount = 1;
input int inputUserDefinedRangeSessionCount  = 1;
input double VolumeThresholdPct = 150.0;   // min. % średniego wolumenu
input double RangeThresholdPct = 50.0;     // max. % średniego zakresu świecy


input group "Średnia świeca i wolumen"
//input double breakoutSizeMultiplier = 1.2;   // mnożnik dla wielkości świecy
//input double breakoutVolumeMultiplier = 1.5; // mnożnik dla wolumenu
input int volumeCheckCandles = 100;          // liczba świec do analizy wolumenu

// Impuls
//input double ImpulseMinVolumePercent = 120.0;
//input double ImpulseMinRangePercent  = 120.0;

// Akumulacja
//input double AccumulationMinVolumePercent = 130.0;
//input double AccumulationMaxRangePercent = 60.0;

// Słabe wybicie
input double WeakBreakoutMaxVolumePercent = 80.0;
input double WeakBreakoutMinRangePercent = 120.0;

input group " Metody Wyjścia"
input int hourToClose = 0;                // Godzina, o której zamykamy pozycje
input int candleCountToWait = 0;          // Liczba świec do odczekania przed anulowaniem zleceń

input group  "MagicNumber "
input ulong inputMagicNumber = 123456;     // Magic Number zleceń
input ulong inputMagicNumberSRBrakeOut = 234567; //MN dla S/R BrakeOut
input ulong inputMagicnumberBoxBrakeOut = 345678; //MN dla Box BrakeOut
input ulong inputImpulseMagicNumber = 456789; //MN dla Impulsu 

input group "RSI StopLoss"
input int inputRSIPeriod = 14;  //Okres RSI 
input int inputRsiSlCandleToWait = 4;     // Ilość świec do uruchomienia RSI SL
input double inputRsiLevelOverbought = 70; // Poziom wykupienia
input double inputRsiLevelOversold = 30; // Poziom wyprzedania
input double inputRsiSlLevel       = 50; // Poziom SL RSI

input group "H/L Trailing Stop"
input bool inputTrailingStop = false; // Trailing Stop H/L

input group " Kalkulator wielkości pozycji"
input int inputCalculationMode = 0;        // Tryb kalkulacji: 0 = Fixed Lot, 1 = Procent ryzyka 
input double inputFixedLot = 0.01;          // Stała wielkość lotu 
input double inputRiskPercentage = 3.0;    // Procent kapitału na ryzyko
input double inputAccountRiskCapital = 300.0; // Kwota ryzykowana (waluta konta)

input group "SL i TP "
input int inputUseSLMethod = 3;           // 0 = Metoda szczytów i dołków, 1 = Mnożnik wysokości konsolidacji, 2 = Stop Loss w punktach
input double inputSLMultiplier = 0;      // Mnożnik dla Stop Loss
input double inputSLPoints = 50;             // Stop Loss w punktach (dla metody 2)
input double inputTPMultiplier = 2;      // Mnożnik dla Take Profit
input int inputExecuteMarginPoints = 2;    // Margines otwierania pozycji

input group "EMA SMA"
input int inputMaValue = 50;              //Okres EMA/SMA

input group "ADX"
input double inputAdxThreshold = 20.0; //wartość ADX
input double inputDiThreshold  = 25.0; //wartości -DI/+DI
input double inputMinDiff      = 5.0; //Minimum<> -DI/+DI

input group "Cluster Detector"
input bool UseATRFilter = false;
input bool UseVolumeFilter = false;
input bool UseStdDevFilter = false;

input group "Globalne parametry wyjść (domyślne)"
input int    Exit_ATR_Period     = 14;
input double Exit_ATR_K_Default  = 2.6;

input int    Exit_Swing_N_Default   = 8;   // liczba świec do lokalnych max/min
input int    Exit_Swing_OffsetPts   = 8;   // bufor w punktach

input group "Eksploracja polityk przy doborze (epsilon-greedy)"
input double Exit_EpsilonGreedy = 0.10;    // 10% próbuj alternatyw

// ===== Progi detekcji oparte o Z-score =====
// Impuls
//input double Impulse_ZRangeMin = 1.0;   // min. "szerokość" świecy w z-score
//input double Impulse_ZVolMin   = 0.5;   // min. "wysoki" wolumen w z-score

// Akumulacja + wybicie
//input int    Accum_WindowBars        = 8;    // ile świec sprawdzamy "ciasność"
//input double Accum_ZRangeMax         = 0.3;  // max |zRange| dla świec w akumulacji
//input double Accum_Breakout_ZRangeMin= 0.8;  // min zRange na świecy wybiciowej
//input double Accum_ZVolMin           = 0.0;  // min zVol na wybiciu (0 = bez wymogu)

// Fakeout (fałszywe wybicie)
//input double Fakeout_ZRangeMin = 0.6;  // świeca relatywnie "większa"
//input double Fakeout_ZRangeMax = 1.8;  // ale nie skrajny impuls
//input double Fakeout_ZVolMin   = 0.0;  // min zVol na świecy fakeout
//input double Fakeout_WickRatio = 1.5;  // knot/bodies (kierunkowy knot większy od korpusu)

// Regime/ExitEngine
// ======= Parametry kalibracyjne (INPUT) =======
input int    Regime_ADXWeak      = 16;      // poniżej: konsolidacja
input int    Regime_ADXStrong    = 20;      // powyżej: silny trend
input int    Regime_DIDiffTrend  = 20;       // min. różnica DI, by uznać kierunek w średnim ADX
input double Regime_ZRangeLow    = 0.50;    // |Z(range)| < Low  => niska zmienność
input double Regime_ZRangeHigh   = 1.50;    // |Z(range)| > High => wysoka zmienność
input int    Regime_SmoothBars   = 3;       // wygładzenie ADX/Z (prosta średnia, 1=brak)
input int    Regime_DrawBars     = 1;     // ile świec wstecz malować
input bool   Regime_DrawOverlay  = true;    // kolorowe „kafelki” pod świecami
input bool   Regime_DrawHUD      = true;    // panel z liczbami
input bool   Regime_DebugPrint   = true;   // spam do dziennika

// ─── MNOŻNIKI PROGÓW DETEKTORA (runtime tuning) ─────────────────────────────
input double DET_ZR_Mult    = 1.00;   // mnożnik dla progu |ZRange| (np. 0.9..1.2)
input double DET_ZV_Mult    = 1.00;   // mnożnik dla progu |ZVol|
//input double DET_SCORE_Mult = 1.00;   // mnożnik dla minimalnego score (jeśli używasz score)

// ===================== DETEKCJA / REGIME =====================
input string DET_ZR_Mults_PD = "1, 1, 1, 0.9, 0.9, 0.85, 1, 1, 1";  // mnożniki progów Z-range per-regime (CSV)
input string DET_ZV_Mults_PD = "1, 1, 1, 0.9, 0.9, 0.85, 1, 1, 1";  // mnożniki progów Z-volume per-regime (CSV)

// ===================== PENDING EXPIRY ========================
input int    inputPendingExpiryBars = 3;  // ile barów ważny pending (używane też w backtestach)

// ===================== RÓG DOPUSZCZEŃ / ANTY-DUPLIKAT =======
input bool   inputOneSignalPerBarPerDirection = true;  // jeden sygnał na bar i kierunek

// ===================== BACKTEST — KOSZTY =====================
input int    inputSimSpreadPoints   = 0;  // spread (pkt) do symulacji
input int    inputSimSlippagePoints = 0;  // slippage (pkt) przy wejściu w symulacji

// ===================== FILTR CZASU SESJI =====================
// Włącza/wyłącza filtr czasu (blokady na początku/końcu sesji i dnia)
input bool UseSessionTimeFilter      = false;

// Blokuj sygnały w PIERWSZYCH X minutach danej sesji (np. 10)
input int  BlockFirstMinutesOfSession = 10;

// Blokuj sygnały w OSTATNICH X minutach danej sesji (np. 10)
input int  BlockLastMinutesOfSession  = 10;

// Blokuj sygnały w OSTATNICH X minutach DNIA (np. 15)
input int  BlockLastMinutesOfDay      = 15;

// ===================== MA per-regime – AUTOMAT =====================
// Używaj MA per-regime w detektorze
input bool UsePerRegimeMA          = true ;
// Automatycznie dobieraj okresy MA per-regime i stosuj je w locie
input bool UsePerRegimeMA_Auto     = true;
// Co ile zamkniętych świec odświeżać rekomendacje (sensownie: 60–240 barów M5)
input int  MARec_RefreshEveryBars  = 120;

// Siatka i lookback dla automatu (możesz dostroić)
input int  MARec_Lookback          = 800;
input int  MARec_MinSamples        = 120;
input int  MARec_FastMin           = 10;
input int  MARec_FastMax           = 40;
input int  MARec_FastStep          = 2;
input int  MARec_SlowMin           = 40;
input int  MARec_SlowMax           = 120;
input int  MARec_SlowStep          = 5;

// CSV fallback (używane gdy Auto=OFF albo jeszcze brak danych do auto)
//input string DET_MA_Fast_Periods   = "20,18,22,20";
//input string DET_MA_Slow_Periods   = "50,45,55,50";

// ====================== TRYB TESTOWY / GATING ======================
enum TestStage
{
   TEST_SESSION_ONLY = 0,    // tylko średnie sesyjne (range/volume) + ich logi
   TEST_REGIME_ONLY  = 1,    // logi reżimu (bez wejść)
   TEST_ENTRY_NO_EXIT= 2,    // wejścia bez polityki wyjścia (czysty SL/TP)
   TEST_FILTER_TUNE  = 3,    // strojenie filtrów (wejścia allowed), bez exit-engine
   TEST_FULL         = 4     // pełny EA
};
input TestStage Test_Mode = TEST_REGIME_ONLY ;

// Globalne przełączniki modułów (domyślnie bezpiecznie OFF do testów)
input bool Enable_LiveTrading       = false; // faktyczne wysyłanie zleceń
input bool Enable_BindExitEngine    = false; // wiązanie ExitEngine z pozycją
input bool Enable_Detector_Live     = true; // wołanie detektora live (sygnały/strzałki)
//input bool Enable_Optimize_Exits    = false; // uruchamianie optymalizacji wyjść
//input bool Enable_Auto_MA_PerRegime = false; // auto-dobór MA per-regime (jeśli używasz)

// ====================== LOGI: Sesje (range/volume) ======================
input bool DebugSessionAnalyzer          = false; // włącz/wyłącz logi modułu sesji
input bool DebugSessionAnalyzer_OnceBar  = false;  // maks. 1 wpis na bar

// ====================== LOGI: Regime / Detektor ======================
input bool DebugRegime                   = false; // zrzut reżimu na barze
input bool DebugRegime_OnceBar           = false;  // maks. 1 wpis na bar

// ====================== LOGI: Zamówienia / Wejścia ======================
input bool DebugOrders                   = true;  // zrzut tego, co wysyłamy / dry-run

// ====================== LOGI: Optymalizator / diagnostyka detektora ======================
input bool DebugOptimizer     = false; // steruje: [OPT][Z-Profile], [OPT][Suggest], [OPT][VAL], [OPT-EXIT]
input bool DebugMARecommend   = true; // steruje logami auto-MA (jeśli jeszcze nie masz tego inputu)


// Parametry detektora (lokalne, z unikalnym sufiksem _PD)
input double IMP_ZR_MIN_PD    = 0.68;   // minimalne |Z-range| dla impulsu
input double IMP_ZV_MIN_PD    = 0.62;   // minimalne |Z-volume| dla impulsu
//input double IMP_SCORE_MIN_PD = 0.60;   // minimalny score (jeśli używasz)

input double DET_ZR_Mult_PD   = 0.8;   // mnożnik runtime dla Z-range
input double DET_ZV_Mult_PD   = 0.8;   // mnożnik runtime dla Z-volume
//input double DET_SC_Mult_PD   = 1.00;   // mnożnik runtime dla score

// ---- miękki filtr MA (G-soft) ----
input bool   DET_MA_Soft            = true;   // true = łagodniejszy test MA (zalecane na H1)
input double DET_MA_Soft_Tolerance  = 0.02;   // 2% tolerancji dla relacji SMAfast vs SMAslow

// ---- progi ADX/DI per-regime (CSV-mnożniki) ----
// mnożniki działają na bazowe: impulseAdxThreshold, impulseMinDiffDI
input string DET_ADX_Mults_PD = "0.95,1,1,1.05,1.1,1,0.9,0.95,1";  // × dla ADX w reżimach 0..(NUM_REGIMES-1)
input string DET_DI_Mults_PD  = "0.95,1,1,1.05,1.1,1,0.9,0.95,1";  // × dla ΔDI w reżimach 0..(NUM_REGIMES-1)


// Debug filtrowania czasu sesji
input bool DebugTimeFilter                 = true;  // włącz/wyłącz logi filtra czasu
input bool TimeFilterLogOnlyLiveBar        = false;  // loguj tylko dla i==1 (świeca live)
input bool TimeFilterLogOncePerBar         = false;  // maks. 1 log na świecę i przyczynę

input bool DebugPatternEval         = false;
input bool DebugPatternImpulse      = true;
//input bool DebugPatternAccumulation = false;
//input bool DebugPatternFakeBreakout = false;
input bool DebugPatternBacktest     = false;

// --- Parametry Z-score (rolling fallback, gdy statystyki sesji niegotowe)
input int Z_Window  = 200;   // okno do rolling Z-score (range/volume)
input int Z_MinBars = 50;    // min. próbka, by Z był wiarygodny

// --- Kierunek wg położenia względem MA oraz potwierdzenie 2 zamknięciami
input bool UseMA_SideDirection   = true;   // nad MA -> long, pod MA -> short (zamiast kierunku z DI)
input bool UseMA_TwoCloseConfirm = true;   // wymagaj 2 kolejnych zamknięć po tej samej stronie pasma MA

//---Kaliblator Regime
input bool Regime_CalibrationMode = true;
