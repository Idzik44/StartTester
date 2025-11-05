//+------------------------------------------------------------------+
//| RegimeExitTypes.mqh – lekkie typy do symulacji exitów            |
//+------------------------------------------------------------------+
#property strict
#ifndef __REGIME_EXIT_TYPES_MQH__
#define __REGIME_EXIT_TYPES_MQH__

// Polityka – wyłącznie do symulacji (BT)
enum ExitPolicy { EXIT_ATR = 0, EXIT_SWING = 1, EXIT_HYBRID = 2 };

// Minimalne parametry do symulacji
struct ExitParamsATR { double kATR; int atrPeriod;    ExitParamsATR():kATR(0.0),atrPeriod(0){} };
struct ExitParamsSW  { int swingN; int offsetPts;     ExitParamsSW():swingN(0),offsetPts(0){} };
struct ExitParamsHYB {
   double tp1R, beAfterR, trailATRk;
   int    timeStopBars;  double timeStopMinR;
   double partialFrac;
   ExitParamsHYB():tp1R(0),beAfterR(0),trailATRk(0),timeStopBars(0),timeStopMinR(0),partialFrac(0){}
};

#endif
