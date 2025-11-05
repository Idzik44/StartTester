//+------------------------------------------------------------------+
//|                     RegimeThresholds.mqh                         |
//|        Trwały zapis/odczyt progów reżimów do COMMON Files        |
//+------------------------------------------------------------------+
#property strict

#ifndef __REGIME_THRESHOLDS_MQH__
#define __REGIME_THRESHOLDS_MQH__

// ---------------------------
// Struktura progów reżimów
// ---------------------------
struct RegimeThresholds
{
   double zLow;       // próg dolny |Z|
   double zHigh;      // próg górny |Z|
   double adxStrong;  // ADX - poziom "silny trend"
   int    diGap;      // różnica DI+ - DI- wymagana dla kierunku
   double zHyst;      // histereza dla wolumen/zasięg
   double adxHyst;    // histereza dla ADX (enter/exit)
};

// ---------------------------
// Ustawienia (Inputs)
// ---------------------------
// Domyślny plik w COMMON — główne EA ma korzystać z best_summary.csv
input string RT_FileNameCommonCSV = "best_regime_thresholds.csv";

// Opcjonalne nadpisanie (globalny „override” z inputów); można wyłączyć
input bool   RT_EnableOverrides     = false;
input double RT_Override_zLow       = 0.30;
input double RT_Override_zHigh      = 0.80;
input double RT_Override_adxStrong  = 22.0;
input int    RT_Override_diGap      = 6;
input double RT_Override_zHyst      = 0.05;
input double RT_Override_adxHyst    = 3.0;

// ---------------------------
// Pomocnicze
// ---------------------------

/*
 Funkcja: __RT_CommonFilesPath
 Opis:    Zwraca pełną ścieżkę do pliku w katalogu COMMON\Files terminala.
 Wywołuje: TerminalInfoString(), konkatenacja stringów.
 Używa globalnych: brak (wykorzystuje parametr fname i stałą ścieżkę COMMON).
*/
string __RT_CommonFilesPath(const string fname)
{
   return TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + fname;
}

/*
 Funkcja: DefaultRegimeThresholds
 Opis:    Tworzy i zwraca domyślny zestaw progów reżimów (bez odczytu z pliku).
 Wywołuje: brak (czysta inicjalizacja struktury).
 Używa globalnych: brak.
*/
RegimeThresholds DefaultRegimeThresholds()
{
   RegimeThresholds t;
   t.zLow       = 0.30;
   t.zHigh      = 0.80;
   t.adxStrong  = 22.0;
   t.diGap      = 6;
   t.zHyst      = 0.05;
   t.adxHyst    = 3.0;
   return t;
}

/*
 Funkcja: ApplyRegimeThresholdsOverrides
 Opis:    Opcjonalnie nadpisuje pola struktury progów wartościami z inputów,
          jeśli RT_EnableOverrides==true. Służy jako globalny override.
 Wywołuje: PrintFormat() (log informacyjny przy aktywnych override).
 Używa globalnych (input): RT_EnableOverrides, RT_Override_*.
*/
void ApplyRegimeThresholdsOverrides(RegimeThresholds &t)
{
   if(!RT_EnableOverrides) return;
   t.zLow      = RT_Override_zLow;
   t.zHigh     = RT_Override_zHigh;
   t.adxStrong = RT_Override_adxStrong;
   t.diGap     = RT_Override_diGap;
   t.zHyst     = RT_Override_zHyst;
   t.adxHyst   = RT_Override_adxHyst;
   PrintFormat("[RT] Overrides aktywne -> zLow=%.2f zHigh=%.2f adx=%.1f di=%d zH=%.2f aH=%.2f",
               t.zLow, t.zHigh, t.adxStrong, t.diGap, t.zHyst, t.adxHyst);
}

// ---------------------------
// ZAPIS do COMMON (CSV z ';')
// ---------------------------
// Uwaga: domyślna wartość parametru MUSI być literałem, więc używamy "" i
// wewnątrz robimy fallback do RT_FileNameCommonCSV.

/*
 Funkcja: SaveRegimeThresholds
 Opis:    Zapisuje progi reżimów do pliku CSV (separator ';') w COMMON\Files.
 Wywołuje: FileOpen(), FileWrite(), FileClose(), __RT_CommonFilesPath(), Print().
 Używa globalnych (input): RT_FileNameCommonCSV (gdy fileNameCommonCSV == "").
 Wejście:  t - struktura progów; fileNameCommonCSV - opcjonalna nazwa pliku.
 Wyjście:  true/false w zależności od powodzenia zapisu.
*/
bool SaveRegimeThresholds(const RegimeThresholds &t, const string fileNameCommonCSV = "")
{
   const string fname = (fileNameCommonCSV == "" ? RT_FileNameCommonCSV : fileNameCommonCSV);

   int h = FileOpen(fname, FILE_WRITE|FILE_COMMON|FILE_CSV, ';');
   if(h == INVALID_HANDLE)
   {
      Print("[RT] ❌ Save: nie można otworzyć do zapisu: ", __RT_CommonFilesPath(fname));
      return false;
   }

   // nagłówek
   FileWrite(h, "zLow", "zHigh", "adxStrong", "diGap", "zHyst", "adxHyst");
   // wartości
   FileWrite(h, DoubleToString(t.zLow,  6),
                DoubleToString(t.zHigh, 6),
                DoubleToString(t.adxStrong, 6),
                (string)t.diGap,
                DoubleToString(t.zHyst, 6),
                DoubleToString(t.adxHyst, 6));
   FileClose(h);

   Print("[RT] ✅ Zapisano progi do COMMON: ", __RT_CommonFilesPath(fname));
   return true;
}

