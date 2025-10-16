//+------------------------------------------------------------------+
//|                           ExitEngine.mqh                         |
//|  Meta-kontroler wyjść + 3 polityki: ATR, Swing, Hybrid           |
//|  Używa progów reżimów z COMMON\Files\best_summary.csv            |
//|  (fallback: best_regime_thresholds.csv).                          |
//+------------------------------------------------------------------+
#ifndef __EXIT_ENGINE_MQH__
#define __EXIT_ENGINE_MQH__
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <StartTester/RegimeThresholds.mqh>        // progi reżimów: load z CSV
#include <StartTester/Zmienne11.mqh>
#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>

// ===== Domyślne parametry HYBRID =====
input double Exit_HYB_TP1_R             = 1.0;   // poziom R dla częściowego wyjścia (0 = wyłącz)
input double Exit_HYB_BE_After_R        = 1.0;   // po ilu R przenieść SL do BE
input double Exit_HYB_TrailATR_K        = 3.2;   // k dla chandelier ATR po BE
input int    Exit_HYB_TimeStop_Bars     = 25;    // czasowy stop (liczba barów, 0 = wyłącz)
input double Exit_HYB_TimeStop_MinR     = 0.3;   // jeśli po T barach MFE < MinR, zamknij
input double Exit_HYB_PartialFrac       = 0.50;  // ułamek do częściowego wyjścia (0 = wyłącz)

input bool DebugExitOptimizer = true;
input bool DebugExit_ATR      = true;
input bool DebugExit_Swing    = true;
input bool DebugExit_Hybrid   = true;
input bool DebugExit_Heartbeat= true;

CTrade __exitTrade;

// --- Polityki wyjścia ---
enum ExitPolicy { EXIT_ATR = 0, EXIT_SWING = 1, EXIT_HYBRID = 2 };

// --- Parametry polityk ---
struct ExitParamsATR { double kATR; int atrPeriod; ExitParamsATR():kATR(0.0),atrPeriod(0){} ExitParamsATR(const ExitParamsATR &o){kATR=o.kATR; atrPeriod=o.atrPeriod;} };
struct ExitParamsSW  { int swingN; int offsetPts;  ExitParamsSW():swingN(0),offsetPts(0){}  ExitParamsSW(const ExitParamsSW  &o){swingN=o.swingN; offsetPts=o.offsetPts;} };
struct ExitParamsHYB {
   double tp1R, beAfterR, trailATRk; int timeStopBars; double timeStopMinR; double partialFrac;
   ExitParamsHYB(){} ExitParamsHYB(const ExitParamsHYB &o){ tp1R=o.tp1R; beAfterR=o.beAfterR; trailATRk=o.trailATRk; timeStopBars=o.timeStopBars; timeStopMinR=o.timeStopMinR; partialFrac=o.partialFrac; }
};
struct ExitConfig { ExitPolicy policy; ExitParamsATR atr; ExitParamsSW sw; ExitParamsHYB hyb; ExitConfig(){} ExitConfig(const ExitConfig &src){policy=src.policy; atr=src.atr; sw=src.sw; hyb=src.hyb;} };

// ====== Pomocnicze ======
inline double Pts(double pts) { return pts * _Point; }

// ===== ADX/DI lokalny cache =====
static int __adxHandle = -1;
static int __adxPeriodCached = -1;
bool EnsureAdxHandle(int period){ if (__adxHandle != -1 && __adxPeriodCached == period) return true; __adxHandle = iADX(_Symbol, _Period, period); __adxPeriodCached = period; return (__adxHandle != -1); }
double ADX_Value   (int barShift, int period=14){ if(!EnsureAdxHandle(period))return 0.0; double b[]; if(CopyBuffer(__adxHandle,0,barShift,1,b)<=0)return 0.0; return b[0]; }
double DIPlus_Value(int barShift, int period=14){ if(!EnsureAdxHandle(period))return 0.0; double b[]; if(CopyBuffer(__adxHandle,1,barShift,1,b)<=0)return 0.0; return b[0]; }
double DIMinus_Value(int barShift,int period=14){ if(!EnsureAdxHandle(period))return 0.0; double b[]; if(CopyBuffer(__adxHandle,2,barShift,1,b)<=0)return 0.0; return b[0]; }
double ATR_Value(int shift,int period){ static int h=-1,p=-1; if(h==-1||p!=period){h=iATR(_Symbol,_Period,period);p=period;} if(h==-1)return 0.0; double b[]; if(CopyBuffer(h,0,shift,1,b)<=0)return 0.0; return b[0]; }

