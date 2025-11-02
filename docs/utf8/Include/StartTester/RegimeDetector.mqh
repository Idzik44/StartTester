#ifndef __REGIME_DETECTOR_MQH__
#define __REGIME_DETECTOR_MQH__

#property strict

#include <StartTester/CandleAndTranactionData11.mqh>

// ─────────────────────────────────────────────────────────────
// Enum: MarketRegime
// Opis: Klasy „reżimu” rynku używane przez klasyfikator.
// Zależności: brak bezpośrednich.
// Globalne: brak.
// ─────────────────────────────────────────────────────────────
enum MarketRegime { REG_TREND_STRONG, REG_TREND_WEAK, REG_CHOP, REG_VOL_SPIKE };

// ─────────────────────────────────────────────────────────────
// Struktura: RegimeFeatures
// Opis: Wejściowy zestaw cech do klasyfikacji reżimu.
// Zależności: wypełniana w GetRegimeFeatures().
// Globalne: pośrednio korzysta z candleHistory i funkcji ADX/DI.
// ─────────────────────────────────────────────────────────────
struct RegimeFeatures {
   double adx, plusDI, minusDI, diffDI;
   double atr14, atr50, atrRatio;
   bool   bullish;
};

// ─────────────────────────────────────────────────────────────
// Ustawienia (stałe robocze ATR) dla ekstrakcji cech
// Globalne: RD_ATR_FAST, RD_ATR_SLOW używane w GetRegimeFeatures().
// ─────────────────────────────────────────────────────────────
static int  RD_ATR_FAST = 14;
static int  RD_ATR_SLOW = 50;

// ─────────────────────────────────────────────────────────────
// Funkcja: RD_ATR
// Opis:    Prosta ATR (średnia z True Range) dla zadanego okresu,
//          liczona od indeksu fromIndex w dół po historii (TR bazuje
//          na aktualnym high/low i close poprzedniej świecy).
// Wywołuje: ArraySize(), MathAbs(), MathMax().
// Używa globalnych: candleHistory[] (z CandleAndTranactionData11.mqh).
// Wejście: period (okres ATR), fromIndex (indeks startowy w candleHistory).
// Wyjście: ATR jako double; 0.0 gdy brak wystarczających danych.
// Uwagi:   Wymaga, aby istniał dostęp do i+1 (poprzednia świeca).
// ─────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────
// Funkcja: GetRegimeFeatures
// Opis:    Zbiera cechy rynkowe na danym indeksie: ADX, +DI, -DI, diffDI,
//          ATR(14), ATR(50), ich stosunek oraz prostą flagę „bullish”.
// Wywołuje: GetCustomADXAt(index), GetCustomPlusDIAt(index),
//           GetCustomMinusDIAt(index) [zewnętrzne]; RD_ATR(); MathAbs().
// Używa globalnych: candleHistory[], RD_ATR_FAST, RD_ATR_SLOW.
// Wejście: index (shift w historii), referencja na RegimeFeatures do wypełnienia.
// Wyjście: wypełniona struktura RegimeFeatures (przez referencję).
// Uwagi:   Zakłada, że wskaźniki ADX/DI są wcześniej policzone (np. ComputeCustomADX()).
// ─────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────
// Funkcja: ClassifyRegime
// Thematyka: Klasyfikacja rynku na podstawie cech.
// Opis:    Proste progi: najpierw wykrywa „VOL_SPIKE” po atrRatio,
//          potem rozróżnia TREND_STRONG/TREND_WEAK po ADX i diffDI,
//          w przeciwnym razie CHOP.
// Wywołuje: brak (czysta logika warunków).
// Używa globalnych: brak (tylko dane z RegimeFeatures).
// Wejście: RegimeFeatures (wypełnione wcześniej GetRegimeFeatures).
// Wyjście: MarketRegime (enum).
// Uwagi:   Progi można kalibrować centralnie — tutaj stałe wartości liczbowe.
// ─────────────────────────────────────────────────────────────
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
