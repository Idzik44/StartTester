//+------------------------------------------------------------------+
//|                                     RangeAndVolumeAnalyzer11.mqh |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict

#ifndef __RANGE_AND_VOLUME_ANALYZER_MQH__
#define __RANGE_AND_VOLUME_ANALYZER_MQH__

#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTransactionData11.mqh>  // uwaga: zgodnie z istniejącą nazwą pliku


//----------------------------------------------------------------------
// Sesje
#define MAX_SESSIONS 100

enum SessionType { SESSION_TOKYO, SESSION_LONDON, SESSION_NEWYORK, SESSION_UNKNOWN };

// Bufory danych (pierścieniowe, po 1 rekordzie dziennie na sesję)
static double tokyoVolumes[MAX_SESSIONS];
static double londonVolumes[MAX_SESSIONS];
static double nyVolumes[MAX_SESSIONS];

static double tokyoRanges[MAX_SESSIONS];
static double londonRanges[MAX_SESSIONS];
static double nyRanges[MAX_SESSIONS];

// Średnie po ostatnich N dniach (dla każdej sesji)
static double avgTokyoVolume = 0, avgLondonVolume = 0, avgNYVolume = 0;
static double avgTokyoRange  = 0, avgLondonRange  = 0, avgNYRange  = 0;

// Aktualna sesja (etykiety do HUD)
static string currentSessionName = "UNKNOWN";
static double currentSessionAvgVolume = 0;
static double currentSessionAvgRange  = 0;

// Liczniki i wskaźniki pierścieni
static int tokyoVolCount = 0, londonVolCount = 0, nyVolCount = 0;
static int tokyoRangeCount = 0, londonRangeCount = 0, nyRangeCount = 0;
static int tokyoVolIndex = 0, londonVolIndex = 0, nyVolIndex = 0;
static int tokyoRangeIndex = 0, londonRangeIndex = 0, nyRangeIndex = 0;
static int lastTokyoDay = 0, lastLondonDay = 0, lastNYDay = 0;

// Flagi gotowości
static bool sessionVolumeReady = false, sessionRangeReady = false;

// ---------------------------------------------------------------------
// Utils czasu i sesji