// ---------------------------
// ODCZYT z CSV (nagłówek + 1 linia) — próba kilku separatorów
// ---------------------------

/*
 Funkcja: __RT_TryLoadCSV
 Opis:    Próbny odczyt pliku CSV z COMMON\Files przy wskazanym separatorze
          (delim). Obsługuje nagłówek i jeden wiersz z wartościami.
 Wywołuje: FileOpen(), FileReadString(), FileIsEnding(), FileClose(),
           StringFind(), StringCompare(), StringToDouble(), StringToInteger().
 Używa globalnych: brak bezpośrednich; korzysta z parametrów fname i delim.
 Wejście:  fname - nazwa pliku; delim - separator; out - referencja na wynik.
 Wyjście:  true/false; w przypadku powodzenia wypełnia out.
 Uwagi:    Zawiera wstępną walidację zakresów pól (progi sensowności).
*/
bool __RT_TryLoadCSV(const string fname, uchar delim, RegimeThresholds &out)
{
   int h = FileOpen(fname, FILE_READ|FILE_COMMON|FILE_CSV, delim);
   if(h == INVALID_HANDLE) return false;

   // Czytamy pierwszy token
   string s1 = FileReadString(h);

   // Jeśli trafiliśmy zły separator: s1 zaczyna się od "zLow", ale zawiera też resztę nagłówka
   // sklejonego innym separatorem (np. "zLow;zHigh;adxStrong;...") — przerwij i daj szansę kolejnemu delim.
   if (StringFind(s1, "zLow") == 0 && s1 != "zLow")
   {
      if (StringFind(s1, ";") >= 0 || StringFind(s1, ",") >= 0 || StringFind(s1, "\t") >= 0)
      {
         FileClose(h);
         return false;
      }
   }

   // Normalny przypadek: nagłówek jako osobne pola
   if (StringCompare(s1, "zLow") == 0)
   {
      // Skip pozostałych 5 kolumn nagłówka
      for(int k=0; k<5 && !FileIsEnding(h); ++k) FileReadString(h);
      if(FileIsEnding(h)){ FileClose(h); return false; }
      s1 = FileReadString(h); // pierwszy field z wiersza danych
   }

   string s2 = FileReadString(h);
   string s3 = FileReadString(h);
   string s4 = FileReadString(h);
   string s5 = FileReadString(h);
   string s6 = FileReadString(h);
   FileClose(h);

   RegimeThresholds t;
   t.zLow       = StringToDouble(s1);
   t.zHigh      = StringToDouble(s2);
   t.adxStrong  = StringToDouble(s3);
   t.diGap      = (int)StringToInteger(s4);
   t.zHyst      = StringToDouble(s5);
   t.adxHyst    = StringToDouble(s6);

   // Walidacja
   bool ok = true;
   if(!(t.zLow >= 0.0 && t.zHigh > t.zLow && t.zHigh < 10.0)) ok = false;
   if(!(t.adxStrong >= 0.0 && t.adxStrong < 100.0)) ok = false;
   if(!(t.diGap >= 0 && t.diGap <= 100)) ok = false;
   if(!(t.zHyst >= 0.0 && t.zHyst < 5.0)) ok = false;
   if(!(t.adxHyst >= 0.0 && t.adxHyst < 50.0)) ok = false;
   if(!ok) return false;

   out = t;
   return true;
}

/*
 Funkcja: __rt_to_double
 Opis:    Zamienia ewentualny przecinek na kropkę i parsuje double.
 Wywołuje: StringReplace(), StringToDouble().
 Używa globalnych: brak.
*/
double __rt_to_double(string s) { StringReplace(s, ",", "."); return StringToDouble(s); }

