#ifndef __EXIT_POLICY_MQH__
#define __EXIT_POLICY_MQH__

#property strict


#include <StartTester/ExitTypes.mqh>
#include <StartTester/RegimeDetector.mqh>

struct ExitParams {
   bool useBE;    double beR;   int beOffsetPts;
   bool usePartial; double partialR; double partialPct;
   TrailMethod trail; int atrPeriod; double atrMult;
   int stepEveryPts; int stepLockPts;
   bool useTimeStop; int maxBars;
   bool useDIExit;  int adxMin; int diMin; int diDiff;
};

// ---------------------------------------------------------------------
// Opis: Kopiuje wszystkie pola ze struktury src do dst (bez alokacji).
// Wywołuje: (brak).
// Używa globalnych: (brak).
// ---------------------------------------------------------------------
void CopyExitParams(ExitParams &dst, const ExitParams &src)
{
   dst.useBE = src.useBE;           dst.beR = src.beR;               dst.beOffsetPts = src.beOffsetPts;
   dst.usePartial = src.usePartial; dst.partialR = src.partialR;     dst.partialPct = src.partialPct;
   dst.trail = src.trail;           dst.atrPeriod = src.atrPeriod;   dst.atrMult = src.atrMult;
   dst.stepEveryPts = src.stepEveryPts; dst.stepLockPts = src.stepLockPts;
   dst.useTimeStop = src.useTimeStop; dst.maxBars = src.maxBars;
   dst.useDIExit = src.useDIExit;   dst.adxMin = src.adxMin;         dst.diMin = src.diMin; dst.diDiff = src.diDiff;
}


// ---------------------------------------------------------------------
// Opis: Sprawdza, czy platforma/symbol wspiera częściowe zamknięcia po wolumenie
//       (na podstawie minimalnego wolumenu i kroku wolumenu). Heurystyka dla BT.
// Wywołuje: SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN / SYMBOL_VOLUME_STEP).
// Używa globalnych: _Symbol (symbol bieżący, MQL5).
// ---------------------------------------------------------------------
bool CanPartialByLot()
{
   double vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double posMin = vol + 2*step; // orientacyjnie
   // w backtestach nie zawsze znamy wolumen wejścia – tu tylko „czy w ogóle możliwe”
   return (posMin > 0.0);
}

// ---------------------------------------------------------------------
// Opis: Buduje i zwraca domyślny zestaw parametrów wyjścia dla zadanego
//       reżimu rynku; uwzględnia flagę allowPartial (czy dopuszczać partial).
// Wywołuje: (brak).
// Używa globalnych: (brak).
// ---------------------------------------------------------------------
ExitParams DefaultExitForRegime(MarketRegime r, bool allowPartial)
{
   ExitParams p;
   // domyślne „wyłączone”
   p.useBE=false; p.beR=1.0; p.beOffsetPts=5;
   p.usePartial=false; p.partialR=1.0; p.partialPct=0.5;
   p.trail=TRAIL_NONE; p.atrPeriod=14; p.atrMult=2.0;
   p.stepEveryPts=100; p.stepLockPts=50;
   p.useTimeStop=false; p.maxBars=20;
   p.useDIExit=false;  p.adxMin=15; p.diMin=15; p.diDiff=5;

   switch(r)
   {
      case REG_TREND_STRONG:
         p.useBE=true;      p.beR=0.9; p.beOffsetPts=5;
         p.usePartial=allowPartial; p.partialR=1.0; p.partialPct=0.5;
         p.trail=TRAIL_ATR; p.atrPeriod=14; p.atrMult=2.2;
         p.useTimeStop=false;
         p.useDIExit=false;
         break;

      case REG_TREND_WEAK:
         p.useBE=true;      p.beR=1.0; p.beOffsetPts=5;
         p.usePartial=allowPartial; p.partialR=1.0; p.partialPct=0.5;
         p.trail=TRAIL_STEP; p.stepEveryPts= (int)(0.5 * 100); p.stepLockPts= (int)(0.25 * 100);
         p.useTimeStop=true; p.maxBars=20;
         p.useDIExit=true;   p.adxMin=15; p.diMin=15; p.diDiff=5;
         break;

      case REG_CHOP:
         p.useBE=true;      p.beR=0.7; p.beOffsetPts=0;
         p.usePartial=allowPartial; p.partialR=0.9; p.partialPct=0.67;
         p.trail=TRAIL_CANDLE;
         p.useTimeStop=true; p.maxBars=10;
         p.useDIExit=true;   p.adxMin=15; p.diMin=15; p.diDiff=5;
         break;

      case REG_VOL_SPIKE:
         p.useBE=true;      p.beR=1.2; p.beOffsetPts=10; // BE później
         p.usePartial=allowPartial; p.partialR=1.0; p.partialPct=0.3;
         p.trail=TRAIL_ATR;  p.atrPeriod=14; p.atrMult=2.8;
         p.useTimeStop=true; p.maxBars=15;
         p.useDIExit=false;
         break;
   }
   return p;
}