// Trend: 0=Down,1=Flat,2=Up  |  Vol: 0=Low,1=Normal,2=High  => 3*3 = 9
#define NUM_REGIMES 9

// ===== Najlepsze polityki/parametry per-regime (opcjonalnie z optymalizatora) =====
static bool __bestReady = false;
static ExitPolicy    __bestPolicy[NUM_REGIMES];
static ExitParamsATR __bestATR[NUM_REGIMES];
static ExitParamsSW  __bestSW[NUM_REGIMES];
static ExitParamsHYB __bestHYB[NUM_REGIMES];
void ExitEngine_SetBestForRegime(int regime, ExitPolicy pol, const ExitParamsATR &a, const ExitParamsSW &s, const ExitParamsHYB &h)
{ if(regime<0||regime>=NUM_REGIMES)return; __bestPolicy[regime]=pol; __bestATR[regime]=a; __bestSW[regime]=s; __bestHYB[regime]=h; __bestReady=true; }

// --- Konfiguracja wewnętrzna (fallback dla histerezy, gdyby brak CSV) ---
bool   RD_UseVolumeFusion()  { return true; }  // fusion Z-range z Z-volume
double RD_Z_Hyst()           { return 0.05; }  // domyślna histereza Z (fallback)
double RD_ADX_Hyst()         { return 2.0; }   // domyślna histereza ADX (fallback)
int    RD_DI_MinGap()        { return 5; }     // domyślny DI gap (fallback)

// ===== Progi reżimów ładowane LAZY z CSV =====
static bool   __RD_LoadedOnce      = false;
static double __RD_ZLow_Override    = -1.0;
static double __RD_ZHigh_Override   = -1.0;
static double __RD_ADXStrong_Ovr    = -1.0;
static int    __RD_DIGap_Override   = -1;
static double __RD_ZHyst_Override   = -1.0;
static double __RD_ADXHyst_Override = -1.0;

void RD_SetOverrides(double zLow,double zHigh,double adxStrong,int diGap,double zHyst,double adxHyst)
{
   __RD_ZLow_Override    = zLow;
   __RD_ZHigh_Override   = zHigh;
   __RD_ADXStrong_Ovr    = adxStrong;
   __RD_DIGap_Override   = diGap;
   __RD_ZHyst_Override   = zHyst;
   __RD_ADXHyst_Override = adxHyst;
   __RD_LoadedOnce = true;
}

// Lazy init – wczytaj progi z CSV przy pierwszym użyciu
void __RD_EnsureThresholds()
{
   if(__RD_LoadedOnce) return;

   RegimeThresholds t = DefaultRegimeThresholds();
   // preferuj best_summary.csv; fallback do best_regime_thresholds.csv
   bool ok = LoadRegimeThresholds(t, "best_regime_thresholds.csv");
   if(!ok)  LoadRegimeThresholds(t, "best_summary.csv");


   RD_SetOverrides(t.zLow, t.zHigh, t.adxStrong, t.diGap, t.zHyst, t.adxHyst);

   PrintFormat("[ExitEngine] Regime thresholds set -> zLow=%.6f zHigh=%.6f adx=%.3f di=%d zH=%.3f aH=%.3f",
               t.zLow, t.zHigh, t.adxStrong, t.diGap, t.zHyst, t.adxHyst);
}

