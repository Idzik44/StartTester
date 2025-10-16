//+------------------------------------------------------------------+
//|                                            ClusterDetector11.mqh |
//|                                             Copyright 2025, Kuba |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict

#ifndef __CLUSTER_DETECTOR_MQH__
#define __CLUSTER_DETECTOR_MQH__

#include <StartTester/CandleAndTranactionData11.mqh>
#include <StartTester/AvarageCandleAndVolume11.mqh>

//+------------------------------------------------------------------+
//| Struktura klastra                                                |
//+------------------------------------------------------------------+
struct CandleCluster {
   int startIndex;
   int endIndex;
   double maxHigh;
   double minLow;
   datetime startTime;
   datetime endTime;
};

//+------------------------------------------------------------------+
//| Klasa ClusterDetector                                            |
//+------------------------------------------------------------------+
class ClusterDetector {
private:
   int minClusterLength;
   int maxClusterLength;
   double maxCandleRangeFactor;
   double maxClusterATRFactor;

   // Zmienna do wykrywania tylko raz na żywo
   bool liveClusterActive;
   int liveClusterStart;
   int liveClusterEnd;
   double liveClusterHigh;
   double liveClusterLow;
   int liveClusterCount;
   datetime liveClusterStartTime;

   // Nowe: ustawienia filtrów
   bool useATRFilter;
   bool useVolumeFilter;
   bool useStdDevFilter;

public:
   ClusterDetector(int minLen = 5, int maxLen = 12, double candleFactor = 0.8, double atrFactor = 3) {
      minClusterLength = minLen;
      maxClusterLength = maxLen;
      maxCandleRangeFactor = candleFactor;
      maxClusterATRFactor = atrFactor;

      liveClusterActive = false;
      liveClusterStart = -1;
      liveClusterEnd = -1;
      liveClusterHigh = 0.0;
      liveClusterLow = 0.0;
      liveClusterCount = 0;


   }

   // Setter'y dla filtrów
   void EnableATRFilter(bool enable) {
      useATRFilter = enable;
   }

   void EnableVolumeFilter(bool enable) {
      useVolumeFilter = enable;
   }

   void EnableStdDevFilter(bool enable) {
      useStdDevFilter = enable;
   }

   // Szukanie klastrów historycznie, tylko raz
   void DetectAndDrawHistoricalClusters() {
      int maxLookback = 100;
      int start = 1;  // omijamy świecę 0 (jeszcze niezakończona)
      int end = MathMin(ArraySize(candleHistory) - 1, maxLookback);

      for (int i = start; i <= end - minClusterLength; i++) {
         CandleCluster cluster;
         if (DetectCluster(i, cluster)) {
            DrawClusterBox(cluster, ColorToARGB(clrDarkSlateBlue, 100));
            Print("[DEBUG] Klaster wykryty od ", TimeToString(cluster.startTime), " do ", TimeToString(cluster.endTime));
            i = cluster.endIndex + 1;
         }
      }
   }

   void DetectLiveCluster() {
      if (ArraySize(candleHistory) < 20)
         return;

      double avgRange1 = CalculateAverageCandleHeight(100);
      double maxCandleRange = avgRange1 * maxCandleRangeFactor;
      double currentRange = candleHistory[1].high - candleHistory[1].low;

      if (currentRange <= maxCandleRange) {
         if (liveClusterCount == 0) {
            liveClusterStart = 1;
            liveClusterHigh = candleHistory[1].high;
            liveClusterLow = candleHistory[1].low;
            liveClusterStartTime = candleHistory[1].time;
            Print("[DEBUG] Rozpoczęcie nowego potencjalnego klastra.");
         } else {
            liveClusterHigh = MathMax(liveClusterHigh, candleHistory[1].high);
            liveClusterLow = MathMin(liveClusterLow, candleHistory[1].low);
         }

         liveClusterCount++;
         Print("[DEBUG] Świeca 1 spełnia warunek klastra. Licznik: ", liveClusterCount);
      } else {
         if (liveClusterCount >= minClusterLength) {
            double clusterRange = liveClusterHigh - liveClusterLow;

            bool atrOk = true;
            if (useATRFilter) {
               double atr = CalculateATR(14, 1);
               if (atr == 0.0 || clusterRange > atr * maxClusterATRFactor)
                  atrOk = false;
            }

            bool volumeOk = true;
            if (useVolumeFilter) {
               double avgVolume1 = CalculateAverageVolume(100);
               double currentVolume = (double)candleHistory[1].tick_volume;
               if (currentVolume > avgVolume1)
                  volumeOk = false;
            }

            bool stdDevOk = true;
            if (useStdDevFilter) {
               double stddev = CalculateStdDev(20, 1);
               if (stddev < clusterRange)
                  stdDevOk = false;
            }

            if (atrOk && volumeOk && stdDevOk) {
               CandleCluster cluster;
               cluster.startIndex = liveClusterStart;
               cluster.endIndex = 1;
               cluster.maxHigh = liveClusterHigh;
               cluster.minLow = liveClusterLow;
               cluster.startTime = liveClusterStartTime;
               cluster.endTime = candleHistory[1].time;

               DrawClusterBox(cluster, ColorToARGB(clrDarkCyan, 120));
               Print("[DEBUG] Klaster wykryty i narysowany od ", TimeToString(cluster.startTime),
                     " do ", TimeToString(cluster.endTime), ". Świece: ", liveClusterCount);
            } else {
               Print("[DEBUG] Klaster odrzucony przez filtr(y). ATR: ", atrOk, ", Volume: ", volumeOk, ", StdDev: ", stdDevOk);
            }
         } else if (liveClusterCount > 0) {
            Print("[DEBUG] Reset. Zbyt mało świec w klastrze: ", liveClusterCount);
         }

         liveClusterCount = 0;
         liveClusterHigh = 0.0;
         liveClusterLow = 0.0;
         liveClusterStart = -1;
         liveClusterStartTime = 0;
      }
   }