// proste „storage” naj-lepszych per reżim (w RAM)
static bool g_hasBest[4] = {false,false,false,false};
static ExitParams g_best[4];

// ---------------------------------------------------------------------
// Opis: Zwraca najlepsze zapisane parametry dla reżimu r (jeśli są w RAM);
//       w przeciwnym razie zwraca domyślne z allowPartial=true.
// Wywołuje: DefaultExitForRegime(r, true).
// Używa globalnych: g_hasBest[], g_best[].
// ---------------------------------------------------------------------
ExitParams LoadBestExitForRegime(MarketRegime r)
{
   if(g_hasBest[(int)r]) return g_best[(int)r];
   return DefaultExitForRegime(r, /*allowPartial*/true);
}

// ---------------------------------------------------------------------
// Opis: Zapisuje (do pamięci) najlepsze parametry p dla reżimu r.
// Wywołuje: (brak; opcjonalnie zapis do pliku w przyszłości).
// Używa globalnych: g_best[], g_hasBest[].
// ---------------------------------------------------------------------
void SaveBestExitForRegime(MarketRegime r, const ExitParams &p)
{
   g_best[(int)r] = p;
   g_hasBest[(int)r] = true;
   // (opcjonalnie: zapisz do pliku, by przetrwać restart)
}

// ---------------------------------------------------------------------
// Opis: Wersja funkcji domyślnej „by reference” — wypełnia strukturę out
//       domyślnymi wartościami zależnymi od reżimu i allowPartial.
// Wywołuje: (brak).
// Używa globalnych: (brak).
// ---------------------------------------------------------------------
void DefaultExitForRegime(MarketRegime r, bool allowPartial, ExitParams &out)
{
   // zacznij od „wyłączone”
   out.useBE=false; out.beR=1.0; out.beOffsetPts=5;
   out.usePartial=false; out.partialR=1.0; out.partialPct=0.5;
   out.trail=TRAIL_NONE; out.atrPeriod=14; out.atrMult=2.0;
   out.stepEveryPts=100; out.stepLockPts=50;
   out.useTimeStop=false; out.maxBars=20;
   out.useDIExit=false; out.adxMin=15; out.diMin=15; out.diDiff=5;

   switch(r)
   {
      case REG_TREND_STRONG:
         out.useBE=true;      out.beR=0.9; out.beOffsetPts=5;
         out.usePartial=allowPartial; out.partialR=1.0; out.partialPct=0.5;
         out.trail=TRAIL_ATR; out.atrPeriod=14; out.atrMult=2.2;
         out.useTimeStop=false; out.useDIExit=false;
         break;

      case REG_TREND_WEAK:
         out.useBE=true;      out.beR=1.0; out.beOffsetPts=5;
         out.usePartial=allowPartial; out.partialR=1.0; out.partialPct=0.5;
         out.trail=TRAIL_STEP; out.stepEveryPts=100; out.stepLockPts=50;
         out.useTimeStop=true; out.maxBars=20;
         out.useDIExit=true;   out.adxMin=15; out.diMin=15; out.diDiff=5;
         break;

      case REG_CHOP:
         out.useBE=true;      out.beR=0.7; out.beOffsetPts=0;
         out.usePartial=allowPartial; out.partialR=0.9; out.partialPct=0.67;
         out.trail=TRAIL_CANDLE;
         out.useTimeStop=true; out.maxBars=10;
         out.useDIExit=true;   out.adxMin=15; out.diMin=15; out.diDiff=5;
         break;

      case REG_VOL_SPIKE:
         out.useBE=true;      out.beR=1.2; out.beOffsetPts=10;
         out.usePartial=allowPartial; out.partialR=1.0; out.partialPct=0.3;
         out.trail=TRAIL_ATR;  out.atrPeriod=14; out.atrMult=2.8;
         out.useTimeStop=true; out.maxBars=15;
         out.useDIExit=false;
         break;
   }
}

// ---------------------------------------------------------------------
// Opis: Wypełnia out najlepszymi parametrami dla reżimu r z RAM,
//       a jeśli brak — ustawia domyślne; zwraca true, jeśli istniał best.
// Wywołuje: CopyExitParams(out, g_best[r]) lub DefaultExitForRegime(r, true, out).
// Używa globalnych: g_hasBest[], g_best[].
// ---------------------------------------------------------------------
bool LoadBestExitForRegime(MarketRegime r, ExitParams &out)
{
   if(g_hasBest[(int)r]) { CopyExitParams(out, g_best[(int)r]); return true; }
   DefaultExitForRegime(r, /*allowPartial*/true, out);
   return false;
}



#endif