// Gettery zawsze po ensure
double RD_GetZLow()      { __RD_EnsureThresholds(); return (__RD_ZLow_Override    >= 0.0) ? __RD_ZLow_Override    : DefaultRegimeThresholds().zLow;  }
double RD_GetZHigh()     { __RD_EnsureThresholds(); return (__RD_ZHigh_Override   >= 0.0) ? __RD_ZHigh_Override   : DefaultRegimeThresholds().zHigh; }
double RD_GetADXStrong() { __RD_EnsureThresholds(); return (__RD_ADXStrong_Ovr    >= 0.0) ? __RD_ADXStrong_Ovr    : DefaultRegimeThresholds().adxStrong; }
int    RD_GetDIGap()     { __RD_EnsureThresholds(); return (__RD_DIGap_Override   >= 0  ) ? __RD_DIGap_Override   : RD_DI_MinGap(); }
double RD_GetZHyst()     { __RD_EnsureThresholds(); return (__RD_ZHyst_Override   >= 0.0) ? __RD_ZHyst_Override   : RD_Z_Hyst(); }
double RD_GetADXHyst()   { __RD_EnsureThresholds(); return (__RD_ADXHyst_Override >= 0.0) ? __RD_ADXHyst_Override : RD_ADX_Hyst(); }

// ===============================
// Regime detector (fusion + hysteresis)
// Trend: 0=DOWN, 1=FLAT, 2=UP
// Vol   : 0=LOW,  1=NORMAL, 2=HIGH
// regimeKey = trend*3 + vol  (0..8)
// ===============================
int __VolBucket_WithHysteresis(int shift)
{
   const double zLowEnter  = RD_GetZLow();
   const double zLowExit   = RD_GetZLow()  + RD_GetZHyst();
   const double zHighEnter = RD_GetZHigh();
   const double zHighExit  = RD_GetZHigh() - RD_GetZHyst();

   double zr = MathAbs(GetStandardizedRange(shift));
   double zv = MathAbs(GetStandardizedVolume(shift));

   static int lastVolBucket = -1;

   // historia (stateless)
   if (shift != 1)
   {
      bool lowCond  = (zr < zLowEnter) && (!RD_UseVolumeFusion() || (zv < zLowEnter));
      bool highCond = (zr > zHighEnter) || (RD_UseVolumeFusion() && (zv > zHighEnter));
      if (lowCond)  return 0;
      if (highCond) return 2;
      return 1;
   }

   // live (stateful)
   if (lastVolBucket < 0)
   {
      bool lowCond  = (zr < zLowEnter) && (!RD_UseVolumeFusion() || (zv < zLowEnter));
      bool highCond = (zr > zHighEnter) || (RD_UseVolumeFusion() && (zv > zHighEnter));
      lastVolBucket = highCond ? 2 : (lowCond ? 0 : 1);
      return lastVolBucket;
   }

   if (lastVolBucket == 0)
   {
      bool leaveLow = (zr >= zLowExit) && (!RD_UseVolumeFusion() || (zv >= zLowExit));
      if (!leaveLow) return 0;
      bool highNow = (zr > zHighEnter) || (RD_UseVolumeFusion() && (zv > zHighEnter));
      lastVolBucket = highNow ? 2 : 1;
      return lastVolBucket;
   }
   else if (lastVolBucket == 2)
   {
      bool leaveHigh = (zr <= zHighExit) && (!RD_UseVolumeFusion() || (zv <= zHighExit));
      if (!leaveHigh) return 2;
      bool lowNow = (zr < zLowEnter) && (!RD_UseVolumeFusion() || (zv < zLowEnter));
      lastVolBucket = lowNow ? 0 : 1;
      return lastVolBucket;
   }
   else
   {
      bool toLow  = (zr < zLowEnter)  && (!RD_UseVolumeFusion() || (zv < zLowEnter));
      bool toHigh = (zr > zHighEnter) || (RD_UseVolumeFusion() && (zv > zHighEnter));
      if (toLow)      lastVolBucket = 0;
      else if (toHigh)lastVolBucket = 2;
      else            lastVolBucket = 1;
      return lastVolBucket;
   }
}