   bool DetectCluster(int startIndex, CandleCluster &clusterOut) {
      double avgRange1 = CalculateAverageCandleHeight(10);
      double maxCandleRange = avgRange1 * maxCandleRangeFactor;

      int count = 0;
      int i = startIndex;
      int endIndex = -1;
      double clusterHigh = 0.0;
      double clusterLow = 0.0;

      for (; i < ArraySize(candleHistory) - 1 && count < maxClusterLength; i++) {
         double range = candleHistory[i].high - candleHistory[i].low;
         if (range <= maxCandleRange) {
            if (count == 0) {
               clusterHigh = candleHistory[i].high;
               clusterLow = candleHistory[i].low;
            } else {
               clusterHigh = MathMax(clusterHigh, candleHistory[i].high);
               clusterLow = MathMin(clusterLow, candleHistory[i].low);
            }
            count++;
            endIndex = i;
         } else {
            break;
         }
      }

      if (count >= minClusterLength) {
         double clusterRange = clusterHigh - clusterLow;

         if (useATRFilter) {
            double atr = CalculateATR(14, startIndex);
            if (atr == 0.0 || clusterRange > atr * maxClusterATRFactor)
               return false;
         }

         if (useVolumeFilter) {
            double avgVolume1 = CalculateAverageVolume(10);
            double clusterVolume = (double)candleHistory[startIndex].tick_volume;
            if (clusterVolume > avgVolume1)
               return false;
         }

         if (useStdDevFilter) {
            double stddev = CalculateStdDev(20, startIndex);
            if (stddev < clusterRange)
               return false;
         }

         clusterOut.startIndex = startIndex;
         clusterOut.endIndex = endIndex;
         clusterOut.maxHigh = clusterHigh;
         clusterOut.minLow = clusterLow;
         clusterOut.startTime = candleHistory[startIndex].time;
         clusterOut.endTime = candleHistory[endIndex].time;
         return true;
      }

      return false;
   }

   void DrawClusterBox(const CandleCluster &cluster, color clr) {
      string timeLabel = TimeToString(TimeCurrent(), TIME_SECONDS);
      string name = StringFormat("cluster_box_%d_%d_%s", cluster.startIndex, cluster.endIndex, timeLabel);

      datetime time1 = cluster.startTime;
      datetime time2 = cluster.endTime;
      double price1 = cluster.maxHigh;
      double price2 = cluster.minLow;

      if (!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2))
         Print("Błąd tworzenia prostokąta: ", name);

      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   double CalculateATR(int period, int index) {
      int handle = iATR(_Symbol, PERIOD_CURRENT, period);
      if (handle == INVALID_HANDLE) return 0.0;

      double buffer[];
      if (CopyBuffer(handle, 0, index, 1, buffer) != 1) return 0.0;

      return buffer[0];
   }

   double CalculateStdDev(int period, int index) {
      int handle = iStdDev(_Symbol, PERIOD_CURRENT, period, 0, MODE_SMA, PRICE_CLOSE);
      if (handle == INVALID_HANDLE) return 0.0;

      double buffer[];
      if (CopyBuffer(handle, 0, index, 1, buffer) != 1) return 0.0;

      return buffer[0];
   }

   double CalculateAverageVolume(int period) {
      if (ArraySize(candleHistory) < period + 1)
         return 0.0;

      double sum = 0.0;
      for (int i = 1; i <= period; i++)
         sum += (double)candleHistory[i].tick_volume;

      return sum / period;
   }
};

#endif // __CLUSTER_DETECTOR_MQH__










