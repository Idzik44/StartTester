#ifndef __REGIME_DETECTOR_MQH__
#define __REGIME_DETECTOR_MQH__

#property strict

#include <StartTester/CandleAndTranactionData11.mqh>   // candleHistory[], ComputeCustomADX(), GetCustom*DI/ADX()
#include <StartTester/RangeAndVolumeAnalyzer11.mqh>    // GetStandardizedRange(), GetStandardizedVolume()

// ─────────────────────────────────────────────────────────────
// Enum: MarketRegime – klasy "miękkie" (opcjonalne, diagnostyka)
// ─────────────────────────────────────────────────────────────
enum MarketRegime { REG_TREND_STRONG, REG_TREND_WEAK, REG_CHOP, REG_VOL_SPIKE };

// ─────────────────────────────────────────────────────────────
// Struktura: RegimeFeatures – cechy wejściowe klasyfikatora
// ─────────────────────────────────────────────────────────────
struct RegimeFeatures {
   double adx, plusDI, minusDI, diffDI;
   double atr14, atr50, atrRatio;
   bool   bullish;
};

// ─────────────────────────────────────────────────────────────
// Ustawienia ATR do ekstrakcji cech
// ─────────────────────────────────────────────────────────────
static int  RD_ATR_FAST = 14;
static int  RD_ATR_SLOW = 50;

// ─────────────────────────────────────────────────────────────
// Progi (można nadpisać wcześniej #define)
// ─────────────────────────────────────────────────────────────
#ifndef REG_Z_LOW
  #define REG_Z_LOW       0.80   // granica LOW→NORMAL dla |Z|
#endif
#ifndef REG_Z_HIGH
  #define REG_Z_HIGH      1.60   // granica NORMAL→HIGH dla |Z|
#endif
#ifndef REG_ADX_TREND
  #define REG_ADX_TREND   18     // min ADX, aby odróżnić trend od FLAT
#endif
#ifndef REG_DI_DIFF_FLAT
  #define REG_DI_DIFF_FLAT 6     // min |+DI − −DI|, aby nie uznać za FLAT
#endif

// ─────────────────────────────────────────────────────────────
// RD_ATR: prosta ATR (True Range) na seriach (ArraySetAsSeries=true)
// ─────────────────────────────────────────────────────────────
double RD_ATR(int period, int fromIndex=1)
{
   const int total = ArraySize(candleHistory);
   if (period <= 0) return 0.0;
   // Potrzebujemy i = fromIndex .. fromIndex+period-1 oraz dostęp do i+1
   if (total <= fromIndex + period) return 0.0;

   double sum = 0.0;
   for (int i = fromIndex; i < fromIndex + period; ++i)
   {
      const double h  = candleHistory[i].high;
      const double l  = candleHistory[i].low;
      const double pc = candleHistory[i+1].close;
      const double tr1 = h - l;
      const double tr2 = MathAbs(h - pc);
      const double tr3 = MathAbs(l - pc);
      sum += MathMax(tr1, MathMax(tr2, tr3));
   }
   return sum / period;
}

// ─────────────────────────────────────────────────────────────
// GetRegimeFeatures: zbiera cechy na barze index
// ─────────────────────────────────────────────────────────────
void GetRegimeFeatures(int index, RegimeFeatures &f)
{
   // Jeśli ADX/DI niepoliczone – policz
   if (GetCustomADXAt(index) < 0) ComputeCustomADX(14);

   f.adx     = GetCustomADXAt(index);
   f.plusDI  = GetCustomPlusDIAt(index);
   f.minusDI = GetCustomMinusDIAt(index);
   f.diffDI  = MathAbs(f.plusDI - f.minusDI);
   f.atr14   = RD_ATR(RD_ATR_FAST, index);
   f.atr50   = RD_ATR(RD_ATR_SLOW, index);
   f.atrRatio= (f.atr50 > 0.0 ? f.atr14 / f.atr50 : 0.0);
   f.bullish = (candleHistory[index].close > candleHistory[index].open);
}

// ─────────────────────────────────────────────────────────────
// ClassifyRegime: prosta klasyfikacja diagnostyczna
// ─────────────────────────────────────────────────────────────
MarketRegime ClassifyRegime(const RegimeFeatures &f)
{
   if (f.atrRatio >= 1.5)           return REG_VOL_SPIKE;
   if (f.adx >= 25 && f.diffDI >= 15) return REG_TREND_STRONG;
   if (f.adx >= 15)                 return REG_TREND_WEAK;
   return REG_CHOP;
}

// ─────────────────────────────────────────────────────────────
// Pomocnicze: kubełek zmienności na bazie |Z| (0=LOW,1=NORM,2=HIGH)
// ─────────────────────────────────────────────────────────────
int __Reg_BucketZ(const double zAbs)
{
   if (zAbs >= REG_Z_HIGH) return 2;
   if (zAbs >= REG_Z_LOW)  return 1;
   return 0;
}

// ─────────────────────────────────────────────────────────────
// DetectRegimeKey(i): zwraca 0..8 = trendComp*3 + volBucket
// trendComp: 0=DOWN, 1=FLAT, 2=UP
// volBucket: 0=LOW, 1=NORMAL, 2=HIGH
// Bez zależności od ExitEngine.
// ─────────────────────────────────────────────────────────────
int DetectRegimeKey(const int i)
{
   const int total = ArraySize(candleHistory);
   if (i < 1 || i >= total) return 4; // FLAT|NORMAL jako bezpieczny default

   // Zapewnij ADX/DI
   if (GetCustomADXAt(i) < 0) ComputeCustomADX(14);

   const double adx = GetCustomADXAt(i);
   const double pdi = GetCustomPlusDIAt(i);
   const double mdi = GetCustomMinusDIAt(i);
   const double diDiff = MathAbs(pdi - mdi);

   // Volatility bucket na bazie Z-score (range/volume)
   double zr = GetStandardizedRange(i);
   double zv = GetStandardizedVolume(i);
   if (!MathIsValidNumber(zr)) zr = 0.0;
   if (!MathIsValidNumber(zv)) zv = 0.0;
   const int vBucket = MathMax(__Reg_BucketZ(MathAbs(zr)),
                               __Reg_BucketZ(MathAbs(zv)));

   // Trend component
   int tComp = 1; // FLAT
   if (adx >= REG_ADX_TREND && diDiff >= REG_DI_DIFF_FLAT)
      tComp = (pdi >= mdi) ? 2 : 0; // UP / DOWN

   return tComp * 3 + vBucket; // 0..8
}

#endif // __REGIME_DETECTOR_MQH__