int __TrendBucket(int shift)
{
   const double strongEnter = RD_GetADXStrong();
   const double strongExit  = RD_GetADXStrong() - RD_GetADXHyst();

   double adx = ADX_Value(shift, 14);
   double pdi = DIPlus_Value(shift, 14);
   double mdi = DIMinus_Value(shift, 14);

   if (adx < strongExit) return 1;

   double diff = pdi - mdi;
   if (adx >= strongEnter)
   {
      if (diff >= RD_GetDIGap())  return 2;
      if (-diff >= RD_GetDIGap()) return 0;
      return 1;
   }

   if (diff >= RD_GetDIGap())  return 2;
   if (-diff >= RD_GetDIGap()) return 0;
   return 1;
}

int DetectRegimeKey(int barShift)
{
   int t = __TrendBucket(barShift);
   int v = __VolBucket_WithHysteresis(barShift);
   return t * 3 + v;
}

string RegimeToString(int regimeKey)
{
   int t = regimeKey / 3, v = regimeKey % 3;
   string ts=(t==2?"UP":(t==0?"DOWN":"FLAT"));
   string vs=(v==2?"HIGH":(v==0?"LOW":"NORMAL"));
   return ts + "|" + vs;
}

// ====== Wybór polityki ======
ExitConfig DefaultConfig()
{
   ExitConfig c;
   c.policy        = EXIT_HYBRID;

   c.atr.kATR      = Exit_ATR_K_Default;
   c.atr.atrPeriod = Exit_ATR_Period;

   c.sw.swingN     = Exit_Swing_N_Default;
   c.sw.offsetPts  = Exit_Swing_OffsetPts;

   c.hyb.tp1R         = Exit_HYB_TP1_R;
   c.hyb.beAfterR     = Exit_HYB_BE_After_R;
   c.hyb.trailATRk    = Exit_HYB_TrailATR_K;
   c.hyb.timeStopBars = Exit_HYB_TimeStop_Bars;
   c.hyb.timeStopMinR = Exit_HYB_TimeStop_MinR;
   c.hyb.partialFrac  = Exit_HYB_PartialFrac;
   return c;
}

double __rand01() { return (double)MathRand() / 32767.0; }  // pamiętaj o MathSrand w OnInit

ExitConfig ChooseExitForRegime(int regime)
{
   // Eksploracja
   if (__rand01() < Exit_EpsilonGreedy) {
      ExitConfig e = DefaultConfig();
      int alt = (int)MathFloor(__rand01() * 3.0);
      e.policy = (ExitPolicy)alt;
      if (DebugExitOptimizer)
         PrintFormat("[Exit] Explore regime=%d -> %s", regime, alt==0?"ATR":(alt==1?"SWING":"HYBRID"));
      return e;
   }

   // Eksploatacja — jeśli mamy wynik optymalizacji per-regime, używamy go
   ExitConfig c = DefaultConfig();
   if (__bestReady) {
      c.policy = __bestPolicy[regime];
      c.atr    = __bestATR[regime];
      c.sw     = __bestSW[regime];
      c.hyb    = __bestHYB[regime];
   } else {
      // fallback: proste mapowanie trend/vol
      int t = regime / 3; // trend
      int v = regime % 3; // vol
      if (t == 2 || t == 0) c.policy = (v == 2) ? EXIT_ATR : EXIT_HYBRID;
      else                  c.policy = (v == 0) ? EXIT_SWING : EXIT_HYBRID;
   }

   if (DebugExitOptimizer)
      PrintFormat("[Exit] Exploit regime=%d -> policy=%d (bestReady=%d)", regime, (int)c.policy, (int)__bestReady);
   return c;
}

// ====== Bindowanie polityki do biletu ======
struct TicketExitBinding {
   ulong ticket;
   ExitConfig cfg;
   bool  used;

   double oneR;
   bool   partialDone;
   datetime entryTime;
   datetime lastLogBar;  // 🔔 do heartbeat
};
TicketExitBinding __bindings[32];
int __bindingsCount = 0;

int FindBindingIndex(ulong ticket)
{
   for (int i=0;i<__bindingsCount;++i)
      if (__bindings[i].used && __bindings[i].ticket==ticket) return i;
   return -1;
}

