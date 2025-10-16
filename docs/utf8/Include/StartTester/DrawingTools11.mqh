//+------------------------------------------------------------------+
//| DrawingTools.mqh                                                 |
//| Funkcje rysujące (opisy świec, prostokąty, linie S/R)            |
//+------------------------------------------------------------------+
#property strict


#ifndef __DRAWINGTOOLS_MQH__
#define __DRAWINGTOOLS_MQH__

#include <StartTester/Zmienne11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>
#include <StartTester/PeaksEnded11.mqh>

string objName = " "; // nazwa prostokąta


// --- Struktura poziomów wsparcia i oporu
struct SupportResistanceLevel {
   double price;
   int type; // LEVEL_SUPPORT lub LEVEL_RESISTANCE
   datetime time;
   bool isConfirmed;

   // Konstruktor domyślny
   SupportResistanceLevel() {
      price = 0.0;
      type = 0;
      time = 0;
      isConfirmed = false;
   }

   // Konstruktor kopiujący
   SupportResistanceLevel(const SupportResistanceLevel &src) {
      price = src.price;
      type = src.type;
      time = src.time;
      isConfirmed = src.isConfirmed;
   }
};


#define LEVEL_SUPPORT 0
#define LEVEL_RESISTANCE 1

SupportResistanceLevel SupportResistanceLevels[];



// Rysowanie rozmiaru świecy względem średniej wysokości
void DrawCandleSizeLabel(datetime time, double openPrice, double closePrice, double highPrice, double lowPrice, double avgcandleHeight, bool drawEnabled)
{
   if (!drawEnabled || avgcandleHeight <= 0)
      return;

   double candleHeight = highPrice - lowPrice;
   int percentOfAvg = int((candleHeight / avgcandleHeight) * 100);

   // Pozycja tekstu (pod/nad świecą)
   double positionPrice;
   if (closePrice > openPrice) // Świeca wzrostowa
      positionPrice = lowPrice - candleHeight * 1; // Pod świecą
   else
      positionPrice = highPrice + candleHeight * 1; // Nad świecą

   // Unikalna nazwa obiektu
   string objectName = "NumberOnCandle_" + IntegerToString(time);

   // Tworzenie obiektu tekstowego
   if (!ObjectCreate(0, objectName, OBJ_TEXT, 0, time, positionPrice))
   {
 //     Print("Nie udało się stworzyć obiektu tekstowego!");
      return;
   }

   // Ustawienia obiektu
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 6);
   ObjectSetString(0, objectName, OBJPROP_TEXT, IntegerToString(percentOfAvg));
}

// Rysowanie Prostokąta



// Funkcja pomocnicza do tworzenia prostokąta
void CreateRectangle(string local_objName, datetime local_sequenceStartTime, datetime local_sequenceEndTime, double local_minLow, double local_maxHigh)
{
    bool created = ObjectCreate(0, local_objName, OBJ_RECTANGLE, 0, local_sequenceStartTime, local_minLow, local_sequenceEndTime, local_maxHigh);

    if (created)
    {
        ObjectSetInteger(0, local_objName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, local_objName, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, local_objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, local_objName, OBJPROP_BACK, false);
//        Print("Prostokąt utworzony: ", local_objName);
    }
    else
    {
//        Print("Błąd podczas tworzenia prostokąta: ", local_objName);
    }
}
void UpdateRectangle(string local_objName, datetime local_sequenceStartTime, datetime local_sequenceEndTime, double local_minLow, double local_maxHigh)
{
    // Usuwamy istniejący prostokąt, jeśli istnieje
    if (ObjectFind(0, objName) != -1)
    {
        if (ObjectDelete(0, objName))
        {
//            Print("Prostokąt ", objName, " został usunięty.");
        }
        else
        {
//            Print("Nie udało się usunąć prostokąta ", objName, ".");
            return;
        }
    }

    // Tworzymy nowy prostokąt z aktualnymi parametrami
    bool created = ObjectCreate(0, objName, OBJ_RECTANGLE, 0, sequenceStartTime, minLow, sequenceEndTime, maxHigh);

    if (created)
    {
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
//        Print("Prostokąt ", objName, " został ponownie narysowany.");
    }
    else
    {
//        Print("Błąd podczas tworzenia prostokąta ", objName, ".");
    }
}


