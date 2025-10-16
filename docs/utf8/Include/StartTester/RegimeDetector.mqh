#ifndef __REGIME_DETECTOR_MQH__
#define __REGIME_DETECTOR_MQH__

#property strict


#include <StartTester/CandleAndTranactionData11.mqh>

enum MarketRegime { REG_TREND_STRONG, REG_TREND_WEAK, REG_CHOP, REG_VOL_SPIKE };

struct RegimeFeatures {
   double adx, plusDI, minusDI, diffDI;
   double atr14, atr50, atrRatio;
   bool   bullish;
};

static int  RD_ATR_FAST = 14;
static int  RD_ATR_SLOW = 50;

// prosta ATR (średnia TR)
double RD_ATR(int period, int fromIndex=1)
{
   int total = ArraySize(candleHistory);
   if(total < fromIndex + period + 2) return 0.0;
   double sum=0.0;
   for(int i=fromIndex; i<fromIndex+period; ++i)
   {
      double h=candleHistory[i].high, l=candleHistory[i].low, pc=candleHistory[i+1].close;
      double tr1=h-l, tr2=MathAbs(h-pc), tr3=MathAbs(l-pc);
      sum += MathMax(tr1, MathMax(tr2,tr3));
   }
   return sum/period;
}

void GetRegimeFeatures(int index, RegimeFeatures &f)
{
   f.adx     = GetCustomADXAt(index);
   f.plusDI  = GetCustomPlusDIAt(index);
   f.minusDI = GetCustomMinusDIAt(index);
   f.diffDI  = MathAbs(f.plusDI - f.minusDI);
   f.atr14   = RD_ATR(RD_ATR_FAST, index);
   f.atr50   = RD_ATR(RD_ATR_SLOW, index);
   f.atrRatio= (f.atr50>0 ? f.atr14/f.atr50 : 0.0);
   f.bullish = (candleHistory[index].close > candleHistory[index].open);
}

MarketRegime ClassifyRegime(const RegimeFeatures &f)
{
   // progi z histerezą możesz później doprecyzować
   bool volSpike = (f.atrRatio >= 1.5);
   if(volSpike) return REG_VOL_SPIKE;

   if(f.adx >= 25 && f.diffDI >= 15) return REG_TREND_STRONG;
   if(f.adx >= 15)                    return REG_TREND_WEAK;
   return REG_CHOP;
}

#endif