void BindExitToTicket(ulong ticket, const ExitConfig &cfg)
{
   int idx = FindBindingIndex(ticket);
   if (idx >= 0) {
      __bindings[idx].cfg = cfg;
      if (DebugExitOptimizer) PrintFormat("[Exit] Rebind ticket=%I64u", ticket);
      return;
   }

   if (__bindingsCount >= 32) {
      Print("[Exit][WARN] Brak miejsca na nowe powiązania (32).");
      return;
   }

   // wylicz 1R i entryTime
   double oneR = 0.0; datetime et = 0;
   if (PositionSelectByTicket(ticket)) {
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl0   = PositionGetDouble(POSITION_SL);
      if (sl0 <= 0.0) {
         double atr = ATR_Value(1, Exit_ATR_Period);
         if (atr <= 0) atr = MathMax(_Point*10, candleHistory[1].high - candleHistory[1].low);
         oneR = atr;
      } else oneR = MathAbs(entry - sl0);
      et = (datetime)PositionGetInteger(POSITION_TIME);
   }

   __bindings[__bindingsCount].ticket      = ticket;
   __bindings[__bindingsCount].cfg         = cfg;
   __bindings[__bindingsCount].used        = true;
   __bindings[__bindingsCount].oneR        = (oneR>0.0?oneR:_Point*10);
   __bindings[__bindingsCount].partialDone = false;
   __bindings[__bindingsCount].entryTime   = et;
   __bindings[__bindingsCount].lastLogBar  = 0;
   __bindingsCount++;

   if (DebugExitOptimizer) PrintFormat("[Exit] Bind ticket=%I64u ok (oneR=%.5f)", ticket, oneR);
}

bool GetExitForTicket(ulong ticket, ExitConfig &out)
{
   for (int i = 0; i < __bindingsCount; ++i) {
      if (__bindings[i].used && __bindings[i].ticket == ticket) { out = __bindings[i].cfg; return true; }
   }
   return false;
}
void UnbindTicket(ulong ticket)
{
   for (int i = 0; i < __bindingsCount; ++i) {
      if (__bindings[i].used && __bindings[i].ticket == ticket) { __bindings[i].used = false; return; }
   }
}

// ====== Implementacje polityk ======
bool ApplyExit_ATR(ulong ticket, bool isLong, const ExitParamsATR &p)
{
   int shift = 1;
   double atr = ATR_Value(shift, p.atrPeriod);
   if (atr <= 0) return false;

   double refPrice = candleHistory[shift].close;
   double dist     = p.kATR * atr;
   double newSL    = isLong ? (refPrice - dist) : (refPrice + dist);

   if (PositionSelectByTicket(ticket)) {
      string sym = PositionGetString(POSITION_SYMBOL);
      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if (isLong) {
         if (curSL == 0 || newSL > curSL) {
            bool ok = __exitTrade.PositionModify(sym, newSL, tp);
            if (DebugExit_ATR) PrintFormat("[ATR] ticket=%I64u SL -> %.5f (k=%.2f, atr=%.5f)", ticket, newSL, p.kATR, atr);
            return ok;
         }
      } else {
         if (curSL == 0 || newSL < curSL) {
            bool ok = __exitTrade.PositionModify(sym, newSL, tp);
            if (DebugExit_ATR) PrintFormat("[ATR] ticket=%I64u SL -> %.5f (k=%.2f, atr=%.5f)", ticket, newSL, p.kATR, atr);
            return ok;
         }
      }
   }
   return false;
}

double HighestHigh(int fromShift, int bars)
{
   double hh = candleHistory[fromShift].high;
   for (int i = fromShift; i < fromShift + bars && i < ArraySize(candleHistory); ++i)
      if (candleHistory[i].high > hh) hh = candleHistory[i].high;
   return hh;
}
double LowestLow(int fromShift, int bars)
{
   double ll = candleHistory[fromShift].low;
   for (int i = fromShift; i < fromShift + bars && i < ArraySize(candleHistory); ++i)
      if (candleHistory[i].low < ll) ll = candleHistory[i].low;
   return ll;
}

