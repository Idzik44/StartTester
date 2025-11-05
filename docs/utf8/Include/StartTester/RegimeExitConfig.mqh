//+------------------------------------------------------------------+
//| RegimeExitConfig.mqh                                             |
//| Mapowanie inputów CSV → parametry SL/TP per reżim                |
//+------------------------------------------------------------------+
#property strict
#ifndef __REGIME_EXIT_CONFIG_MQH__
#define __REGIME_EXIT_CONFIG_MQH__

#include <StartTester/Zmienne11.mqh>

// Parser CSV → double z bezpiecznym fallbackiem
double _CsvGetDouble(const string csv, const int idx, const double defv)
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if (n <= 0 || idx < 0 || idx >= n) return defv;

   string s = parts[idx];
   StringTrimLeft(s);
   StringTrimRight(s);
   if (StringLen(s) == 0) return defv;

   return (double)StringToDouble(s);
}

// Parser CSV → int (oparty o _CsvGetDouble)
int _CsvGetInt(const string csv, const int idx, const int defv)
{
   double v = _CsvGetDouble(csv, idx, (double)defv);
   return (int)MathFloor(v + 1e-8);
}

/*
  GetRegimeExitConfig:
  Zwraca metodę SL i parametry per reżim z inputów CSV.
  useSLMethod: 0..3; slMultiplier: dla metody 1; slPoints: dla 2/3; tpMultiplier: dla wszystkich
*/
void GetRegimeExitConfig(const int regimeIdx,
                         int   &useSLMethod,
                         double &slMultiplier,
                         double &slPoints,
                         double &tpMultiplier)
{
   // Domyślne, gdy CSV krótsze/błędny indeks
   useSLMethod  = 1;
   slMultiplier = 0.5;
   slPoints     = 50.0;
   tpMultiplier = 1.5;

   if (regimeIdx < 0) return;

   useSLMethod  = _CsvGetInt(   Exit_Method_ByRegime_CSV,   regimeIdx, useSLMethod);
   slMultiplier = _CsvGetDouble(Exit_SLMult_ByRegime_CSV,   regimeIdx, slMultiplier);
   slPoints     = _CsvGetDouble(Exit_SLPoints_ByRegime_CSV, regimeIdx, slPoints);
   tpMultiplier = _CsvGetDouble(Exit_TPMult_ByRegime_CSV,   regimeIdx, tpMultiplier);

   // Porządkuj zakresy
   if (useSLMethod < 0) useSLMethod = 0;
   if (useSLMethod > 3) useSLMethod = 3;
   if (slMultiplier < 0) slMultiplier = 0;
   if (slPoints < 0)     slPoints = 0;
   if (tpMultiplier <= 0) tpMultiplier = 1.0;
}

#endif // __REGIME_EXIT_CONFIG_MQH__