// ─────────────────────────────────────────────────────────────
// Funkcja: GetDateKey
// Opis:    Tworzy klucz daty w formacie YYYYMMDD dla podanego czasu.
// Wywołuje: TimeToStruct.
// Używa globalnych: brak.
// ─────────────────────────────────────────────────────────────
int GetDateKey(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: GetSession
// Opis:    Określa typ sesji (TOKYO/LONDON/NEWYORK/UNKNOWN) na podstawie godziny.
//          Mapowanie: 00–07:59 Tokyo, 08–12:59 London, 13–21:59 New York.
// Wywołuje: TimeToStruct.
// Używa globalnych: brak.
// ─────────────────────────────────────────────────────────────
SessionType GetSession(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   int hour = dt.hour;

   // Mapowanie okien:
   // 13–21:59 NY, 8–12:59 London, 0–7:59 Tokyo (prosty, bez nakładania)
   if(hour >= 13 && hour < 22) return SESSION_NEWYORK;
   if(hour >= 8  && hour < 13) return SESSION_LONDON;
   if(hour >= 0  && hour < 8)  return SESSION_TOKYO;
   return SESSION_UNKNOWN;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: SessionTypeToString
// Opis:    Zamienia typ sesji na napis do logów/HUD.
// Wywołuje: brak.
// Używa globalnych: brak.
// ─────────────────────────────────────────────────────────────
string SessionTypeToString(SessionType session)
{
   switch(session) {
      case SESSION_TOKYO:   return "TOKYO";
      case SESSION_LONDON:  return "LONDON";
      case SESSION_NEWYORK: return "NEW YORK";
      default:              return "UNKNOWN";
   }
}

// ---- LOG helpery dla modułu sesji ----
static datetime __SA_lastLogBar = 0;

// ─────────────────────────────────────────────────────────────
// Funkcja: SA_LogOnce
// Opis:    Jednorazowy log na bar – jeśli DebugSessionAnalyzer i (opcjonalnie)
//          DebugSessionAnalyzer_OnceBar, wypisuje komunikat maks. raz na świecę.
// Wywołuje: Print.
// Używa globalnych: DebugSessionAnalyzer, DebugSessionAnalyzer_OnceBar, __SA_lastLogBar.
// ─────────────────────────────────────────────────────────────
void SA_LogOnce(const string msg, datetime tbar)
{
   if(!DebugSessionAnalyzer) return;
   if(DebugSessionAnalyzer_OnceBar){
      if(__SA_lastLogBar == tbar) return;
      __SA_lastLogBar = tbar;
   }
   Print(msg);
}

// ─────────────────────────────────────────────────────────────
// Funkcja: SessionAnalyzer_DumpSnapshot
// Opis:    Jednorazowy snapshot (log) stanu gotowości i średnich/ liczników sesji.
// Wywołuje: PrintFormat.
// Używa globalnych: sessionVolumeReady/sessionRangeReady, *VolCount/*RangeCount,
//                   avgTokyoVolume/avgLondonVolume/avgNYVolume,
//                   avgTokyoRange/avgLondonRange/avgNYRange.
// ─────────────────────────────────────────────────────────────
void SessionAnalyzer_DumpSnapshot()
{
   string readyV = sessionVolumeReady ? "Y" : "N";
   string readyR = sessionRangeReady  ? "Y" : "N";
   PrintFormat("[SA] Ready V=%s R=%s | TOKYO: Nvol=%d Nrng=%d avgV=%.2f avgR=%.5f | LONDON: Nvol=%d Nrng=%d avgV=%.2f avgR=%.5f | NY: Nvol=%d Nrng=%d avgV=%.2f avgR=%.5f",
               readyV, readyR,
               tokyoVolCount, tokyoRangeCount, avgTokyoVolume, avgTokyoRange,
               londonVolCount, londonRangeCount, avgLondonVolume, avgLondonRange,
               nyVolCount, nyRangeCount, avgNYVolume, avgNYRange);
}

// ---------------------------------------------------------------------
// Ring helpers (ostatnie N elementów liczymy „wstecz” od writeIndex)

// ─────────────────────────────────────────────────────────────
// Funkcja: RingAvg
// Thematyka: średnia po ostatnich N elementach z bufora pierścieniowego.
// Opis:    Liczy średnią „wstecz” od writeIndex.
// Wywołuje: MathMin.
// Używa globalnych: MAX_SESSIONS.
// ─────────────────────────────────────────────────────────────
double RingAvg(const double &arr[], int haveCount, int writeIndex, int useLastN)
{
   int n = MathMin(haveCount, useLastN);
   if(n <= 0) return 0.0;
   double s = 0.0;
   for(int k=0; k<n; ++k){
      int pos = (writeIndex - 1 - k);
      while(pos < 0) pos += MAX_SESSIONS;
      s += arr[pos % MAX_SESSIONS];
   }
   return s / n;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: RingStd
// Thematyka: odchylenie standardowe po ostatnich N elementach bufora pierścieniowego.
// Opis:    Liczy std „wstecz” od writeIndex na bazie średniej mean.
// Wywołuje: MathMin, MathSqrt.
// Używa globalnych: MAX_SESSIONS.
// ─────────────────────────────────────────────────────────────
double RingStd(const double &arr[], int haveCount, int writeIndex, int useLastN, double mean)
{
   int n = MathMin(haveCount, useLastN);
   if(n <= 1) return 0.0;
   double ss = 0.0;
   for(int k=0; k<n; ++k){
      int pos = (writeIndex - 1 - k);
      while(pos < 0) pos += MAX_SESSIONS;
      double v = arr[pos % MAX_SESSIONS];
      ss += (v - mean)*(v - mean);
   }
   return MathSqrt(ss / (n - 1));
}

// ---------------------------------------------------------------------
// Główne wejście zapisujące DZIEŃ dla danej sesji (spójne dla całego modułu)

// ─────────────────────────────────────────────────────────────
// Funkcja: PushSessionDayStat
// Opis:    Zapisuje uśrednione wartości (wolumen i range per bar) dla danej sesji i dnia
//          do buforów pierścieniowych; aktualizuje flagi gotowości i średnie.
// Wywołuje: RingAvg, PrintFormat (opcjonalnie).
// Używa globalnych: bufory tokyo*/london*/ny*, indeksy i liczniki, last*Day,
//                   sessionVolumeReady/sessionRangeReady,
//                   inputUserDefinedVolumeSessionCount, inputUserDefinedRangeSessionCount,
//                   avg*Volume, avg*Range, DebugSessionAnalyzer.
// ─────────────────────────────────────────────────────────────
void PushSessionDayStat(SessionType session, double avgVolPerBar, double avgRangePerBar, int dayKey)
{
   if(session == SESSION_TOKYO){
      tokyoVolumes[tokyoVolIndex] = avgVolPerBar;
      tokyoRanges[tokyoRangeIndex] = avgRangePerBar;
      tokyoVolIndex   = (tokyoVolIndex + 1) % MAX_SESSIONS;
      tokyoRangeIndex = (tokyoRangeIndex + 1) % MAX_SESSIONS;
      if(tokyoVolCount   < MAX_SESSIONS) tokyoVolCount++;
      if(tokyoRangeCount < MAX_SESSIONS) tokyoRangeCount++;
      lastTokyoDay = dayKey;
   }
   else if(session == SESSION_LONDON){
      londonVolumes[londonVolIndex] = avgVolPerBar;
      londonRanges[londonRangeIndex] = avgRangePerBar;
      londonVolIndex   = (londonVolIndex + 1) % MAX_SESSIONS;
      londonRangeIndex = (londonRangeIndex + 1) % MAX_SESSIONS;
      if(londonVolCount   < MAX_SESSIONS) londonVolCount++;
      if(londonRangeCount < MAX_SESSIONS) londonRangeCount++;
      lastLondonDay = dayKey;
   }
   else if(session == SESSION_NEWYORK){
      nyVolumes[nyVolIndex] = avgVolPerBar;
      nyRanges[nyRangeIndex] = avgRangePerBar;
      nyVolIndex   = (nyVolIndex + 1) % MAX_SESSIONS;
      nyRangeIndex = (nyRangeIndex + 1) % MAX_SESSIONS;
      if(nyVolCount   < MAX_SESSIONS) nyVolCount++;
      if(nyRangeCount < MAX_SESSIONS) nyRangeCount++;
      lastNYDay = dayKey;
   }

   // gotowości: wymagamy min. N dni dla każdej sesji
   sessionVolumeReady = (tokyoVolCount  >= inputUserDefinedVolumeSessionCount) &&
                        (londonVolCount >= inputUserDefinedVolumeSessionCount) &&
                        (nyVolCount     >= inputUserDefinedVolumeSessionCount);

   sessionRangeReady  = (tokyoRangeCount  >= inputUserDefinedRangeSessionCount) &&
                        (londonRangeCount >= inputUserDefinedRangeSessionCount) &&
                        (nyRangeCount     >= inputUserDefinedRangeSessionCount);

   // średnie po ostatnich N dniach (ring-aware)
   int Nvol = inputUserDefinedVolumeSessionCount;
   int Nrng = inputUserDefinedRangeSessionCount;

   avgTokyoVolume  = RingAvg(tokyoVolumes,  tokyoVolCount,  tokyoVolIndex,  Nvol);
   avgLondonVolume = RingAvg(londonVolumes, londonVolCount, londonVolIndex, Nvol);
   avgNYVolume     = RingAvg(nyVolumes,     nyVolCount,     nyVolIndex,     Nvol);

   avgTokyoRange   = RingAvg(tokyoRanges,   tokyoRangeCount,  tokyoRangeIndex,  Nrng);
   avgLondonRange  = RingAvg(londonRanges,  londonRangeCount, londonRangeIndex, Nrng);
   avgNYRange      = RingAvg(nyRanges,      nyRangeCount,     nyRangeIndex,     Nrng);

   if(DebugSessionAnalyzer){
      PrintFormat("📊 %s | avgVol(last%u)=%.2f | avgRange(last%u)=%.5f",
                  SessionTypeToString(session), Nvol,
                  (session==SESSION_TOKYO?avgTokyoVolume:session==SESSION_LONDON?avgLondonVolume:avgNYVolume),
                  Nrng,
                  (session==SESSION_TOKYO?avgTokyoRange:session==SESSION_LONDON?avgLondonRange:avgNYRange));
   }
}

// ---------------------------------------------------------------------
// Reset całości

// ─────────────────────────────────────────────────────────────
// Funkcja: ResetSessionStats
// Opis:    Zeruje bufor, liczniki, średnie i flagi gotowości; resetuje aktualną sesję.
// Wywołuje: ArrayInitialize, Print.
// Używa globalnych: wszystkie bufory i pola stanu modułu sesyjnego.
// ─────────────────────────────────────────────────────────────
void ResetSessionStats()
{
   if(DebugSessionAnalyzer) Print("🔄 Resetowanie statystyk sesji...");

   ArrayInitialize(tokyoVolumes, 0);
   ArrayInitialize(londonVolumes, 0);
   ArrayInitialize(nyVolumes, 0);
   ArrayInitialize(tokyoRanges, 0);
   ArrayInitialize(londonRanges, 0);
   ArrayInitialize(nyRanges, 0);

   tokyoVolCount = londonVolCount = nyVolCount = 0;
   tokyoRangeCount = londonRangeCount = nyRangeCount = 0;

   tokyoVolIndex = londonVolIndex = nyVolIndex = 0;
   tokyoRangeIndex = londonRangeIndex = nyRangeIndex = 0;

   avgTokyoVolume = avgLondonVolume = avgNYVolume = 0;
   avgTokyoRange  = avgLondonRange  = avgNYRange  = 0;

   lastTokyoDay = lastLondonDay = lastNYDay = 0;
   sessionVolumeReady = false;
   sessionRangeReady  = false;

   currentSessionName = "UNKNOWN";
   currentSessionAvgVolume = 0;
   currentSessionAvgRange  = 0;
}

// ---------------------------------------------------------------------
// Akumulator bieżącej sesji (sumy per dzień/sesja)
static SessionType aggSession = SESSION_UNKNOWN;
static int         aggDayKey  = -1;
static double      aggVolSum  = 0.0;
static double      aggRangeSum= 0.0;
static int         aggBars    = 0;

// ─────────────────────────────────────────────────────────────
/* Funkcja: ResetAgg
   Opis:   Resetuje zmienne akumulatora dla bieżącej sesji.
   Wywołuje: brak.
   Używa globalnych: aggSession, aggDayKey, aggVolSum, aggRangeSum, aggBars. */
void ResetAgg()
{
   aggSession = SESSION_UNKNOWN;
   aggDayKey  = -1;
   aggVolSum  = 0.0;
   aggRangeSum= 0.0;
   aggBars    = 0;
}

// ─────────────────────────────────────────────────────────────
/* Funkcja: ProcessBarForSessionAccumulators
   Opis:    Dla podanej świecy dolicza range i wolumen do akumulatora
            aktywnej sesji; przy zmianie sesji/dnia finalizuje poprzednią
            (PushSessionDayStat) i rozpoczyna nową.
   Wywołuje: GetSession, GetDateKey, PushSessionDayStat.
   Używa globalnych: aggSession, aggDayKey, aggVolSum, aggRangeSum, aggBars. */
void ProcessBarForSessionAccumulators(const MqlRates &candle)
{
   SessionType s = GetSession(candle.time);
   int dayKey = GetDateKey(candle.time);
   double range = candle.high - candle.low;
   double vol   = (double)candle.tick_volume;

   // inicjalizacja akumulatora
   if(aggSession == SESSION_UNKNOWN){
      aggSession = s; aggDayKey = dayKey; aggVolSum = 0.0; aggRangeSum = 0.0; aggBars = 0;
   }

   // zmiana sesji/dnia? – finalize poprzednią i start nowej
   if(s != aggSession || dayKey != aggDayKey){
      if(aggBars > 0){
         double avgVolPerBar   = aggVolSum   / aggBars;
         double avgRangePerBar = aggRangeSum / aggBars;
         PushSessionDayStat(aggSession, avgVolPerBar, avgRangePerBar, aggDayKey);
      }
      aggSession = s; aggDayKey = dayKey; aggVolSum = 0.0; aggRangeSum = 0.0; aggBars = 0;
   }

   // akumulacja bieżącej świecy do aktywnej sesji
   if(s != SESSION_UNKNOWN){
      aggVolSum   += vol;
      aggRangeSum += range;
      aggBars     += 1;
   }
}

// ─────────────────────────────────────────────────────────────
/* Funkcja: FinalizeAggIfAny
   Opis:    Finalizuje (wypycha) zebrane dane bieżącej sesji, jeśli istnieją,
            i resetuje akumulator.
   Wywołuje: PushSessionDayStat, ResetAgg.
   Używa globalnych: aggSession, aggBars, aggVolSum, aggRangeSum, aggDayKey. */
void FinalizeAggIfAny()
{
   if(aggSession != SESSION_UNKNOWN && aggBars > 0){
      double avgVolPerBar   = aggVolSum   / aggBars;
      double avgRangePerBar = aggRangeSum / aggBars;
      PushSessionDayStat(aggSession, avgVolPerBar, avgRangePerBar, aggDayKey);
   }
   ResetAgg();
}

// ---------------------------------------------------------------------
// ZACHOWANIE KOMPATYBILNOŚCI: stare API AddSessionData() → deleguje do PushSessionDayStat()

// ─────────────────────────────────────────────────────────────
/* Funkcja: AddSessionData
   Opis:    Zgodność wstecz: dodaje dzienny rekord dla sesji tylko raz (sprawdza last*Day),
            a faktyczny zapis deleguje do PushSessionDayStat.
   Wywołuje: SessionTypeToString, PushSessionDayStat, Print (opcjonalnie).
   Używa globalnych: DebugSessionAnalyzer, lastTokyoDay/lastLondonDay/lastNYDay. */
void AddSessionData(SessionType session, double volume, double range, int dayKey)
{
   if (DebugSessionAnalyzer)
      Print("📥 Dodawanie danych: ", SessionTypeToString(session),
            ", Dzień=", dayKey, ", Vol=", volume, ", Range=", range);

   // Jeden wpis na dzień/sesję
   if (session == SESSION_TOKYO) {
      if (dayKey != lastTokyoDay)
         PushSessionDayStat(session, volume, range, dayKey);
   }
   else if (session == SESSION_LONDON) {
      if (dayKey != lastLondonDay)
         PushSessionDayStat(session, volume, range, dayKey);
   }
   else if (session == SESSION_NEWYORK) {
      if (dayKey != lastNYDay)
         PushSessionDayStat(session, volume, range, dayKey);
   }
}


// ---------------------------------------------------------------------
// Skany historii i LIVE

// ─────────────────────────────────────────────────────────────
/* Funkcja: AnalyzeInitialSessionRangesAndVolumes
   Opis:    Analiza wstępna historii: resetuje stan, przelicza sesje „od najstarszej”
            do świecy [1], agreguje dane dzienne i ustawia średnie/flagę gotowości.
   Wywołuje: ArraySize, Print, ResetSessionStats, ResetAgg, ProcessBarForSessionAccumulators,
             FinalizeAggIfAny, GetSession, SessionTypeToString, GetAverageVolume, GetAverageRange.
   Używa globalnych: candleHistory[], DebugSessionAnalyzer, currentSessionName/currentSessionAvg*. */
void AnalyzeInitialSessionRangesAndVolumes()
{
   if(sessionVolumeReady && sessionRangeReady) return;

   int totalBars = ArraySize(candleHistory);
   if(totalBars <= 1) return;

   if(DebugSessionAnalyzer) Print("🔍 Analiza wstępna sesji na ", totalBars, " świecach...");

   ResetSessionStats();
   ResetAgg();

   // od najstarszej do [1] (pomijamy niedomkniętą [0])
   for (int i = totalBars - 1; i >= 1; --i) {
      MqlRates c = candleHistory[i];
      ProcessBarForSessionAccumulators(c);
      if(sessionVolumeReady && sessionRangeReady){
         if(DebugSessionAnalyzer) Print("✅ Zebrano wystarczająco danych sesyjnych — skracam analizę.");
         break;
      }
   }
   FinalizeAggIfAny();

   // ustaw aktualne „currentSession*” wg świecy [1]
   SessionType curS = GetSession(candleHistory[1].time);
   currentSessionName    = SessionTypeToString(curS);
   currentSessionAvgVolume = GetAverageVolume(curS);
   currentSessionAvgRange  = GetAverageRange(curS);
}

// ─────────────────────────────────────────────────────────────
/* Funkcja: UpdateLiveSessionVolume
   Opis:    Tryb LIVE: na każdej nowej zamkniętej świecy [1] aktualizuje akumulator,
            bieżącą nazwę sesji i średnie; opcjonalnie loguje jeden wpis na bar.
   Wywołuje: ArraySize, SA_LogOnce, GetSession, SessionTypeToString,
             GetAverageVolume, GetAverageRange, ProcessBarForSessionAccumulators.
   Używa globalnych: candleHistory[], DebugSessionAnalyzer, currentSessionName/currentSessionAvg*. */
void UpdateLiveSessionVolume()
{
    static datetime lastBarTime = 0;
    int total = ArraySize(candleHistory);
    if(total <= 1) return;

    if (candleHistory[1].time == lastBarTime) return;
    lastBarTime = candleHistory[1].time;

   MqlRates c = candleHistory[1]; // zamknięta świeca
   ProcessBarForSessionAccumulators(c);

   SessionType session = GetSession(c.time);
   currentSessionName     = SessionTypeToString(session);
   currentSessionAvgVolume= GetAverageVolume(session);
   currentSessionAvgRange = GetAverageRange(session);

   if(DebugSessionAnalyzer) {
      string __msg = StringFormat("🔁 [SA] LIVE: %s | tickVol=%.0f | range=%.5f | avgVol=%.2f | avgRange=%.5f",
                                  currentSessionName, (double)c.tick_volume, (c.high-c.low),
                                  currentSessionAvgVolume, currentSessionAvgRange);
      SA_LogOnce(__msg, c.time);
   }

}

// ---------------------------------------------------------------------
// Gettery

// ─────────────────────────────────────────────────────────────
// Funkcja: IsSessionDataReady
// Opis:    Zwraca true, gdy dostępne są minimalne dane sesyjne dla wolumenu i range.
// Wywołuje: brak.
// Używa globalnych: sessionVolumeReady, sessionRangeReady.
// ─────────────────────────────────────────────────────────────
bool IsSessionDataReady() { return sessionVolumeReady && sessionRangeReady; }

// ─────────────────────────────────────────────────────────────
// Funkcja: GetAverageVolume
// Opis:    Zwraca średni wolumen dla podanej sesji (ostatnie N dni wg RingAvg).
// Wywołuje: brak.
// Używa globalnych: avgTokyoVolume/avgLondonVolume/avgNYVolume.
// ─────────────────────────────────────────────────────────────
double GetAverageVolume(SessionType session)
{
   switch(session) {
      case SESSION_TOKYO:   return avgTokyoVolume;
      case SESSION_LONDON:  return avgLondonVolume;
      case SESSION_NEWYORK: return avgNYVolume;
   }
   return 0;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: GetAverageRange
// Opis:    Zwraca średni range dla podanej sesji (ostatnie N dni wg RingAvg).
// Wywołuje: brak.
// Używa globalnych: avgTokyoRange/avgLondonRange/avgNYRange.
// ─────────────────────────────────────────────────────────────
double GetAverageRange(SessionType session)
{
   switch(session) {
      case SESSION_TOKYO:   return avgTokyoRange;
      case SESSION_LONDON:  return avgLondonRange;
      case SESSION_NEWYORK: return avgNYRange;
   }
   return 0;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: GetCurrentSessionAverageVolume
// Opis:    Zwraca cache’owaną średnią wolumenu dla bieżącej sesji.
// Wywołuje: brak.
// Używa globalnych: currentSessionAvgVolume.
// ─────────────────────────────────────────────────────────────
double GetCurrentSessionAverageVolume() { return currentSessionAvgVolume; }

// ─────────────────────────────────────────────────────────────
// Funkcja: GetCurrentSessionAverageRange
// Opis:    Zwraca cache’owaną średnią range dla bieżącej sesji.
// Wywołuje: brak.
// Używa globalnych: currentSessionAvgRange.
// ─────────────────────────────────────────────────────────────
double GetCurrentSessionAverageRange()  { return currentSessionAvgRange; }

// ─────────────────────────────────────────────────────────────
// Funkcja: GetStdVolume
// Opis:    Odchylenie standardowe wolumenu dla sesji (ostatnie N zapisanych dni).
// Wywołuje: RingAvg, RingStd.
// Używa globalnych: bufory *Volumes, *VolCount, *VolIndex, inputUserDefinedVolumeSessionCount.
// ─────────────────────────────────────────────────────────────
double GetStdVolume(SessionType s)
{
   int N = inputUserDefinedVolumeSessionCount;
   if(s == SESSION_TOKYO){
      double mu = RingAvg(tokyoVolumes, tokyoVolCount, tokyoVolIndex, N);
      return RingStd(tokyoVolumes, tokyoVolCount, tokyoVolIndex, N, mu);
   } else if(s == SESSION_LONDON){
      double mu = RingAvg(londonVolumes, londonVolCount, londonVolIndex, N);
      return RingStd(londonVolumes, londonVolCount, londonVolIndex, N, mu);
   } else if(s == SESSION_NEWYORK){
      double mu = RingAvg(nyVolumes, nyVolCount, nyVolIndex, N);
      return RingStd(nyVolumes, nyVolCount, nyVolIndex, N, mu);
   }
   return 0.0;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: GetStdRange
// Opis:    Odchylenie standardowe range dla sesji (ostatnie N zapisanych dni).
// Wywołuje: RingAvg, RingStd.
// Używa globalnych: bufory *Ranges, *RangeCount, *RangeIndex, inputUserDefinedRangeSessionCount.
// ─────────────────────────────────────────────────────────────
double GetStdRange(SessionType s)
{
   int N = inputUserDefinedRangeSessionCount;
   if(s == SESSION_TOKYO){
      double mu = RingAvg(tokyoRanges, tokyoRangeCount, tokyoRangeIndex, N);
      return RingStd(tokyoRanges, tokyoRangeCount, tokyoRangeIndex, N, mu);
   } else if(s == SESSION_LONDON){
      double mu = RingAvg(londonRanges, londonRangeCount, londonRangeIndex, N);
      return RingStd(londonRanges, londonRangeCount, londonRangeIndex, N, mu);
   } else if(s == SESSION_NEWYORK){
      double mu = RingAvg(nyRanges, nyRangeCount, nyRangeIndex, N);
      return RingStd(nyRanges, nyRangeCount, nyRangeIndex, N, mu);
   }
   return 0.0;
}

// ---------------------------------------------------------------------
// Rolling Z-score fallback (gdy statystyki sesji niegotowe lub sd≈0)

// ─────────────────────────────────────────────────────────────
// Funkcja: __RangeAt
// Opis:    Range (high-low) dla świecy o podanym shift’cie.
// Wywołuje: ArraySize.
// Używa globalnych: candleHistory[].
// ─────────────────────────────────────────────────────────────
double __RangeAt(int shift)
{
   if (shift < 0 || shift >= ArraySize(candleHistory)) return 0.0;
   return candleHistory[shift].high - candleHistory[shift].low;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: __VolAt
// Opis:    Wolumen tickowy dla świecy o podanym shift’cie.
// Wywołuje: ArraySize.
// Używa globalnych: candleHistory[].
// ─────────────────────────────────────────────────────────────
double __VolAt(int shift)
{
   if (shift < 0 || shift >= ArraySize(candleHistory)) return 0.0;
   return (double)candleHistory[shift].tick_volume;
}

// ─────────────────────────────────────────────────────────────
// Funkcja: __Z_Local
// Opis:    Lokalny Z-score w oknie W liczonym „do przodu” od shift (i..i+W-1).
//          Używane jako fallback, gdy statystyki sesji nie są gotowe.
// Wywołuje: ArraySize, MathMin, MathSqrt, __RangeAt/__VolAt.
// Używa globalnych: candleHistory[], Z_MinBars, Z_Window.
// ─────────────────────────────────────────────────────────────
double __Z_Local(int shift, int W, bool useRange)
{
   const int total = ArraySize(candleHistory);
   if (total < Z_MinBars || shift + 10 >= total) return 0.0;

   // licz okno do przodu w historii (i, i+1, ..., i+W-1)
   const int last = MathMin(total - 1, shift + MathMax(W, Z_MinBars) - 1);

   // mean
   double sum = 0.0; int cnt = 0;
   for (int j = shift; j <= last; ++j) {
      sum += (useRange ? __RangeAt(j) : __VolAt(j));
      cnt++;
   }
   if (cnt < Z_MinBars) return 0.0;
   const double mean = sum / cnt;

   // std
   double var = 0.0;
   for (int j = shift; j <= last; ++j) {
      const double v = (useRange ? __RangeAt(j) : __VolAt(j)) - mean;
      var += v * v;
   }
   const double sd = MathSqrt(var / MathMax(1, cnt - 1));
   if (sd <= 1e-12) return 0.0;

   const double x0 = (useRange ? __RangeAt(shift) : __VolAt(shift));
   return (x0 - mean) / sd;
}


// ---------------------------------------------------------------------
// Standaryzacja (Z-score) dla świecy `shift` (domyślnie 1)

// ─────────────────────────────────────────────────────────────
// Funkcja: GetStandardizedVolume
// Opis:    Zwraca Z-score wolumenu świecy (sesyjny, a jeśli brak gotowości – rolling).
// Wywołuje: GetSession, GetAverageVolume, GetStdVolume, __VolAt, __Z_Local, ArraySize.
// Używa globalnych: candleHistory[], sessionVolumeReady, Z_Window.
// ─────────────────────────────────────────────────────────────
double GetStandardizedVolume(int shift=1)
{
   if(shift < 1 || shift >= ArraySize(candleHistory)) return 0.0;

   SessionType s = GetSession(candleHistory[shift].time);
   double mu = GetAverageVolume(s);
   double sd = GetStdVolume(s);

   // jeśli mamy gotowe statystyki sesji – użyj ich
   if (sd > 1e-9 && sessionVolumeReady)
      return (__VolAt(shift) - mu) / sd;

   // fallback: rolling Z-score
   return __Z_Local(shift, Z_Window, /*useRange=*/false);
}

// ─────────────────────────────────────────────────────────────
// Funkcja: GetStandardizedRange
// Opis:    Zwraca Z-score range świecy (sesyjny, a jeśli brak gotowości – rolling).
// Wywołuje: GetSession, GetAverageRange, GetStdRange, __RangeAt, __Z_Local, ArraySize.
// Używa globalnych: candleHistory[], sessionRangeReady, Z_Window.
// ─────────────────────────────────────────────────────────────
double GetStandardizedRange(int shift=1)
{
   if(shift < 1 || shift >= ArraySize(candleHistory)) return 0.0;

   SessionType s = GetSession(candleHistory[shift].time);
   double mu = GetAverageRange(s);
   double sd = GetStdRange(s);

   // jeśli mamy gotowe statystyki sesji – użyj ich
   if (sd > 1e-12 && sessionRangeReady) {
      double r = __RangeAt(shift);
      return (r - mu) / sd;
   }

   // fallback: rolling Z-score
   return __Z_Local(shift, Z_Window, /*useRange=*/true);
}

// ---------------------------------------------------------------------
// Pomocnicze: szybki dump do kalibracji progów reżimów

// ─────────────────────────────────────────────────────────────
// Funkcja: DumpZStats_Range
// Opis:    Wypisuje statystyki |Z(range)| dla ostatnich `bars` świec (do kalibracji).
// Wywołuje: ArraySize, GetStandardizedRange, PrintFormat, MathMin, MathAbs.
// Używa globalnych: candleHistory[], Z_Window.
// ─────────────────────────────────────────────────────────────
void DumpZStats_Range(int bars=1500)
{
   int total = ArraySize(candleHistory);
   int upto = MathMin(bars, total - 2);
   double mn=1e9, mx=-1e9, sum=0.0; int c=0;
   for (int i=1; i<=upto; ++i) {
      double z = GetStandardizedRange(i);
      double a = MathAbs(z);
      if (a == 0.0) continue;
      mn = MathMin(mn, a); mx = MathMax(mx, a); sum += a; c++;
   }
   double avg = (c ? sum/c : 0.0);
   PrintFormat("[Z-RANGE] sample=%d win=%d | |Z| avg=%.3f min=%.3f max=%.3f",
               c, Z_Window, avg, mn, mx);
}

// ─────────────────────────────────────────────────────────────
// Funkcja: DumpZStats_Volume
// Opis:    Wypisuje statystyki |Z(volume)| dla ostatnich `bars` świec (do kalibracji).
// Wywołuje: ArraySize, GetStandardizedVolume, PrintFormat, MathMin, MathAbs.
// Używa globalnych: candleHistory[], Z_Window.
// ─────────────────────────────────────────────────────────────
void DumpZStats_Volume(int bars=1500)
{
   int total = ArraySize(candleHistory);
   int upto = MathMin(bars, total - 2);
   double mn=1e9, mx=-1e9, sum=0.0; int c=0;
   for (int i=1; i<=upto; ++i) {
      double z = GetStandardizedVolume(i);
      double a = MathAbs(z);
      if (a == 0.0) continue;
      mn = MathMin(mn, a); mx = MathMax(mx, a); sum += a; c++;
   }
   double avg = (c ? sum/c : 0.0);
   PrintFormat("[Z-VOL]   sample=%d win=%d | |Z| avg=%.3f min=%.3f max=%.3f",
               c, Z_Window, avg, mn, mx);
}

#endif