bool ApplyExit_Swing(ulong ticket, bool isLong, const ExitParamsSW &p)
{
   int shift = 1;
   double newSL;
   if (isLong) { double ll = LowestLow(shift, p.swingN); newSL = ll - Pts(p.offsetPts); }
   else        { double hh = HighestHigh(shift, p.swingN); newSL = hh + Pts(p.offsetPts); }

   if (PositionSelectByTicket(ticket)) {
      string sym = PositionGetString(POSITION_SYMBOL);
      double curSL = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if (isLong) {
         if (curSL == 0 || newSL > curSL) {
            bool ok = __exitTrade.PositionModify(sym, newSL, tp);
            if (DebugExit_Swing) PrintFormat("[SWING] ticket=%I64u SL -> %.5f (N=%d, off=%dpts)", ticket, newSL, p.swingN, p.offsetPts);
            return ok;
         }
      } else {
         if (curSL == 0 || newSL < curSL) {
            bool ok = __exitTrade.PositionModify(sym, newSL, tp);
            if (DebugExit_Swing) PrintFormat("[SWING] ticket=%I64u SL -> %.5f (N=%d, off=%dpts)", ticket, newSL, p.swingN, p.offsetPts);
            return ok;
         }
      }
   }
   return false;
}

void LogHybridHeartbeat(ulong ticket, const ExitParamsHYB &p, double oneR, bool isLong)
{
   if (!DebugExit_Heartbeat) return;
   if (!PositionSelectByTicket(ticket)) return;

   int idx = FindBindingIndex(ticket);
   datetime barTime = candleHistory[1].time;
   if (idx >= 0 && __bindings[idx].lastLogBar == barTime) return; // już log tej świecy
   if (idx >= 0) __bindings[idx].lastLogBar = barTime;

   string sym   = PositionGetString(POSITION_SYMBOL);
   double price = PositionGetDouble(POSITION_PRICE_OPEN);
   long   type  = (long)PositionGetInteger(POSITION_TYPE);
   double sl    = PositionGetDouble(POSITION_SL);

   double close1 = candleHistory[1].close;
   double atr    = ATR_Value(1, Exit_ATR_Period);
   double trailC = isLong ? (close1 - p.trailATRk * atr) : (close1 + p.trailATRk * atr);
   double cur    = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
   double move   = (type == POSITION_TYPE_BUY) ? (cur - price) : (price - cur);
   double rNow   = (oneR>0.0 ? move/oneR : 0.0);

   PrintFormat("[HYB-HB] t=%I64u %s | bar=%s | R=%.2f | SL=%.5f | trailCand=%.5f(k=%.2f,ATR=%.5f) | BE@>=%.2fR | TP1(partial)=%.2fR frac=%.2f | Tstop=%d/<%.2fR>",
      ticket, sym, TimeToString(barTime, TIME_DATE|TIME_MINUTES), rNow, sl, trailC, p.trailATRk, atr,
      p.beAfterR, p.tp1R, p.partialFrac, p.timeStopBars, p.timeStopMinR);
}

