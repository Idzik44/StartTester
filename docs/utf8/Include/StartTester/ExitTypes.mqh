//+------------------------------------------------------------------+
//| ExitTypes.mqh — lekkie typy wspólne                              |
//+------------------------------------------------------------------+
#ifndef __EXIT_TYPES_MQH__
#define __EXIT_TYPES_MQH__

#property strict


// Używany w ExitPolicy/ExitOptimizer/ExitManager/PatternBacktest
enum TrailMethod
{
   TRAIL_NONE = 0,
   TRAIL_ATR  = 1,
   TRAIL_STEP = 2,
   TRAIL_CANDLE = 3
};

#endif // __EXIT_TYPES_MQH__

