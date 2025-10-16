//+------------------------------------------------------------------+
//| EA_PathConfig.mqh — centralna konfiguracja ścieżek i IO          |
//+------------------------------------------------------------------+
#pragma once
#property strict

// ----------------- USTAWIENIA NAZW -----------------
#define EA_VENDOR      "StartTester"        // nazwa folderu w Include/Files/Images
#define EA_NAME        "StartTester"        // nazwa EA (do logów/prefixów)
#define EA_FILES_SUB   "StartTester"        // podfolder w MQL5/Files
#define EA_COMMON_SUB  "StartTester"        // podfolder w Common/Files

// ----------------- IMPORTY SYSTEMOWE ----------------
#include <Trade/Trade.mqh>   // jeśli potrzebujesz
// ... inne globalne importy, wspólne dla całego projektu

// ----------------- HELPERY STRING -------------------
string PathJoin(const string a, const string b)
{
   if(StringLen(a)==0) return b;
   string sep = "\\";
   if(StringSubstr(a, StringLen(a)-1, 1)=="\\" || StringSubstr(a, StringLen(a)-1, 1)=="/")
      return a + b;
   return a + sep + b;
}

// ----------------- KONTEKST ŚCIEŻEK -----------------
namespace EA_PATH
{
   // Lokalny folder terminala (konto/tester) -> MQL5\Files
   string FilesRoot()
   {
      // Zawsze działa: zapis do MQL5\Files\...
      string root = "Files";
      // W strategii/testerze i na żywo path logicznie wskazuje ten sam wirtualny „Files”.
      return PathJoin(root, EA_FILES_SUB);
   }

   // Wspólny folder (Common\Files) — współdzielony między terminalami
   string CommonRoot()
   {
      // Zapis z flagą FILE_COMMON idzie tu
      return EA_COMMON_SUB;
   }

   string LogsLocal()    { return PathJoin(FilesRoot(), "logs");  }
   string DataLocal()    { return PathJoin(FilesRoot(), "data");  }
   string LogsCommon()   { return PathJoin(CommonRoot(), "logs"); }
   string DataCommon()   { return PathJoin(CommonRoot(), "data"); }
}

// ----------------- TWORZENIE KATALOGÓW -----------------
bool EnsureDirLocal(const string rel)   // w MQL5\Files
{
   // CreateDirectory działa relatywnie do Files (dla File* bez FILE_COMMON)
   return (bool)FileIsExist(rel) || (bool)FolderCreate(rel);
}

bool EnsureDirCommon(const string rel)  // w Common\Files
{
   // Wspólny folder: trzeba podać FILE_COMMON przy zapisie/otwarciu pliku.
   // Sam FolderCreate tworzy relatywnie do MQL5\Files, więc tu trik:
   // utworzymy „marker” plik i go usuniemy, co wymusi drzewo katalogów.
   string marker = PathJoin(rel, "~.mkdir");
   int h = FileOpen(marker, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h!=INVALID_HANDLE)
   {
      FileClose(h);
      FileDelete(marker, FILE_COMMON);
      return true;
   }
   return false;
}

void EnsureAllDirs()
{
   // Lokalne
   EnsureDirLocal(EA_PATH::LogsLocal());
   EnsureDirLocal(EA_PATH::DataLocal());
   // Wspólne
   EnsureDirCommon(EA_PATH::LogsCommon());
   EnsureDirCommon(EA_PATH::DataCommon());
}

// ----------------- BEZPIECZNE OTWARCIE PLIKÓW --------
int OpenLocal(const string rel, uint flags = FILE_WRITE|FILE_TXT)
{
   // rel np. "StartTester\\logs\\file.csv"
   // UWAGA: żadnych dwukropków ani ścieżek absolute!
   return FileOpen(rel, flags);
}

int OpenCommon(const string rel, uint flags = FILE_WRITE|FILE_TXT)
{
   // rel np. "StartTester\\logs\\file.csv"
   return FileOpen(rel, flags|FILE_COMMON);
}

// ----------------- POMOCNICY CSV ---------------------
bool CsvWriteHeader(const int handle, const string header[])
{
   if(handle==INVALID_HANDLE) return false;
   for(int i=0;i<ArraySize(header);++i)
   {
      if(i>0) FileWriteString(handle, ";");
      FileWriteString(handle, header[i]);
   }
   FileWriteString(handle, "\r\n");
   return true;
}

bool CsvWriteRow(const int handle, const string cols[])
{
   if(handle==INVALID_HANDLE) return false;
   for(int i=0;i<ArraySize(cols);++i)
   {
      if(i>0) FileWriteString(handle, ";");
      FileWriteString(handle, cols[i]);
   }
   FileWriteString(handle, "\r\n");
   return true;
}

// ----------------- DIAGNOSTYKA -----------------------
#define LOG_PREFIX  "[" EA_NAME "] "

void LogInfo(const string msg)   { Print(LOG_PREFIX, msg); }
void LogWarn(const string msg)   { Print(LOG_PREFIX, "⚠ ", msg); }
void LogError(const string msg)  { Print(LOG_PREFIX, "⛔ ", msg); }
