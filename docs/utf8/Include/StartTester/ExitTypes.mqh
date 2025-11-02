//+------------------------------------------------------------------+
//| ExitTypes.mqh — lekkie typy wspólne                              |
//+------------------------------------------------------------------+
#ifndef __EXIT_TYPES_MQH__
#define __EXIT_TYPES_MQH__

#property strict


// ---------------------------------------------------------------------
// Opis: Enum TrailMethod — typ wyliczeniowy określający metodę trailing
//       stopu używaną w modułach wyjścia (ExitPolicy/ExitOptimizer/
//       ExitManager/PatternBacktest).
// Wywołuje: (brak; to tylko definicja typu).
// Używa globalnych: (brak).
// Uwaga: Wartości są wykorzystywane jako przełączniki logiki w innych
//        plikach (np. TRAIL_ATR → trailing po ATR, TRAIL_STEP → schodkowy,
//        TRAIL_CANDLE → za poprzednią świecą). Nie zmieniaj kolejności
//        i wartości bez aktualizacji kodu korzystającego z enum.
// ---------------------------------------------------------------------
enum TrailMethod
{
   TRAIL_NONE = 0,
   TRAIL_ATR  = 1,
   TRAIL_STEP = 2,
   TRAIL_CANDLE = 3
};

#endif // __EXIT_TYPES_MQH__
