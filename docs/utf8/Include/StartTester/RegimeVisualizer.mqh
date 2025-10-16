//+------------------------------------------------------------------+
//|                         RegimeVisualizer.mqh                     |
//| Prosty overlay: etykieta UP/DOWN/FLAT i LOW/NORMAL/HIGH          |
//| Kolor bazuje na trendzie, odcień na zmienności                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __REGIME_VISUALIZER_MQH__
#define __REGIME_VISUALIZER_MQH__

#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/ExitEngine.mqh>      // DetectRegimeKey()

// --------- KONFIG WEWNĘTRZNY (bez nowych inputów) ----------------
#define RV_PREFIX      "RV"
#define RV_MAX_BARS    240     // ile ostatnich świec rysować
#define RV_FONT_SIZE   8
#define RV_PAD_PIPS    15      // odległość etykiety od świecy (w pipsach)

// Kolory wg trendu i zmienności
// Trend UP
#define RV_UP_LOW      clrLime
#define RV_UP_NORMAL   clrGreen
#define RV_UP_HIGH     clrDarkGreen
// Trend DOWN
#define RV_DN_LOW      clrTomato
#define RV_DN_NORMAL   clrRed
#define RV_DN_HIGH     clrMaroon
// Trend FLAT
#define RV_FL_LOW      clrSilver
#define RV_FL_NORMAL   clrGray
#define RV_FL_HIGH     clrDimGray

// --------- HELPERS -----------------------------------------------
string RV_ObjTxtName(datetime t)
{
   // unikalnie: symbol + TF + czas
   return StringFormat("%s_TXT_%s_%d_%I64d", RV_PREFIX, _Symbol, (int)_Period, (long)t);
}

color RV_ColorForRegime(int regime)
{
   int t = regime / 3; // 0=DOWN,1=FLAT,2=UP
   int v = regime % 3; // 0=LOW,1=NORMAL,2=HIGH
   if (t == 2) { // UP
      if (v == 0) return RV_UP_LOW;
      if (v == 1) return RV_UP_NORMAL;
      return RV_UP_HIGH;
   } else if (t == 0) { // DOWN
      if (v == 0) return RV_DN_LOW;
      if (v == 1) return RV_DN_NORMAL;
      return RV_DN_HIGH;
   } else { // FLAT
      if (v == 0) return RV_FL_LOW;
      if (v == 1) return RV_FL_NORMAL;
      return RV_FL_HIGH;
   }
}

string RV_KeyToString(int regime)
{
   int t = regime / 3;
   int v = regime % 3;
   string ts = (t==2?"UP":(t==0?"DOWN":"FLAT"));
   string vs = (v==2?"HIGH":(v==0?"LOW":"NORMAL"));
   return ts + "|" + vs;
}

// --------- API: usuń wszystkie obiekty wizualizera ----------------
void RegimeViz_Clear()
{
   const int total = ObjectsTotal(0, 0, -1);
   for (int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, RV_PREFIX + "_") == 0)
         ObjectDelete(0, name);
   }
}

// --------- API: narysuj overlay dla ostatnich N świec -------------
void RegimeViz_DrawOverlay(int lookbackBars = RV_MAX_BARS, bool showText = true)
{
   int total = ArraySize(candleHistory);
   if (total < 2) return;

   int tfSec = PeriodSeconds(_Period);
   if (tfSec <= 0) tfSec = 60;

   // pips → w punktach instrumentu
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip   = point * 10.0;           // w wielu brokerach 1 pip = 10 punktów (5-cyfrowe kwotowania)
   double pad   = RV_PAD_PIPS * pip;      // odstęp etykiety od świecy

   int from = MathMax(1, total - 1 - lookbackBars);
   for (int i = from; i >= 1; --i) // od starszych do nowszych
   {
      datetime t1 = candleHistory[i].time;
      datetime tMid = (datetime)(t1 + tfSec/2);
      double hi = candleHistory[i].high;
      double lo = candleHistory[i].low;

      int regime = DetectRegimeKey(i);
      color c    = RV_ColorForRegime(regime);

      if (showText)
      {
         string name = RV_ObjTxtName(t1);
         double y = hi + pad;   // nad świecą; gdyby wychodziło poza widok – przybliż wykres

         if (ObjectFind(0, name) < 0)
         {
            ObjectCreate(0, name, OBJ_TEXT, 0, tMid, y);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, false);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, RV_FONT_SIZE);
         }
         else
         {
            ObjectMove(0, name, 0, tMid, y);
         }

         ObjectSetString(0,  name, OBJPROP_TEXT, RV_KeyToString(regime));
         ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      }
   }
}

#endif // __REGIME_VISUALIZER_MQH__