bool ApplyExit_Hybrid(ulong ticket, bool isLong, const ExitParamsHYB &p)
{
   if (!PositionSelectByTicket(ticket)) return false;

   string sym   = PositionGetString(POSITION_SYMBOL);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   double price = PositionGetDouble(POSITION_PRICE_OPEN);
   long   type  = (long)PositionGetInteger(POSITION_TYPE);
   double vol   = PositionGetDouble(POSITION_VOLUME);

   // parametry symbolu/brokera
   int    stopsPts  = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezePts = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   int    digits    = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double minVol    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double stepVol   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double minDist = stopsPts * _Point;

   // wyznacz 1R (fallback na ATR jeśli brak SL startowego)
   double initialSL = sl;
   if (initialSL == 0.0) {
      double atr = ATR_Value(1, Exit_ATR_Period);
      if (atr <= 0) atr = candleHistory[1].high - candleHistory[1].low;
      initialSL = isLong ? (price - atr) : (price + atr);
   }
   double oneR = MathMax(1e-8, MathAbs(price - initialSL));

   // bieżące R
   double cur   = (type == POSITION_TYPE_BUY) ? bid : ask;
   double move  = (type == POSITION_TYPE_BUY) ? (cur - price) : (price - cur);
   double rNow  = (oneR > 0.0 ? move / oneR : 0.0);

   // heartbeat (opcjonalnie)
   if (DebugExit_Heartbeat) {
      double atr = ATR_Value(1, Exit_ATR_Period);
      double trailCand = isLong ? (candleHistory[1].close - p.trailATRk * atr)
                                : (candleHistory[1].close + p.trailATRk * atr);
      PrintFormat("[HYB-HB] t=%I64u %s | R=%.2f | SL=%.5f | trailCand=%.5f(k=%.2f,ATR=%.5f) | BE>=%.2fR | TP1=%.2fR frac=%.2f | Tstop=%d/<%.2fR> | stops=%d freeze=%d",
                  ticket, sym, rNow, sl, trailCand, p.trailATRk, atr,
                  p.beAfterR, p.tp1R, p.partialFrac, p.timeStopBars, p.timeStopMinR, stopsPts, freezePts);
   }

   bool changed = false;

   // ==== TIME-STOP ====
   if (p.timeStopBars > 0) {
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsElapsed = (int)MathFloor((candleHistory[1].time - entryTime) / PeriodSeconds(_Period));
      if (DebugExit_Hybrid)
         PrintFormat("[HYB] time-stop check: bars=%d/%d rNow=%.2f<%.2f ?", barsElapsed, p.timeStopBars, rNow, p.timeStopMinR);

      if (barsElapsed >= p.timeStopBars && rNow < p.timeStopMinR) {
         bool ok = __exitTrade.PositionClose(sym);
         uint rc = __exitTrade.ResultRetcode(); string rd = __exitTrade.ResultRetcodeDescription();
         if (!ok) PrintFormat("[HYB] ❌ TIME-STOP close FAIL rc=%u (%s)", rc, rd);
         else     PrintFormat("[HYB] ✅ TIME-STOP CLOSE t=%I64u @%.5f", ticket, cur);
         return ok;
      }
   }

   // ==== PARTIAL TAKE ====
   if (p.tp1R > 0.0 && p.partialFrac > 0.0 && rNow >= p.tp1R) {
      double part = MathMax(minVol, MathFloor(vol * p.partialFrac / stepVol) * stepVol);
      if (part >= minVol && part < vol) {
         if (DebugExit_Hybrid)
            PrintFormat("[HYB] try PARTIAL t=%I64u vol=%.2f part=%.2f rNow=%.2f", ticket, vol, part, rNow);
         bool pok = __exitTrade.PositionClosePartial(sym, part);
         uint rc = __exitTrade.ResultRetcode(); string rd = __exitTrade.ResultRetcodeDescription();
         if (!pok) PrintFormat("[HYB] ❌ PARTIAL FAIL rc=%u (%s)", rc, rd);
         else      { changed = true; PrintFormat("[HYB] ✅ PARTIAL DONE t=%I64u part=%.2f @%.5f", ticket, part, cur); }
      }
   }

   // ==== BREAK-EVEN ====
   if (p.beAfterR > 0.0 && rNow >= p.beAfterR) {
      double minBEoffPts = (double)MathMax(stopsPts, Exit_Swing_OffsetPts);
      double off = Pts((int)MathMax(2, (int)minBEoffPts));
      double desiredBE = isLong ? (price + off) : (price - off);

      double beClamped = desiredBE;
      if (isLong) { double maxSL = bid - minDist; beClamped = MathMin(desiredBE, maxSL); }
      else        { double minSL = ask + minDist; beClamped = MathMax(desiredBE, minSL); }
      beClamped = NormalizeDouble(beClamped, digits);

      bool improvement = (sl == 0.0) ||
                         (isLong  && beClamped > sl + tickSize) ||
                         (!isLong && beClamped < sl - tickSize);

      if (DebugExit_Hybrid)
         PrintFormat("[HYB] BE check: desired=%.5f clamped=%.5f curSL=%.5f improve=%s",
                     desiredBE, beClamped, sl, improvement ? "YES" : "NO");

      if (improvement) {
         bool ok = __exitTrade.PositionModify(sym, beClamped, tp);
         uint rc = __exitTrade.ResultRetcode(); string rd = __exitTrade.ResultRetcodeDescription();
         if (!ok) PrintFormat("[HYB] ❌ BE modify FAIL rc=%u (%s)", rc, rd);
         else {
            sl = PositionGetDouble(POSITION_SL);
            changed = true;
            PrintFormat("[HYB] ✅ BE moved -> SL=%.5f (rc=%u %s)", sl, rc, rd);
         }
      }
   }

   // ==== ATR TRAIL ====
   if (p.trailATRk > 0.0) {
      double atr = ATR_Value(1, Exit_ATR_Period);
      if (atr > 0) {
         double refClose = candleHistory[1].close;
         double desired = isLong ? (refClose - p.trailATRk * atr)
                                 : (refClose + p.trailATRk * atr);

         double cand = desired;
         if (isLong) { double maxSL = bid - minDist; cand = MathMin(desired, maxSL); }
         else        { double minSL = ask + minDist; cand = MathMax(desired, minSL); }
         cand = NormalizeDouble(cand, digits);

         bool improvement = (sl == 0.0) ||
                            (isLong  && cand > sl + tickSize) ||
                            (!isLong && cand < sl - tickSize);

         if (DebugExit_Hybrid)
            PrintFormat("[HYB] trail check: desired=%.5f clamped=%.5f curSL=%.5f improve=%s (k=%.2f ATR=%.5f)",
                        desired, cand, sl, improvement ? "YES" : "NO", p.trailATRk, atr);

         if (improvement) {
            bool ok = __exitTrade.PositionModify(sym, cand, tp);
            uint rc = __exitTrade.ResultRetcode(); string rd = __exitTrade.ResultRetcodeDescription();
            if (!ok) PrintFormat("[HYB] ❌ trail modify FAIL rc=%u (%s)", rc, rd);
            else {
               sl = PositionGetDouble(POSITION_SL);
               changed = true;
               PrintFormat("[HYB] ✅ trail SL -> %.5f (rc=%u %s)", sl, rc, rd);
            }
         }
      }
   }

   return changed;
}