// Funkcja do rysowania linii wsparcia i oporu i zapisywania ich do struktury
void DrawPeaksAndLows() {
    if (!inputSRLineDrav)
        return;

    // Wyczyść istniejące poziomy
    ArrayFree(SupportResistanceLevels);
    int levelIndex = 0;

    int startFromHigh = Highs[1].index > Lows[1].index ? 1 : 2;
    int startFromLow = Lows[1].index > Highs[1].index ? 1 : 2;
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Rysuj poziomy oporu
    for (int i = startFromHigh; i < 9; i++) {
        if (!Highs[i].isValid) continue;

        string highLineName = "ResistanceLine" + IntegerToString(i);
        double highPrice = Highs[i].value;
        datetime time1 = Highs[i].time;

        ObjectCreate(0, highLineName, OBJ_TREND, 0, time1, highPrice, currentTime, highPrice);
        ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 1);

        // Zapisz poziom oporu do struktury
        ArrayResize(SupportResistanceLevels, levelIndex + 1);
        SupportResistanceLevels[levelIndex].price = highPrice;
        SupportResistanceLevels[levelIndex].type = LEVEL_RESISTANCE;
        SupportResistanceLevels[levelIndex].time = time1;
        levelIndex++;
    }

    // Rysuj poziomy wsparcia
    for (int i = startFromLow; i < 9; i++) {
        if (!Lows[i].isValid) continue;

        string lowLineName = "SupportLine" + IntegerToString(i);
        double lowPrice = Lows[i].value;
        datetime time1 = Lows[i].time;

        ObjectCreate(0, lowLineName, OBJ_TREND, 0, time1, lowPrice, currentTime, lowPrice);
        ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrBlue);
        ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 1);

        // Zapisz poziom wsparcia do struktury
        ArrayResize(SupportResistanceLevels, levelIndex + 1);
        SupportResistanceLevels[levelIndex].price = lowPrice;
        SupportResistanceLevels[levelIndex].type = LEVEL_SUPPORT;
        SupportResistanceLevels[levelIndex].time = time1;
        levelIndex++;
    }
}

void ManageRectangle(
    bool RectangleDrav,
    int ccurrentCandleCount,
    int DefinedCandleCount,
    string oobjName,
    datetime ssequenceStartTime,
    datetime ssequenceEndTime,
    double mminLow,
    double mmaxHigh)
{
    // Tworzymy lub aktualizujemy prostokąt, jeśli warunki są spełnione
    if (inputRectangleDrav)
    {
        if (currentCandleCount == userDefinedCandleCount && objName != " ")
        {
            // Print("Tworzenie prostokąta: StartTime=", sequenceStartTime, ", EndTime=", sequenceEndTime, ", MinLow=", minLow, ", MaxHigh=", maxHigh);
            CreateRectangle(objName, sequenceStartTime, sequenceEndTime, minLow, maxHigh);
        }
        else if (currentCandleCount == userDefinedCandleCount && objName == " ")
        {
            // Print("Błąd: objName jest pusty. Prostokąt nie może zostać utworzony.");
        }
        // Aktualizacja Prostokąta
        if (currentCandleCount > userDefinedCandleCount && objName != " ")
        {
            UpdateRectangle(objName, sequenceStartTime, sequenceEndTime, minLow, maxHigh);
        }
    }
}
//+----------------------------------------------------------------+
//                     RYSOWANIE MA                                |
//+----------------------------------------------------------------+

void DrawDirectionArrow(datetime time, double price, int direction, color clr) {
   string name = "Arrow_" + IntegerToString((int)time) + "_" + IntegerToString(direction);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);

   int arrowCode = 234; // default: right arrow
   if (direction == 1) arrowCode = 233; // up
   else if (direction == 2) arrowCode = 234; // down

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DrawVWAPChannelPoint(datetime time, double price, color clr = clrGray) {
   string name = "VWAP_CH_" + IntegerToString((int)time) + "_" + DoubleToString(price, 5);
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 158); // małe kółko
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

#endif