/*
 Funkcja: __RT_TryLoadTXT
 Opis:    Roboczy loader „TXT” z autodetekcją separatora (;, , lub TAB)
          i obsługą nagłówka. Działa na pliku COMMON\Files.
 Wywołuje: FileOpen(), FileReadString(), FileIsEnding(), FileClose(),
           StringFind(), StringSplit(), __rt_to_double().
 Używa globalnych: brak.
 Wejście: fname - nazwa pliku; out - referencja na wynik.
 Wyjście: true/false; w przypadku powodzenia wypełnia out.
 Uwagi:   Wykonuje walidację zakresów pól podobnie jak CSV loader.
*/
bool __RT_TryLoadTXT(const string fname, RegimeThresholds &out)
{
   int h = FileOpen(fname, FILE_READ|FILE_COMMON|FILE_TXT|FILE_ANSI);
   if (h == INVALID_HANDLE) return false;

   if (FileIsEnding(h)) { FileClose(h); return false; }
   string line1 = FileReadString(h);
   string line2 = "";
   if (!FileIsEnding(h)) line2 = FileReadString(h);
   FileClose(h);

   bool hasHeader = (StringFind(line1, "zLow") != -1) && (StringFind(line1, "zHigh") != -1);

   // autodetekcja separatora: ; -> , -> TAB
   string probe = hasHeader ? line1 : line2;
   ushort sep = ';';
   if (StringFind(probe, ";") >= 0)      sep = ';';
   else if (StringFind(probe, ",") >= 0) sep = ',';
   else if (StringFind(probe, "\t")>= 0) sep = 9;  // TAB
   else {
      string other = hasHeader ? line2 : line1;
      if      (StringFind(other, ";")  >= 0) sep = ';';
      else if (StringFind(other, ",")  >= 0) sep = ',';
      else if (StringFind(other, "\t") >= 0) sep = 9;
      else return false;
   }

   string valsLine = hasHeader ? line2 : line1;
   string a[]; int n = StringSplit(valsLine, sep, a);
   if (n < 6) return false;

   RegimeThresholds t;
   t.zLow       = __rt_to_double(a[0]);
   t.zHigh      = __rt_to_double(a[1]);
   t.adxStrong  = __rt_to_double(a[2]);
   t.diGap      = (int)StringToInteger(a[3]);
   t.zHyst      = __rt_to_double(a[4]);
   t.adxHyst    = __rt_to_double(a[5]);

   // walidacja
   bool ok = true;
   if(!(t.zLow >= 0.0 && t.zHigh > t.zLow && t.zHigh < 10.0)) ok = false;
   if(!(t.adxStrong >= 0.0 && t.adxStrong < 100.0)) ok = false;
   if(!(t.diGap >= 0 && t.diGap <= 100)) ok = false;
   if(!(t.zHyst >= 0.0 && t.zHyst < 5.0)) ok = false;
   if(!(t.adxHyst >= 0.0 && t.adxHyst < 50.0)) ok = false;
   if(!ok) return false;

   out = t;
   return true;
}


// ---------------------------
// ODCZYT z COMMON — preferuj best_summary.csv, fallback do best_regime_thresholds.csv
// ---------------------------

/*
 Funkcja: LoadRegimeThresholds
 Opis:    Wczytuje progi reżimów z COMMON\Files, preferując nazwę z parametru
          (lub RT_FileNameCommonCSV), a następnie podejmuje fallback na drugi
          plik (best_summary.csv vs best_regime_thresholds.csv). Kolejno próbuje:
          TXT (autodetekcja), CSV z ';', CSV z ',', CSV z TAB.
 Wywołuje: DefaultRegimeThresholds(), __RT_TryLoadTXT(), __RT_TryLoadCSV(),
           ApplyRegimeThresholdsOverrides(), PrintFormat(), __RT_CommonFilesPath().
 Używa globalnych (input): RT_FileNameCommonCSV, RT_EnableOverrides i RT_Override_* (przez Apply*()).
 Wejście: out - referencja na wynik; fileNameCommonCSV - opcjonalna nazwa pliku.
 Wyjście: true/false; w przypadku braku plików/parsingu zwraca false i ustawia domyślne progi.
*/
bool LoadRegimeThresholds(RegimeThresholds &out, const string fileNameCommonCSV = "")
{
   // preferuj best_regime_thresholds.csv (zgodnie z Twoją prośbą)
   string primary   = (fileNameCommonCSV == "" ? RT_FileNameCommonCSV : fileNameCommonCSV);
   string secondary = (primary == "best_regime_thresholds.csv" ? "best_summary.csv" : "best_regime_thresholds.csv");

   RegimeThresholds t = DefaultRegimeThresholds();

   // 1) TXT (autodetekcja) – najpewniejszy
   bool ok = __RT_TryLoadTXT(primary, t)
          || __RT_TryLoadCSV(primary, ';',  t)
          || __RT_TryLoadCSV(primary, ',',  t)
          || __RT_TryLoadCSV(primary, '\t', t);

   // 2) fallback na drugi plik
   if(!ok)
      ok = __RT_TryLoadTXT(secondary, t)
        || __RT_TryLoadCSV(secondary, ';',  t)
        || __RT_TryLoadCSV(secondary, ',',  t)
        || __RT_TryLoadCSV(secondary, '\t', t);

   if(!ok)
   {
      Print("[RT] ⚠️ Load: brak/nieczytelny plik (", primary, " / ", secondary, "). Używam domyślnych.");
      out = DefaultRegimeThresholds();
      ApplyRegimeThresholdsOverrides(out);
      return false;
   }

   out = t;
   ApplyRegimeThresholdsOverrides(out);

   PrintFormat("[RT] ✅ Wczytano: zLow=%.6f zHigh=%.6f adx=%.3f di=%d zH=%.6f aH=%.3f  (plik: %s)",
               out.zLow, out.zHigh, out.adxStrong, out.diGap, out.zHyst, out.adxHyst,
               __RT_CommonFilesPath(primary));
   return true;
}


#endif // __REGIME_THRESHOLDS_MQH__