// ====== Zarządzanie otwartymi pozycjami ======
void ManageOpenPositions()
{
   CPositionInfo pos;
   int total = (int)PositionsTotal();
   for (int i = total - 1; i >= 0; --i)
   {
      if (!pos.SelectByIndex(i)) continue;
      if (pos.Symbol() != _Symbol) continue;

      ulong  ticket = (ulong)pos.Ticket();
      long   type   = (long)pos.Type();
      bool   isLong = (type == POSITION_TYPE_BUY);

      ExitConfig cfg;
      if (!GetExitForTicket(ticket, cfg))
      {
         int regime = DetectRegimeKey(1);
         cfg = ChooseExitForRegime(regime);
         BindExitToTicket(ticket, cfg);
      }

      switch (cfg.policy)
      {
         case EXIT_ATR:    ApplyExit_ATR(ticket, isLong, cfg.atr);     break;
         case EXIT_SWING:  ApplyExit_Swing(ticket, isLong, cfg.sw);    break;
         case EXIT_HYBRID: ApplyExit_Hybrid(ticket, isLong, cfg.hyb);  break;
      }
   }
}

// ====== Helper: zbindowanie polityki do aktualnej pozycji ======
void BindPolicyForSymbolPosition(const string symbol)
{
   if (!PositionSelect(symbol)) {
      if (DebugExitOptimizer) PrintFormat("[Entry] Brak aktywnej pozycji na %s — nic nie bindować.", symbol);
      return;
   }

   ulong posTicket = (ulong)PositionGetInteger(POSITION_TICKET);
   int   regime    = DetectRegimeKey(1);
   ExitConfig cfg  = ChooseExitForRegime(regime);
   BindExitToTicket(posTicket, cfg);

   if (DebugExitOptimizer)
      PrintFormat("[Entry] ticket=%I64u regime=%d policy=%d", posTicket, regime, (int)cfg.policy);
}

#endif // __EXIT_ENGINE_MQH__
