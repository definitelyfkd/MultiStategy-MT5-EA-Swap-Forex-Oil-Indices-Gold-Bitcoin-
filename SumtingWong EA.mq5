//+------------------------------------------------------------------+
//|                                                SumtingWong?.mq5  |
//|                                        Date Created: 04-10-2026  |
//|                          Threshold trading + Gold + S/R (Merged) |
//|        Fixed $ Risk/Profit, Custom Block BO, Virtual Breakout    |
//|                      Gold Pip Multiplier                         |
//|                  Blackout Mode + Error Handling                  |
//|                 + Swap Trading with Daily Level Touch            |
//|                 + High/Low Strategy + Box Re-Entry (1H close)    |
//|          FIXED: MT5 v1.33 - one trade per symbol enforcement     |
//|          ADDED: Unique BO swap threshold + Reversible ADX logic  |
//|          MERGED: MT4 features – Daily Reset, 1H Filter, BO Re-Entry|
//|          NEW: BO Reverse Trades parameter, Total P/L Counter      |
//|          UPDATED: BO mode now uses Wack-A-Mole reversal logic     |
//|                   on the top swap symbols                         |
//+------------------------------------------------------------------+
#property copyright "Eggroll Enterprise"
#property link      "https://kick.com/h4vokx"
#property version   "1.40"
#property strict

enum ENUM_TRADE_DIRECTION_FILTER
{
   DIRECTION_DEFAULT,      // Both long and short allowed
   DIRECTION_LONG_ONLY,    // Only buy trades
   DIRECTION_SHORT_ONLY    // Only sell trades
};

enum ENUM_SWAP_MASTER_MODE
{
   SWAP_MODE_LENIENT,      // Instant entry
   SWAP_MODE_MODERATE,     // RVI Entry entry
   SWAP_MODE_STRICT        // Threshold entry
};


#include <Trade/Trade.mqh>
CTrade Trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string   Passkey = "";      // Enter the correct passkey to run the EA

input string   GeneralTradeOptions = " --- General Options ---";
bool           EnableTrading = true;
input int      MagicNumber = 04011994;
bool           ReverseTrades = true;
int            StartupDelaySeconds = 10;
input double   JPY_BlockThresh = 161.0;     // Set price for BOJ intervention
input          ENUM_TIMEFRAMES Timeframe = PERIOD_H1;      // Timeframe To trade On
int            BlockHours = 12;                // Block length (same as BO)
input int      StartTradingHour = 0;    // Server hour to start opening new trades
input int      StopTradingHour  = 24;   // Server hour to stop opening new trades (24 = always on)
input int      RVIPeriod = 10;           // Set Period for RVI features


// --- Risk Management (Multiplier) ---
input string   TradeManagment = " --- Profit Target ---";
input double   TP_Multiplier = 2.0;          // TP distance = Stop Loss pips × Multiplier
input double   RiskPercent = 0.50;         // Risk per trade (% of balance)
input bool     UseVirtualBalance = true;       // Use virtual balance instead of real balance for risk calculation
input double   VirtualBalance = 100000.0;       // Virtual balance amount for risk calculation
bool     PostEntrySLTP = false;
double   GlobalSL_Pips = 25;
int      GlobalMaxTradesPerSymbol = 1;    //Max amounts of trades per symbol traded at a time
int      MaxDailyTradesPerSymbol = 2;   // Max trades opened per symbol per day (all modes)
input  int      MaxDailyTradesGlobal = 10;   // Max total trades across all symbols per day (0 = unlimited)

input string   AutoProfitOptions = "--- AUTO PROFIT CLOSE ---";
input bool     AutoCloseEnable = true;                // Close all trades when profit reaches threshold
input double   AutoClosePercentage = 1.0;              // Profit percentage to trigger close (based on balance)
input bool     AutoCloseStopForDay = true;           // Stop trading for the day after profit threshold triggers

// --- Partial Take Profit ---
input string   TakeProfitOptions = " --- TAKE PROFIT OPTIONS ---";
input bool     UsePartialTP = true;
input bool     BreakEvenAfterPartial = true;
input double   BEPercentofTP = 5.0;

input string   StopLossOptions = " --- STOP LOSS OPTIONS ---";
bool     UseATR_SLTP = true;          // Replace half‑block / GlobalSL with ATR‑based SL/TP
int      ATR_SL_Period = 14;           // ATR period
input double   ATR_SL_Multiplier = 3.0;      // Stop Loss = ATR × this multiplier
input bool     EnableTrailingStop = true;
double   TrailStepPips          = 1;    // Step size (pips) – 0 = every tick
double   TrailActivationPercent = 20.0;   // Trailing activates when profit reaches this % of TP

// --- Entry Threshold ---
input string   EntryPoints = " --- ENTRY POINTS ---";
input bool     EnableThresholdTrading = true;
bool     Threshold_UseSwapFilter = true;   // Apply BO?style swap filter to forex entries
bool     UseOneHourCloseConfirmation = true;   // Wait for 1H candle close; enter only if close beyond signal price
input int      MaxForexTrades = 3;
double   StrongEntryThreshold = 60.0;   
double   WeakEntryThreshold  = 40.0;     
double   MinGapEntry = 20.0;
int      MinGapDurationSeconds = 0;
double   MaxSpreadPips = 3.0; 

// --- BO Mode ---
input string   BOModeOptions = "--- BO Mode (Reversal) ---";
input bool     EnableBOMode = true;
input int      MaxBOTrades = 3;
bool     BO_ReverseTrades = false;
bool     BO_UseSwapFilter = true;

// NEW: BO Reversal Parameters
string   BO_ReversalOptions = "--- BO Reversal ---";
bool     BO_UseReversalEntry = true;                
int      BO_RevLookbackDays = 28;                   // History days for average calculation
int      BO_RevTopCount = 21;                       // Top N biggest reversal candles to average
input    double   BO_RevCandleMultiplier = 1.5;              // Entry threshold = average * multiplier
int      BO_RevReversalMinutes = 30;                // Price must cross candle open within this window (for history calculation)
input bool     BO_RevImmediateEntry = false;              // If true, enter immediately when candle reaches size; else wait for candle close 
input double   BO_RevMinBodyPercent = 5.0;  
input int      BO_MultiCandleLookback = 3;              // 0=off, 1‑3 = check combined range over this many candles

// ---------------------------------------------------------------
// NEW: Master Mode + Sub?parameters
// ---------------------------------------------------------------
input string   SwapTradingOptions = " --- SWAP TRADING ---";
input bool     EnableSwapTrading = true;
input string   SwapMasterModeOptions = "--- SWAP MASTER MODE ---";
input ENUM_SWAP_MASTER_MODE SwapMasterMode = SWAP_MODE_STRICT;  // Lenient/Moderate/Strict

input string   SwapStrictOptions = "--- STRICT: Threshold Settings ---";
input bool     SwapStrict_WaitClose = true;   // Wait for 1H candle close; false = instant when threshold met
bool     StrictSwap_UseDynamicCandleSize = true;   // Use BO‑style candle‑average filter
input    double   StrictSwap_CandleAvgMultiplier = 1.0;     // Required candle size = boRevAvg × this
double   SwapRiskMultiplier = 1.0;  
bool     TradeWithTopNSwap = false;   // Trade with top N?swap leader: open all top N when leader enters, close all when leader exits
int      BOTopSwapCount = 3;   
input int      MaxSwapTrades = 3;
input int      TopSwapCount = 3;               // How many pairs to hold (top N carry trades)
input double   SwapEntryAbsThreshold = 2.5;     // Minimum positive swap to be considered
input double   SwapCloseAbsThreshold = 0.5; 


input string   DirectionFilterOptions = "--- DIRECTION FILTER (Oil/Indices/Gold/BTC) ---";
input ENUM_TRADE_DIRECTION_FILTER DirectionFilter = DIRECTION_DEFAULT;  // Long Only / Short Only / Default

// GOLD 
input string   GoldModeOptions = " --- GOLD TRADING ---";
input bool     TradeGold = true;
input int      MaxGoldTrades = 1;
input int      MaxBOGoldTrades = 1;
input double   MaxSpreadAU = 5.0;
double   GoldPipMultiplier = 1.00;
bool     GoldRVI_UsePartialTP = true;   // Keep – used for gold BO partial TP



// --- Oil Breakout (RVIs) ---
input string   OilBreakoutOptions = "--- OIL BREAKOUT ---";
input bool     TradeOil              = true;          // Enable USOIL trading
input int      MaxOilTrades          = 1;             // Max simultaneous oil trades
input double   MaxSpreadOil = 10.0;   // Max spread allowed for oil RVI entries (in pips or points)
bool     OilRVI_UsePartialTP   = true;   // Keep – used for oil BO partial TP


// --- Index Trading ---
input string   IndexTradingOptions = "--- INDEX TRADING ---";
input bool     EnableIndexTrading = true;      // Enable index breakout trades
bool     Index_UsePartialTP = true;           // Enable partial take profit for index trades
bool     Index_EnableTP = true;               // Enable take-profit for index trades
input int      MaxIndexTrades = 6;            // Max total open index trades
input double   MaxSpreadIndices = 50.0;       // Max spread allowed for indices


// --- Bitcoin Trading ---
input string   BTCTradingOptions = "--- BITCOIN TRADING ---";
input bool     TradeBitcoin = true;               // Enable Bitcoin trading
input int      MaxBitcoinTrades = 1;              // Max simultaneous Bitcoin trades
input bool     BTC_UsePartialTP = true;   // under Bitcoin Trading
input double   MaxSpreadBTC = 300.0;              // Max spread allowed for Bitcoin


// --- Daily Reset (24h block) ---
input string   DailyResetOptions = "--- DAILY RESET (24h block) ---";
input bool     EnableDailyReset = true;
input bool     MondaySpecial_BypassDailyReset = true;   // If true, Monday Special trades survive daily reset
input bool     ForexThreshold_DailyBypass    = true;   // If true, Forex threshold trades survive daily reset
input bool     Swap_DailyBypass              = true;   // If true, Swap trades are never closed during daily reset
input bool     ForexBO_DailyBypass           = true;   // If true, Forex BO trades survive daily reset
input bool     GoldThreshold_DailyBypass     = false;   // If true, Gold threshold trades survive daily reset
input bool     Oil_DailyBypass               = false;   // If true, Oil BO trades survive daily reset
input bool     GoldBO_DailyBypass            = false;   // If true, Gold BO trades survive daily reset
input bool     Index_DailyBypass             = false;   // If true, Index BO trades survive daily reset
input bool     BTC_DailyBypass               = false;   // If true, Bitcoin BO trades survive daily reset
input bool     DailyClose_SkipCandleAgrees   = false;   // Don't close if last 1H candle agrees with trade direction
int      DailyResetHour = 0;       // Hour of day (0?23) when new 24h block starts
input int      DailyCloseHour   = 23;   // Server hour to close trades (0‑23)
input int      DailyCloseMinute = 55;   // Server minute to close trades (0‑59)
input int      DailyResumeHour   = 2;  // Server hour to resume trading after close (0‑23)
input int      DailyResumeMinute = 0;  // Server minute to resume trading after close (0‑59)
input double   DailyClose_SwapProfitPercent = 25.0;   // Close swap trades if profit >= this percentage of SL distance (0 = never close)


// --- RVI Close Filter ---
input string   RVI_CloseOptions = "--- RVI CLOSE FILTER ---";
// ---------- new inputs (place under RVI Close Filter) ----------
input bool   RVI_CloseEnabled = true;           // Enable closing trades on RVI crossover
input bool   MondaySpecial_RVIBypass = true;   // If true, RVI close will skip Monday Special trades
input bool   RVISwapCloseBypass = true;
input bool   ForexBO_RVIBypass  = true;   // RVI will NOT close Forex BO trades
input bool   GoldBO_RVIBypass   = false;   // RVI will NOT close Gold BO trades
input bool   OilBO_RVIBypass    = false;   // RVI will NOT close Oil BO trades
input bool   IndexBO_RVIBypass  = false;   // RVI will NOT close Index BO trades
input bool   RVI_BTCBypass = false;            // If true, RVI will NOT close Bitcoin trades
bool     RVI_OpenOpposite = false;           // Open opposite trade when RVI closes a trade (ignores all filters)

string   FalseBreakoutOptions = "--- FALSE BREAKOUT RVI ENTRY ---";
bool     EnableFalseBreakoutRVI = true;             // Use RVI crossover for false breakout entries

// --- Entry Filters ---
string   EntryFilterOptions = " --- ENTRY FILTERS ---";
bool     UseOneHourCandleFilter = true;

string   DontTouchOptions = "";
double   WeightRSI = 40.0;
double   WeightMomentum = 35.0;
double   WeightTrend = 25.0;
double   WeightPriceChange = 5.0;
double   PriceChangeSensitivity = 5.0;
bool     AutoDetectPairs = true;
bool     AutoDetectSymbolSuffix = true;
string   SymbolPrefix = "";
string   SymbolSuffix = "";

string   AudioOptions = " --- AUDIO OPTIONS ---";
bool     PlaySounds = true;
string   SoundFileOpen         = "OrderFilled.wav";   // Sound for trade open
string   SoundFileClose        = "OrderClosed.wav";   // Sound for full close (SL/TP hit)
string   SoundFilePartialClose = "PartialTP.wav";   // Sound for partial TP close
string   SoundFilePending      = "PendingOrder.wav";   // Sound for BO pending order placement
string   ProfitAlertSound      = "ProfitAlert.wav";   // Sound for profit alert

// --- S/R Detection ---
string   SROptions = "";
int      SR_ATRPeriod = 740;
double   SR_Accuracy = 2;
int      SR_SafeDistance = 350;
bool     SR_DrawLines = false;
color    SR_ResistanceColor = clrGreen;
color    SR_SupportColor = clrRed;
int      SR_LineThickness = 2;
bool     SR_DrawZones = false;
color    SR_ZoneResistanceColor = clrMediumSeaGreen;
color    SR_ZoneSupportColor = clrLightSalmon;

// --- Dashboard ---
input string   DashboardPanelOptions = " --- DASHBOARD OPTIONS ---";
input bool     ShowDashboard = true;
input bool     ShowMainPanel     = true;
input bool     ShowLivePanel     = true;
input bool     ShowPairsPanel    = true;
input bool     ShowGoldPanel     = true;
input bool     ShowSettingsPanel = true;
input bool     ShowSRColumn      = true;
input bool     ShowBOMonitorPanel = true;
int      BODaysToShow = 20;
bool     DrawHLLines = false;
int      DashboardX = 10;
int      DashboardY = 30;

bool     BlackoutMode = true;

string   MetalsOptions = "--- PRECIOUS METALS STRENGTH ---";
bool     ShowMetalsStrength = true;    // Enable metals strength bar

// --- Logging ---
string   Eventlogging = " --- EVENT LOGGING ---";
bool     VerboseLogging = true;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
string Currencies[] = {"USD","EUR","GBP","JPY","CAD","AUD","CHF","NZD"};
string PossiblePairs[] = {
   "EURUSD","GBPUSD","USDJPY","USDCAD","AUDUSD","USDCHF","NZDUSD",
   "EURGBP","EURJPY","EURCAD","EURCHF","EURAUD","EURNZD","AUDNZD",
   "GBPJPY","GBPCAD","GBPCHF","GBPAUD","GBPNZD","AUDCHF","NZDCAD",
   "CADCHF","CADJPY","CHFJPY","AUDJPY","AUDCAD","NZDJPY","NZDCHF"
};
struct Pair { string symbol; };
Pair Pairs[50];
int PairCount = 0;
double CurrencyStrength[8];

// === ADD THESE LINES ===
string MetalSymbols[10];      // Detected metal symbols
int    MetalCount = 0;        // Number of metals found
double MetalsStrength = 0.0;  // Average metal strength (0–100)

#define MAX_BO_SYMBOLS 51

bool g_swapReEntryTaken[MAX_BO_SYMBOLS];   // true after a re‑entry trade was taken

// Session times in SERVER time (adjust if your broker offset differs)
#define SESSION_SYDNEY_START  0   // 0:00 server time (market open)
#define SESSION_SYDNEY_END    9   // 9:00
#define SESSION_TOKYO_START   3   // 3:00 (matches your Tokyo block)
#define SESSION_TOKYO_END    12   // 12:00
#define SESSION_LONDON_START  10   // 8:00
#define SESSION_LONDON_END   19   // 17:00
#define SESSION_NY_START     15   // 13:00
#define SESSION_NY_END       24   // 22:00

struct TradeInfo {
   ulong ticket;
   double openPrice;
   double entryDiff;
   datetime openTime;
   double currentSL;
   string pairSymbol;
   bool isGold;
   int entryType;
   int lastTrailStep;
   bool isBO;
   double lastTrailPrice;
   datetime lastTrailTime;
   bool partialDone;
   datetime lastPartialTime;
   // ---- breakeven candle‑close confirmation ----
   bool   breakevenPending;
   double breakevenSL;
   datetime lastBECheckCandle;

   // ---- NEW multi?tier fields ----
   double originalLot;                // lot size when trade entered
   bool   partial25Done;
   bool   partial50Done;
   bool   partial75Done;
};


TradeInfo Trades[50];
int TradeCount = 0;

// Ticket → entryType mapping (survives partial close comment loss)
struct TypeMapEntry { ulong ticket; int entryType; };
TypeMapEntry g_typeMap[100];
int g_typeMapCount = 0;

void SetEntryType(ulong ticket, int eType)
{
   for(int i=0; i<g_typeMapCount; i++)
      if(g_typeMap[i].ticket == ticket) { g_typeMap[i].entryType = eType; return; }
   if(g_typeMapCount < 100) { g_typeMap[g_typeMapCount].ticket = ticket; g_typeMap[g_typeMapCount].entryType = eType; g_typeMapCount++; }
}

int GetEntryType(ulong ticket)
{
   for(int i=0; i<g_typeMapCount; i++)
      if(g_typeMap[i].ticket == ticket) return g_typeMap[i].entryType;
   return -1;
}

void RemoveClosedFromMap()
{
   for(int i=g_typeMapCount-1; i>=0; i--)
      if(!PositionSelectByTicket(g_typeMap[i].ticket))
      { g_typeMap[i] = g_typeMap[g_typeMapCount-1]; g_typeMapCount--; }
}

string g_topSwapSymbols[MAX_BO_SYMBOLS];   // top swap symbols for dash coloring
int    g_topSwapCount = 0;                 // how many are in the list

// ========================= NEW: BO Reversal globals =========================
double   boRevAvg[MAX_BO_SYMBOLS];                 // reversal average (points)
datetime boLastCandleTime[MAX_BO_SYMBOLS];          // open time of last processed candle
bool     boRevTradeAllowed[MAX_BO_SYMBOLS];         // allow one trade per candle (immediate or close)
bool     boRevAvgComputed[MAX_BO_SYMBOLS];          // has the average been computed?
// ===========================================================================

// ========================= INDEX TRADING =========================
string   indexSymbols[50];          // detected index symbols
int      indexSymbolCount = 0;
double   idxBlockHigh[50];          // previous block high for each index
double   idxBlockLow[50];           // previous block low
bool     idxPrevPeriodReady[50];    // has the block levels been loaded?
datetime idxLastBlockStart[50];     // start time of the block that was last loaded
datetime idxSignalCandleTime[50];   // prevents multiple trades on the same candle
// =================================================================

string BTCSymbol = "";
bool   BTCTradeAllowed = false;

bool g_breakoutUp[MAX_BO_SYMBOLS + 50];   // unified breakout flags (forex + indices)
bool g_breakoutDown[MAX_BO_SYMBOLS + 50];

// False Breakout RVI – candle lockout
datetime swapFB_RVIBarTime[MAX_BO_SYMBOLS];   // last bar processed per symbol (swap)
datetime idxFB_RVIBarTime[50];                // last bar processed per index

datetime idxRVICloseBarTime[50];   // last processed RVI bar for index close check

// Swap breakout flags – remain true once a 1H candle closes outside the block
datetime g_swapSignalCandleTime[MAX_BO_SYMBOLS];   // prevents multiple swap trades on same candle

bool g_profitThresholdTriggered = false;
bool g_profitAlertTriggered = false;
bool g_profitStopTrading = false;   

double CurrentGap = 0;
string CurrentPair = "";
int CurrentStrongest = 0, CurrentWeakest = 0;
bool TradeReady = false;
bool      g_pendingSignal = false;
string    g_signalSymbol;
int       g_signalDirection;
double    g_signalPrice;
datetime  g_signalCandleOpen;
bool      g_signalLocked = false;      // prevents new signals until conditions reset

bool      g_goldPendingSignal = false;
int       g_goldSignalDirection;
double    g_goldSignalPrice;
datetime  g_goldSignalCandleOpen;
bool      g_goldSignalLocked = false;


// --- Monday open breakout state for indices ---
bool   mondayActive[50];               // true if Monday condition still possible for this symbol
int    mondayDirection[50];            // ORDER_TYPE_BUY or ORDER_TYPE_SELL
double mondayPrevLow[50];              // previous period low
double mondayPrevHigh[50];             // previous period high
datetime mondayExpiry[50];             // condition expires at this time (Monday 03:00)
bool   mondayFirstCandleProcessed[50]; // whether we have evaluated the first candle

datetime rviLastBarTime[MAX_BO_SYMBOLS];           // Tracks last checked 1H bar open time for RVI

int g_dailyTradeGlobalCount = 0;   // total trades opened today

string GoldSymbol = "";
bool GoldTradeAllowed = false;

string OilSymbol = "";
bool   OilTradeAllowed = false;

string   g_usdjpySymbol = "";
bool     g_allTradingPaused = false;

bool     g_jpyBlockTriggeredToday = false;
datetime g_tokyoPauseEndTime = 0;   

bool g_dailyLenientSwapDone = false;   // reset at the start of each new day

datetime g_swapLastH1Open[MAX_BO_SYMBOLS];
bool     g_swapLastH1Init[MAX_BO_SYMBOLS];
ulong    g_swapGroupLeaderTicket = 0;       // ticket of the group leader when TradeWithTopNSwap is active

datetime g_lastBORevCalc = 0;   // last time BO reversal averages were recalculated

datetime LastTradeTime = 0;
string DynamicStatus = "Waiting for signal";

int DashboardXpos, DashboardYpos;
int SecondPanelXpos, ThirdPanelXpos, FourthPanelXpos, FifthPanelXpos;

string LastCloseReason = "";
datetime LastCloseTime = 0;

struct SRLevel {
   double levelPrice;
   bool isResistance;
   int touches;
};
SRLevel currentSRLevels[100];
int currentSRCount = 0;

struct SRCache {
   string symbol;
   SRLevel levels[100];
   int count;
   datetime lastCalc;
};
SRCache srCache[50];
int srCacheCount = 0;
datetime lastSRCalcDraw = 0;

double Array[];
string uPairs[50];
int uCounts[50];
double uGaps[50];

datetime lastSRCalcLog = 0;
datetime lastMarketUpdate = 0;
int dotAnimStep = 0;

struct SymbolCache {
   double point;
   double pipSize;
   int digits;
   double lastSpread;
   datetime lastSpreadUpdate;
};

SymbolCache symCache[MAX_BO_SYMBOLS];

bool symCacheInit = false;

string boSymbols[MAX_BO_SYMBOLS];
int    boSymbolCount = 0;
double boPrevPeriodHigh[MAX_BO_SYMBOLS];
double boPrevPeriodLow[MAX_BO_SYMBOLS];
bool   boPrevPeriodReady[MAX_BO_SYMBOLS];
bool   boIsGold[MAX_BO_SYMBOLS];
bool   boOrdersPlaced[MAX_BO_SYMBOLS];

int g_goldBoIndex = -1;
int g_oilBoIndex = -1;
int g_btcBoIndex = -1;
int g_indexBoIndex[50];   // maps indexSymbols[i] → boSymbols index


ulong    SwapBuyTicket[MAX_BO_SYMBOLS];
ulong    SwapSellTicket[MAX_BO_SYMBOLS];
datetime SwapBuyOpenTime[MAX_BO_SYMBOLS];
datetime SwapSellOpenTime[MAX_BO_SYMBOLS];

datetime g_initTime = 0;
datetime g_currentDailyBlockStart = 0;   // Start of current 24h block
string  g_nextDailyResetStr = "";
bool     g_dailyResetPauseActive = false;   // True during the 30s pause before reset
datetime g_dailyPauseStartTime = 0;
bool     g_dailyCloseDone = false; 
datetime g_dailyResumeTime = 0;   // absolute resume time after daily close

struct SLBackup {
   ulong ticket;
   double originalSL;
};
SLBackup g_slBackup[50];
int g_slBackupCount = 0;

datetime g_lastKnownServerTime = 0;      // last fresh server time
uint     g_lastTickCount = 0;            // GetTickCount() at that moment

// Indicator handles for strength calculation
int rsiHandles[50];
int ma20Handles[50];
int ma50Handles[50];

struct DailyTradeRecord { string symbol; int count; };
DailyTradeRecord g_dailyTrades[100];
int g_dailyTradeTotal = 0;

void DailyTradeCount_Reset()
{
   g_dailyTradeTotal = 0;
   g_dailyTradeGlobalCount = 0;
}

void DailyTradeCount_Increment(string sym)
{
   g_dailyTradeGlobalCount++;
   for(int i=0; i<g_dailyTradeTotal; i++)
      if(g_dailyTrades[i].symbol == sym) { g_dailyTrades[i].count++; return; }
   if(g_dailyTradeTotal < 100)
   {
      g_dailyTrades[g_dailyTradeTotal].symbol = sym;
      g_dailyTrades[g_dailyTradeTotal].count = 1;
      g_dailyTradeTotal++;
   }
}

int DailyTradeCount_Get(string sym) {
   for(int i = 0; i < g_dailyTradeTotal; i++)
      if(g_dailyTrades[i].symbol == sym) return g_dailyTrades[i].count;
   return 0;
}

//+------------------------------------------------------------------+
//| Return the current ATR value for a symbol (cached handle)         |
//+------------------------------------------------------------------+
double GetATRValue(string symbol)
{
   int atrHandle = iATR(symbol, Timeframe, ATR_SL_Period);
   if(atrHandle == INVALID_HANDLE) return 0.0;
   double atrBuf[1];
   bool ok = (CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0);
   IndicatorRelease(atrHandle);
   if(!ok || atrBuf[0] <= 0) return 0.0;
   return atrBuf[0];
}

double GetHalfBlockHeight(string symbol)
{
   for(int b = 0; b < boSymbolCount; b++)
   {
      if(boSymbols[b] == symbol)
      {
         if(boPrevPeriodReady[b])
         {
            double h = (boPrevPeriodHigh[b] - boPrevPeriodLow[b]) / 2.0;
            if(h > 0) return h;      // block is ready and has range → use it
         }
         break;
      }
   }

   // Fallback: previous day’s range (1H close might be missing on Monday/holidays)
   double dayHigh[1], dayLow[1];
   if(CopyHigh(symbol, PERIOD_D1, 1, 1, dayHigh) == 1 &&
      CopyLow(symbol, PERIOD_D1, 1, 1, dayLow) == 1)
   {
      double dayHalf = (dayHigh[0] - dayLow[0]) / 2.0;
      if(dayHalf > 0) return dayHalf;
   }

   // Absolute last resort (should never happen with valid data)
   return 1.0;   // tiny safety value to avoid division by zero
}

//+------------------------------------------------------------------+
//| Get unified breakout index for any symbol (forex or index)        |
//+------------------------------------------------------------------+
int GetUnifiedBreakoutIndex(string symbol)
{
   for(int b = 0; b < boSymbolCount; b++)
      if(boSymbols[b] == symbol) return b;
   for(int i = 0; i < indexSymbolCount && i < 50; i++)
      if(indexSymbols[i] == symbol) return MAX_BO_SYMBOLS + i;
   return -1;
}

//+------------------------------------------------------------------+
//| Custom GetBarShift for MT5                                       |
//+------------------------------------------------------------------+
int GetBarShift(string symbol, ENUM_TIMEFRAMES tf, datetime time, bool exact = false) {
   if(time <= 0) return -1;
   datetime timeArray[];
   ArraySetAsSeries(timeArray, true);
   int copied = CopyTime(symbol, tf, 0, 10000, timeArray);
   if(copied <= 0) return -1;
   if(time < timeArray[copied-1]) return -1;
   for(int i = 0; i < copied; i++) {
      if(timeArray[i] <= time) {
         if(exact && timeArray[i] != time) return -1;
         return i;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| LOGGING FUNCTION                                                 |
//+------------------------------------------------------------------+
void Log(string msg, bool isImportant = false) {
   if(VerboseLogging || isImportant)
      Print(msg);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+
void CreateMarketStatusLabel() {
   ObjectCreate(0, "MarketStatus", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MarketStatus", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "MarketStatus", OBJPROP_XDISTANCE, 72);
   ObjectSetInteger(0, "MarketStatus", OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, "MarketStatus", OBJPROP_FONTSIZE, 6);
   ObjectSetInteger(0, "MarketStatus", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetString(0, "MarketStatus", OBJPROP_TEXT, "Checking...");
}

//+------------------------------------------------------------------+
//| Count total open positions (any type) for a given symbol         |
//+------------------------------------------------------------------+
int CountTradesForSymbol(string symbol)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol)
         cnt++;
   }
   return cnt;
}

void UpdateMarketStatus() {
    if (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED) {
        MqlDateTime currentTime;
        TimeCurrent(currentTime);
        datetime from, to;
        if (SymbolInfoSessionTrade(Symbol(), (ENUM_DAY_OF_WEEK)currentTime.day_of_week, 0, from, to)) {
            MqlDateTime sessionStart = currentTime;
            MqlDateTime sessionEnd = currentTime;
            sessionStart.hour = (int)(from / 3600);
            sessionStart.min = (int)((from % 3600) / 60);
            sessionEnd.hour = (int)(to / 3600);
            sessionEnd.min = (int)((to % 3600) / 60);
            datetime sessionStartTime = StructToTime(sessionStart);
            datetime sessionEndTime = StructToTime(sessionEnd);
            datetime now = TimeCurrent();
            if (now >= sessionStartTime && now <= sessionEndTime) {
                ObjectSetString(0, "MarketStatus", OBJPROP_TEXT, "Market : OPENED");
                ObjectSetInteger(0, "MarketStatus", OBJPROP_COLOR, clrGreen);
                return;
            }
        }
    }
    ObjectSetString(0, "MarketStatus", OBJPROP_TEXT, "Market : CLOSED");
    ObjectSetInteger(0, "MarketStatus", OBJPROP_COLOR, clrCrimson);
}

void RemoveAllIndicators() {
   int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   for(int w = totalWindows - 1; w >= 0; w--) {
      int totalIndicators = ChartIndicatorsTotal(0, w);
      for(int i = totalIndicators - 1; i >= 0; i--) {
         string indName = ChartIndicatorName(0, w, i);
         ChartIndicatorDelete(0, w, indName);
      }
   }
   ChartRedraw();
}

void ApplyBlackoutMode() {
   if(!BlackoutMode) return;
   RemoveAllIndicators();
   
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_GRID, clrBlack);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   ChartSetInteger(0, CHART_COLOR_BID, clrBlack);
   ChartSetInteger(0, CHART_COLOR_ASK, clrBlack);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlack);
   ChartSetInteger(0, CHART_COLOR_VOLUME, clrBlack);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, false);
   ChartSetInteger(0, CHART_SHOW_DATE_SCALE, false);
   ChartSetInteger(0, CHART_SHOW_PRICE_SCALE, false);
   ChartSetInteger(0, CHART_AUTOSCROLL, false);
   ChartSetInteger(0, CHART_SCALE, 0);
   ChartSetInteger(0, CHART_SCALEFIX, true);
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(0, CHART_SHOW_OHLC, false);
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK, false);
   ChartSetInteger(0, CHART_SHOW_TICKER, false);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);
   
   int total = ObjectsTotal(0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i);
      if(StringFind(name, "DB") == 0) continue;
      if(StringFind(name, "MarketStatus") == 0) continue;
      ObjectDelete(0, name);
   }
   
   ChartRedraw();
   Log("Blackout mode applied (dashboard kept).", false);
}

bool IsSymbolValidForTrading(string symbol) {
   if(symbol == "") return false;
   if(SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) return false;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0 || ask < bid) return false;   // <-- corrected
   return true;
}

string GetFullSymbol(string base) { return SymbolPrefix + base + SymbolSuffix; }

//+------------------------------------------------------------------+
//| Symbol Caching Functions                                         |
//+------------------------------------------------------------------+
void InitSymbolCache() {
   for(int i=0; i<boSymbolCount; i++) {
      string sym = boSymbols[i];
      symCache[i].point = GetSymbolPoint(sym);
      symCache[i].pipSize = GetPipSize(sym);
      symCache[i].digits = GetDigits(sym);
      symCache[i].lastSpreadUpdate = 0;
   }
   symCacheInit = true;
}

int GetCachedIndex(string symbol) {
   for(int i=0; i<boSymbolCount; i++) if(boSymbols[i] == symbol) return i;
   return -1;
}

double GetCachedSpread(string symbol) {
   int idx = GetCachedIndex(symbol);
   if(idx < 0) return GetCurrentSpread(symbol);
   if(TimeCurrent() - symCache[idx].lastSpreadUpdate > 1) {
      symCache[idx].lastSpread = GetCurrentSpread(symbol);
      symCache[idx].lastSpreadUpdate = TimeCurrent();
   }
   return symCache[idx].lastSpread;
}

double GetPipSize(string symbol)
{
   // Gold is handled explicitly, no fallback needed here.
   if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0)
      return 1.0;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0)
   {
      // Fallback: provide correct **point** values for common digit formats
      if(digits == 5)       point = 0.00001;
      else if(digits == 3)  point = 0.001;    // JPY with 3 digits
      else if(digits == 4)  point = 0.0001;
      else if(digits == 2)  point = 0.01;     // JPY with 2 digits
      else                  point = 0.00001;  // ultimate fallback
   }

   // Standard MT4/5 logic: pip size = 10 points for 5?/3?digit brokers, else 1 point
   return (digits == 5 || digits == 3) ? point * 10 : point;
}

int GetDigits(string s) { int d = (int)SymbolInfoInteger(s, SYMBOL_DIGITS); return (d==0)?5:d; }

double GetSymbolPoint(string symbol) {
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point > 0) return point;
   int digits = GetDigits(symbol);
   bool isGold = (StringFind(symbol, "XAU")>=0 || StringFind(symbol, "GOLD")>=0);
   if(isGold) {
      if(digits == 2) return 0.01;
      if(digits == 3) return 0.001;
      return 0.01;
   }
   // Indices fallback (common symbols)
   if(StringFind(symbol, "US30")>=0 || StringFind(symbol, "DE30")>=0 || 
      StringFind(symbol, "GER30")>=0 || StringFind(symbol, "JP225")>=0 ||
      StringFind(symbol, "EU50")>=0 || StringFind(symbol, "ESTX50")>=0)
   {
      if(digits <= 1) return 1.0;       // e.g. US30 typical point = 1.0
      if(digits == 2) return 0.01;
      return 1.0;
   }
   // Forex / others
   if(digits == 5 || digits == 3) return 0.001;
   if(digits == 4 || digits == 2) return 0.0001;
   return 0.00001;
}

string GetCleanSymbol(string sym) {
   string clean = sym;
   if(SymbolPrefix != "" && StringFind(clean, SymbolPrefix) == 0)
      clean = StringSubstr(clean, StringLen(SymbolPrefix));
   int dot = StringFind(clean, ".");
   if(dot >= 0) clean = StringSubstr(clean, 0, dot);
   int dash = StringFind(clean, "-");
   if(dash >= 0) clean = StringSubstr(clean, 0, dash);
   if(StringLen(clean) > 6) clean = StringSubstr(clean, 0, 6);
   return clean;
}

double GetCurrentSpread(string symbol) {
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize : GetPipSize(symbol);
   return (ask - bid) / pipSize;
}

int CountForexTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 0) cnt++;
   }
   return cnt;
}

int CountGoldTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 2) cnt++;
   }
   return cnt;
}

int CountBOTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 3) cnt++;
   }
   return cnt;
}

int CountBOGoldTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 4) cnt++;
   }
   return cnt;
}

int CountSwapTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 7) cnt++;
   }
   return cnt;
}

int CountSwapTradesForSymbol(string symbol) {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 7 && PositionGetString(POSITION_SYMBOL) == symbol) cnt++;
   }
   return cnt;
}

int CountIndexTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 5) cnt++;
   }
   return cnt;
}

int CountOilTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 6) cnt++;
   }
   return cnt;
}

int CountBTCTrades() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(GetEntryType(ticket) == 8) cnt++;
   }
   return cnt;
}

// Keep CountTradesForSymbol as is – it counts any magic number trade (used for per‑symbol limit).
int CountBOTradesForSymbol(string symbol) {
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         if(PositionGetString(POSITION_SYMBOL) == symbol && StringFind(PositionGetString(POSITION_COMMENT), "BreakOut Order") >= 0) cnt++;
      }
   }
   return cnt;
}

int CountTradesForPair(string symbol) {
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         string sym = PositionGetString(POSITION_SYMBOL);
         string cmt = PositionGetString(POSITION_COMMENT);
         if(StringFind(sym, "XAU")<0 && StringFind(sym, "GOLD")<0 && sym == symbol && StringFind(cmt, "BreakOut Order") < 0 && StringFind(cmt, "Swap Order") < 0) cnt++;
      }
   }
   return cnt;
}

int CountIndexTradesForSymbol(string symbol) {
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            StringFind(PositionGetString(POSITION_COMMENT), "Index Order") >= 0) cnt++;
      }
   }
   return cnt;
}



double GetPairGap(string symbol) {
   string clean = GetCleanSymbol(symbol);
   if(StringLen(clean) < 6) return 0;
   string cA = StringSubstr(clean,0,3);
   string cB = StringSubstr(clean,3,3);
   double sA = 0, sB = 0;
   for(int i=0;i<8;i++) {
      if(Currencies[i]==cA) sA = CurrencyStrength[i];
      if(Currencies[i]==cB) sB = CurrencyStrength[i];
   }
   return MathAbs(sA - sB);
}

double GetPairStrengthBias(string symbol) {
   string clean = GetCleanSymbol(symbol);
   if(StringLen(clean) < 6) return 0;
   string base = StringSubstr(clean,0,3);
   string quote = StringSubstr(clean,3,3);
   double sBase = 0, sQuote = 0;
   for(int i=0; i<8; i++) {
      if(Currencies[i] == base) sBase = CurrencyStrength[i];
      if(Currencies[i] == quote) sQuote = CurrencyStrength[i];
   }
   return sBase - sQuote;
}

void DetectBitcoinSymbol()
{
   string possibleBTC[] = {"BTCUSD", "BTCUSD.", "BTCUSDi", "XBTUSD"};
   BTCSymbol = "";
   for(int i=0; i<ArraySize(possibleBTC); i++)
   {
      string full = FindSymbolAuto(possibleBTC[i]);
      if(IsSymbolValidForTrading(full))
      {
         BTCSymbol = full;
         break;
      }
   }
   BTCTradeAllowed = (BTCSymbol != "");
   if(BTCTradeAllowed) Print("Bitcoin symbol detected: ", BTCSymbol);
}

void DetectUSDJPYSymbol() {
   string possible[] = {"USDJPY", "USDJPYm", "USDJPY."};
   g_usdjpySymbol = "";
   for(int i=0; i<ArraySize(possible); i++) {
      string full = FindSymbolAuto(possible[i]);
      if(IsSymbolValidForTrading(full)) {
         g_usdjpySymbol = full;
         break;
      }
   }
   if(g_usdjpySymbol != "") Print("USDJPY symbol detected: ", g_usdjpySymbol);
}

void DetectGoldSymbol() {
   string possibleGold[] = {"XAUUSD", "GOLD", "XAUUSDm", "XAUUSD."};
   GoldSymbol = "";
   for(int i=0; i<ArraySize(possibleGold); i++) {
      string full = FindSymbolAuto(possibleGold[i]);
      if(IsSymbolValidForTrading(full)) {
         GoldSymbol = full;
         break;
      }
   }
   GoldTradeAllowed = (GoldSymbol != "");
   if(GoldTradeAllowed) Print("Gold symbol detected: ", GoldSymbol);
}

string FindSymbolAuto(string base) {
   string manual = GetFullSymbol(base);
   if(IsSymbolValidForTrading(manual)) return manual;
   if(!AutoDetectSymbolSuffix) return manual;
   
   for(int i=0; i<SymbolsTotal(false); i++) {
      string sym = SymbolName(i, false);
      if(StringFind(sym, base) >= 0 && IsSymbolValidForTrading(sym))
         return sym;
   }
   return manual;
}

void AutoDetect() {
   PairCount = 0;
   
   boSymbolCount = 0;
   for(int i=0; i<ArraySize(PossiblePairs); i++) {
      string base = PossiblePairs[i];
      string full = FindSymbolAuto(base);
      if(IsSymbolValidForTrading(full)) {
         Pairs[PairCount].symbol = full;
         PairCount++;
      }
   }
   
   boSymbolCount = 0;
   for(int i=0; i<PairCount; i++) {
      boSymbols[boSymbolCount] = Pairs[i].symbol;
      boIsGold[boSymbolCount] = false;
      boSymbolCount++;
   }
   if(TradeGold && GoldSymbol != "") {
      boSymbols[boSymbolCount] = GoldSymbol;
      boIsGold[boSymbolCount] = true;
      g_goldBoIndex = boSymbolCount;   // ← store index
      boSymbolCount++;
   }
   if(TradeOil && OilSymbol != "")
   {
      boSymbols[boSymbolCount] = OilSymbol;
      boIsGold[boSymbolCount] = false;
      g_oilBoIndex = boSymbolCount;    // ← store index
      boSymbolCount++;
   }
   if(TradeBitcoin && BTCSymbol != "")
   {
      boSymbols[boSymbolCount] = BTCSymbol;
      boIsGold[boSymbolCount] = false;
      g_btcBoIndex = boSymbolCount;    // ← store index
      boSymbolCount++;
   }
      // Add index symbols to boSymbols for reversal averages
   for(int i = 0; i < indexSymbolCount && i < 50; i++)
   {
      if(boSymbolCount >= MAX_BO_SYMBOLS) break;   // prevent overflow
      boSymbols[boSymbolCount] = indexSymbols[i];
      boIsGold[boSymbolCount] = false;
      g_indexBoIndex[i] = boSymbolCount;
      boSymbolCount++;
   }
      
   if(!symCacheInit) InitSymbolCache();
}

void CheckAllLimits() {
   Log("========== SYMBOL TRADING LIMITS ==========", false);
   for(int i=0; i<PairCount; i++) {
      string sym = Pairs[i].symbol;
      long stopLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      long freezeLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
      int spread = (int)SymbolInfoInteger(sym, SYMBOL_SPREAD);
      Log("Symbol: " + sym, false);
      Log("   Stop Level  : " + IntegerToString(stopLevel) + " points", false);
      Log("   Freeze Level: " + IntegerToString(freezeLevel) + " points", false);
      Log("   Spread      : " + IntegerToString(spread) + " points", false);
   }
   Log("============================================", false);
}

//+------------------------------------------------------------------+
//| Detect precious metal symbols                                     |
//+------------------------------------------------------------------+
void DetectMetalSymbols() {
   MetalCount = 0;
   string prefixes[] = {"XAU", "GOLD", "XAG", "SILVER", "XPD", "PALLADIUM", "XPT", "PLATINUM"};
   for(int p = 0; p < ArraySize(prefixes); p++) {
      for(int i = 0; i < SymbolsTotal(false); i++) {
         string sym = SymbolName(i, false);
         if(StringFind(sym, prefixes[p]) >= 0) {
            if(SymbolInfoDouble(sym, SYMBOL_BID) > 0) {
               bool already = false;
               for(int m = 0; m < MetalCount; m++) {
                  if(MetalSymbols[m] == sym) { already = true; break; }
               }
               if(!already) {
                  MetalSymbols[MetalCount] = sym;
                  MetalCount++;
                  if(MetalCount >= 10) break;
               }
            }
         }
      }
   }
   if(VerboseLogging) Print("Metals detected: ", MetalCount);
}

void DetectOilSymbol()
{
   string possibleOil[] = {"USOIL", "USOIL.c", "WTI", "XTIUSD", "Crude"};
   OilSymbol = "";
   for(int i=0; i<ArraySize(possibleOil); i++)
   {
      string full = FindSymbolAuto(possibleOil[i]);
      if(IsSymbolValidForTrading(full))
      {
         OilSymbol = full;
         break;
      }
   }
   OilTradeAllowed = (OilSymbol != "");
   if(OilTradeAllowed) Print("Oil symbol detected: ", OilSymbol);
}
//+------------------------------------------------------------------+
//| Calculate strength for a single metal symbol (0–100) - MT5        |
//+------------------------------------------------------------------+
double CalculateMetalStrength(string symbol) {
   double rsiBuf[1], close0[1], close5[1], ma20[1], ma50[1];
   
   int rsiHandle = iRSI(symbol, PERIOD_M1, 14, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE) return 50.0;
   CopyBuffer(rsiHandle, 0, 1, 1, rsiBuf);
   IndicatorRelease(rsiHandle);
   
   CopyClose(symbol, PERIOD_M1, 0, 1, close0);
   CopyClose(symbol, PERIOD_M1, 5, 1, close5);
   
   int ma20Handle = iMA(symbol, PERIOD_M1, 20, 0, MODE_SMA, PRICE_CLOSE);
   int ma50Handle = iMA(symbol, PERIOD_M1, 50, 0, MODE_SMA, PRICE_CLOSE);
   if(ma20Handle != INVALID_HANDLE) CopyBuffer(ma20Handle, 0, 1, 1, ma20);
   if(ma50Handle != INVALID_HANDLE) CopyBuffer(ma50Handle, 0, 1, 1, ma50);
   IndicatorRelease(ma20Handle);
   IndicatorRelease(ma50Handle);
   
   // RSI (already 0–100)
   double rsiComp = (rsiBuf[0] > 0) ? rsiBuf[0] : 50.0;
   
   // Momentum (0–100)
   double momComp = 50.0;
   if(close0[0] > 0 && close5[0] > 0) {
      double mom = 50.0 + ((close0[0] - close5[0]) / close5[0]) * 100.0;
      momComp = MathMax(0.0, MathMin(100.0, mom));
   }
   
   // Trend (0–100)
   double trendComp = 50.0;
   if(ma20[0] > 0 && ma50[0] > 0) {
      double trend = 50.0 + ((ma20[0] - ma50[0]) / ma50[0]) * 100.0;
      trendComp = MathMax(0.0, MathMin(100.0, trend));
   }
   
   // Weighted combination (without PriceChange)
   double totalWeight = WeightRSI + WeightMomentum + WeightTrend;
   if(totalWeight == 0) totalWeight = 1.0;
   double strength = (rsiComp * WeightRSI + momComp * WeightMomentum + trendComp * WeightTrend) / totalWeight;
   return MathMax(0.0, MathMin(100.0, strength));
}


void CalculateStrength() {
   double rsiSum[8], momSum[8], trendSum[8];
   int rsiCount[8], momCount[8], trendCount[8];
   for(int i=0;i<8;i++) { rsiSum[i]=momSum[i]=trendSum[i]=0; rsiCount[i]=momCount[i]=trendCount[i]=0; }
   for(int i=0; i<PairCount; i++) {
      string sym = Pairs[i].symbol;
      string clean = GetCleanSymbol(sym);
      if(StringLen(clean) < 6) continue;
      string base = StringSubstr(clean,0,3), quote = StringSubstr(clean,3,3);
      int idxBase=-1, idxQuote=-1;
      for(int c=0;c<8;c++) {
         if(Currencies[c]==base) idxBase=c;
         if(Currencies[c]==quote) idxQuote=c;
      }
      if(idxBase==-1 || idxQuote==-1) continue;
      
      double rsiBuf[1];
      if(CopyBuffer(rsiHandles[i], 0, 1, 1, rsiBuf) > 0) {
         double rsi = rsiBuf[0];
         if(rsi > 0 && rsi <= 100) {
            rsiSum[idxBase] += rsi; rsiCount[idxBase]++;
            rsiSum[idxQuote] += (100 - rsi); rsiCount[idxQuote]++;
         }
      }
      double close[6];
      if(CopyClose(sym, PERIOD_M1, 0, 6, close) >= 6) {
         double c5 = close[5], c0 = close[0];
         if(c5>0 && c0>0) {
            double mom = 50 + ((c0-c5)/c5)*100;
            mom = MathMax(0, MathMin(100, mom));
            momSum[idxBase] += mom; momCount[idxBase]++;
            momSum[idxQuote] += (100 - mom); momCount[idxQuote]++;
         }
      }
      double ma20Buf[1], ma50Buf[1];
      if(CopyBuffer(ma20Handles[i], 0, 1, 1, ma20Buf) > 0 &&
         CopyBuffer(ma50Handles[i], 0, 1, 1, ma50Buf) > 0) {
         double ma20 = ma20Buf[0], ma50 = ma50Buf[0];
         if(ma20>0 && ma50>0) {
            double trend = 50 + ((ma20-ma50)/ma50)*100;
            trend = MathMax(0, MathMin(100, trend));
            trendSum[idxBase] += trend; trendCount[idxBase]++;
            trendSum[idxQuote] += (100 - trend); trendCount[idxQuote]++;
         }
      }
   }
   double rsiComp[8], momComp[8], trendComp[8];
   for(int i=0; i<8; i++) {
      rsiComp[i] = (rsiCount[i]>0) ? rsiSum[i]/rsiCount[i] : 50;
      momComp[i] = (momCount[i]>0) ? momSum[i]/momCount[i] : 50;
      trendComp[i] = (trendCount[i]>0) ? trendSum[i]/trendCount[i] : 50;
   }
   double priceChangeComp[8], totalChange[8]={0}; int changeCount[8]={0};
   for(int i=0; i<PairCount; i++) {
      string sym = Pairs[i].symbol;
      double close[2];
      if(CopyClose(sym, PERIOD_M1, 0, 2, close) >= 2) {
         double closeNow = close[0], closePast = close[1];
         if(closeNow<=0 || closePast<=0) continue;
         double percentChange = (closeNow - closePast) / closePast * 100.0;
         string clean = GetCleanSymbol(sym);
         if(StringLen(clean)<6) continue;
         string base = StringSubstr(clean,0,3), quote = StringSubstr(clean,3,3);
         int idxBase=-1, idxQuote=-1;
         for(int c=0;c<8;c++) {
            if(Currencies[c]==base) idxBase=c;
            if(Currencies[c]==quote) idxQuote=c;
         }
         if(idxBase!=-1) { totalChange[idxBase] += percentChange; changeCount[idxBase]++; }
         if(idxQuote!=-1) { totalChange[idxQuote] -= percentChange; changeCount[idxQuote]++; }
      }
   }
   double avgChange[8], sum=0;
   for(int i=0; i<8; i++) { avgChange[i] = (changeCount[i]>0) ? totalChange[i]/changeCount[i] : 0; sum += avgChange[i]; }
   double mean = sum/8.0, variance=0;
   for(int i=0; i<8; i++) variance += (avgChange[i]-mean)*(avgChange[i]-mean);
   double stdDev = MathSqrt(variance/8.0); if(stdDev<0.0001) stdDev=0.0001;
   for(int i=0; i<8; i++) {
      double z = (avgChange[i]-mean)/stdDev;
      priceChangeComp[i] = MathMax(0, MathMin(100, 50.0 + PriceChangeSensitivity * z));
   }
   double totalWeight = WeightRSI + WeightMomentum + WeightTrend + WeightPriceChange;
   if(totalWeight==0) totalWeight=1;
   for(int i=0; i<8; i++) {
      CurrencyStrength[i] = (rsiComp[i]*WeightRSI + momComp[i]*WeightMomentum + trendComp[i]*WeightTrend + priceChangeComp[i]*WeightPriceChange) / totalWeight;
      CurrencyStrength[i] = MathMax(0, MathMin(100, CurrencyStrength[i]));
   }
   CurrentStrongest=0; CurrentWeakest=0;
   for(int i=1;i<8;i++) {
      if(CurrencyStrength[i] > CurrencyStrength[CurrentStrongest]) CurrentStrongest=i;
      if(CurrencyStrength[i] < CurrencyStrength[CurrentWeakest]) CurrentWeakest=i;
   }
   CurrentGap = CurrencyStrength[CurrentStrongest] - CurrencyStrength[CurrentWeakest];
   CurrentPair = "";
   string strong = Currencies[CurrentStrongest], weak = Currencies[CurrentWeakest];
   for(int i=0; i<PairCount; i++) {
      string clean = GetCleanSymbol(Pairs[i].symbol);
      if(clean == strong+weak || clean == weak+strong) { CurrentPair = Pairs[i].symbol; break; }
   }
   if(CurrentPair=="") {
      for(int i=0; i<PairCount; i++) {
         if(StringFind(Pairs[i].symbol, strong)>=0 && StringFind(Pairs[i].symbol, weak)>=0) {
            CurrentPair = Pairs[i].symbol; break;
         }
      }
   }
    // +------------------------------------------------------------------+
   // | METALS STRENGTH CALCULATION (INSERT HERE)                         |
   // +------------------------------------------------------------------+
   MetalsStrength = 0.0;
   if(ShowMetalsStrength && MetalCount > 0) {
      double sum = 0.0;
      int valid = 0;
      for(int m = 0; m < MetalCount; m++) {
         double s = CalculateMetalStrength(MetalSymbols[m]);
         if(s > 0) {
            sum += s;
            valid++;
         }
      }
      if(valid > 0) MetalsStrength = sum / valid;
   }
}  // <-- FINAL CLOSING BRACE OF CalculateStrength()

double GetADX(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   int adxHandle = iADX(symbol, tf, period);
   if(adxHandle == INVALID_HANDLE) return 0.0;
   double adxBuf[1];
   if(CopyBuffer(adxHandle, 0, 0, 1, adxBuf) <= 0)
   {
      IndicatorRelease(adxHandle);
      return 0.0;
   }
   IndicatorRelease(adxHandle);
   return adxBuf[0];
}

double GetValidLotSize(string symbol, double requestedLot) {
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;
   double normLot = MathFloor(requestedLot / step) * step;
   if(normLot < minLot) normLot = minLot;
   if(normLot > maxLot) normLot = maxLot;
   int digits = (int)MathRound(-MathLog10(step));
   if(digits < 0) digits = 2;
   return NormalizeDouble(normLot, digits);
}

//+------------------------------------------------------------------+
//| Risk?based lot size: percent of balance scaled by SL distance      |
//| slPriceDist = absolute distance from entry to stop?loss (in price) |
//+------------------------------------------------------------------+
double GetRiskBasedLot(string symbol, double slPriceDist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(UseVirtualBalance && VirtualBalance > 0 && balance >= VirtualBalance)
      balance = VirtualBalance;
   
   if(balance <= 0 || slPriceDist <= 0) return 0.01;

   double riskAmount = balance * (RiskPercent / 100.0);
   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0 || tickValue <= 0)
      return 0.01;

   double slDistanceInTicks = slPriceDist / tickSize;
   double lot = riskAmount / (slDistanceInTicks * tickValue);

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)   step   = 0.01;
   if(minLot <= 0) minLot = 0.01;
   if(maxLot <= 0) maxLot = 100.0;

   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| 1H Candle Direction Check                                        |
//+------------------------------------------------------------------+
bool IsOneHourCandleBullish(string symbol)
{
   double open[1], close[1];
   if(CopyOpen(symbol, Timeframe, 1, 1, open) <= 0) return false;
   if(CopyClose(symbol, Timeframe, 1, 1, close) <= 0) return false;
   return (close[0] > open[0]);
}


//+------------------------------------------------------------------+
//| BO Swap Filter (direction + threshold)                           |
//+------------------------------------------------------------------+
bool IsSwapValidForBO(string symbol, ENUM_ORDER_TYPE type)
{
   double swapLong  = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   
   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT)
      return (swapLong > 0 && MathAbs(swapLong) >= SwapEntryAbsThreshold);
   else if(type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_LIMIT)
      return (swapShort > 0 && MathAbs(swapShort) >= SwapEntryAbsThreshold);
   return false;
}

//+------------------------------------------------------------------+
//| Daily Reset (24h block)                                          |
//+------------------------------------------------------------------+
datetime GetCurrentDailyBlockStart()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = DailyResetHour;
   dt.min = 0;
   dt.sec = 0;
   datetime blockStart = StructToTime(dt);
   if(now < blockStart)
      blockStart -= 86400;
  

   return blockStart;
}

//+------------------------------------------------------------------+
//| Perform the actual close/delete actions (used by pre-reset and   |
//| normal reset)                                                    |
//+------------------------------------------------------------------+
void PerformDailyCloseAndReset() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      // --- Swap trades: separate check with its own bypass ---
      if(StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") >= 0)
      {
         // Swap_DailyBypass = true → leave all swaps untouched
         if(Swap_DailyBypass)
            continue;

         if(DailyClose_SwapProfitPercent <= 0)
         {
            g_swapGroupLeaderTicket = 0;
            continue;
         }

         string sym = PositionGetString(POSITION_SYMBOL);
         ENUM_POSITION_TYPE swapType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double slPrice   = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double pipSize = GetPipSize(sym);

         double profitPips;
         if(swapType == POSITION_TYPE_BUY) profitPips = (bid - openPrice) / pipSize;
         else                              profitPips = (openPrice - ask) / pipSize;

         double slPips = 0;
         if(slPrice != 0 && pipSize > 0) {
            if(swapType == POSITION_TYPE_BUY) slPips = (openPrice - slPrice) / pipSize;
            else                              slPips = (slPrice - openPrice) / pipSize;
         }

         if(slPips <= 0) {
            if(VerboseLogging) Print("[DailyReset] Cannot compute SL distance for swap trade on ", sym, " – skipping close check.");
            continue;
         }

         double profitPercent = (profitPips / slPips) * 100.0;
         if(profitPercent >= DailyClose_SwapProfitPercent)
         {
            Trade.PositionClose(ticket);
            Log("[DailyReset] Closed swap trade on " + sym +
                " (profit=" + DoubleToString(profitPips,1) + " pips, " +
                DoubleToString(profitPercent,1) + "% of SL)", false);
         }
         continue;
      }

      // --- Non‑swap market orders: close normally ---
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY || type == POSITION_TYPE_SELL) {

         // Identify trade type via stored entryType (survives comment loss)
         int stored = GetEntryType(ticket);

         // BO reversal trades – per‑commodity bypass only
         if(stored == 3 || stored == 4 || stored == 5 || stored == 6 || stored == 8)
         {
            if(stored == 6 && Oil_DailyBypass)   continue;
            if(stored == 5 && Index_DailyBypass) continue;
            if(stored == 8 && BTC_DailyBypass)   continue;
            if(stored == 3 && ForexBO_DailyBypass) continue;
            if(stored == 4 && GoldBO_DailyBypass) continue;  
            // If none of the per‑commodity bypasses matched, the trade will fall through and be closed.
         }
         // Forex threshold trades
         else if(stored == 0)
         {
            if(ForexThreshold_DailyBypass) continue;
         }
         // Gold threshold trades
         else if(stored == 2)
         {
            if(GoldThreshold_DailyBypass) continue;
         }

         // Monday Special bypass (still uses comment)
         if(MondaySpecial_BypassDailyReset && StringFind(PositionGetString(POSITION_COMMENT), "Monday Special") >= 0)
            continue;

         // Optional: skip closing if candle direction agrees with trade
         if(DailyClose_SkipCandleAgrees)
         {
            string symClose = PositionGetString(POSITION_SYMBOL);
            bool candleBullish = IsOneHourCandleBullish(symClose);
            bool skipClose = false;
            if(type == POSITION_TYPE_BUY && candleBullish)   skipClose = true;
            if(type == POSITION_TYPE_SELL && !candleBullish) skipClose = true;
            if(skipClose) continue;
         }

         Trade.PositionClose(ticket);
         Log("[DailyReset] Closed market order on " + PositionGetString(POSITION_SYMBOL), false);
      }
   }

   // Delete pending orders (never delete swap pending orders)
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), "Swap Order") >= 0) continue;
      Trade.OrderDelete(ticket);
      Log("[DailyReset] Deleted pending order on " + OrderGetString(ORDER_SYMBOL), false);
   }

   // Reset BO reversal state and box display readiness
   for(int idx = 0; idx < boSymbolCount; idx++) {
      g_breakoutUp[idx]   = false;
      g_breakoutDown[idx] = false;
      swapFB_RVIBarTime[idx] = 0;
      boLastCandleTime[idx] = 0;
      boRevTradeAllowed[idx] = true;
      boPrevPeriodReady[idx] = false;
      rviLastBarTime[idx] = 0;
      g_swapSignalCandleTime[idx] = 0;
   }
}

//+------------------------------------------------------------------+
//| Remove SL from all surviving trades at the start of the pause     |
//+------------------------------------------------------------------+
void RemoveSLForSurvivingTrades()
{
   g_slBackupCount = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if(g_slBackupCount < 50)
      {
         g_slBackup[g_slBackupCount].ticket = ticket;
         g_slBackup[g_slBackupCount].originalSL = PositionGetDouble(POSITION_SL);
         g_slBackupCount++;
      }

      // Remove SL by setting it to 0 (TP remains unchanged)
      Trade.PositionModify(ticket, 0, PositionGetDouble(POSITION_TP));
   }
}

void RetryReapplySL()
{
   if(g_slBackupCount == 0) return;
   // Only try once every 30 seconds to avoid spamming the broker
   static datetime lastRetry = 0;
   if(TimeCurrent() - lastRetry < 30) return;
   lastRetry = TimeCurrent();
   ReapplySLForSurvivingTrades();
}

//+------------------------------------------------------------------+
//| Reapply the original SL after the pause ends                      |
//+------------------------------------------------------------------+
void ReapplySLForSurvivingTrades()
{
   for(int i = g_slBackupCount - 1; i >= 0; i--)
   {
      ulong ticket = g_slBackup[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         // Trade no longer exists – remove from backup
         g_slBackup[i] = g_slBackup[g_slBackupCount - 1];
         g_slBackupCount--;
         continue;
      }

      double sl = g_slBackup[i].originalSL;
      if(sl != 0)
      {
         if(Trade.PositionModify(ticket, sl, PositionGetDouble(POSITION_TP)))
         {
            // Success – remove from backup
            g_slBackup[i] = g_slBackup[g_slBackupCount - 1];
            g_slBackupCount--;
         }
         else
         {
            uint err = Trade.ResultRetcode();
            if(err == 10018) // Market closed – keep in backup for later
               continue;
            // Other errors – remove anyway to avoid endless loop
            Print("[Daily] Failed to reapply SL for ticket ", ticket, " error=", err);
            g_slBackup[i] = g_slBackup[g_slBackupCount - 1];
            g_slBackupCount--;
         }
      }
   }
}

void PerformFridayCloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      Trade.PositionClose(ticket);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      Trade.OrderDelete(ticket);
   }
   g_swapGroupLeaderTicket = 0;   // avoid orphan group logic
   Log("Friday close – all positions and orders removed.", true);
}

void CheckAndPerformDailyReset()
{
   if(!EnableDailyReset) return;
   
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // --- Compute today's close and resume datetimes ---
   dt.hour   = DailyCloseHour;
   dt.min    = DailyCloseMinute;
   dt.sec    = 0;
   datetime closeTime = StructToTime(dt);
   
   dt.hour   = DailyResumeHour;
   dt.min    = DailyResumeMinute;
   dt.sec    = 0;
   datetime resumeTime = StructToTime(dt);

   // Handle cases where resume is on the next day (e.g., close 23:00, resume 01:00)
   if(resumeTime <= closeTime)
      resumeTime += 86400;

   // --- If we haven't closed yet and we are inside the close window ---
   if(!g_dailyCloseDone && now >= closeTime && now < resumeTime)
   {
      MqlDateTime dtCheck;
      TimeToStruct(now, dtCheck);
      bool isFriday = (dtCheck.day_of_week == 5);

      if(isFriday)
      {
         Log("========== FRIDAY CLOSE (ALL TRADES) ==========", true);
         PerformFridayCloseAll();
      }
      else
      {
         Log("========== DAILY CLOSE (" + 
             IntegerToString(DailyCloseHour) + ":" + StringFormat("%02d", DailyCloseMinute) +
             " server) ==========", true);
         PerformDailyCloseAndReset();
      }
      
      // Start trading pause & store absolute resume time
      g_dailyResetPauseActive = true;
      g_dailyPauseStartTime = now;
      g_dailyCloseDone = true;
      RemoveSLForSurvivingTrades();

      // Calculate absolute resume time ONCE (handles midnight crossing)
      MqlDateTime dtResume;
      TimeToStruct(now, dtResume);
      dtResume.hour = DailyResumeHour;
      dtResume.min  = DailyResumeMinute;
      dtResume.sec  = 0;
      g_dailyResumeTime = StructToTime(dtResume);
      if(g_dailyResumeTime <= now)
         g_dailyResumeTime += 86400;

      Log("Trading paused until " + TimeToString(g_dailyResumeTime, TIME_DATE|TIME_MINUTES), true);
   }
   
   // --- Keep trading paused until the stored absolute resume time ---
   if(g_dailyResetPauseActive)
   {
      if(now >= g_dailyResumeTime)
      {
         g_dailyResetPauseActive = false;
         g_dailyResumeTime = 0;
         Log("Trading pause ended. Trading resumed.", true);
         ReapplySLForSurvivingTrades();
      }
   }
   // --- Reset the daily close flag and daily counts when a new block starts ---
   datetime currentBlockStart = GetCurrentDailyBlockStart();
   if(currentBlockStart > g_currentDailyBlockStart)
   {
      g_currentDailyBlockStart = currentBlockStart;
      datetime nextReset = currentBlockStart + 86400;
      g_nextDailyResetStr = TimeToString(nextReset, TIME_DATE);
      
      g_dailyCloseDone = false;
      g_dailyLenientSwapDone = false;
      DailyTradeCount_Reset();
      g_profitStopTrading = false;
      
      if(!(g_jpyBlockTriggeredToday && TimeCurrent() < g_tokyoPauseEndTime))
         g_allTradingPaused = false;
      g_jpyBlockTriggeredToday = false; 
      
      BO_LoadAllPreviousPeriodLevels();
      
      Log("New daily block started. Next reset at: " + g_nextDailyResetStr, true);
   }
   
   // Edge case: if we are past resume but pause is still active, clear it
   if(now >= resumeTime && g_dailyResetPauseActive)
      g_dailyResetPauseActive = false;
}

//+------------------------------------------------------------------+
//| Threshold Swap Filter (same as BO: positive & >= threshold)       |
//+------------------------------------------------------------------+
bool IsSwapValidForThreshold(string symbol, ENUM_ORDER_TYPE type)
{
   double swapLong  = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   
   if(type == ORDER_TYPE_BUY)
      return (swapLong > 0 && MathAbs(swapLong) >= SwapEntryAbsThreshold);
   else if(type == ORDER_TYPE_SELL)
      return (swapShort > 0 && MathAbs(swapShort) >= SwapEntryAbsThreshold);
   return false;
}

//+------------------------------------------------------------------+
//| Gold Swap Filter – only take trade if our swap >= opposite swap   |
//+------------------------------------------------------------------+
bool IsSwapValidForGold(string symbol, ENUM_ORDER_TYPE type)
{
   double swapLong  = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
   double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
   
   if(type == ORDER_TYPE_BUY)
      return (swapLong >= swapShort);
   else if(type == ORDER_TYPE_SELL)
      return (swapShort >= swapLong);
   return false;
}


//+------------------------------------------------------------------+
//| ENTRY ALLOWED (Forex)                                            |
//+------------------------------------------------------------------+
bool IsEntryAllowed() {
   if(g_profitStopTrading) return false;
   if(g_allTradingPaused) return false;
   if(g_dailyResetPauseActive) return false;
   if(!EnableTrading) return false;
   if(!EnableThresholdTrading) return false;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return false;
   if(CountForexTrades() >= MaxForexTrades) return false;
   if(CurrentPair == "") return false;
   if(!IsSymbolValidForTrading(CurrentPair)) return false;
   if(GetCurrentSpread(CurrentPair) > MaxSpreadPips) return false;
   if(CurrencyStrength[CurrentStrongest] < StrongEntryThreshold || CurrencyStrength[CurrentWeakest] > WeakEntryThreshold || CurrentGap < MinGapEntry) return false;
   
   if(UseOneHourCandleFilter)
   {
      int dir = GetTradeDirection();
      bool candleBullish = IsOneHourCandleBullish(CurrentPair);
      
      if(ReverseTrades)
      {
         if(dir == ORDER_TYPE_BUY && candleBullish)   return false;
         if(dir == ORDER_TYPE_SELL && !candleBullish) return false;
      }
      else
      {
         if(dir == ORDER_TYPE_BUY && !candleBullish) return false;
         if(dir == ORDER_TYPE_SELL && candleBullish) return false;
      }
   }
   
      // --- Swap Filter for Threshold Entries ---
   if(Threshold_UseSwapFilter)
   {
      int dir = GetTradeDirection();
      if(!IsSwapValidForThreshold(CurrentPair, (ENUM_ORDER_TYPE)dir))
      {
         if(VerboseLogging) Print("[Threshold] ", CurrentPair, " rejected: Swap filter failed.");
         return false;
      }
   }
   return true;
}

int GetTradeDirection() {
   if(CurrentPair == "") return -1;
   string clean = GetCleanSymbol(CurrentPair);
   bool normalBuy = (StringFind(clean, Currencies[CurrentStrongest]) == 0);
   if(ReverseTrades) return normalBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   return normalBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}


//+------------------------------------------------------------------+
//| Gold Entry Allowed (Unified Thresholds – Metals + USD) - MT5      |
//+------------------------------------------------------------------+
bool IsGoldEntryAllowed(int &direction) {
   if(g_profitStopTrading) return false;
   if(g_allTradingPaused) return false;
   if(g_dailyResetPauseActive) return false;
   if(!EnableTrading) return false;
   if(!EnableThresholdTrading) return false;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return false;
   if(!TradeGold || !GoldTradeAllowed) return false;
   if(CountGoldTrades() >= MaxGoldTrades) return false;
   if(!IsSymbolValidForTrading(GoldSymbol)) return false;
   if(GetCurrentSpread(GoldSymbol) > MaxSpreadAU) return false;
   
   // --- Strengths ---
   double metals = MetalsStrength;
   double usd    = CurrencyStrength[0];  // USD is index 0
   
   // --- BUY signal: Metals strong AND USD weak ---
   bool metalsStrong = (metals >= StrongEntryThreshold);
   bool usdWeak      = (usd <= WeakEntryThreshold);
   bool buySignal    = (metalsStrong && usdWeak);
   
   // --- SELL signal: Metals weak AND USD strong ---
   bool metalsWeak   = (metals <= WeakEntryThreshold);
   bool usdStrong    = (usd >= StrongEntryThreshold);
   bool sellSignal   = (metalsWeak && usdStrong);
   
   if(!buySignal && !sellSignal) return false;
   
   // Apply ReverseTrades
   if(ReverseTrades) {
      if(buySignal)      direction = ORDER_TYPE_SELL;
      else if(sellSignal) direction = ORDER_TYPE_BUY;
      else return false;
   } else {
      if(buySignal)      direction = ORDER_TYPE_BUY;
      else if(sellSignal) direction = ORDER_TYPE_SELL;
      else return false;
   }
   
   // 1H Candle Filter
   if(UseOneHourCandleFilter) {
      bool candleBullish = IsOneHourCandleBullish(GoldSymbol);
      if(ReverseTrades) {
         if(direction == ORDER_TYPE_BUY && candleBullish)   return false;
         if(direction == ORDER_TYPE_SELL && !candleBullish) return false;
      } else {
         if(direction == ORDER_TYPE_BUY && !candleBullish) return false;
         if(direction == ORDER_TYPE_SELL && candleBullish) return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trade Execution with retry – no halving on error 10019            |
//+------------------------------------------------------------------+
bool RetryPositionOpen(string symbol, ENUM_ORDER_TYPE cmd, double volume, double price, double sl, double tp, string comment, int maxRetries = 5) {
   int digits = GetDigits(symbol);

   for(int attempt = 0; attempt < maxRetries; attempt++) {
      if(cmd == ORDER_TYPE_BUY)  price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(cmd == ORDER_TYPE_SELL) price = SymbolInfoDouble(symbol, SYMBOL_BID);
      price = NormalizeDouble(price, digits);
      
      Trade.SetExpertMagicNumber(MagicNumber);
      double sendSL = sl, sendTP = tp;
      if(PostEntrySLTP) { sendSL = 0; sendTP = 0; }
      
      if(!Trade.PositionOpen(symbol, cmd, volume, price, sendSL, sendTP, comment)) {
         uint err = Trade.ResultRetcode();
         
         // If error 10019 (insufficient margin) or other unrecoverable errors, skip the trade.
         if(err == 10019) {
            Log(StringFormat("[ERROR] Insufficient margin on %s. Skipping trade.", symbol), true);
            return false;
         }
         // Temporary errors – retry after delay
         if(err == 10004 || err == 10008) { Sleep(100); continue; }
         
         if(attempt == 0) Log("PositionOpen error on " + symbol + " (cmd " + EnumToString(cmd) + "): " + IntegerToString((long)err), true);
         return false;
      }
      
      ulong ticket = Trade.ResultOrder();
      if(ticket > 0) {
         if(PostEntrySLTP && (sl != 0 || tp != 0)) {
            Sleep(50);
            double modSL = (sl != 0) ? NormalizeDouble(sl, digits) : 0;
            double modTP = (tp != 0) ? NormalizeDouble(tp, digits) : 0;
            for(int retry = 0; retry < 3; retry++) {
               if(Trade.PositionModify(ticket, modSL, modTP)) {
                  Log("Post-entry SL/TP set for ticket " + IntegerToString(ticket), false);
                  break;
               }
               uint err = Trade.ResultRetcode();
               if(err == 10004 || err == 10008) { Sleep(50); continue; }
               Log("Failed to set post-entry SL/TP for ticket " + IntegerToString(ticket) + ". Error: " + IntegerToString((long)err), true);
               break;
            }
         }
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Index RVI Crossover Mode (replaces block breakout)                |
//+------------------------------------------------------------------+
void CheckIndicesRVIMode()
{
   if(!EnableIndexTrading) return;
   if(!IsTradingHourAllowed()) return;
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(g_profitStopTrading) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   for(int i = 0; i < indexSymbolCount && i < 50; i++)
   {
      string sym = indexSymbols[i];
      if(!IsSymbolValidForTrading(sym)) continue;
      if(GetCurrentSpread(sym) > MaxSpreadIndices) continue;
      if(CountIndexTrades() >= MaxIndexTrades) continue;

      int boIdx = g_indexBoIndex[i];
      if(boIdx < 0 || !boRevAvgComputed[boIdx]) continue;

      double avg = boRevAvg[boIdx];
      double threshold = avg * BO_RevCandleMultiplier;
      double point = GetSymbolPoint(sym);

      // --- Immediate entry mode ---
      if(BO_RevImmediateEntry)
      {
         datetime currentCandleTime = iTime(sym, Timeframe, 0);
         if(currentCandleTime == 0) continue;
         if(currentCandleTime != boLastCandleTime[boIdx])
         {
            boLastCandleTime[boIdx] = currentCandleTime;
            boRevTradeAllowed[boIdx] = true;
         }
         if(!boRevTradeAllowed[boIdx]) continue;

         double highArr[], lowArr[], openArr[];
         if(CopyHigh(sym, Timeframe, 0, 1, highArr) != 1) continue;
         if(CopyLow(sym, Timeframe, 0, 1, lowArr)  != 1) continue;
         if(CopyOpen(sym, Timeframe, 0, 1, openArr) != 1) continue;
         double rangePoints = (highArr[0] - lowArr[0]) / point;
         double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 0, BO_MultiCandleLookback) : 0.0;
         if(rangePoints >= threshold || multiRange >= threshold)
         {
            double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            int dir = (bid > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) continue;
            if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  continue;

            if(CountIndexTrades() < MaxIndexTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
            {
               boRevTradeAllowed[boIdx] = false;
               if(!g_allTradingPaused)
                  OpenBOCommodityTrade(sym, dir, false, 5);   // entryType 5 = Index
            }
         }
      }
      else   // Close‑confirm mode
      {
         datetime currentCandleTime = iTime(sym, Timeframe, 0);
         if(currentCandleTime == 0) continue;
         if(currentCandleTime != boLastCandleTime[boIdx])
         {
            boLastCandleTime[boIdx] = currentCandleTime;
            double openArr[], highArr[], lowArr[], closeArr[];
            if(CopyOpen(sym, Timeframe, 1, 1, openArr)  != 1) continue;
            if(CopyHigh(sym, Timeframe, 1, 1, highArr)  != 1) continue;
            if(CopyLow(sym, Timeframe, 1, 1, lowArr)    != 1) continue;
            if(CopyClose(sym, Timeframe, 1, 1, closeArr) != 1) continue;
            double rangePoints = (highArr[0] - lowArr[0]) / point;
            double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 1, BO_MultiCandleLookback) : 0.0;
            if(rangePoints >= threshold || multiRange >= threshold)
            {
               if(BO_RevMinBodyPercent > 0)
               {
                  double bodyPoints = MathAbs(closeArr[0] - openArr[0]) / point;
                  double minBodyPoints = rangePoints * (BO_RevMinBodyPercent / 100.0);
                  if(bodyPoints < minBodyPoints) continue;
               }
               int dir = (closeArr[0] > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

               if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) continue;
               if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  continue;

               if(CountIndexTrades() < MaxIndexTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
               {
                  if(!g_allTradingPaused)
                     OpenBOCommodityTrade(sym, dir, false, 5);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| BTC RVI Crossover Mode             |
//+------------------------------------------------------------------+
void CheckBTCRVIMode()
{
   if(!TradeBitcoin) return;
   if(!IsTradingHourAllowed()) return;
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(g_profitStopTrading) return;
   if(!BTCTradeAllowed) return;
   if(GetCurrentSpread(BTCSymbol) > MaxSpreadBTC) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   if(g_btcBoIndex < 0 || !boRevAvgComputed[g_btcBoIndex]) return;

   string sym = BTCSymbol;
   double avg = boRevAvg[g_btcBoIndex];
   double threshold = avg * BO_RevCandleMultiplier;
   double point = GetSymbolPoint(sym);

   if(BO_RevImmediateEntry)
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_btcBoIndex])
      {
         boLastCandleTime[g_btcBoIndex] = currentCandleTime;
         boRevTradeAllowed[g_btcBoIndex] = true;
      }
      if(!boRevTradeAllowed[g_btcBoIndex]) return;

      double highArr[], lowArr[], openArr[];
      if(CopyHigh(sym, Timeframe, 0, 1, highArr) != 1) return;
      if(CopyLow(sym, Timeframe, 0, 1, lowArr)  != 1) return;
      if(CopyOpen(sym, Timeframe, 0, 1, openArr) != 1) return;
      double rangePoints = (highArr[0] - lowArr[0]) / point;
      double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 0, BO_MultiCandleLookback) : 0.0;
      if(rangePoints >= threshold || multiRange >= threshold)
      {
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         int dir = (bid > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

         if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
         if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;

         if(CountBTCTrades() < MaxBitcoinTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
         {
            boRevTradeAllowed[g_btcBoIndex] = false;
            if(!g_allTradingPaused)
               OpenBOCommodityTrade(sym, dir, false, 8);
         }
      }
   }
   else   // Close‑confirm mode
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_btcBoIndex])
      {
         boLastCandleTime[g_btcBoIndex] = currentCandleTime;
         double openArr[], highArr[], lowArr[], closeArr[];
         if(CopyOpen(sym, Timeframe, 1, 1, openArr)  != 1) return;
         if(CopyHigh(sym, Timeframe, 1, 1, highArr)  != 1) return;
         if(CopyLow(sym, Timeframe, 1, 1, lowArr)    != 1) return;
         if(CopyClose(sym, Timeframe, 1, 1, closeArr) != 1) return;
         double rangePoints = (highArr[0] - lowArr[0]) / point;
         double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 1, BO_MultiCandleLookback) : 0.0;
         if(rangePoints >= threshold || multiRange >= threshold)
         {
            if(BO_RevMinBodyPercent > 0)
            {
               double bodyPoints = MathAbs(closeArr[0] - openArr[0]) / point;
               double minBodyPoints = rangePoints * (BO_RevMinBodyPercent / 100.0);
               if(bodyPoints < minBodyPoints) return;
            }
            int dir = (closeArr[0] > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
            if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;

            if(CountBTCTrades() < MaxBitcoinTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
            {
               if(!g_allTradingPaused)
                  OpenBOCommodityTrade(sym, dir, false, 8);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Gold RVI Crossover Mode (replaces old 24h block breakout)        |
//+------------------------------------------------------------------+
void CheckGoldRVIMode()
{
   if(!TradeGold) return;
   if(!IsTradingHourAllowed()) return;
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(g_profitStopTrading) return;
   if(!GoldTradeAllowed) return;
   if(GetCurrentSpread(GoldSymbol) > MaxSpreadAU) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   if(g_goldBoIndex < 0 || !boRevAvgComputed[g_goldBoIndex]) return;

   string sym = GoldSymbol;
   double avg = boRevAvg[g_goldBoIndex];
   double threshold = avg * BO_RevCandleMultiplier;
   double point = GetSymbolPoint(sym);

   // --- Immediate entry mode ---
   if(BO_RevImmediateEntry)
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_goldBoIndex])
      {
         boLastCandleTime[g_goldBoIndex] = currentCandleTime;
         boRevTradeAllowed[g_goldBoIndex] = true;
      }
      if(!boRevTradeAllowed[g_goldBoIndex]) return;

      double highArr[], lowArr[], openArr[];
      if(CopyHigh(sym, Timeframe, 0, 1, highArr) != 1) return;
      if(CopyLow(sym, Timeframe, 0, 1, lowArr)  != 1) return;
      if(CopyOpen(sym, Timeframe, 0, 1, openArr) != 1) return;
      double rangePoints = (highArr[0] - lowArr[0]) / point;
      double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 0, BO_MultiCandleLookback) : 0.0;
      if(rangePoints >= threshold || multiRange >= threshold)
      {
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         int dir = (bid > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

         if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
         if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;


         if(CountBOGoldTrades() < MaxBOGoldTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
         {
            boRevTradeAllowed[g_goldBoIndex] = false;
            if(!g_allTradingPaused)
               OpenBOTrade(sym, dir, true);
         }
      }
   }
   else   // Close‑confirm mode
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_goldBoIndex])
      {
         boLastCandleTime[g_goldBoIndex] = currentCandleTime;
         double openArr[], highArr[], lowArr[], closeArr[];
         if(CopyOpen(sym, Timeframe, 1, 1, openArr)  != 1) return;
         if(CopyHigh(sym, Timeframe, 1, 1, highArr)  != 1) return;
         if(CopyLow(sym, Timeframe, 1, 1, lowArr)    != 1) return;
         if(CopyClose(sym, Timeframe, 1, 1, closeArr) != 1) return;
         double rangePoints = (highArr[0] - lowArr[0]) / point;
         double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 1, BO_MultiCandleLookback) : 0.0;
         if(rangePoints >= threshold || multiRange >= threshold)
         {
            if(BO_RevMinBodyPercent > 0)
            {
               double bodyPoints = MathAbs(closeArr[0] - openArr[0]) / point;
               double minBodyPoints = rangePoints * (BO_RevMinBodyPercent / 100.0);
               if(bodyPoints < minBodyPoints) return;
            }
            int dir = (closeArr[0] > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
            if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;

            if(CountBOGoldTrades() < MaxBOGoldTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
            {
               if(!g_allTradingPaused)
                  OpenBOTrade(sym, dir, true);
            }
         }
      }
   }
}

void CheckOilRVIMode()
{
   if(!TradeOil) return;
   if(!IsTradingHourAllowed()) return;
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(g_profitStopTrading) return;
   if(!OilTradeAllowed) return;
   if(GetCurrentSpread(OilSymbol) > MaxSpreadOil) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   if(g_oilBoIndex < 0 || !boRevAvgComputed[g_oilBoIndex]) return;

   string sym = OilSymbol;
   double avg = boRevAvg[g_oilBoIndex];
   double threshold = avg * BO_RevCandleMultiplier;
   double point = GetSymbolPoint(sym);

   if(BO_RevImmediateEntry)
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_oilBoIndex])
      {
         boLastCandleTime[g_oilBoIndex] = currentCandleTime;
         boRevTradeAllowed[g_oilBoIndex] = true;
      }
      if(!boRevTradeAllowed[g_oilBoIndex]) return;

      double highArr[], lowArr[], openArr[];
      if(CopyHigh(sym, Timeframe, 0, 1, highArr) != 1) return;
      if(CopyLow(sym, Timeframe, 0, 1, lowArr)  != 1) return;
      if(CopyOpen(sym, Timeframe, 0, 1, openArr) != 1) return;
      double rangePoints = (highArr[0] - lowArr[0]) / point;
      double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 0, BO_MultiCandleLookback) : 0.0;
      if(rangePoints >= threshold || multiRange >= threshold)
      {
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         int dir = (bid > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

         if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
         if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;

         if(CountOilTrades() < MaxOilTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
         {
            boRevTradeAllowed[g_oilBoIndex] = false;
            if(!g_allTradingPaused)
            {
               // Open as an oil-specific BO trade (entryType = 6)
               OpenBOCommodityTrade(sym, dir, false, 6);
            }
         }
      }
   }
   else   // Close‑confirm mode
   {
      datetime currentCandleTime = iTime(sym, Timeframe, 0);
      if(currentCandleTime == 0) return;
      if(currentCandleTime != boLastCandleTime[g_oilBoIndex])
      {
         boLastCandleTime[g_oilBoIndex] = currentCandleTime;
         double openArr[], highArr[], lowArr[], closeArr[];
         if(CopyOpen(sym, Timeframe, 1, 1, openArr)  != 1) return;
         if(CopyHigh(sym, Timeframe, 1, 1, highArr)  != 1) return;
         if(CopyLow(sym, Timeframe, 1, 1, lowArr)    != 1) return;
         if(CopyClose(sym, Timeframe, 1, 1, closeArr) != 1) return;
         double rangePoints = (highArr[0] - lowArr[0]) / point;
         double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(sym, 1, BO_MultiCandleLookback) : 0.0;
         if(rangePoints >= threshold || multiRange >= threshold)
         {
            if(BO_RevMinBodyPercent > 0)
            {
               double bodyPoints = MathAbs(closeArr[0] - openArr[0]) / point;
               double minBodyPoints = rangePoints * (BO_RevMinBodyPercent / 100.0);
               if(bodyPoints < minBodyPoints) return;
            }
            int dir = (closeArr[0] > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
            if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;

            if(CountOilTrades() < MaxOilTrades && CountTradesForSymbol(sym) < GlobalMaxTradesPerSymbol)
            {
               if(!g_allTradingPaused)
                  OpenBOCommodityTrade(sym, dir, false, 6);
            }
         }
      }
   }
}

void OpenGoldTrade(int dir) {
   if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return;
   if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return;
   
   if(CountTradesForSymbol(GoldSymbol) >= GlobalMaxTradesPerSymbol)
   {
      if(VerboseLogging) Print("[GOLD] ", GoldSymbol, " already has max positions. Skipping.");
      return;
   }
   int digits = GetDigits(GoldSymbol);
   double entry = (dir==ORDER_TYPE_BUY) ? SymbolInfoDouble(GoldSymbol, SYMBOL_ASK) : SymbolInfoDouble(GoldSymbol, SYMBOL_BID);
   entry = NormalizeDouble(entry, digits);
   
   double pipSize = 1.0;
   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(GoldSymbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : GlobalSL_Pips * GoldPipMultiplier * pipSize;
   }
   else
      slPriceDist = GlobalSL_Pips * GoldPipMultiplier * pipSize;
   double lotSize = GetRiskBasedLot(GoldSymbol, slPriceDist);
   double validLot = GetValidLotSize(GoldSymbol, lotSize);
   
   double tpPriceDist = slPriceDist * TP_Multiplier;
   
   double spread = SymbolInfoDouble(GoldSymbol, SYMBOL_ASK) - SymbolInfoDouble(GoldSymbol, SYMBOL_BID);
   double sl=0, tp=0;
   if(dir==ORDER_TYPE_BUY) { sl = entry - slPriceDist; tp = entry + tpPriceDist + spread; }
   else                    { sl = entry + slPriceDist; tp = entry - tpPriceDist - spread; }
   sl = NormalizeDouble(sl, digits); tp = NormalizeDouble(tp, digits);
   
   if(DailyTradeCount_Get(GoldSymbol) >= MaxDailyTradesPerSymbol) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;
   if(!IsTradingHourAllowed()) return;   // or continue if inside a loop
   if(RetryPositionOpen(GoldSymbol, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, "Threshold Order")) {
      ulong ticket = Trade.ResultOrder();
      
      SetEntryType(ticket, 2);   // gold threshold      

      DailyTradeCount_Increment(GoldSymbol);
           
      Log(StringFormat("[GOLD] XAUUSD | %s | Lot=%.2f | Entry=%.2f | SL=%.2f | TP=%.2f | Reason: Metals=%.1f%% / USD=%.1f%%",
                       (dir==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       validLot, entry, sl, tp,
                       MetalsStrength, CurrencyStrength[0]), true);
      
      DynamicStatus = "Gold order accepted";
      LastTradeTime = TimeCurrent();
      if(TradeCount < 50) {
         Trades[TradeCount].ticket = ticket;
         Trades[TradeCount].openPrice = entry;
         Trades[TradeCount].entryDiff = CurrencyStrength[0];
         Trades[TradeCount].openTime = TimeCurrent();
         Trades[TradeCount].currentSL = sl;
         Trades[TradeCount].pairSymbol = GoldSymbol;
         Trades[TradeCount].isGold = true;
         Trades[TradeCount].entryType = 2;
         Trades[TradeCount].lastTrailStep = 0;
         Trades[TradeCount].isBO = false;
         Trades[TradeCount].lastTrailPrice = entry;
         Trades[TradeCount].lastTrailTime = TimeCurrent();
         Trades[TradeCount].partialDone = false;
         Trades[TradeCount].lastPartialTime = 0;

         // NEW multi?tier fields – BEFORE increment
         Trades[TradeCount].originalLot     = validLot;
         Trades[TradeCount].partial25Done   = false;
         Trades[TradeCount].partial50Done   = false;
         Trades[TradeCount].partial75Done   = false;

         TradeCount++;
         if(ShowDashboard) UpdateDashboard();
      }
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
   } else { DynamicStatus = "Gold order failed"; if(ShowDashboard) UpdateDashboard(); }
}

void OpenTradeConfirmed(string symbol, int dir, double entryPrice) {
   if(CountTradesForSymbol(symbol) >= GlobalMaxTradesPerSymbol)
   {
      if(VerboseLogging) Print("[TRADE-1H] ", symbol, " already has max positions. Skipping.");
      return;
   }
   int digits = GetDigits(symbol);
   double entry = entryPrice;
   entry = NormalizeDouble(entry, digits);

   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize : GetPipSize(symbol);
   bool isGold = (StringFind(symbol, "XAU")>=0 || StringFind(symbol, "GOLD")>=0);
   if(isGold) pipSize = 1.0;

   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(symbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : (isGold ? GlobalSL_Pips * GoldPipMultiplier : GlobalSL_Pips) * pipSize;
   }
   else
   {
      double slPips = GlobalSL_Pips;
      if(isGold) slPips *= GoldPipMultiplier;
      slPriceDist = slPips * pipSize;
   }
   
   double lotSize = GetRiskBasedLot(symbol, slPriceDist);
   double validLot = GetValidLotSize(symbol, lotSize);
   
   double tpPriceDist = slPriceDist * TP_Multiplier;
   
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl=0, tp=0;
   if(dir==ORDER_TYPE_BUY) { sl = entry - slPriceDist; tp = entry + tpPriceDist + spread; }
   else                    { sl = entry + slPriceDist; tp = entry - tpPriceDist - spread; }
   sl = NormalizeDouble(sl, digits); tp = NormalizeDouble(tp, digits);

   if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;
   if(!IsTradingHourAllowed()) return;   // or continue if inside a loop
   if(RetryPositionOpen(symbol, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, "Threshold Order")) {
      ulong ticket = Trade.ResultOrder();
     
      SetEntryType(ticket, isGold ? 2 : 0);   // gold threshold or forex
      
      DailyTradeCount_Increment(symbol);
      
      Log(StringFormat("[TRADE-1H] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | Reason: 1H close confirmation (gap=%.1f%%, %s vs %s)",
                       symbol,
                       (dir==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       validLot, entry, sl, tp,
                       CurrentGap, Currencies[CurrentStrongest], Currencies[CurrentWeakest]), true);
      
      DynamicStatus = "Order accepted";
      LastTradeTime = TimeCurrent();
      if(TradeCount < 50) {
         Trades[TradeCount].ticket     = ticket;
         Trades[TradeCount].openPrice  = entry;
         Trades[TradeCount].entryDiff  = (isGold ? CurrencyStrength[0] : CurrentGap);
         Trades[TradeCount].openTime   = TimeCurrent();
         Trades[TradeCount].currentSL  = sl;
         Trades[TradeCount].pairSymbol = symbol;
         Trades[TradeCount].isGold     = isGold;
         Trades[TradeCount].entryType  = 0;
         Trades[TradeCount].lastTrailStep = 0;
         Trades[TradeCount].isBO       = false;
         Trades[TradeCount].lastTrailPrice = entry;
         Trades[TradeCount].lastTrailTime  = TimeCurrent();
         Trades[TradeCount].partialDone    = false;
         Trades[TradeCount].lastPartialTime = 0;

         // NEW multi?tier fields – BEFORE increment
         Trades[TradeCount].originalLot     = validLot;
         Trades[TradeCount].partial25Done   = false;
         Trades[TradeCount].partial50Done   = false;
         Trades[TradeCount].partial75Done   = false;

         TradeCount++;
         if(ShowDashboard) UpdateDashboard();
      }
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
   } else { DynamicStatus = "Order failed"; if(ShowDashboard) UpdateDashboard(); }
}

void OpenTrade() {
   int dir = GetTradeDirection();
   if(dir == -1) return;
   string symbol = CurrentPair;
   // Check global per-symbol limit
   if(CountTradesForSymbol(symbol) >= GlobalMaxTradesPerSymbol)
   {
      if(VerboseLogging) Print("[TRADE] ", symbol, " already has max positions (", GlobalMaxTradesPerSymbol, "). Skipping.");
      return;
   }
   int digits = GetDigits(symbol);
   double entry = (dir==ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   entry = NormalizeDouble(entry, digits);
   
   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize : GetPipSize(symbol);
   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(symbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : GlobalSL_Pips * pipSize;   // fallback if ATR fails
   }
   else
      slPriceDist = GlobalSL_Pips * pipSize;
   
   double lotSize = GetRiskBasedLot(symbol, slPriceDist);
   double validLot = GetValidLotSize(symbol, lotSize);
   
   double tpPriceDist = slPriceDist * TP_Multiplier;
   
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl=0, tp=0;
   if(dir==ORDER_TYPE_BUY) { sl = entry - slPriceDist; tp = entry + tpPriceDist + spread; }
   else                    { sl = entry + slPriceDist; tp = entry - tpPriceDist - spread; }
   sl = NormalizeDouble(sl, digits); tp = NormalizeDouble(tp, digits);
   
   if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;
   
   if(!IsTradingHourAllowed()) return;   // or continue if inside a loop
   
   if(RetryPositionOpen(symbol, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, "Threshold Order")) {
      ulong ticket = Trade.ResultOrder();
      
      SetEntryType(ticket, 0);   // forex threshold
      
      DailyTradeCount_Increment(symbol);
      
      // --- NEW LOG ---
      Log(StringFormat("[TRADE] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | Reason: Threshold (gap=%.1f%%, %s vs %s)",
                       symbol,
                       (dir==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       validLot, entry, sl, tp,
                       CurrentGap, Currencies[CurrentStrongest], Currencies[CurrentWeakest]), true);
      
      DynamicStatus = "Order accepted";
      LastTradeTime = TimeCurrent();
      TradeReady = false;
      if(TradeCount < 50) {
         Trades[TradeCount].ticket         = ticket;
         Trades[TradeCount].openPrice      = entry;
         Trades[TradeCount].entryDiff      = CurrentGap;
         Trades[TradeCount].openTime       = TimeCurrent();
         Trades[TradeCount].currentSL      = sl;
         Trades[TradeCount].pairSymbol     = symbol;
         Trades[TradeCount].isGold         = false;
         Trades[TradeCount].entryType      = 0;
         Trades[TradeCount].lastTrailStep  = 0;
         Trades[TradeCount].isBO           = false;
         Trades[TradeCount].lastTrailPrice = entry;
         Trades[TradeCount].lastTrailTime  = TimeCurrent();
         Trades[TradeCount].partialDone    = false;
         Trades[TradeCount].lastPartialTime = 0;
   
         // NEW multi?tier fields – added BEFORE the increment
         Trades[TradeCount].originalLot    = validLot;
         Trades[TradeCount].partial25Done  = false;
         Trades[TradeCount].partial50Done  = false;
         Trades[TradeCount].partial75Done  = false;
   
         TradeCount++;   // only ONE increment, AFTER all fields
         if(ShowDashboard) UpdateDashboard();
      }
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
   } else { DynamicStatus = "Order failed"; if(ShowDashboard) UpdateDashboard(); }
}

//+------------------------------------------------------------------+
//| BO MODE FUNCTIONS (High/Low Breakout + Re-Entry)                 |
//+------------------------------------------------------------------+
void BO_InitializeSymbols() {

   for(int i=0; i < boSymbolCount; i++) {
      g_breakoutUp[i]   = false;
      g_breakoutDown[i] = false;
      boPrevPeriodHigh[i] = 0;
      boPrevPeriodLow[i] = 999999;
      boPrevPeriodReady[i] = false;
      boOrdersPlaced[i] = false;
      SwapBuyTicket[i] = 0;
      SwapSellTicket[i] = 0;
      SwapBuyOpenTime[i] = 0;
      SwapSellOpenTime[i] = 0;
      boRevAvg[i] = 0;
      boRevAvgComputed[i] = false;
      boLastCandleTime[i] = 0;
      boRevTradeAllowed[i] = true;
      rviLastBarTime[i] = 0;               // <<< ADDED: initialise RVI last bar time
      g_lastBORevCalc = TimeCurrent();
   }
   for(int i=0; i<boSymbolCount; i++) {
      if(BO_UseReversalEntry) {
         boRevAvg[i] = ComputeBOReversalAverage(boSymbols[i]);
         boRevAvgComputed[i] = (boRevAvg[i] > 0);
         Print("[BO-Rev] ", boSymbols[i],
               " reversal avg=", DoubleToString(boRevAvg[i], 1), " pts",
               " | Threshold=", DoubleToString(boRevAvg[i] * BO_RevCandleMultiplier, 1), " pts");
      }
   }
}

void BO_LoadPreviousPeriodLevelsForSymbol(int idx) {
   string symbol = boSymbols[idx];
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int currentBlockHour = (dt.hour / BlockHours) * BlockHours;
   dt.hour = currentBlockHour; dt.min = 0; dt.sec = 0;
   datetime currentBlockStart = StructToTime(dt);
   datetime prevBlockStart = currentBlockStart - BlockHours * 3600;
   datetime prevBlockEnd   = currentBlockStart;
   double boxHigh = -1, boxLow = 1e9; bool found = false;
   ENUM_TIMEFRAMES tf = Timeframe;
   int startBar = GetBarShift(symbol, tf, prevBlockStart, false);
   int endBar   = GetBarShift(symbol, tf, prevBlockEnd, false);
   if(startBar < 0) startBar = 0; if(endBar < 0) endBar = 0;
   if(startBar > endBar) { int tmp = startBar; startBar = endBar; endBar = tmp; }
   for(int i = startBar; i <= endBar; i++) {
      datetime timeArray[1];
      if(CopyTime(symbol, tf, i, 1, timeArray) != 1) continue;
      if(timeArray[0] < prevBlockStart || timeArray[0] >= prevBlockEnd) continue;
      double h[1], l[1];
      if(CopyHigh(symbol, tf, i, 1, h) != 1 || CopyLow(symbol, tf, i, 1, l) != 1) continue;
      if(h[0] > boxHigh) boxHigh = h[0];
      if(l[0] < boxLow)  boxLow  = l[0];
      found = true;
   }
   if(!found) {
      double dailyHigh[1], dailyLow[1];
      if(CopyHigh(symbol, PERIOD_D1, 1, 1, dailyHigh) == 1 && CopyLow(symbol, PERIOD_D1, 1, 1, dailyLow) == 1) {
         boxHigh = dailyHigh[0]; boxLow = dailyLow[0]; found = true;
      }
   }
   if(found) {
      boPrevPeriodHigh[idx] = boxHigh;
      boPrevPeriodLow[idx]  = boxLow;
      boPrevPeriodReady[idx] = true;

      // ---- Set initial breakout flags based on current state (prevents startup false breakout) ----
      double close1H[1];
      if(CopyClose(symbol, Timeframe, 1, 1, close1H) == 1)
      {
         if(close1H[0] > boxHigh)      g_breakoutUp[idx]   = true;
         else if(close1H[0] < boxLow)  g_breakoutDown[idx] = true;
      }
   } else {
      boPrevPeriodReady[idx] = false;
   }
}

void BO_LoadAllPreviousPeriodLevels() { for(int i=0; i<boSymbolCount; i++) BO_LoadPreviousPeriodLevelsForSymbol(i); }

//+------------------------------------------------------------------+
//| NEW: Compute reversal average for a symbol (like Wack-A-Mole)    |
//+------------------------------------------------------------------+
double ComputeBOReversalAverage(string symbol)
{
   double avg = 0;
   double point = GetSymbolPoint(symbol);
   if(point <= 0) return 0;

   datetime now = TimeCurrent();
   int barsTotal = Bars(symbol, Timeframe);
   if(barsTotal < 3) return 0;
   int barsPerDay = 86400 / PeriodSeconds(Timeframe);
   int lookbackBars = BO_RevLookbackDays * barsPerDay;
   if(lookbackBars > barsTotal) lookbackBars = barsTotal;

   double heights[];
   ArrayResize(heights, 0);

   double openArr[], highArr[], lowArr[];

   for(int i = lookbackBars - 1; i >= 1; i--)
   {
      if(CopyOpen(symbol, Timeframe, i, 1, openArr) != 1) continue;
      if(CopyHigh(symbol, Timeframe, i, 1, highArr) != 1) continue;
      if(CopyLow(symbol, Timeframe, i, 1, lowArr)  != 1) continue;
      
      double o = openArr[0];
      double h = highArr[0];
      double l = lowArr[0];
      double candlePoints = (h - l) / point;
      
      datetime barCloseTime = iTime(symbol, Timeframe, i) + PeriodSeconds(Timeframe);

      bool reversed = false;
      for(int j = i - 1; j >= 0; j--)
      {
         datetime barTime = iTime(symbol, Timeframe, j);
         if(barTime + PeriodSeconds(Timeframe) <= barCloseTime) continue;
         if(barTime > barCloseTime + BO_RevReversalMinutes * 60) break;

         double jHigh[], jLow[];
         if(CopyHigh(symbol, Timeframe, j, 1, jHigh) != 1) continue;
         if(CopyLow(symbol, Timeframe, j, 1, jLow)  != 1) continue;
         if(jLow[0] <= o && jHigh[0] >= o)
         {
            reversed = true;
            break;
         }
      }

      if(reversed)
      {
         int sz = ArraySize(heights);
         ArrayResize(heights, sz + 1);
         heights[sz] = candlePoints;
      }
   }

   int total = ArraySize(heights);
   if(total == 0) return 0;

   ArraySort(heights);
   ArrayReverse(heights);

   int top = MathMin(BO_RevTopCount, total);
   double sum = 0;
   for(int i = 0; i < top; i++)
      sum += heights[i];

   avg = sum / top;
   return avg;
}

double GetMultiCandleRange(string symbol, int startShift, int count)
{
   if(count < 2) return 0.0;
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if(CopyHigh(symbol, Timeframe, startShift, count, highs) != count) return 0.0;
   if(CopyLow(symbol, Timeframe, startShift, count, lows)   != count) return 0.0;
   double highest = highs[0];
   double lowest  = lows[0];
   for(int i = 1; i < count; i++)
   {
      if(highs[i] > highest) highest = highs[i];
      if(lows[i]  < lowest)  lowest  = lows[i];
   }
   return (highest - lowest) / GetSymbolPoint(symbol);
}

//+------------------------------------------------------------------+
//| BO MODE – candle tracking always active, entry blocked if paused   |
//+------------------------------------------------------------------+
void CheckBOMode() {
   if(!EnableBOMode || !BO_UseReversalEntry) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;
   
   for(int idx = 0; idx < boSymbolCount; idx++) {
      string symbol = boSymbols[idx];
      
      if(symbol == GoldSymbol || symbol == OilSymbol || symbol == BTCSymbol)
         continue;
      bool isGold = boIsGold[idx];
      if(!IsSymbolValidForTrading(symbol) || g_dailyResetPauseActive) continue;
      bool spreadOk = isGold ? GetCachedSpread(symbol) <= MaxSpreadAU : GetCachedSpread(symbol) <= MaxSpreadPips;
      if(!spreadOk || !boRevAvgComputed[idx]) continue;
            // Skip index symbols
      bool isIndexSym = false;
      for(int j = 0; j < indexSymbolCount; j++)
         if(indexSymbols[j] == symbol) { isIndexSym = true; break; }
      if(isIndexSym) continue;
      
      double avg = boRevAvg[idx];
      double threshold = avg * BO_RevCandleMultiplier;
      double point = GetSymbolPoint(symbol);
      
      // ===== IMMEDIATE ENTRY MODE =====
      if(BO_RevImmediateEntry) {
         datetime currentCandleTime = iTime(symbol, Timeframe, 0);
         if(currentCandleTime == 0) continue;
         if(currentCandleTime != boLastCandleTime[idx]) {
            boLastCandleTime[idx] = currentCandleTime;
            boRevTradeAllowed[idx] = true;
         }
         if(!boRevTradeAllowed[idx]) continue;
         double highArr[], lowArr[], openArr[];
         if(CopyHigh(symbol, Timeframe, 0, 1, highArr) != 1) continue;
         if(CopyLow(symbol, Timeframe, 0, 1, lowArr)  != 1) continue;
         if(CopyOpen(symbol, Timeframe, 0, 1, openArr) != 1) continue;
         double rangePoints = (highArr[0] - lowArr[0]) / point;
         double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(symbol, 0, BO_MultiCandleLookback) : 0.0; 
         if(rangePoints >= threshold || multiRange >= threshold) {                                                      
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            int dir = (bid > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            if(BO_UseSwapFilter && !IsSwapValidForBO(symbol, (ENUM_ORDER_TYPE)dir))
               continue;

            int boCount = isGold ? CountBOGoldTrades() : CountBOTrades();
            int maxAllowed = isGold ? MaxBOGoldTrades : MaxBOTrades;
            if(boCount < maxAllowed) {
               // ---- ALWAYS consume the signal, only open trade if not paused ----
               boRevTradeAllowed[idx] = false;
               if(!g_allTradingPaused)
                  OpenBOTrade(symbol, dir, isGold);
            }
         }
      }
      // ===== CLOSE‑CONFIRM MODE =====
      else {
         datetime currentCandleTime = iTime(symbol, Timeframe, 0);
         if(currentCandleTime == 0) continue;
         if(currentCandleTime != boLastCandleTime[idx]) {
            boLastCandleTime[idx] = currentCandleTime;
            double openArr[], highArr[], lowArr[], closeArr[];
            if(CopyOpen(symbol, Timeframe, 1, 1, openArr)  != 1) continue;
            if(CopyHigh(symbol, Timeframe, 1, 1, highArr)  != 1) continue;
            if(CopyLow(symbol, Timeframe, 1, 1, lowArr)    != 1) continue;
            if(CopyClose(symbol, Timeframe, 1, 1, closeArr) != 1) continue;
            double rangePoints = (highArr[0] - lowArr[0]) / point;
            double multiRange = (BO_MultiCandleLookback > 0) ? GetMultiCandleRange(symbol, 1, BO_MultiCandleLookback) : 0.0; 
            if(rangePoints >= threshold || multiRange >= threshold) {                                                   
               if(BO_RevMinBodyPercent > 0) {
                  double bodyPoints = MathAbs(closeArr[0] - openArr[0]) / point;
                  double minBodyPoints = rangePoints * (BO_RevMinBodyPercent / 100.0);
                  if(bodyPoints < minBodyPoints) {
                     continue;
                  }
               }
               int dir = (closeArr[0] > openArr[0]) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               if(BO_ReverseTrades) dir = (dir == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

               if(BO_UseSwapFilter && !IsSwapValidForBO(symbol, (ENUM_ORDER_TYPE)dir))
                  continue;

               int boCount = isGold ? CountBOGoldTrades() : CountBOTrades();
               int maxAllowed = isGold ? MaxBOGoldTrades : MaxBOTrades;
               if(boCount < maxAllowed) {
                  // ---- Only open trade if not paused ----
                  if(!g_allTradingPaused)
                     OpenBOTrade(symbol, dir, isGold);
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Count live BO positions + pending BO orders for one symbol        |
//+------------------------------------------------------------------+
int GetBOExposureForSymbol(string symbol) {
   int live = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == symbol &&
         StringFind(PositionGetString(POSITION_COMMENT), "BO ") >= 0) live++;
   }
   return live;
}

void OpenBOTrade(string symbol, int dir, bool isGold) {
   
    if(!IsTradingHourAllowed()) return;

   // >>> NEW GLOBAL CHECK (replaces old exposure check) <<<
   if(CountTradesForSymbol(symbol) >= GlobalMaxTradesPerSymbol)
   {
      if(VerboseLogging) Print("[BO] ", symbol, " already has max positions. Skipping.");
      return;
   }
   
   int digits = GetDigits(symbol);
   double entry = (dir == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(symbol, SYMBOL_BID);
   entry = NormalizeDouble(entry, digits);
   
   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize
                               : (isGold ? 1.0 : GetSymbolPoint(symbol) * ((digits==3||digits==5) ? 10 : 1));
   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(symbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : (isGold ? GlobalSL_Pips * GoldPipMultiplier : GlobalSL_Pips) * pipSize;
   }
   else
   {
      double slPips = GlobalSL_Pips;
      if(isGold) slPips *= GoldPipMultiplier;
      slPriceDist = slPips * pipSize;
   }
   
   double lotSize = GetRiskBasedLot(symbol, slPriceDist);
   double validLot = GetValidLotSize(symbol, lotSize);
   
   double tpPriceDist = slPriceDist * TP_Multiplier;
   
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   if(dir == ORDER_TYPE_BUY) {
      sl = entry - slPriceDist;
      tp = entry + tpPriceDist + spread;
   } else {
      sl = entry + slPriceDist;
      tp = entry - tpPriceDist - spread;
   }
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   string comment = "BO " + (isGold ? "Gold" : "Forex") + " REV " + (dir == ORDER_TYPE_BUY ? "BUY" : "SELL");

   if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;
   
   if(RetryPositionOpen(symbol, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, comment)) {
      ulong ticket = Trade.ResultOrder();
      
      SetEntryType(ticket, isGold ? 4 : 3);   // BO gold or BO forex

      DailyTradeCount_Increment(symbol);
      
      Log(StringFormat("[BO-REV] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | Reason: Reversal candle signal",
                       symbol,
                       (dir==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       validLot, entry, sl, tp), true);
      
      DynamicStatus = "BO order accepted";
      LastTradeTime = TimeCurrent();
      
      if(TradeCount < 50) {
         Trades[TradeCount].ticket         = ticket;
         Trades[TradeCount].openPrice      = entry;
         Trades[TradeCount].entryDiff      = 0;
         Trades[TradeCount].openTime       = TimeCurrent();
         Trades[TradeCount].currentSL      = sl;
         Trades[TradeCount].pairSymbol     = symbol;
         Trades[TradeCount].isGold         = isGold;
         Trades[TradeCount].entryType      = isGold ? 4 : 3;
         Trades[TradeCount].lastTrailStep  = 0;
         Trades[TradeCount].isBO           = true;
         Trades[TradeCount].lastTrailPrice = entry;
         Trades[TradeCount].lastTrailTime  = TimeCurrent();
         Trades[TradeCount].partialDone    = false;
         Trades[TradeCount].lastPartialTime = 0;

         // NEW multi?tier fields – BEFORE increment
         Trades[TradeCount].originalLot     = validLot;
         Trades[TradeCount].partial25Done   = false;
         Trades[TradeCount].partial50Done   = false;
         Trades[TradeCount].partial75Done   = false;

         TradeCount++;
         if(ShowDashboard) UpdateDashboard();
      }
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
   } else {
      uint err = Trade.ResultRetcode();
      if(err == 10016) {
         Log("[BO] Error 10016 (Invalid stops) on " + symbol, true);
      }
   }
}

void OpenBOCommodityTrade(string symbol, int dir, bool isGold, int entryTypeOverride)
{
   if(!IsTradingHourAllowed()) return;

   if(CountTradesForSymbol(symbol) >= GlobalMaxTradesPerSymbol)
   {
      if(VerboseLogging) Print("[BO] ", symbol, " already has max positions. Skipping.");
      return;
   }

   int digits = GetDigits(symbol);
   double entry = (dir == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(symbol, SYMBOL_BID);
   entry = NormalizeDouble(entry, digits);

   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize
                               : (isGold ? 1.0 : GetSymbolPoint(symbol) * ((digits==3||digits==5) ? 10 : 1));
   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(symbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : (isGold ? GlobalSL_Pips * GoldPipMultiplier : GlobalSL_Pips) * pipSize;
   }
   else
   {
      double slPips = GlobalSL_Pips;
      if(isGold) slPips *= GoldPipMultiplier;
      slPriceDist = slPips * pipSize;
   }

   double lotSize = GetRiskBasedLot(symbol, slPriceDist);
   double validLot = GetValidLotSize(symbol, lotSize);

   double tpPriceDist = slPriceDist * TP_Multiplier;

   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   if(dir == ORDER_TYPE_BUY) {
      sl = entry - slPriceDist;
      tp = entry + tpPriceDist + spread;
   } else {
      sl = entry + slPriceDist;
      tp = entry - tpPriceDist - spread;
   }
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   string comment = "BO ";
   if(symbol == OilSymbol)
      comment += "Oil";
   else if(symbol == BTCSymbol)
      comment += "BTC";
   else
      comment += "Index";
   comment += " REV " + (dir == ORDER_TYPE_BUY ? "BUY" : "SELL");

   if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;

   if(RetryPositionOpen(symbol, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, comment)) {
      ulong ticket = Trade.ResultOrder();

      SetEntryType(ticket, entryTypeOverride);   // Use the override

      DailyTradeCount_Increment(symbol);

      Log(StringFormat("[BO-REV] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | Reason: Reversal candle signal",
                       symbol,
                       (dir==ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       validLot, entry, sl, tp), true);

      DynamicStatus = "BO order accepted";
      LastTradeTime = TimeCurrent();

      if(TradeCount < 50) {
         Trades[TradeCount].ticket         = ticket;
         Trades[TradeCount].openPrice      = entry;
         Trades[TradeCount].entryDiff      = 0;
         Trades[TradeCount].openTime       = TimeCurrent();
         Trades[TradeCount].currentSL      = sl;
         Trades[TradeCount].pairSymbol     = symbol;
         Trades[TradeCount].isGold         = isGold;
         Trades[TradeCount].entryType      = entryTypeOverride;
         Trades[TradeCount].lastTrailStep  = 0;
         Trades[TradeCount].isBO           = true;
         Trades[TradeCount].lastTrailPrice = entry;
         Trades[TradeCount].lastTrailTime  = TimeCurrent();
         Trades[TradeCount].partialDone    = false;
         Trades[TradeCount].lastPartialTime = 0;
         Trades[TradeCount].originalLot     = validLot;
         Trades[TradeCount].partial25Done   = false;
         Trades[TradeCount].partial50Done   = false;
         Trades[TradeCount].partial75Done   = false;
         TradeCount++;
         if(ShowDashboard) UpdateDashboard();
      }
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
   } else {
      uint err = Trade.ResultRetcode();
      if(err == 10016) {
         Log("[BO] Error 10016 (Invalid stops) on " + symbol, true);
      }
   }
}

void ApplySLTPToNewBOTrades() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetDouble(POSITION_SL) != 0 || PositionGetDouble(POSITION_TP) != 0) continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "BO ") < 0) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL) continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      bool isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int digits = GetDigits(symbol);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double pipSize = isGold ? 1.0 : point * ((digits==3||digits==5) ? 10 : 1);
      double slPips = GlobalSL_Pips;
      if(isGold) slPips *= GoldPipMultiplier;
      double slPriceDist = slPips * pipSize;

      // Get the actual lot size of the position (balance?based when opened)
      double lotSize = PositionGetDouble(POSITION_VOLUME);
      double tpPriceDist = slPriceDist * TP_Multiplier;

      double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl = 0, tp = 0;
      if(type == POSITION_TYPE_BUY) {
         sl = openPrice - slPriceDist;
         tp = openPrice + tpPriceDist + spread;
      } else {
         sl = openPrice + slPriceDist;
         tp = openPrice - tpPriceDist - spread;
      }
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      if(Trade.PositionModify(ticket, sl, tp)) {
         Log("[BO SL/TP] Applied to ticket " + IntegerToString(ticket), false);
      }
   }
}



//+------------------------------------------------------------------+
//| Check if a swap trade can be entered via currency strength        |
//| thresholds for a given symbol and direction.                      |
//+------------------------------------------------------------------+
bool IsSwapThresholdEntryAllowed(string symbol, ENUM_ORDER_TYPE direction)
{
   // --- Basic validity checks (spread, trading enabled, etc.) are done by caller ---

   // Get the base and quote currencies from the symbol
   string clean = GetCleanSymbol(symbol);
   if(StringLen(clean) < 6) return false;
   string base   = StringSubstr(clean, 0, 3);
   string quote  = StringSubstr(clean, 3, 3);

   // Find currency indexes and strengths
   int idxBase = -1, idxQuote = -1;
   for(int c = 0; c < 8; c++)
   {
      if(Currencies[c] == base)   idxBase   = c;
      if(Currencies[c] == quote)  idxQuote  = c;
   }
   if(idxBase == -1 || idxQuote == -1) return false;

   double strBase  = CurrencyStrength[idxBase];
   double strQuote = CurrencyStrength[idxQuote];
   double gap      = MathAbs(strBase - strQuote);

   // Check threshold conditions (same as main threshold)
   bool canBuy  = (strBase >= StrongEntryThreshold && strQuote <= WeakEntryThreshold && gap >= MinGapEntry);
   bool canSell = (strBase <= WeakEntryThreshold && strQuote >= StrongEntryThreshold && gap >= MinGapEntry);

   if(!canBuy && !canSell) return false;

   // Determine natural direction based on currency strength (without reversal)
   int naturalDir = -1;
   if(canBuy)                       naturalDir = ORDER_TYPE_BUY;
   else if(canSell)                 naturalDir = ORDER_TYPE_SELL;

   // Apply global ReverseTrades
   if(ReverseTrades)
   {
      if(naturalDir == ORDER_TYPE_BUY)       naturalDir = ORDER_TYPE_SELL;
      else if(naturalDir == ORDER_TYPE_SELL) naturalDir = ORDER_TYPE_BUY;
   }

   // Must match the requested direction
   if(direction != naturalDir) return false;

   // --- Additional filters (same as main threshold) ---
   if(Threshold_UseSwapFilter && !IsSwapValidForThreshold(symbol, direction))
      return false;


   if(UseOneHourCandleFilter)
   {
      bool candleBullish = IsOneHourCandleBullish(symbol);
      if(ReverseTrades)
      {
         if(direction == ORDER_TYPE_BUY && candleBullish)   return false;
         if(direction == ORDER_TYPE_SELL && !candleBullish) return false;
      }
      else
      {
         if(direction == ORDER_TYPE_BUY && !candleBullish) return false;
         if(direction == ORDER_TYPE_SELL && candleBullish) return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Helper: open a swap trade with multiply SL and 10x TP                   |
//| NEW: reason parameter for detailed logging                        |
//+------------------------------------------------------------------+
void OpenSwapTrade(string symbol, ENUM_ORDER_TYPE cmd, double lot, string comment,
                   string reason = "", double overrideSLDist = 0.0)
{  
   if(!IsTradingHourAllowed()) return;
   if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) return;
   
   // SAFEGUARD: Only allow swap trades on top-N swap symbols (gold exempted for fallback)
   if(!IsTopSwapSymbol(symbol) && StringFind(symbol, "XAU") < 0 && StringFind(symbol, "GOLD") < 0)
   {
      if(VerboseLogging)
         Print("[SWAP-BLOCK] ", symbol, " is not in top-", TopSwapCount, " swap list. Entry blocked.");
      return;
   }
   
   int digits = GetDigits(symbol);
   bool isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
   int idx = GetCachedIndex(symbol);
   double pipSize = (idx >= 0) ? symCache[idx].pipSize : GetPipSize(symbol);
   if(isGold) pipSize = 1.0;

   double entry = (cmd == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(symbol, SYMBOL_BID);
   entry = NormalizeDouble(entry, digits);

   double slPriceDist;
   if(UseATR_SLTP)
   {
      double atr = GetATRValue(symbol);
      slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : (isGold ? GlobalSL_Pips * GoldPipMultiplier : GlobalSL_Pips * SwapRiskMultiplier) * pipSize;
   }
   else if(overrideSLDist > 0.0)
      slPriceDist = overrideSLDist;
   else
   {
      double slPips = GlobalSL_Pips * SwapRiskMultiplier;
      if(isGold) slPips *= GoldPipMultiplier;
      slPriceDist = slPips * pipSize;
   }

   double tpPriceDist = slPriceDist * TP_Multiplier;
   double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl, tp;

   if(cmd == ORDER_TYPE_BUY)
   {
      sl = entry - slPriceDist;
      tp = entry + tpPriceDist + spread;
   }
   else
   {
      sl = entry + slPriceDist;
      tp = entry - tpPriceDist - spread;
   }
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   Trade.SetExpertMagicNumber(MagicNumber);
   bool success = false;
   
   if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) return;      
   if(cmd == ORDER_TYPE_BUY)
      success = Trade.Buy(lot, symbol, entry, sl, tp, comment);
   else
      success = Trade.Sell(lot, symbol, entry, sl, tp, comment);

   if(success)
   {  
      if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
      DailyTradeCount_Increment(symbol);
      string reasonStr = (reason == "") ? "" : " | Reason: " + reason;
      ulong swTicket = Trade.ResultOrder();
      SetEntryType(swTicket, 7);   // swap        
      Log(StringFormat("[SWAP-ENTRY] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f%s",
                       symbol,
                       (cmd == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                       lot, entry, sl, tp, reasonStr), true);
   }
}

//+------------------------------------------------------------------+
//| False Breakout RVI Entry (works for both swap & index modes)      |
//+------------------------------------------------------------------+
void CheckFalseBreakoutRVI()
{
   if(!EnableFalseBreakoutRVI) return;
   if(!IsTradingHourAllowed()) return;    
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(g_profitStopTrading) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   // ------- 1. Forex/Swap symbols -------
   for(int idx = 0; idx < boSymbolCount; idx++)
   {
      if(boIsGold[idx]) continue;   // gold handled separately if needed

      string sym = boSymbols[idx];
      if(!IsSymbolValidForTrading(sym)) continue;
      if(!g_breakoutUp[idx] && !g_breakoutDown[idx]) continue;

      // RVI once per new bar
      datetime currentBar = iTime(sym, Timeframe, 0);
      if(currentBar == 0) continue;
      if(currentBar == swapFB_RVIBarTime[idx]) continue;
      swapFB_RVIBarTime[idx] = currentBar;

      // RVI crossover
      int rviHandle = iRVI(sym, Timeframe, RVIPeriod);
      if(rviHandle == INVALID_HANDLE) continue;

      double green1[], red1[], green2[], red2[];
      ArraySetAsSeries(green1, true); ArraySetAsSeries(red1, true);
      ArraySetAsSeries(green2, true); ArraySetAsSeries(red2, true);

      if(CopyBuffer(rviHandle, 0, 1, 1, green1) <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 1, 1, 1, red1)   <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 0, 2, 1, green2) <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 1, 2, 1, red2)   <= 0) { IndicatorRelease(rviHandle); continue; }
      IndicatorRelease(rviHandle);

      bool bearCross = (green2[0] > red2[0] && green1[0] < red1[0]);   // green ↓ red
      bool bullCross = (green2[0] < red2[0] && green1[0] > red1[0]);   // green ↑ red

      // Determine direction based on breakout flag + crossover
      int dir = -1;
      if(g_breakoutUp[idx] && bearCross)   dir = ORDER_TYPE_SELL; // false up → short on bear cross
      else if(g_breakoutDown[idx] && bullCross) dir = ORDER_TYPE_BUY;

      if(dir == -1) continue;
      
      // >>> SAFEGUARD: only trade if the symbol is in the current top-N swap list
      if(!IsTopSwapSymbol(sym)) continue;
      
      if(!IsSwapValidForThreshold(sym, (ENUM_ORDER_TYPE)dir))
         continue;

      // Trade limits
      if(CountSwapTrades() >= MaxSwapTrades) continue;
      if(GetCachedSpread(sym) > MaxSpreadPips) continue;

      // --- Open a swap trade (use the standard swap opening function) ---
      bool isGold = false; // forex only here
      double pipSize = GetPipSize(sym);
      double slPips = GlobalSL_Pips * SwapRiskMultiplier;
      double slPriceDist = slPips * pipSize;
      double lot = GetRiskBasedLot(sym, slPriceDist);
      // >>> GLOBAL SYMBOL LIMIT <<<
      if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
         continue;
      double halfBlockHeight = GetHalfBlockHeight(sym);
      OpenSwapTrade(sym, (ENUM_ORDER_TYPE)dir, lot, "Swap Order", "FalseBrk RVI", halfBlockHeight);
   }
}

//+------------------------------------------------------------------+
//| Update all breakout flags (forex + indices)                       |
//+------------------------------------------------------------------+
void UpdateAllBreakoutFlags()
{
   // --- Forex symbols (skip gold) ---
   for(int i = 0; i < boSymbolCount; i++)
   {
      if(boIsGold[i]) continue;
      string symbol = boSymbols[i];
      if(!boPrevPeriodReady[i]) continue;

      double blockHigh = boPrevPeriodHigh[i];
      double blockLow  = boPrevPeriodLow[i];

      // Block‑start reset
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      int currentBlockHour = (dt.hour / BlockHours) * BlockHours;
      dt.hour = currentBlockHour; dt.min = 0; dt.sec = 0;
      datetime currentBlockStart = StructToTime(dt);

      static datetime lastForexBlockStart[MAX_BO_SYMBOLS];
      if(currentBlockStart != lastForexBlockStart[i])
      {
         g_breakoutUp[i]   = false;
         g_breakoutDown[i] = false;
         lastForexBlockStart[i] = currentBlockStart;
      }

      double close1H[1];
      if(CopyClose(symbol, Timeframe, 1, 1, close1H) == 1)
      {
         if(close1H[0] > blockHigh && !g_breakoutUp[i])
         {
            g_breakoutUp[i] = true;
            g_swapReEntryTaken[i] = false;
         }
         if(close1H[0] < blockLow && !g_breakoutDown[i])
         {
            g_breakoutDown[i] = true;
            g_swapReEntryTaken[i] = false;
         }
      }

      if(close1H[0] > blockLow && close1H[0] < blockHigh)
      {
         if(g_breakoutUp[i])   g_breakoutUp[i]   = false;
         if(g_breakoutDown[i]) g_breakoutDown[i] = false;
      }
   }

   // --- Index symbols ---
   for(int i = 0; i < indexSymbolCount && i < 50; i++)
   {
      string symbol = indexSymbols[i];
      LoadIndexBlockLevels(i);   // ensures block levels are current
      if(!idxPrevPeriodReady[i]) continue;

      int idx = MAX_BO_SYMBOLS + i;
      double blockHigh = idxBlockHigh[i];
      double blockLow  = idxBlockLow[i];

      // Block‑start reset
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      int currentBlockHour = (dt.hour / BlockHours) * BlockHours;
      dt.hour = currentBlockHour; dt.min = 0; dt.sec = 0;
      datetime currentBlockStart = StructToTime(dt);

      static datetime lastIndexBlockStart[50];
      if(currentBlockStart != lastIndexBlockStart[i])
      {
         g_breakoutUp[idx]   = false;
         g_breakoutDown[idx] = false;
         lastIndexBlockStart[i] = currentBlockStart;
      }

      double close1H[1];
      if(CopyClose(symbol, Timeframe, 1, 1, close1H) == 1)
      {
         if(close1H[0] > blockHigh && !g_breakoutUp[idx])
            g_breakoutUp[idx] = true;
         if(close1H[0] < blockLow && !g_breakoutDown[idx])
            g_breakoutDown[idx] = true;
      }

      if(close1H[0] > blockLow && close1H[0] < blockHigh)
      {
         if(g_breakoutUp[idx])   g_breakoutUp[idx]   = false;
         if(g_breakoutDown[idx]) g_breakoutDown[idx] = false;
      }
   }
}

//+------------------------------------------------------------------+
//| SWAP TRADING SYSTEM (half‑block‑height SL on moderate breakout)   |
//+------------------------------------------------------------------+
void CheckAndManageSwapTrades()
{
   g_topSwapCount = 0;
   if(!EnableSwapTrading) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   // Now stop if trading is paused (but flags are already fresh)
   if(g_allTradingPaused) return;

   // -----------------------------------------------
   // 1. Build RAW candidates – purely by swap value
   // -----------------------------------------------
   struct SwapCandidate
   {
      string   symbol;
      double   swapValue;
      ENUM_ORDER_TYPE direction;
   };

   SwapCandidate rawCandidates[];
   ArrayResize(rawCandidates, boSymbolCount * 2);
   int rawCount = 0;

   for(int i = 0; i < boSymbolCount; i++)
   {
      string sym = boSymbols[i];
      if(boIsGold[i]) continue;
      // Also skip oil symbols (they have no meaningful swap)
      if(StringFind(sym, "OIL") >= 0 || StringFind(sym, "WTI") >= 0 || StringFind(sym, "XTI") >= 0 || StringFind(sym, "Crude") >= 0)
         continue;   
      if(!IsSymbolValidForTrading(sym)) continue;

      double longSwap  = SymbolInfoDouble(sym, SYMBOL_SWAP_LONG);
      double shortSwap = SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT);

      bool longValid = (longSwap > 0 && MathAbs(longSwap) >= SwapEntryAbsThreshold && longSwap >= shortSwap);
      bool shortValid = (shortSwap > 0 && MathAbs(shortSwap) >= SwapEntryAbsThreshold && shortSwap > longSwap);

      if(!longValid && !shortValid) continue;

      ENUM_ORDER_TYPE swapDir = (longSwap > shortSwap) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double swapVal = (swapDir == ORDER_TYPE_BUY) ? longSwap : shortSwap;

      rawCandidates[rawCount].symbol    = sym;
      rawCandidates[rawCount].swapValue = swapVal;
      rawCandidates[rawCount].direction = swapDir;
      rawCount++;
   }

   for(int i = 0; i < rawCount - 1; i++)
      for(int j = i + 1; j < rawCount; j++)
         if(rawCandidates[j].swapValue > rawCandidates[i].swapValue)
         {
            SwapCandidate tmp = rawCandidates[i];
            rawCandidates[i] = rawCandidates[j];
            rawCandidates[j] = tmp;
         }

   int listCount = MathMin(TopSwapCount, rawCount);
   string selectedSymbols[];
   ArrayResize(selectedSymbols, listCount);
   for(int s = 0; s < listCount; s++)
      selectedSymbols[s] = rawCandidates[s].symbol;

   g_topSwapCount = listCount;
   for(int s = 0; s < listCount && s < MAX_BO_SYMBOLS; s++)
      g_topSwapSymbols[s] = selectedSymbols[s];

   // ---- Fallback: if no raw candidates exist ----
   if(rawCount == 0 && EnableSwapTrading && TradeGold && GoldTradeAllowed)
   {
      bool anyPositiveSwap = false;
      for(int i = 0; i < boSymbolCount; i++)
      {
         string sym = boSymbols[i];
         if(boIsGold[i]) continue;
         if(!IsSymbolValidForTrading(sym)) continue;
         double longSwap  = SymbolInfoDouble(sym, SYMBOL_SWAP_LONG);
         double shortSwap = SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT);
         if(longSwap > 0 || shortSwap > 0) { anyPositiveSwap = true; break; }
      }

      if(anyPositiveSwap) return;

      if(GetCurrentSpread(GoldSymbol) > MaxSpreadAU)
      {
         Log("[SWAP] Fallback skipped – gold spread too wide.", true);
         return;
      }

      Log("[SWAP] All forex swap rates are negative. Falling back to 3 XAUUSD buy orders.", true);
      int existingSwapTrades = CountSwapTrades();
      int maxToPlace = MathMin(3, MaxSwapTrades - existingSwapTrades);

      for(int i = 0; i < maxToPlace; i++)
      {
         double pipSize = 1.0;  // gold
         double slPips = GlobalSL_Pips * SwapRiskMultiplier * GoldPipMultiplier;
         double slPriceDist = slPips * pipSize;
         double lot = GetRiskBasedLot(GoldSymbol, slPriceDist);
         double halfBlockHeight = GetHalfBlockHeight(GoldSymbol);
         OpenSwapTrade(GoldSymbol, ORDER_TYPE_BUY, lot, "Swap Order", "Gold fallback", halfBlockHeight);
         Log("[SWAP-Fallback] Opened XAUUSD buy #" + IntegerToString(i+1), true);
      }
      return;
   }

   if(rawCount == 0) return;

   // -----------------------------------------------
   // 2. Build TRADABLE candidates – filter by master mode
   // -----------------------------------------------
   SwapCandidate tradableCandidates[];
   ArrayResize(tradableCandidates, rawCount);
   int tradableCount = 0;

   for(int i = 0; i < rawCount; i++)
   {
      string sym = rawCandidates[i].symbol;
      ENUM_ORDER_TYPE dir = rawCandidates[i].direction;
      if(GetCachedSpread(sym) > MaxSpreadPips) continue;

      bool passed = false;
      switch(SwapMasterMode)
      {
         case SWAP_MODE_LENIENT:
            if(i < TopSwapCount && !g_dailyLenientSwapDone)
            {
               // Skip symbols that already have a trade, but DO NOT lock the day
               if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
                  continue;
               passed = true;
            }
            break;

         case SWAP_MODE_MODERATE:
         {
            // RVI once per new bar (we need a static array for last bar time)
            static datetime lastModerateBarTime[MAX_BO_SYMBOLS] = {0};
            int symIdx = -1;
            for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; break; }
            if(symIdx < 0) continue;

            datetime currentBarOpen = iTime(sym, Timeframe, 0);
            if(currentBarOpen == 0) continue;
            if(currentBarOpen == lastModerateBarTime[symIdx]) continue;
            lastModerateBarTime[symIdx] = currentBarOpen;

            int rviHandle = iRVI(sym, Timeframe, RVIPeriod);
            if(rviHandle == INVALID_HANDLE) continue;

            double green1[], red1[], green2[], red2[];
            ArraySetAsSeries(green1, true); ArraySetAsSeries(red1, true);
            ArraySetAsSeries(green2, true); ArraySetAsSeries(red2, true);

            bool ok = (CopyBuffer(rviHandle, 0, 1, 1, green1) > 0 &&
                       CopyBuffer(rviHandle, 1, 1, 1, red1)   > 0 &&
                       CopyBuffer(rviHandle, 0, 2, 1, green2) > 0 &&
                       CopyBuffer(rviHandle, 1, 2, 1, red2)   > 0);
            IndicatorRelease(rviHandle);
            if(!ok) continue;

            bool buySignal  = (green2[0] < red2[0] && green1[0] > red1[0]);
            bool sellSignal = (green2[0] > red2[0] && green1[0] < red1[0]);
            if(!buySignal && !sellSignal) continue;

            ENUM_ORDER_TYPE rviDir = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

            // Apply swap filter – must have positive swap in that direction
            if(!IsSwapValidForThreshold(sym, rviDir)) continue;

            passed = true;
            // Override the direction in the candidate (the current one was based on swap value, not RVI)
            rawCandidates[i].direction = rviDir;
            break;
         }

         case SWAP_MODE_STRICT:
            if(IsSwapThresholdEntryAllowed(sym, dir))
            {
               // ---- Find symbol index (needed for candle‑size and wait‑close) ----
               int symIdx = -1;
               for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; break; }
               if(symIdx < 0) continue;

               // ---- Dynamic candle‑size filter (BO‑style average) ----
               if(StrictSwap_UseDynamicCandleSize && boRevAvgComputed[symIdx] && boRevAvg[symIdx] > 0)
               {
                  int candleShift = SwapStrict_WaitClose ? 1 : 0;   // 0 = current candle, 1 = previous
                  double highArr[1], lowArr[1];
                  if(CopyHigh(sym, Timeframe, candleShift, 1, highArr) == 1 &&
                     CopyLow(sym, Timeframe, candleShift, 1, lowArr)  == 1)
                  {
                     double candleSizePips = (highArr[0] - lowArr[0]) / GetPipSize(sym);
                     double requiredPips   = boRevAvg[symIdx] * StrictSwap_CandleAvgMultiplier;
                     if(candleSizePips < requiredPips)
                        continue;   // candle too small → skip this symbol
                  }
               }

               // ---- Wait‑close logic (unchanged) ----
               if(!SwapStrict_WaitClose)
                  passed = true;           // all conditions met, open immediately
               else
               {
                  datetime currentH1Open = iTime(sym, Timeframe, 0);
                  if(!g_swapLastH1Init[symIdx])
                  { g_swapLastH1Open[symIdx] = currentH1Open; g_swapLastH1Init[symIdx] = true; continue; }
                  if(currentH1Open == g_swapLastH1Open[symIdx]) continue;
                  g_swapLastH1Open[symIdx] = currentH1Open;
                  passed = true;
               }
            }
            break;
      }
      if(passed) { tradableCandidates[tradableCount] = rawCandidates[i]; tradableCount++; }
   }

   // Lock Lenient for the day if no candidate passed and we already have a trade on any top symbol
   if(SwapMasterMode == SWAP_MODE_LENIENT && !g_dailyLenientSwapDone && tradableCount == 0)
   {
      for(int j = 0; j < TopSwapCount && j < rawCount; j++)
      {
         if(CountTradesForSymbol(rawCandidates[j].symbol) >= GlobalMaxTradesPerSymbol)
         {
            g_dailyLenientSwapDone = true;
            break;
         }
      }
   }

   int swapTradeCount = MathMin(TopSwapCount, MaxSwapTrades);
   
   // -----------------------------------------------
   // 3. Get current swap positions
   // -----------------------------------------------
   struct HeldSwap { ulong ticket; string symbol; bool isBuy; };
   HeldSwap held[];
   ArrayResize(held, MaxSwapTrades);
   int heldCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") < 0) continue;
      held[heldCount].ticket = ticket;
      held[heldCount].symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      held[heldCount].isBuy  = (type == POSITION_TYPE_BUY);
      heldCount++;
   }

   // -----------------------------------------------
   // 4. TradeWithTopNSwap – group leader logic
   // -----------------------------------------------
   if(TradeWithTopNSwap)
   {
      if(tradableCount > 0)
      {
         string leaderSym = tradableCandidates[0].symbol;
         ENUM_ORDER_TYPE leaderDir = tradableCandidates[0].direction;
         bool groupExists = (CountSwapTrades() > 0);
         bool leaderConditionMet = false;
         switch(SwapMasterMode)
         {
            case SWAP_MODE_LENIENT:   leaderConditionMet = true; break;
            case SWAP_MODE_MODERATE:  leaderConditionMet = true; break;
            case SWAP_MODE_STRICT:    leaderConditionMet = true; break;
         }
         if(groupExists)
         {
            if(leaderConditionMet)
            {
               bool anyMissing = false;
               for(int i = 0; i < swapTradeCount && i < tradableCount; i++)
               {
                  string sym = tradableCandidates[i].symbol;
                  ENUM_ORDER_TYPE dir = tradableCandidates[i].direction;
                  bool heldAlready = false;
                  for(int h = 0; h < heldCount; h++)
                     if(held[h].ticket != 0 && held[h].symbol == sym && ((held[h].isBuy && dir == ORDER_TYPE_BUY) || (!held[h].isBuy && dir == ORDER_TYPE_SELL)))
                     { heldAlready = true; break; }
                  if(!heldAlready) { anyMissing = true; break; }
               }
               if(anyMissing)
               {
                  Log(StringFormat("[SwapGroup] Leader condition met again on %s %s – appending missing members.",
                                   leaderSym, (leaderDir == ORDER_TYPE_BUY ? "BUY" : "SELL")), true);
                  if(CountSwapTrades() >= MaxSwapTrades)
                     Log("[SwapGroup] MaxSwapTrades already reached – cannot append.", true);
                  else
                  {
                     for(int i = 0; i < swapTradeCount && i < tradableCount; i++)
                     {
                        if(CountSwapTrades() >= MaxSwapTrades) { Log("[SwapGroup] MaxSwapTrades reached inside append loop – stopping.", true); break; }
                        string sym = tradableCandidates[i].symbol;
                        ENUM_ORDER_TYPE dir = tradableCandidates[i].direction;

                        bool alreadyHeld = false;
                        for(int h = 0; h < heldCount; h++)
                           if(held[h].ticket != 0 && held[h].symbol == sym && ((held[h].isBuy && dir == ORDER_TYPE_BUY) || (!held[h].isBuy && dir == ORDER_TYPE_SELL)))
                           { alreadyHeld = true; break; }
                        if(alreadyHeld) continue;

                        for(int h = 0; h < heldCount; h++)
                           if(held[h].ticket != 0 && held[h].symbol == sym && ((held[h].isBuy && dir != ORDER_TYPE_BUY) || (!held[h].isBuy && dir != ORDER_TYPE_SELL)))
                           { Trade.PositionClose(held[h].ticket); Log("[SwapGroup] Closed opposite direction on " + sym, true); held[h].ticket = 0; }

                        if(GetCachedSpread(sym) > MaxSpreadPips)
                        { Log(StringFormat("[SwapGroup] Member %s skipped (spread %.1f > %.1f)", sym, GetCachedSpread(sym), MaxSpreadPips), true); continue; }

                        int symIdx = -1;
                        for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; break; }
                        if(symIdx >= 0)
                        {
                           datetime signalCandleTime = iTime(sym, Timeframe, 1);
                           if(signalCandleTime != 0 && signalCandleTime == g_swapSignalCandleTime[symIdx]) continue;
                           g_swapSignalCandleTime[symIdx] = signalCandleTime;
                        }

                        // --- compute risk-based lot size ---
                        bool isGold = boIsGold[symIdx];
                        double pipSize = isGold ? 1.0 : GetPipSize(sym);
                        double slPips = GlobalSL_Pips * SwapRiskMultiplier;
                        if(isGold) slPips *= GoldPipMultiplier;
                        double slPriceDist = slPips * pipSize;
                        double lot = GetRiskBasedLot(sym, slPriceDist);

                        if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
                        {
                           Log("[SwapGroup] Cannot append " + sym + " – max positions reached.", true);
                           continue;
                        }

                        // Store current breakout flags and candle lock
                        int grpIdx = -1;
                        for(int b = 0; b < boSymbolCount; b++)
                           if(boSymbols[b] == sym) { grpIdx = b; break; }
                        bool wasUp   = (grpIdx >= 0) ? g_breakoutUp[grpIdx]   : false;
                        bool wasDown = (grpIdx >= 0) ? g_breakoutDown[grpIdx] : false;

                        // ===== CANDLE LOCK =====
                        if(grpIdx >= 0)
                        {
                           datetime signalCandleTime = iTime(sym, Timeframe, 1);
                           if(signalCandleTime == 0) continue;
                           if(signalCandleTime == g_swapSignalCandleTime[grpIdx]) continue;
                           g_swapSignalCandleTime[grpIdx] = signalCandleTime;
                        }
                        // =======================

                        double halfBlockHeight = GetHalfBlockHeight(sym);
                        OpenSwapTrade(sym, dir, lot, "Swap Order", "Group member appended", halfBlockHeight);
                        Log(StringFormat("[SwapGroup] Member appended: %s %s, ticket=%d", sym, (dir==ORDER_TYPE_BUY?"BUY":"SELL"), Trade.ResultOrder()), true);

                        // Mark re‑entry lock without touching breakout flags
                        if(wasDown && dir == ORDER_TYPE_BUY)
                           g_swapReEntryTaken[grpIdx] = true;
                        else if(wasUp && dir == ORDER_TYPE_SELL)
                           g_swapReEntryTaken[grpIdx] = true;
                        if(heldCount < MaxSwapTrades)
                        {
                           held[heldCount].symbol = sym;
                           held[heldCount].isBuy  = (dir == ORDER_TYPE_BUY);
                           held[heldCount].ticket = Trade.ResultOrder();
                           heldCount++;
                        }
                     }
                  }
               }
            }
         }
         else // No group exists → fresh group opening
         {
            if(leaderConditionMet)
            {
               Log(StringFormat("[SwapGroup] Leader signal on %s %s", leaderSym, (leaderDir == ORDER_TYPE_BUY ? "BUY" : "SELL")), true);
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  ulong ticket = PositionGetTicket(i);
                  if(!PositionSelectByTicket(ticket)) continue;
                  if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
                  if(StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") >= 0) Trade.PositionClose(ticket);
               }
               heldCount = 0;
               ArrayFree(held);
               ArrayResize(held, MaxSwapTrades);

               for(int i = 0; i < swapTradeCount && i < tradableCount; i++)
               {
                  string sym = tradableCandidates[i].symbol;
                  ENUM_ORDER_TYPE dir = tradableCandidates[i].direction;

                  if(GetCachedSpread(sym) > MaxSpreadPips)
                  {
                     if(i == 0) Log(StringFormat("[SwapGroup] Leader %s rejected: spread %.1f > %.1f", sym, GetCachedSpread(sym), MaxSpreadPips), true);
                     else Log(StringFormat("[SwapGroup] Member %s skipped (spread)", sym), true);
                     if(i == 0) break;
                     continue;
                  }

                  int symIdx = -1;
                  bool isGold = false;
                  for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; isGold = boIsGold[b]; break; }
                  if(symIdx < 0) continue;

                  double pipSize = isGold ? 1.0 : GetPipSize(sym);
                  double slPips = GlobalSL_Pips * SwapRiskMultiplier;
                  if(isGold) slPips *= GoldPipMultiplier;
                  double slPriceDist = slPips * pipSize;
                  double lot = GetRiskBasedLot(sym, slPriceDist);

                  if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
                  {
                     Log("[SwapGroup] Cannot open " + sym + " – max positions reached.", true);
                     if(i == 0) break;
                     continue;
                  }

                  // Store current breakout flags
                  int grpIdx = symIdx;
                  bool wasUp   = (grpIdx >= 0) ? g_breakoutUp[grpIdx]   : false;
                  bool wasDown = (grpIdx >= 0) ? g_breakoutDown[grpIdx] : false;

                  // ===== CANDLE LOCK =====
                  if(grpIdx >= 0)
                  {
                     datetime signalCandleTime = iTime(sym, Timeframe, 1);
                     if(signalCandleTime == 0) continue;
                     if(signalCandleTime == g_swapSignalCandleTime[grpIdx]) continue;
                     g_swapSignalCandleTime[grpIdx] = signalCandleTime;
                  }
                  // =======================

                  double halfBlockHeight = GetHalfBlockHeight(sym);
                  OpenSwapTrade(sym, dir, lot, "Swap Order", (i==0 ? "Group leader initial" : "Group member initial"), halfBlockHeight);
                  if(i == 0) g_swapGroupLeaderTicket = Trade.ResultOrder();
                  Log(StringFormat("[SwapGroup] %s opened: %s %s, ticket=%d", (i==0 ? "Leader" : "Member"), sym, (dir==ORDER_TYPE_BUY?"BUY":"SELL"), Trade.ResultOrder()), true);
                  
                  if(SwapMasterMode == SWAP_MODE_LENIENT && i == 0)
                     g_dailyLenientSwapDone = true;

                  // Mark re‑entry lock without touching breakout flags
                  if(wasDown && dir == ORDER_TYPE_BUY)
                     g_swapReEntryTaken[grpIdx] = true;
                  else if(wasUp && dir == ORDER_TYPE_SELL)
                     g_swapReEntryTaken[grpIdx] = true;

                  if(heldCount < MaxSwapTrades)
                  {
                     held[heldCount].symbol = sym;
                     held[heldCount].isBuy  = (dir == ORDER_TYPE_BUY);
                     held[heldCount].ticket = Trade.ResultOrder();
                     heldCount++;
                  }
               }
            }
         }
      }
   }

   // -----------------------------------------------
   // 5. Swap close threshold
   // -----------------------------------------------
   if(SwapCloseAbsThreshold > 0)
   {
      for(int h = 0; h < heldCount; h++)
      {
         if(held[h].ticket == 0) continue;
         double longSwap  = SymbolInfoDouble(held[h].symbol, SYMBOL_SWAP_LONG);
         double shortSwap = SymbolInfoDouble(held[h].symbol, SYMBOL_SWAP_SHORT);
         bool closeMe = false;
         if( held[h].isBuy  && longSwap  < SwapCloseAbsThreshold) closeMe = true;
         if(!held[h].isBuy && shortSwap < SwapCloseAbsThreshold) closeMe = true;
         if(closeMe)
         {
            Trade.PositionClose(held[h].ticket);
            Log("[SWAP] Closed " + held[h].symbol + " – swap below close threshold.", true);
            held[h].ticket = 0;
         }
      }
   }

   // -----------------------------------------------
   // 6. Manage positions when NOT using group leader
   // -----------------------------------------------
   if(!TradeWithTopNSwap)
   {
      for(int s = 0; s < swapTradeCount && s < tradableCount; s++)
      {
         string sym = tradableCandidates[s].symbol;
         ENUM_ORDER_TYPE dir = tradableCandidates[s].direction;

         bool already = false;
         for(int h = 0; h < heldCount; h++)
            if(held[h].ticket != 0 && held[h].symbol == sym && ((held[h].isBuy && dir == ORDER_TYPE_BUY) || (!held[h].isBuy && dir == ORDER_TYPE_SELL)))
            { already = true; break; }
         if(already) continue;

         for(int h = 0; h < heldCount; h++)
            if(held[h].ticket != 0 && held[h].symbol == sym)
            { Trade.PositionClose(held[h].ticket); Log("[SWAP] Closed opposite direction on " + sym, true); held[h].ticket = 0; }

         int symIdx = -1;
         for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; break; }
         if(symIdx < 0) continue;

         // --- candle lock ---
         datetime signalCandleTime = iTime(sym, Timeframe, 1);
         if(signalCandleTime == 0) continue;
         if(signalCandleTime == g_swapSignalCandleTime[symIdx]) continue;
         g_swapSignalCandleTime[symIdx] = signalCandleTime;

         if(GetCachedSpread(sym) > MaxSpreadPips) continue;

         if(CountSwapTrades() >= MaxSwapTrades) continue;

         if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
         {
            if(VerboseLogging) Print("[SWAP] ", sym, " already has max positions. Skipping.");
            continue;
         }

         // --- Compute risk-based lot size for this swap trade ---
         bool isGold = boIsGold[symIdx];
         double pipSize = isGold ? 1.0 : GetPipSize(sym);
         double slPips = GlobalSL_Pips * SwapRiskMultiplier;
         if(isGold) slPips *= GoldPipMultiplier;
         double slPriceDist = slPips * pipSize;
         double lot = GetRiskBasedLot(sym, slPriceDist);

         string reason = "RVI Crossover";

         // Store the current breakout flags (use the existing symIdx)
         bool wasUp   = (symIdx >= 0) ? g_breakoutUp[symIdx]   : false;
         bool wasDown = (symIdx >= 0) ? g_breakoutDown[symIdx] : false;

         double halfBlockHeight = GetHalfBlockHeight(sym);
         OpenSwapTrade(sym, dir, lot, "Swap Order", reason, halfBlockHeight);
         Log(StringFormat("[SWAP] %s | %s | Lot=%.2f | %s", sym, (dir == ORDER_TYPE_BUY ? "BUY" : "SELL"), lot, reason), true);
         
         if(SwapMasterMode == SWAP_MODE_LENIENT)
            g_dailyLenientSwapDone = true;

         // Mark re‑entry lock without touching breakout flags
         if(wasDown && dir == ORDER_TYPE_BUY)
            g_swapReEntryTaken[symIdx] = true;
         else if(wasUp && dir == ORDER_TYPE_SELL)
            g_swapReEntryTaken[symIdx] = true;

         if(heldCount < MaxSwapTrades)
         {
            held[heldCount].symbol = sym;
            held[heldCount].isBuy  = (dir == ORDER_TYPE_BUY);
            held[heldCount].ticket = Trade.ResultOrder();
            heldCount++;
         }
      }
   }

   // -----------------------------------------------
   // 7. TradeWithTopNSwap – close all if leader closed
   // -----------------------------------------------
   if(TradeWithTopNSwap && g_swapGroupLeaderTicket != 0)
   {
      if(!PositionSelectByTicket(g_swapGroupLeaderTicket))
      {
         Log("[SwapGroup] Leader closed externally – closing entire swap group.", true);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
            if(StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") >= 0)
            {
               Log(StringFormat("[SwapGroup] Closing %s ticket=%d", PositionGetString(POSITION_SYMBOL), ticket), true);
               Trade.PositionClose(ticket);
            }
         }
         g_swapGroupLeaderTicket = 0;
      }
   }
}

//-------------------------------------------------------------------+
//| HELPER FUNCTION                            |
//+------------------------------------------------------------------+

bool IsTopSwapSymbol(string sym)
{
   for(int i = 0; i < g_topSwapCount; i++)
      if(g_topSwapSymbols[i] == sym)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| RVI Close Check – closes trades on green/red crossover (1H)       |
//| NOW also immediately enters a false‑breakout RVI trade if         |
//| a breakout flag is active and ADX is met.                         |
//| UPDATE: ADX filter removed from close decision; close only         |
//|   depends on RVI crossover + current candle direction vs trade.   |
//+------------------------------------------------------------------+
void CheckRVIClose()
{
   if(!RVI_CloseEnabled) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType != POSITION_TYPE_BUY && posType != POSITION_TYPE_SELL) continue;

      // Find forex/swap index (symIdx) and also try index symbol index
      int symIdx = -1;
      for(int b = 0; b < boSymbolCount; b++)
         if(boSymbols[b] == symbol) { symIdx = b; break; }

      int idxIndex = -1;
      for(int j = 0; j < indexSymbolCount; j++)
         if(indexSymbols[j] == symbol) { idxIndex = j; break; }

      // ---------- RVI calculation (once per new 1H bar) ----------
      datetime currentBarOpen = iTime(symbol, Timeframe, 0);
      if(currentBarOpen == 0) continue;
      
      // ---------- Only process once per new bar (safe split) ----------
      bool isIndexSymbolForRVI = (idxIndex >= 0);
      if(isIndexSymbolForRVI)
      {
         if(idxRVICloseBarTime[idxIndex] == currentBarOpen)
            continue;
         idxRVICloseBarTime[idxIndex] = currentBarOpen;
      }
      else
      {
         if(symIdx >= 0)
         {
            if(rviLastBarTime[symIdx] == currentBarOpen)
               continue;
            rviLastBarTime[symIdx] = currentBarOpen;
         }
      }

      int rviHandle = iRVI(symbol, Timeframe, RVIPeriod);  // uses your chosen RVIPeriod
      if(rviHandle == INVALID_HANDLE) continue;

      double green1[], red1[], green2[], red2[];
      ArraySetAsSeries(green1, true);
      ArraySetAsSeries(red1, true);
      ArraySetAsSeries(green2, true);
      ArraySetAsSeries(red2, true);

      if(CopyBuffer(rviHandle, 0, 1, 1, green1) <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 1, 1, 1, red1)   <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 0, 2, 1, green2) <= 0) { IndicatorRelease(rviHandle); continue; }
      if(CopyBuffer(rviHandle, 1, 2, 1, red2)   <= 0) { IndicatorRelease(rviHandle); continue; }
      IndicatorRelease(rviHandle);

      bool closeTrade   = false;
      bool openOpposite  = false;

      if(posType == POSITION_TYPE_BUY)
      {
         if(green2[0] > red2[0] && green1[0] < red1[0])  // bear cross
         {
            closeTrade = true;
            openOpposite = RVI_OpenOpposite;
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(green2[0] < red2[0] && green1[0] > red1[0])  // bull cross
         {
            closeTrade = true;
            openOpposite = RVI_OpenOpposite;
         }
      }

      if(closeTrade)
      {
         // ---------- REMOVED ADX FILTER for close ----------
         // Do not close if the CLOSED candle that triggered the crossover
         // agrees with the trade direction
         double openArr[1], closeArr[1];
         if(CopyOpen(symbol, Timeframe, 1, 1, openArr) == 1 &&
            CopyClose(symbol, Timeframe, 1, 1, closeArr) == 1)
         {
            bool candleBullish = (closeArr[0] > openArr[0]);
            if((posType == POSITION_TYPE_BUY && candleBullish) ||
               (posType == POSITION_TYPE_SELL && !candleBullish))
            {
               if(VerboseLogging)
                  Print("[RVI] Skip closing ", symbol, " (", (posType==POSITION_TYPE_BUY?"BUY":"SELL"),
                        ") – candle direction matches trade");
               continue;
            }
         }

         string posComment = PositionGetString(POSITION_COMMENT);

         if(RVISwapCloseBypass && StringFind(posComment, "Swap Order") >= 0)
            continue;

         datetime tradeOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(tradeOpenTime >= currentBarOpen)
            continue;

         double lotSize = PositionGetDouble(POSITION_VOLUME);

         if(RVI_BTCBypass && StringFind(posComment, "BTC") >= 0)
            continue;

         // --- Monday Special RVI bypass (NEW) ---
         if(MondaySpecial_RVIBypass && StringFind(posComment, "Monday Special") >= 0) continue;
         if(ForexBO_RVIBypass  && StringFind(posComment, "BO Forex")  >= 0) continue;
         if(GoldBO_RVIBypass   && StringFind(posComment, "BO Gold")   >= 0) continue;
         if(OilBO_RVIBypass    && StringFind(posComment, "BO Oil")    >= 0) continue;
         if(IndexBO_RVIBypass  && StringFind(posComment, "BO Index")  >= 0) continue;
            
         Trade.PositionClose(ticket);

         if(VerboseLogging)
            Print("[RVI] Closed ", symbol, " (",
                  (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  ") on RVI crossover.");

         // ---- IMMEDIATE FALSE‑BREAKOUT RVI ENTRY (same crossover) ----
         bool isIndexSymbol = (idxIndex >= 0);
         bool canEnterFB = (isIndexSymbol || (symIdx >= 0 && !boIsGold[symIdx]));

         if(canEnterFB)
         {
            bool flagUp = false, flagDown = false;
            if(isIndexSymbol)
            {
               if(idxIndex >= 0 && idxPrevPeriodReady[idxIndex])
               {
                  flagUp   = g_breakoutUp[MAX_BO_SYMBOLS + idxIndex];
                  flagDown = g_breakoutDown[MAX_BO_SYMBOLS + idxIndex];
               }
            }
            else
            {
               flagUp   = g_breakoutUp[symIdx];
               flagDown = g_breakoutDown[symIdx];
            }

            ENUM_ORDER_TYPE fbDir = -1;
            if(posType == POSITION_TYPE_BUY && flagUp)   fbDir = ORDER_TYPE_SELL;
            if(posType == POSITION_TYPE_SELL && flagDown) fbDir = ORDER_TYPE_BUY;

            if(fbDir != -1)
            {
               // No ADX filter – proceed directly with limit / spread checks
               bool limitOk = false;
               if(isIndexSymbol)
                  limitOk = (CountIndexTrades() < MaxIndexTrades &&
                             CountTradesForSymbol(symbol) < GlobalMaxTradesPerSymbol);
               else
                  limitOk = (CountSwapTrades() < MaxSwapTrades &&
                             CountTradesForSymbol(symbol) < GlobalMaxTradesPerSymbol);

               double spread = (isIndexSymbol) ? GetCurrentSpread(symbol) : GetCachedSpread(symbol);
               double maxSpread = (isIndexSymbol) ? MaxSpreadIndices : MaxSpreadPips;
               if(limitOk && spread <= maxSpread)
               {
                  if(!IsTradingHourAllowed()) continue;
                  if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) continue;
                  if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) continue;

                  if(isIndexSymbol)
                  {
                     if(idxPrevPeriodReady[idxIndex])
                     {
                        double blockHigh = idxBlockHigh[idxIndex];
                        double blockLow  = idxBlockLow[idxIndex];
                        double blockMid  = (blockHigh + blockLow) / 2.0;
                        int digits = GetDigits(symbol);
                        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
                        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
                        double entry = (fbDir == ORDER_TYPE_BUY) ? ask : bid;
                        entry = NormalizeDouble(entry, digits);
                        double sl = NormalizeDouble(blockMid, digits);
                        double slDist = MathAbs(entry - blockMid);
                        double tpDist = slDist * TP_Multiplier;
                        double tp = 0;
                        if(Index_EnableTP)
                        {
                           if(fbDir == ORDER_TYPE_BUY) tp = entry + tpDist;
                           else                        tp = entry - tpDist;
                           tp = NormalizeDouble(tp, digits);
                        }
                        double lotSizeFB = GetRiskBasedLot(symbol, slDist);
                        double validLot  = GetValidLotSize(symbol, lotSizeFB);
                        string comment = "Index Order FalseBrk RVI " + (fbDir == ORDER_TYPE_BUY ? "BUY" : "SELL");

                        if(!IsTradingHourAllowed()) continue;

                        if(!g_allTradingPaused && RetryPositionOpen(symbol, fbDir, validLot, entry, sl, tp, comment))
                        {
                           Log(StringFormat("[RVI-FB-ENTRY] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f",
                                            symbol, (fbDir==ORDER_TYPE_BUY?"BUY":"SELL"),
                                            validLot, entry, sl, tp), true);
                           if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);

                           if(Index_UsePartialTP && TradeCount < 50)
                           {
                              Trades[TradeCount].ticket         = Trade.ResultOrder();
                              Trades[TradeCount].openPrice      = entry;
                              Trades[TradeCount].openTime       = TimeCurrent();
                              Trades[TradeCount].currentSL      = sl;
                              Trades[TradeCount].pairSymbol     = symbol;
                              Trades[TradeCount].isGold         = false;
                              Trades[TradeCount].isBO           = false;
                              Trades[TradeCount].entryType      = 5;
                              Trades[TradeCount].lastTrailStep  = 0;
                              Trades[TradeCount].lastTrailPrice = entry;
                              Trades[TradeCount].lastTrailTime  = TimeCurrent();
                              Trades[TradeCount].partialDone    = false;
                              Trades[TradeCount].lastPartialTime = 0;
                              Trades[TradeCount].originalLot    = validLot;
                              Trades[TradeCount].partial25Done  = false;
                              Trades[TradeCount].partial50Done  = false;
                              Trades[TradeCount].partial75Done  = false;
                              TradeCount++;
                           }
                        }
                     }
                  }
                  else   // forex / swap symbol
                  {
                      if(!IsTopSwapSymbol(symbol))
                      {
                          if(VerboseLogging)
                              Print("[RVI-FB] Skipped non‑top swap ", symbol);
                          continue;
                      }

                      double halfBlockHeight = GetHalfBlockHeight(symbol);
                      double lot = GetRiskBasedLot(symbol, halfBlockHeight);
                      double validLot = GetValidLotSize(symbol, lot);
                      if(!g_allTradingPaused)
                      {
                          OpenSwapTrade(symbol, fbDir, validLot, "Swap Order", "FalseBrk RVI immediate", halfBlockHeight);
                          Log(StringFormat("[RVI-FB-ENTRY] Swap %s | %s | Lot=%.2f",
                                           symbol, (fbDir==ORDER_TYPE_BUY?"BUY":"SELL"), validLot), true);
                      }
                  }
               }
            }
         }

         // ---- Optional opposite trade (RVI_OpenOpposite) ----
         if(openOpposite)
         {
            if(!IsTradingHourAllowed()) continue;
            if(CountTradesForSymbol(symbol) >= GlobalMaxTradesPerSymbol) continue;
            if(DailyTradeCount_Get(symbol) >= MaxDailyTradesPerSymbol) continue;
            if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) continue;

            ENUM_ORDER_TYPE oppositeCmd = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            double price = (oppositeCmd == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                                           : SymbolInfoDouble(symbol, SYMBOL_BID);
            int digits = GetDigits(symbol);
            price = NormalizeDouble(price, digits);

            double lotSizeOpp = lotSize;
            double spreadOpp  = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
            double slDist = GetHalfBlockHeight(symbol);
            if(slDist <= 0.0)
               slDist = GlobalSL_Pips * GetPipSizeForSymbol(symbol);
            double tpDist = slDist * TP_Multiplier;
            double newSL = 0, newTP = 0;
            if(oppositeCmd == ORDER_TYPE_BUY)
            {
               newSL = price - slDist;
               newTP = price + tpDist + spreadOpp;
            }
            else
            {
               newSL = price + slDist;
               newTP = price - tpDist - spreadOpp;
            }
            newSL = NormalizeDouble(newSL, digits);
            newTP = NormalizeDouble(newTP, digits);
            if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal) continue;

            if(RetryPositionOpen(symbol, oppositeCmd, lotSizeOpp, price, newSL, newTP, "RVI Opposite"))
            {
               if(VerboseLogging)
                  Print("[RVI] Opened opposite trade ", symbol,
                        " (", (oppositeCmd == ORDER_TYPE_BUY ? "BUY" : "SELL"), ").");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE TRADES & TRAILING & PARTIAL TP                            |
//+------------------------------------------------------------------+
void ManageTrades() {
   RemoveClosedFromMap();
   // ----- 1. Check if any previously tracked trade closed (for sound) -----
   bool anyClosed = false;
   for(int i = 0; i < TradeCount; i++) {
      if(!PositionSelectByTicket(Trades[i].ticket)) {
         anyClosed = true;
         break;
      }
   }
   if(anyClosed) {
      if(PlaySounds && SoundFileClose != "") PlaySound(SoundFileClose);
   }

   // ----- 2. Save partial‑TP / trailing state for all currently tracked tickets -----
   datetime prevPartialTime[50];
   double   prevTrailPrice[50];
   bool     prevPartialDone[50];
   ulong    prevTicket[50];
   double   prevOriginalLot[50];
   bool     prevPartial25[50], prevPartial50[50], prevPartial75[50];

   int prevCount = TradeCount;
   for(int j = 0; j < prevCount; j++) {
      prevTicket[j]       = Trades[j].ticket;
      prevPartialTime[j]  = Trades[j].lastPartialTime;
      prevTrailPrice[j]   = Trades[j].lastTrailPrice;
      prevPartialDone[j]  = Trades[j].partialDone;
      prevOriginalLot[j]  = Trades[j].originalLot;
      prevPartial25[j]    = Trades[j].partial25Done;
      prevPartial50[j]    = Trades[j].partial50Done;
      prevPartial75[j]    = Trades[j].partial75Done;
   }

     // ----- 3. Rebuild Trades[] from actual open positions (ALWAYS) -----
   TradeCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         Trades[TradeCount].ticket     = ticket;
         Trades[TradeCount].openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
         Trades[TradeCount].openTime   = (datetime)PositionGetInteger(POSITION_TIME);
         Trades[TradeCount].currentSL  = PositionGetDouble(POSITION_SL);
         Trades[TradeCount].pairSymbol = PositionGetString(POSITION_SYMBOL);
         
         string cmt      = PositionGetString(POSITION_COMMENT);
         bool   isGold   = (StringFind(Trades[TradeCount].pairSymbol, "XAU") >= 0 || 
                            StringFind(Trades[TradeCount].pairSymbol, "GOLD") >= 0);
         bool   isBO     = (StringFind(cmt, "BO ") >= 0);
         bool   isIndex  = (StringFind(cmt, "Index Order") >= 0);
         bool   isOilRVI = (StringFind(cmt, "OilRVI") >= 0);
         bool   isGoldRVI = (StringFind(cmt, "GoldRVI") >= 0);
         bool   isOilBO  = (StringFind(cmt, "BO Oil") >= 0);
         bool   isBTCBO  = (StringFind(cmt, "BO BTC") >= 0);
         bool   isIndexBO = (StringFind(cmt, "BO Index") >= 0);
         bool isSwap = (StringFind(cmt, "Swap Order") >= 0);
         bool isBTC = (StringFind(cmt, "BTC") >= 0);

         Trades[TradeCount].isGold = isGold;
         Trades[TradeCount].isBO   = isBO;
         
         
         // --- Determine entry type from comment ---
         if(isOilRVI)
            Trades[TradeCount].entryType = 6;
         else if(isGoldRVI)
            Trades[TradeCount].entryType = 4;
         else if(isOilBO)
            Trades[TradeCount].entryType = 6;
         else if(isBTCBO)
            Trades[TradeCount].entryType = 8;
         else if(isIndexBO)
            Trades[TradeCount].entryType = 5;
         else if(isBO)
            Trades[TradeCount].entryType = isGold ? 4 : 3;
         else if(isIndex)
            Trades[TradeCount].entryType = 5;
         else if(isSwap)
            Trades[TradeCount].entryType = 7;
         else if(isGold)
            Trades[TradeCount].entryType = 2;
         else if(isBTC)
            Trades[TradeCount].entryType = 8;
         else
            Trades[TradeCount].entryType = 0;

         // --- Always override with stored type if available ---
         int storedType = GetEntryType(ticket);
         if(storedType >= 0)
            Trades[TradeCount].entryType = storedType;
         
         Trades[TradeCount].lastTrailStep = 0;
         Trades[TradeCount].lastTrailTime = (datetime)PositionGetInteger(POSITION_TIME);
         
         // ----- Restore saved cooldown / trailing / tier data for this ticket -----
         Trades[TradeCount].lastPartialTime = 0;
         Trades[TradeCount].lastTrailPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
         Trades[TradeCount].partialDone     = false;
         Trades[TradeCount].originalLot     = 0;
         Trades[TradeCount].partial25Done   = false;
         Trades[TradeCount].partial50Done   = false;
         Trades[TradeCount].partial75Done   = false;
         
         for(int j = 0; j < prevCount; j++) {
            if(prevTicket[j] == ticket) {
               Trades[TradeCount].lastPartialTime = prevPartialTime[j];
               Trades[TradeCount].lastTrailPrice  = prevTrailPrice[j];
               Trades[TradeCount].partialDone     = prevPartialDone[j];
               Trades[TradeCount].originalLot     = prevOriginalLot[j];
               Trades[TradeCount].partial25Done   = prevPartial25[j];
               Trades[TradeCount].partial50Done   = prevPartial50[j];
               Trades[TradeCount].partial75Done   = prevPartial75[j];
               break;
            }
         }
         TradeCount++;
      }
   }

   // ---- 4. Clear swap candle lock if no swap trade remains on a symbol ----
   for(int b = 0; b < boSymbolCount; b++)
   {
      if(CountSwapTradesForSymbol(boSymbols[b]) == 0)
         g_swapSignalCandleTime[b] = 0;
   }

   // ---- 5. One‑time fix: correct entryType for Gold/Oil RVI trades already in the array ----
   for(int t = 0; t < TradeCount; t++)
   {
      if(!PositionSelectByTicket(Trades[t].ticket)) continue;
      string cmt = PositionGetString(POSITION_COMMENT);

      // Skip BTC trades – they may contain "Index Order" but are actually Bitcoin trades
      if(StringFind(cmt, "BTC") >= 0) continue;

      if(StringFind(cmt, "GoldRVI") >= 0 && Trades[t].entryType != 4)
      {
         Trades[t].entryType = 4;
         Trades[t].isBO = false;
         Log("Corrected entryType to 4 (Gold RVI) for ticket " + IntegerToString(Trades[t].ticket), false);
      }
      if(StringFind(cmt, "OilRVI") >= 0 && Trades[t].entryType != 6)
      {
         Trades[t].entryType = 6;
         Trades[t].isBO = false;
         Log("Corrected entryType to 6 (Oil RVI) for ticket " + IntegerToString(Trades[t].ticket), false);
      }
      if(StringFind(cmt, "Index Order") >= 0 && Trades[t].entryType != 5)
      {
         Trades[t].entryType = 5;
         Trades[t].isBO = false;
         Log("Corrected entryType to 5 (Index) for ticket " + IntegerToString(Trades[t].ticket), false);
      }
   }

   // ---- 6. Check partial take‑profit & run trailing stop (unchanged) ----
   CheckPartialTakeProfit();
   RunTrailingStopForMagic();
}

// Apply a new stop‑loss if it is better (higher for buy, lower for sell)
bool ApplyBetterSL(ulong ticket, int tradeIdx, double newSL, ENUM_POSITION_TYPE dir, string sym)
{
   double curSL = PositionGetDouble(POSITION_SL);
   if(dir == POSITION_TYPE_BUY && newSL <= curSL) return false;
   if(dir == POSITION_TYPE_SELL && newSL >= curSL) return false;

   double currentPrice = (dir == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                     : SymbolInfoDouble(sym, SYMBOL_ASK);
   long   minStopPoints = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double point         = SymbolInfoDouble(sym, SYMBOL_POINT);
   double minDist       = minStopPoints * point;

   if(dir == POSITION_TYPE_BUY && (currentPrice - newSL) < minDist)
      newSL = currentPrice - minDist;
   if(dir == POSITION_TYPE_SELL && (newSL - currentPrice) < minDist)
      newSL = currentPrice + minDist;

   newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));

   if(Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
   {
      Trades[tradeIdx].currentSL      = newSL;
      Trades[tradeIdx].lastTrailPrice = currentPrice;
      Trades[tradeIdx].lastTrailTime  = TimeCurrent();
      return true;
   }
   return false;
}

void CheckPartialTakeProfit() {
   if(!UsePartialTP) return;
   
      // --- Check any pending breakeven candle‑close confirmations ---
   for(int t = 0; t < TradeCount; t++)
   {
      if(!Trades[t].breakevenPending) continue;
      if(!PositionSelectByTicket(Trades[t].ticket)) { Trades[t].breakevenPending = false; continue; }

      string sym        = Trades[t].pairSymbol;
      ENUM_POSITION_TYPE dir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double breakevenSL = Trades[t].breakevenSL;

      datetime currentCandle = iTime(sym, Timeframe, 0);
      if(currentCandle == 0) continue;
      if(currentCandle == Trades[t].lastBECheckCandle) continue;   // same candle → wait

      Trades[t].lastBECheckCandle = currentCandle;

      double closeArr[1];
      if(CopyClose(sym, Timeframe, 1, 1, closeArr) != 1) continue;

      bool confirmed = false;
      if(dir == POSITION_TYPE_BUY)
         confirmed = (closeArr[0] > breakevenSL);
      else   // SELL
         confirmed = (closeArr[0] < breakevenSL);

      if(confirmed)
      {
         // Move SL to the breakeven level
         if(ApplyBetterSL(Trades[t].ticket, t, breakevenSL, dir, sym))
         {
            Trades[t].partial25Done = true;
            Log("Partial TP 25%: SL trailed to " + DoubleToString(breakevenSL, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) + " on " + sym, true);
            if(PlaySounds && SoundFilePartialClose != "") PlaySound(SoundFilePartialClose);
         }
         Trades[t].breakevenPending = false;
      }
      else
      {
         // Candle close didn't confirm – clear pending, will re‑trigger if price returns
         Trades[t].breakevenPending = false;
      }
   }
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      string sym        = PositionGetString(POSITION_SYMBOL);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double tpPrice    = PositionGetDouble(POSITION_TP);
      string cmt        = PositionGetString(POSITION_COMMENT);
      bool isIndex      = (StringFind(cmt, "Index Order") >= 0);
      
      if(tpPrice <= 0) continue;

      int tradeIdx = -1;
      for(int t = 0; t < TradeCount; t++) {
         if(Trades[t].ticket == ticket) { tradeIdx = t; break; }
      }

      // ---- AUTO‑REGISTER missing trades (all types except swaps) ----
      if(tradeIdx < 0 && TradeCount < 50) {
         if(StringFind(cmt, "Swap Order") >= 0)
            continue;

         // No more per‑mode bypass – always register for counting.
         // The partial‑TP tiers will later respect the per‑mode flags.

         int autoEntryType = -1;
         bool isGoldSymbol = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);

         // Primary: use stored entry type from g_typeMap (survives partial close comment loss)
         int storedType = GetEntryType(ticket);
         if(storedType >= 0)
         {
            autoEntryType = storedType;
         }
         // Fallback: parse comment if stored type not available
         else if(StringFind(cmt, "GoldRVI") >= 0)
            autoEntryType = 4;
         else if(StringFind(cmt, "BreakOut Order") >= 0 && StringFind(cmt, "G_") >= 0)
            autoEntryType = 4;
         else if(StringFind(cmt, "BreakOut Order") >= 0)
            autoEntryType = 3;
         else if(StringFind(cmt, "Index Order") >= 0)
            autoEntryType = 5;
         else if(StringFind(cmt, "Threshold Order") >= 0)
            autoEntryType = isGoldSymbol ? 2 : 0;
         else if(StringFind(cmt, "OilRVI") >= 0)
            autoEntryType = 6;
         else if(StringFind(cmt, "BTC") >= 0)
            autoEntryType = 8;
         // Last resort: guess
         else if(isGoldSymbol)
            autoEntryType = 2;
         else
            autoEntryType = 0;
         
         double pipSizeTemp = (autoEntryType == 2 || autoEntryType == 4) ? 1.0 : GetPipSizeForSymbol(sym);  
         
         ENUM_POSITION_TYPE dir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentPriceTemp = (dir == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                              : SymbolInfoDouble(sym, SYMBOL_ASK);

         tradeIdx = TradeCount;
         Trades[tradeIdx].ticket         = ticket;
         Trades[tradeIdx].openPrice      = openPrice;
         Trades[tradeIdx].openTime       = (datetime)PositionGetInteger(POSITION_TIME);
         Trades[tradeIdx].currentSL      = PositionGetDouble(POSITION_SL);
         Trades[tradeIdx].pairSymbol     = sym;
         Trades[tradeIdx].isGold         = (autoEntryType == 2 || autoEntryType == 4);
         Trades[tradeIdx].isBO           = (autoEntryType == 3 || autoEntryType == 4);
         Trades[tradeIdx].entryType      = autoEntryType;
         SetEntryType(ticket, autoEntryType);   // store type so counters use it
         Trades[tradeIdx].lastTrailStep  = 0;
         Trades[tradeIdx].lastTrailPrice = currentPriceTemp;
         Trades[tradeIdx].lastTrailTime  = TimeCurrent();
         Trades[tradeIdx].partialDone    = false;
         Trades[tradeIdx].lastPartialTime = 0;
         Trades[tradeIdx].originalLot    = PositionGetDouble(POSITION_VOLUME);
         Trades[tradeIdx].partial25Done  = false;
         Trades[tradeIdx].partial50Done  = false;
         Trades[tradeIdx].partial75Done  = false;
         TradeCount++;
         Log("Auto‑registered trade " + IntegerToString(ticket) + " (type " + IntegerToString(autoEntryType) + ")", false);
      }
      
      if(tradeIdx < 0) continue;

      double pipSize = isIndex ? 1.0 : GetPipSizeForSymbol(sym);
      double fullTpPips = MathAbs(tpPrice - openPrice) / pipSize;
      if(fullTpPips <= 0) continue;

      ENUM_POSITION_TYPE dir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (dir == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                       : SymbolInfoDouble(sym, SYMBOL_ASK);
      double currentProfitPips = (dir == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / pipSize
                                                            : (openPrice - currentPrice) / pipSize;
      
      double originalVol = Trades[tradeIdx].originalLot;
      if(originalVol <= 0) originalVol = PositionGetDouble(POSITION_VOLUME);
      
      double positionVol = PositionGetDouble(POSITION_VOLUME);
      double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      // --- Tier 1 (25%) – set pending breakeven, wait for candle close ---
      if(!Trades[tradeIdx].partial25Done && !Trades[tradeIdx].breakevenPending &&
         currentProfitPips >= fullTpPips * 0.25)
      {
         if(Trades[tradeIdx].entryType == 4 && !GoldRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 6 && !OilRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 5 && !Index_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 8 && !BTC_UsePartialTP) continue;

         if(BreakEvenAfterPartial)
         {
            double tpDist = MathAbs(tpPrice - openPrice);
            double breakevenSL = (dir == POSITION_TYPE_BUY) ? openPrice + (BEPercentofTP * 0.01) * tpDist
                                                             : openPrice - (BEPercentofTP * 0.01) * tpDist;

            // Set pending confirmation – will be checked at candle close
            Trades[tradeIdx].breakevenPending = true;
            Trades[tradeIdx].breakevenSL = breakevenSL;
            Trades[tradeIdx].lastBECheckCandle = 0;   // force check on next new candle
            Trades[tradeIdx].lastPartialTime = TimeCurrent();
         }
         // No lots closed, no SL moved yet
         positionVol = PositionGetDouble(POSITION_VOLUME);
      }

      // --- Tier 2 (50%) ---
      if(!Trades[tradeIdx].partial50Done && currentProfitPips >= fullTpPips * 0.50) {
         if(Trades[tradeIdx].entryType == 4 && !GoldRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 6 && !OilRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 5 && !Index_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 8 && !BTC_UsePartialTP) continue;
         double closeLot = 0.25 * originalVol;
         closeLot = MathFloor(closeLot / lotStep) * lotStep;
         if(closeLot < minLot) closeLot = MathMin(minLot, positionVol);
         closeLot = NormalizeDouble(closeLot, 2);
         if(closeLot >= minLot && (positionVol - closeLot) >= minLot) {
            if(Trade.PositionClosePartial(ticket, closeLot)) {
               Trades[tradeIdx].partial50Done   = true;
               Trades[tradeIdx].lastPartialTime = TimeCurrent();
               Log("Partial TP 50% closed " + DoubleToString(closeLot, 2) + " lots on " + sym, true);
               if(PlaySounds && SoundFilePartialClose != "") PlaySound(SoundFilePartialClose);

               positionVol = PositionGetDouble(POSITION_VOLUME);
            }
         }
      }

      // --- Tier 3 (75%) ---
      if(!Trades[tradeIdx].partial75Done && currentProfitPips >= fullTpPips * 0.75) {
         if(Trades[tradeIdx].entryType == 4 && !GoldRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 6 && !OilRVI_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 5 && !Index_UsePartialTP) continue;
         if(Trades[tradeIdx].entryType == 8 && !BTC_UsePartialTP) continue;
         double closeLot = 0.25 * originalVol;
         closeLot = MathFloor(closeLot / lotStep) * lotStep;
         if(closeLot < minLot) closeLot = MathMin(minLot, positionVol);
         closeLot = NormalizeDouble(closeLot, 2);
         if(closeLot >= minLot && (positionVol - closeLot) >= minLot) {
            if(Trade.PositionClosePartial(ticket, closeLot)) {
               Trades[tradeIdx].partial75Done   = true;
               Trades[tradeIdx].lastPartialTime = TimeCurrent();
               Log("Partial TP 75% closed " + DoubleToString(closeLot, 2) + " lots on " + sym, true);
               if(PlaySounds && SoundFilePartialClose != "") PlaySound(SoundFilePartialClose);

            }
         }
      }
   }
}

double GetPipSizeForSymbol(string sym) {
   int idx = GetCachedIndex(sym);
   if(idx >= 0) return symCache[idx].pipSize;
   return GetPipSize(sym);
}

void RunTrailingStopForMagic() {
   if(!EnableTrailingStop) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string sym    = PositionGetString(POSITION_SYMBOL);
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      bool   isGold = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);
      
      // --- Index?aware pip size (same scaling as entry) ---
      string cmt = PositionGetString(POSITION_COMMENT);
      bool isIndex = (StringFind(cmt, "Index Order") >= 0);
      
      double pipSize;
      if(isGold)            pipSize = 1.0;
      else if(isIndex)      pipSize = 1.0;               // 1 pip = 100 points (index scaling)
      else                  pipSize = (digits == 3 || digits == 5) ? point * 10 : point;

      double entryPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE dir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (dir == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      double profitPips   = (dir == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) / pipSize : (entryPrice - currentPrice) / pipSize;

      // --- Activation: percentage of full TP distance ---
      double tpPrice = PositionGetDouble(POSITION_TP);
      double tpPips  = (tpPrice != 0.0) ? MathAbs(tpPrice - entryPrice) / pipSize : 0.0;
      double activationPips = 0.0;
      if(tpPips > 0)
         activationPips = tpPips * TrailActivationPercent / 100.0;
      else
         activationPips = 1.0;   // fallback – activate immediately if no TP (should never happen)

      if(isGold) activationPips *= GoldPipMultiplier;

      // Not enough profit yet to trigger trailing
      if(profitPips < activationPips) {
         continue;
      }

      // --- Dynamic trail distance / step based on progress toward TP ---
      double profitFraction = 0.0;
      if(tpPips > 0) {
         profitFraction = profitPips / tpPips;
         if(profitFraction > 1.0) profitFraction = 1.0;
      }

      // --- NEW: base distance starts as full TP distance, shrinks with profit ---
      double baseDistPips = tpPips * (1.0 - profitFraction);  // starts at tpPips, goes to 0
      if(isGold) baseDistPips *= GoldPipMultiplier;
      if(StringFind(cmt, "Swap Order") >= 0)
          baseDistPips *= SwapRiskMultiplier;
      
      // Step distance remains constant (or you can also shrink it if desired)
      double stepDistPips = TrailStepPips;
      if(isGold) stepDistPips *= GoldPipMultiplier;
      
      double trailDist = baseDistPips * pipSize;
      double stepDist  = stepDistPips * pipSize;

      double newStop;
      if(dir == POSITION_TYPE_BUY)
         newStop = currentPrice - trailDist;
      else
         newStop = currentPrice + trailDist;

      double currentSL = PositionGetDouble(POSITION_SL);

      // Stop already at or beyond target – no modification needed
      if(dir == POSITION_TYPE_BUY && newStop <= currentSL) continue;
      if(dir == POSITION_TYPE_SELL && newStop >= currentSL) continue;

      // Check step distance
      int tradeIdx = -1;
      for(int t=0; t<TradeCount; t++) { if(Trades[t].ticket == ticket) { tradeIdx = t; break; } }
      double lastTrailPrice = (tradeIdx >= 0 && Trades[tradeIdx].lastTrailPrice != 0) ? Trades[tradeIdx].lastTrailPrice : entryPrice;
      // --- CORRECTED step check (TrailStepPips=0 now works) ---
      if(dir == POSITION_TYPE_BUY)
      {
         if(stepDist > 0 && (currentPrice - lastTrailPrice) < stepDist)
         {
            Print("[TRAIL-DEBUG] ", sym, " ticket=", ticket, " step not met, price diff:", currentPrice - lastTrailPrice, " needed:", stepDist);
            continue;
         }
      }
      else
      {
         if(stepDist > 0 && (lastTrailPrice - currentPrice) < stepDist)
         {
            Print("[TRAIL-DEBUG] ", sym, " ticket=", ticket, " step not met, price diff:", lastTrailPrice - currentPrice, " needed:", stepDist);
            continue;
         }
      }

      // Respect broker minimum stop distance
      long minStopPoints = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = minStopPoints * point;
      if(MathAbs(currentPrice - newStop) < minStopDist) {
         Print("[TRAIL-DEBUG] ", sym, " ticket=", ticket, " Stop too close to market. dist=", MathAbs(currentPrice - newStop)/_Point, " pts, min allowed=", minStopDist/_Point, " pts");
         continue;
      }

      newStop = NormalizeDouble(newStop, digits);

      // --- Modify the position ---
      if(Trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP))) {
         if(tradeIdx >= 0) {
            Trades[tradeIdx].currentSL      = newStop;
            Trades[tradeIdx].lastTrailPrice = currentPrice;
            Trades[tradeIdx].lastTrailTime  = TimeCurrent();
         }
         // >>> Log the trailing event
         Log(StringFormat("[TRAIL] %s | Ticket=%d | Profit=%.1f pips (%.0f%% of TP) | SL moved to %.5f",
                          sym, ticket, profitPips, profitFraction*100, newStop), false);
      }
   }
}

//+------------------------------------------------------------------+
//| S/R DETECTION (MT5)                                              |
//+------------------------------------------------------------------+
void CalculateSRLevelsForSymbol(string symbol) {
   if(!ShowSRColumn && !SR_DrawLines) return;
   if(TimeCurrent() - lastSRCalcLog >= 300) {
      Log("[SR] Calculating levels for " + symbol, false);
      lastSRCalcLog = TimeCurrent();
   }
   int cacheIdx = -1;
   for(int i=0; i<srCacheCount; i++) {
      if(srCache[i].symbol == symbol) {
         cacheIdx = i;
         break;
      }
   }
   if(cacheIdx >= 0 && (TimeCurrent() - srCache[cacheIdx].lastCalc) < 3600) {
      currentSRCount = srCache[cacheIdx].count;
      for(int i=0; i<currentSRCount; i++) {
         currentSRLevels[i] = srCache[cacheIdx].levels[i];
      }
      return;
   }
   int maxBars = 1000;
   int barsToIgnore = 0;
   int _maxBars = MathMin(Bars(symbol, Timeframe), maxBars);
   if(_maxBars <= 0) return;
   
   int highestIdx = iHighest(symbol, Timeframe, MODE_HIGH, _maxBars, 0);
   int lowestIdx  = iLowest(symbol, Timeframe, MODE_LOW, _maxBars, 0);
   if(highestIdx < 0 || lowestIdx < 0) return;
   
   double highBuf[1], lowBuf[1];
   if(CopyHigh(symbol, Timeframe, highestIdx, 1, highBuf) <= 0) return;
   if(CopyLow(symbol, Timeframe, lowestIdx, 1, lowBuf) <= 0) return;
   double highest = highBuf[0];
   double lowest  = lowBuf[0];
   
   int atrHandle = iATR(symbol, Timeframe, SR_ATRPeriod);
   if(atrHandle == INVALID_HANDLE) return;
   double atrBuf[1];
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0) { IndicatorRelease(atrHandle); return; }
   double atr = atrBuf[0];
   IndicatorRelease(atrHandle);
   if(atr <= 0) return;
   
   double step = atr * SR_Accuracy;
   if(step == 0) return;
   
   int steps = (int)MathCeil((highest - lowest) / step) + 1;
   double levels[];
   ArrayResize(levels, steps);
   ArrayInitialize(levels, 0);
   
   int fractalsHandle = iFractals(symbol, Timeframe);
   if(fractalsHandle == INVALID_HANDLE) return;
   
   for(int i=0; i<steps; i++) {
      double startRange = lowest + step * i;
      double endRange = lowest + step * (i+1);
      int barCount = 0;
      double totalPrice = 0;
      
      for(int j=barsToIgnore; j<_maxBars+barsToIgnore; j++) {
         double upperFractal[1], lowerFractal[1];
         if(CopyBuffer(fractalsHandle, 0, j, 1, upperFractal) <= 0) continue;
         if(CopyBuffer(fractalsHandle, 1, j, 1, lowerFractal) <= 0) continue;
         
         double fractal = 0;
         if(upperFractal[0] > 0 && upperFractal[0] != EMPTY_VALUE) fractal = upperFractal[0];
         else if(lowerFractal[0] > 0 && lowerFractal[0] != EMPTY_VALUE) fractal = lowerFractal[0];
         
         if(fractal > 0 && fractal >= startRange && fractal <= endRange) {
            barCount++;
            totalPrice += fractal;
         }
      }
      if(barCount > 0) levels[i] = totalPrice / barCount;
   }
   IndicatorRelease(fractalsHandle);
   
   currentSRCount = 0;
   for(int i=0; i<steps; i++) {
      if(levels[i] > 0) {
         bool exists = false;
         for(int j=0; j<currentSRCount; j++) {
            if(MathAbs(currentSRLevels[j].levelPrice - levels[i]) <= step/2) {
               exists = true;
               currentSRLevels[j].touches++;
               break;
            }
         }
         if(!exists && currentSRCount < 100) {
            currentSRLevels[currentSRCount].levelPrice = levels[i];
            double close[1];
            if(CopyClose(symbol, Timeframe, 0, 1, close) > 0)
               currentSRLevels[currentSRCount].isResistance = (levels[i] > close[0]);
            else
               currentSRLevels[currentSRCount].isResistance = false;
            currentSRLevels[currentSRCount].touches = 1;
            currentSRCount++;
         }
      }
   }
   
   for(int i=0; i<currentSRCount-1; i++) {
      for(int j=i+1; j<currentSRCount; j++) {
         if(currentSRLevels[i].levelPrice > currentSRLevels[j].levelPrice) {
            SRLevel temp = currentSRLevels[i];
            currentSRLevels[i] = currentSRLevels[j];
            currentSRLevels[j] = temp;
         }
      }
   }
   
   if(cacheIdx == -1) {
      cacheIdx = srCacheCount;
      srCacheCount++;
   }
   srCache[cacheIdx].symbol = symbol;
   srCache[cacheIdx].count = currentSRCount;
   srCache[cacheIdx].lastCalc = TimeCurrent();
   for(int i=0; i<currentSRCount; i++) srCache[cacheIdx].levels[i] = currentSRLevels[i];
   if(SR_DrawLines && symbol == Symbol()) DrawSRLevels();
}

void DrawSRLevels() {
   if(!SR_DrawLines) return;
   for(int i=0; i<100; i++) {
      ObjectDelete(0, "EF_SR_" + IntegerToString(i));
      if(SR_DrawZones) ObjectDelete(0, "EF_SR_ZONE_" + IntegerToString(i));
   }
   for(int i=0; i<currentSRCount; i++) {
      string name = "EF_SR_" + IntegerToString(i);
      color lineColor = currentSRLevels[i].isResistance ? SR_ResistanceColor : SR_SupportColor;
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, currentSRLevels[i].levelPrice);
      ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, SR_LineThickness);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      string label = (currentSRLevels[i].isResistance ? "Res " : "Sup ") + DoubleToString(currentSRLevels[i].levelPrice, _Digits);
      ObjectSetString(0, name, OBJPROP_TEXT, label);
      if(SR_DrawZones) {
         string zoneName = "EF_SR_ZONE_" + IntegerToString(i);
         double upperPrice = currentSRLevels[i].levelPrice + SR_SafeDistance * _Point;
         double lowerPrice = currentSRLevels[i].levelPrice - SR_SafeDistance * _Point;
         color zoneColor = currentSRLevels[i].isResistance ? SR_ZoneResistanceColor : SR_ZoneSupportColor;
         ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, TimeCurrent(), lowerPrice, TimeCurrent()+PeriodSeconds()*1000, upperPrice);
         ObjectSetInteger(0, zoneName, OBJPROP_COLOR, zoneColor);
         ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
         ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
      }
   }
}

double GetNearestSRDistance(string symbol) {
   if(!ShowSRColumn) return -1;
   CalculateSRLevelsForSymbol(symbol);
   if(currentSRCount == 0) return -1;
   double close[1];
   if(CopyClose(symbol, Timeframe, 0, 1, close) <= 0) return -1;
   double currentClose = close[0];
   double point = GetSymbolPoint(symbol);
   double minDist = 9999999;
   for(int i=0; i<currentSRCount; i++) {
      double dist = MathAbs(currentClose - currentSRLevels[i].levelPrice) / point;
      if(dist < minDist) minDist = dist;
   }
   return minDist;
}

bool IsPriceTouchingSR(string symbol) {
   if(!ShowSRColumn) return false;
   CalculateSRLevelsForSymbol(symbol);
   if(currentSRCount == 0) return false;
   double close[1];
   if(CopyClose(symbol, Timeframe, 0, 1, close) <= 0) return false;
   double currentClose = close[0];
   double point = GetSymbolPoint(symbol);
   double touchBuffer = point * 2.0;
   for(int i=0; i<currentSRCount; i++) {
      if(MathAbs(currentClose - currentSRLevels[i].levelPrice) <= touchBuffer) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD FUNCTIONS (MT5)                                        |
//+------------------------------------------------------------------+
void SafeSetText(string name, string text) {
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DeleteDashboard() {
   for(int i=0;i<8;i++) {
      ObjectDelete(0,"DB_Curr_"+Currencies[i]);
      ObjectDelete(0,"DB_BarBg_"+Currencies[i]);
      ObjectDelete(0,"DB_Bar_"+Currencies[i]);
      
   }
   string objs[] = {"DB_BG","DB_Header","DB_Title","DB_StatusLabel","DB_Status","DB_Reverse","DB_Trendfilter","DB_BarHeader",
                    "DB_GapLabel","DB_GapOpen","DB_GapOpenVal","DB_GapClose","DB_GapCloseVal",
                    "DB_CurrGapLabel","DB_CurrGapVal","DB_SpreadLabel","DB_SpreadVal",
                    "DB_StrongWeak","DB_Target","DB_GapValueLabel","DB_GapValue"};
   for(int i=0;i<ArraySize(objs);i++) ObjectDelete(0,objs[i]);
   for(int i=0; i<15; i++) {
      ObjectDelete(0,"DB2_PairName_"+IntegerToString(i));
      ObjectDelete(0,"DB2_PairGap_"+IntegerToString(i));
      ObjectDelete(0,"DB2_PairCount_"+IntegerToString(i));
   }
   ObjectDelete(0,"DB2_FxCounter");
   ObjectDelete(0,"DB2_BOCounter");
   ObjectDelete(0,"DB2_AuCounter");
   ObjectDelete(0,"DB2_BOGoldCounter");
   ObjectDelete(0,"DB2_SwapCounter");
   ObjectDelete(0,"DB2_IndexCounter");
   ObjectDelete(0,"DB2_BG");
   ObjectDelete(0,"DB2_Header");
   ObjectDelete(0,"DB2_Title");
   ObjectDelete(0,"DB2_CloseStatusLabel");
   for(int i=0; i<PairCount; i++) {
      ObjectDelete(0,"DB3_PairName_"+IntegerToString(i));
      ObjectDelete(0,"DB3_PairGap_"+IntegerToString(i));
      if(ShowSRColumn) ObjectDelete(0,"DB3_SRDist_"+IntegerToString(i));
      if(ShowBOMonitorPanel) ObjectDelete(0, "DB3_BOStatus_"+IntegerToString(i));
      if(ShowBOMonitorPanel) ObjectDelete(0, "DB3_BOThr_"+IntegerToString(i));
      ObjectDelete(0, "DB3_Swap_"+IntegerToString(i));
   }
   ObjectDelete(0,"DB3_Header");
   ObjectDelete(0,"DB3_Title");
   ObjectDelete(0,"DB3_Hdr_Pair");
   ObjectDelete(0,"DB3_Hdr_Gap");
   ObjectDelete(0,"DB3_Hdr_SR");
   ObjectDelete(0,"DB3_Hdr_BO");
   ObjectDelete(0,"DB3_Hdr_Swap");
   ObjectDelete(0,"DB4_BG");
   ObjectDelete(0,"DB4_Header");
   ObjectDelete(0,"DB4_Title");
   ObjectDelete(0,"DB4_GoldEnabled");
   ObjectDelete(0,"DB4_UsdStrength");
   ObjectDelete(0,"DB4_SellOpen");
   ObjectDelete(0,"DB4_BuyOpen");
   ObjectDelete(0,"DB4_CloseThreshold");
   ObjectDelete(0,"DB4_GoldSpread");
   ObjectDelete(0,"DB4_StatusLabel");
   ObjectDelete(0,"DB4_GoldTradeStatus");
   ObjectDelete(0,"DB4_GoldTradePips");
   ObjectDelete(0,"DB4_GoldParamsHeader");
   string paramIds[4] = {"ProfitDollars","SLPips","MaxTrades","MaxSpread"};
   for(int p=0; p<4; p++) {
      ObjectDelete(0, "DB4_"+paramIds[p]+"_Lbl");
      ObjectDelete(0, "DB4_"+paramIds[p]+"_Val");
   }
   ObjectDelete(0,"DB5_BG");
   ObjectDelete(0,"DB5_Header");
   ObjectDelete(0,"DB5_Title");
   ObjectDelete(0,"DB5_TradingLabel");
   ObjectDelete(0,"DB5_TradingValue");
   ObjectDelete(0,"DB5_MagicLabel");
   ObjectDelete(0,"DB5_MagicValue");
   ObjectDelete(0,"DB5_ProfitLabel");
   ObjectDelete(0,"DB5_ProfitValue");
   ObjectDelete(0,"DB5_SLPipsLabel");
   ObjectDelete(0,"DB5_SLPipsValue");
   ObjectDelete(0,"DB5_BOLabel");
   ObjectDelete(0,"DB5_BOValue");
   ObjectDelete(0,"DB5_BOMaxPerSymbolLabel");
   ObjectDelete(0,"DB5_BOMaxPerSymbolValue");
   ObjectDelete(0,"DB5_BOBlockHoursLabel");
   ObjectDelete(0,"DB5_BOBlockHoursValue");
   ObjectDelete(0,"DB5_BOSwapThresholdLabel");
   ObjectDelete(0,"DB5_BOSwapThresholdValue");
   ObjectDelete(0,"DB5_BORevADXLabel");
   ObjectDelete(0,"DB5_BORevADXValue");
   ObjectDelete(0,"DB5_SwapLabel");
   ObjectDelete(0,"DB5_SwapValue");
   ObjectDelete(0,"DB5_TrailingLabel");
   ObjectDelete(0,"DB5_TrailingValue");
   ObjectDelete(0,"DB5_TriggerLabel");
   ObjectDelete(0,"DB5_TriggerValue");
   ObjectDelete(0,"DB5_PyramidLabel");
   ObjectDelete(0,"DB5_PyramidValue");
   ObjectDelete(0,"DB5_DailyResetLabel");
   ObjectDelete(0,"DB5_DailyResetValue");
   ObjectDelete(0, "DB_Curr_METALS");
   ObjectDelete(0, "DB_BarBg_METALS");
   ObjectDelete(0, "DB_Bar_METALS");
   ObjectDelete(0, "DB5_TrailActLabel");
   ObjectDelete(0, "DB5_TrailActValue");
   ObjectDelete(0, "DB5_TrailDistLabel");
   ObjectDelete(0, "DB5_TrailDistValue");
   ObjectDelete(0, "DB5_TrailStepLabel");
   ObjectDelete(0, "DB5_TrailStepValue");
   ObjectDelete(0, "DB5_Session");
   ObjectDelete(0,"DB2_OilCounter");
   ObjectDelete(0,"DB2_DailyTradesCounter");
   ObjectDelete(0,"DB2_BTCCounter");
}

void CreateDashboard() {
   DeleteDashboard();
   
   int w1 = 355, w2 = 275, w3 = ShowSRColumn ? (ShowBOMonitorPanel ? 470 : 280) : (ShowBOMonitorPanel ? 370 : 250), w4 = 170, w5 = 240, h = 460 + (ShowMetalsStrength ? 22 : 0), spacing = 5;
   
   bool visPairs   = ShowDashboard && ShowPairsPanel;
   bool visMain    = ShowDashboard && ShowMainPanel;
   bool visLive    = ShowDashboard && ShowLivePanel;
   bool visGold    = ShowDashboard && ShowGoldPanel && TradeGold;
   bool visSettings= ShowDashboard && ShowSettingsPanel;
   
   string panelOrder[5];
   int    panelWidths[5];
   int    visibleCount = 0;
   
   if(visPairs)    { panelOrder[visibleCount] = "Pairs";    panelWidths[visibleCount] = w3; visibleCount++; }
   if(visMain)     { panelOrder[visibleCount] = "Main";     panelWidths[visibleCount] = w1; visibleCount++; }
   if(visLive)     { panelOrder[visibleCount] = "Live";     panelWidths[visibleCount] = w2; visibleCount++; }
   if(visGold)     { panelOrder[visibleCount] = "Gold";     panelWidths[visibleCount] = w4; visibleCount++; }
   if(visSettings) { panelOrder[visibleCount] = "Settings"; panelWidths[visibleCount] = w5; visibleCount++; }
   
   int currentX = DashboardXpos;
   int x_pairs = 0, x_main = 0, x_live = 0, x_gold = 0, x_settings = 0;
   
   for(int i = 0; i < visibleCount; i++) {
      if(panelOrder[i] == "Pairs")    { x_pairs = currentX; ThirdPanelXpos = currentX; }
      if(panelOrder[i] == "Main")     { x_main  = currentX; }
      if(panelOrder[i] == "Live")     { x_live  = currentX; SecondPanelXpos = currentX; }
      if(panelOrder[i] == "Gold")     { x_gold  = currentX; FourthPanelXpos = currentX; }
      if(panelOrder[i] == "Settings") { x_settings = currentX; FifthPanelXpos = currentX; }
      currentX += panelWidths[i] + spacing;
   }

   // ========== MAIN PANEL ==========
   if(visMain) {
      ObjectCreate(0,"DB_BG",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_BG",OBJPROP_XDISTANCE, x_main);
      ObjectSetInteger(0,"DB_BG",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB_BG",OBJPROP_XSIZE, w1);
      ObjectSetInteger(0,"DB_BG",OBJPROP_YSIZE, h);
      ObjectSetInteger(0,"DB_BG",OBJPROP_BGCOLOR, C'25,30,40');
      ObjectSetInteger(0,"DB_BG",OBJPROP_BORDER_COLOR, C'25,30,40');

      ObjectCreate(0,"DB_Header",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_Header",OBJPROP_XDISTANCE, x_main);
      ObjectSetInteger(0,"DB_Header",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB_Header",OBJPROP_XSIZE, w1);
      ObjectSetInteger(0,"DB_Header",OBJPROP_YSIZE, 35);
      ObjectSetInteger(0,"DB_Header",OBJPROP_BGCOLOR, C'45,70,110');
      ObjectSetInteger(0,"DB_Header",OBJPROP_BORDER_COLOR, C'45,70,110');

      ObjectCreate(0,"DB_Title",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_Title",OBJPROP_XDISTANCE, x_main + 15);
      ObjectSetInteger(0,"DB_Title",OBJPROP_YDISTANCE, DashboardYpos + 10);
      ObjectSetString(0,"DB_Title",OBJPROP_TEXT, "S&D Trading EA");
      ObjectSetInteger(0,"DB_Title",OBJPROP_COLOR, C'255,255,255');
      ObjectSetInteger(0,"DB_Title",OBJPROP_FONTSIZE, 12);

      int x = x_main;
      int y = DashboardYpos;
      int col1 = 15, col3 = 200, row = 50;

      ObjectCreate(0,"DB_StatusLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_StatusLabel",OBJPROP_XDISTANCE, x+col1);
      ObjectSetInteger(0,"DB_StatusLabel",OBJPROP_YDISTANCE, y+row);
      ObjectSetString(0,"DB_StatusLabel",OBJPROP_TEXT, "STATUS");
      ObjectSetInteger(0,"DB_StatusLabel",OBJPROP_COLOR, C'220,240,255');
      ObjectSetInteger(0,"DB_StatusLabel",OBJPROP_FONTSIZE, 11);
      row += 20;

      ObjectCreate(0,"DB_Status",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_Status",OBJPROP_XDISTANCE, x+col1);
      ObjectSetInteger(0,"DB_Status",OBJPROP_YDISTANCE, y+row);
      ObjectSetString(0,"DB_Status",OBJPROP_TEXT, "Status: Waiting");
      ObjectSetInteger(0,"DB_Status",OBJPROP_COLOR, C'255,255,200');
      ObjectSetInteger(0,"DB_Status",OBJPROP_FONTSIZE, 11);
      row += 18;

      ObjectCreate(0,"DB_Reverse",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_Reverse",OBJPROP_XDISTANCE, x+col1);
      ObjectSetInteger(0,"DB_Reverse",OBJPROP_YDISTANCE, y+row);
      ObjectSetString(0,"DB_Reverse",OBJPROP_TEXT, ReverseTrades ? "Reverse: ON" : "Reverse: OFF");
      ObjectSetInteger(0,"DB_Reverse",OBJPROP_COLOR, ReverseTrades ? C'255,150,150' : C'150,255,150');
      ObjectSetInteger(0,"DB_Reverse",OBJPROP_FONTSIZE, 10);

      row += 33;
      ObjectCreate(0,"DB_BarHeader",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_BarHeader",OBJPROP_XDISTANCE, x+col1);
      ObjectSetInteger(0,"DB_BarHeader",OBJPROP_YDISTANCE, y+row);
      ObjectSetString(0,"DB_BarHeader",OBJPROP_TEXT, "CURRENCY STRENGTH");
      ObjectSetInteger(0,"DB_BarHeader",OBJPROP_COLOR, C'220,240,255');
      ObjectSetInteger(0,"DB_BarHeader",OBJPROP_FONTSIZE, 11);
      row += 20;

      for(int i=0; i<8; i++) {
         int r = row + i*22;
         ObjectCreate(0, "DB_Curr_"+Currencies[i], OBJ_LABEL, 0,0,0);
         ObjectSetInteger(0, "DB_Curr_"+Currencies[i], OBJPROP_XDISTANCE, x+col1);
         ObjectSetInteger(0, "DB_Curr_"+Currencies[i], OBJPROP_YDISTANCE, y+r);
         ObjectSetString(0, "DB_Curr_"+Currencies[i], OBJPROP_TEXT, Currencies[i]+": 0.0%");
         ObjectSetInteger(0, "DB_Curr_"+Currencies[i], OBJPROP_COLOR, C'150,220,255');
         ObjectSetInteger(0, "DB_Curr_"+Currencies[i], OBJPROP_FONTSIZE, 10);

         ObjectCreate(0, "DB_BarBg_"+Currencies[i], OBJ_RECTANGLE_LABEL, 0,0,0);
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_XDISTANCE, x+col3);
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_YDISTANCE, y+r-2);
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_XSIZE, 100);
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_YSIZE, 14);
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_BGCOLOR, C'40,45,55');
         ObjectSetInteger(0, "DB_BarBg_"+Currencies[i], OBJPROP_BORDER_COLOR, C'40,45,55');

         ObjectCreate(0, "DB_Bar_"+Currencies[i], OBJ_RECTANGLE_LABEL, 0,0,0);
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_XDISTANCE, x+col3);
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_YDISTANCE, y+r-2);
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_XSIZE, 0);
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_YSIZE, 14);
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_BGCOLOR, C'0,160,80');
         ObjectSetInteger(0, "DB_Bar_"+Currencies[i], OBJPROP_BORDER_COLOR, C'0,160,80');
      }
      row += 8*22 + 28;
      
            // +------------------------------------------------------------------+
      // | PRECIOUS METALS STRENGTH BAR                                      |
      // +------------------------------------------------------------------+
      if(ShowMetalsStrength) {
         int metalsRow = row;
         ObjectCreate(0, "DB_Curr_METALS", OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, "DB_Curr_METALS", OBJPROP_XDISTANCE, x+col1);
         ObjectSetInteger(0, "DB_Curr_METALS", OBJPROP_YDISTANCE, y+metalsRow-29);
         ObjectSetString(0, "DB_Curr_METALS", OBJPROP_TEXT, "METALS: 0.0%");
         ObjectSetInteger(0, "DB_Curr_METALS", OBJPROP_COLOR, C'255,215,0');
         ObjectSetInteger(0, "DB_Curr_METALS", OBJPROP_FONTSIZE, 10);

         ObjectCreate(0, "DB_BarBg_METALS", OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_XDISTANCE, x+col3);
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_YDISTANCE, y+metalsRow-29);
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_XSIZE, 100);
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_YSIZE, 14);
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_BGCOLOR, C'40,45,55');
         ObjectSetInteger(0, "DB_BarBg_METALS", OBJPROP_BORDER_COLOR, C'40,45,55');

         ObjectCreate(0, "DB_Bar_METALS", OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_XDISTANCE, x+col3);
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_YDISTANCE, y+metalsRow-29);
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_XSIZE, 0);
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_YSIZE, 14);
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_BGCOLOR, C'255,215,0');
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_BORDER_COLOR, C'255,215,0');

         row += 22;  // Make room for the metals bar
      }

      ObjectCreate(0,"DB_Target",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_Target",OBJPROP_XDISTANCE, x+col1);
      ObjectSetInteger(0,"DB_Target",OBJPROP_YDISTANCE, y+row+86);
      ObjectSetString(0,"DB_Target",OBJPROP_TEXT, "TARGET: ---");
      ObjectSetInteger(0,"DB_Target",OBJPROP_COLOR, C'255,220,100');
      ObjectSetInteger(0,"DB_Target",OBJPROP_FONTSIZE, 11);
      row += 20;

      int bottomY = y + row -29;
      int leftLabelX = x + col1;
      int leftValueX = leftLabelX + 80;
      int rightLabelX = x + col3 - 20;
      int rightValueX = rightLabelX + 60;

      ObjectCreate(0,"DB_GapLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapLabel",OBJPROP_XDISTANCE, leftLabelX);
      ObjectSetInteger(0,"DB_GapLabel",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapLabel",OBJPROP_TEXT, "ENTRY THRESHOLDS");
      ObjectSetInteger(0,"DB_GapLabel",OBJPROP_COLOR, C'220,240,255');
      ObjectSetInteger(0,"DB_GapLabel",OBJPROP_FONTSIZE, 11);
      bottomY += 20;

      ObjectCreate(0,"DB_GapOpen",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapOpen",OBJPROP_XDISTANCE, leftLabelX);
      ObjectSetInteger(0,"DB_GapOpen",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapOpen",OBJPROP_TEXT, "> Thresh:");
      ObjectSetInteger(0,"DB_GapOpen",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_GapOpen",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB_GapOpenVal",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapOpenVal",OBJPROP_XDISTANCE, leftValueX-15);
      ObjectSetInteger(0,"DB_GapOpenVal",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapOpenVal",OBJPROP_TEXT, DoubleToString(StrongEntryThreshold,1)+"%");
      ObjectSetInteger(0,"DB_GapOpenVal",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_GapOpenVal",OBJPROP_FONTSIZE, 10);
      bottomY += 18;

      ObjectCreate(0,"DB_GapClose",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapClose",OBJPROP_XDISTANCE, leftLabelX);
      ObjectSetInteger(0,"DB_GapClose",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapClose",OBJPROP_TEXT, "< Thresh:");
      ObjectSetInteger(0,"DB_GapClose",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_GapClose",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB_GapCloseVal",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapCloseVal",OBJPROP_XDISTANCE, leftValueX-15);
      ObjectSetInteger(0,"DB_GapCloseVal",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapCloseVal",OBJPROP_TEXT, DoubleToString(WeakEntryThreshold,1)+"%");
      ObjectSetInteger(0,"DB_GapCloseVal",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_GapCloseVal",OBJPROP_FONTSIZE, 10);
      bottomY += 18;

      ObjectCreate(0,"DB_CurrGapLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_CurrGapLabel",OBJPROP_XDISTANCE, leftLabelX);
      ObjectSetInteger(0,"DB_CurrGapLabel",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_CurrGapLabel",OBJPROP_TEXT, "Strong / Weak:");
      ObjectSetInteger(0,"DB_CurrGapLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_CurrGapLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB_CurrGapVal",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_XDISTANCE, leftValueX+15);
      ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_CurrGapVal",OBJPROP_TEXT, "");
      ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_COLOR, C'255,220,100');
      ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_FONTSIZE, 10);
      bottomY += 18;

      ObjectCreate(0,"DB_GapValueLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapValueLabel",OBJPROP_XDISTANCE, leftLabelX);
      ObjectSetInteger(0,"DB_GapValueLabel",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapValueLabel",OBJPROP_TEXT, "Gap / Min:");
      ObjectSetInteger(0,"DB_GapValueLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_GapValueLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB_GapValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_GapValue",OBJPROP_XDISTANCE, leftValueX-17);
      ObjectSetInteger(0,"DB_GapValue",OBJPROP_YDISTANCE, bottomY);
      ObjectSetString(0,"DB_GapValue",OBJPROP_TEXT, "");
      ObjectSetInteger(0,"DB_GapValue",OBJPROP_COLOR, C'255,220,100');
      ObjectSetInteger(0,"DB_GapValue",OBJPROP_FONTSIZE, 10);
      bottomY += 18;

      ObjectCreate(0,"DB_SpreadLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_SpreadLabel",OBJPROP_XDISTANCE, rightLabelX);
      ObjectSetInteger(0,"DB_SpreadLabel",OBJPROP_YDISTANCE, bottomY-18);
      ObjectSetString(0,"DB_SpreadLabel",OBJPROP_TEXT, "Spread:");
      ObjectSetInteger(0,"DB_SpreadLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_SpreadLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB_SpreadVal",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB_SpreadVal",OBJPROP_XDISTANCE, rightValueX-10);
      ObjectSetInteger(0,"DB_SpreadVal",OBJPROP_YDISTANCE, bottomY-18);
      ObjectSetString(0,"DB_SpreadVal",OBJPROP_TEXT, "0.0 / "+DoubleToString(MaxSpreadPips,1)+" pips");
      ObjectSetInteger(0,"DB_SpreadVal",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB_SpreadVal",OBJPROP_FONTSIZE, 10);
   }

   // ========== LIVE TRADES PANEL ==========
   if(visLive) {
      int counterY = DashboardYpos + h - 50;
      ObjectCreate(0,"DB2_BG",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_BG",OBJPROP_XDISTANCE, SecondPanelXpos);
      ObjectSetInteger(0,"DB2_BG",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB2_BG",OBJPROP_XSIZE, w2);
      ObjectSetInteger(0,"DB2_BG",OBJPROP_YSIZE, h);
      ObjectSetInteger(0,"DB2_BG",OBJPROP_BGCOLOR, C'25,30,40');
      ObjectSetInteger(0,"DB2_BG",OBJPROP_BORDER_COLOR, C'25,30,40');

      ObjectCreate(0,"DB2_Header",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_Header",OBJPROP_XDISTANCE, SecondPanelXpos);
      ObjectSetInteger(0,"DB2_Header",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB2_Header",OBJPROP_XSIZE, w2);
      ObjectSetInteger(0,"DB2_Header",OBJPROP_YSIZE, 35);
      ObjectSetInteger(0,"DB2_Header",OBJPROP_BGCOLOR, C'45,70,110');
      ObjectSetInteger(0,"DB2_Header",OBJPROP_BORDER_COLOR, C'45,70,110');

      ObjectCreate(0,"DB2_Title",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_Title",OBJPROP_XDISTANCE, SecondPanelXpos+15);
      ObjectSetInteger(0,"DB2_Title",OBJPROP_YDISTANCE, DashboardYpos+10);
      ObjectSetString(0,"DB2_Title",OBJPROP_TEXT, "LIVE TRADES");
      ObjectSetInteger(0,"DB2_Title",OBJPROP_COLOR, C'255,255,255');
      ObjectSetInteger(0,"DB2_Title",OBJPROP_FONTSIZE, 11);

      for(int i=0; i<15; i++) {
         string pairName = "DB2_PairName_"+IntegerToString(i);
         string pairGap = "DB2_PairGap_"+IntegerToString(i);
         string pairCount = "DB2_PairCount_"+IntegerToString(i);
         ObjectCreate(0,pairName, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,pairName, OBJPROP_XDISTANCE, SecondPanelXpos+10);
         ObjectSetInteger(0,pairName, OBJPROP_YDISTANCE, DashboardYpos+50 + i*12);
         ObjectSetString(0,pairName, OBJPROP_TEXT, "");
         ObjectSetInteger(0,pairName, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0,pairName, OBJPROP_FONTSIZE, 10);
         ObjectCreate(0,pairGap, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,pairGap, OBJPROP_XDISTANCE, SecondPanelXpos+100);
         ObjectSetInteger(0,pairGap, OBJPROP_YDISTANCE, DashboardYpos+50 + i*12);
         ObjectSetString(0,pairGap, OBJPROP_TEXT, "");
         ObjectSetInteger(0,pairGap, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0,pairGap, OBJPROP_FONTSIZE, 10);
         ObjectCreate(0,pairCount, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,pairCount, OBJPROP_XDISTANCE, SecondPanelXpos+150);
         ObjectSetInteger(0,pairCount, OBJPROP_YDISTANCE, DashboardYpos+50 + i*12);
         ObjectSetString(0,pairCount, OBJPROP_TEXT, "");
         ObjectSetInteger(0,pairCount, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0,pairCount, OBJPROP_FONTSIZE, 10);
      }
      
      int yOffset = counterY - 180;

      yOffset += 20;
      ObjectCreate(0,"DB2_DailyTradesCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_DailyTradesCounter",OBJPROP_TEXT, "Daily Trades: 0 / "+IntegerToString(MaxDailyTradesGlobal));
      ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_FxCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_FxCounter",OBJPROP_TEXT, "Open FX Trades: 0 / "+IntegerToString(MaxForexTrades));
      ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_BOCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_BOCounter",OBJPROP_TEXT, "Open BO Trades: 0 / "+IntegerToString(MaxBOTrades));
      ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_AuCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_AuCounter",OBJPROP_TEXT, "Open XAU Trades: 0 / "+IntegerToString(MaxGoldTrades));
      ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_BOGoldCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_BOGoldCounter",OBJPROP_TEXT, "Open BO XAU: 0 / "+IntegerToString(MaxBOGoldTrades));
      ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_OilCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_OilCounter",OBJPROP_TEXT, "Open Oil Trades: 0 / "+IntegerToString(MaxOilTrades));
      ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_BTCCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_BTCCounter",OBJPROP_TEXT, "Open BTC Trades: 0 / "+IntegerToString(MaxBitcoinTrades));
      ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_SwapCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_SwapCounter",OBJPROP_TEXT, "Open Swap Trades: 0 / "+IntegerToString(MaxSwapTrades));
      ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_FONTSIZE, 10);
      
      ObjectCreate(0,"DB2_CloseStatusLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_YDISTANCE, DashboardYpos+h-29);
      ObjectSetString(0,"DB2_CloseStatusLabel",OBJPROP_TEXT, "Status: Waiting to close");
      ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_COLOR, C'255,200,100');
      ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_FONTSIZE, 10);
      
      yOffset += 20;
      ObjectCreate(0,"DB2_IndexCounter",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_XDISTANCE, SecondPanelXpos+8);
      ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0,"DB2_IndexCounter",OBJPROP_TEXT, "Open Index Trades: 0 / "+IntegerToString(MaxIndexTrades));
      ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_FONTSIZE, 10);
   }

   // ========== PAIRS PANEL ==========
   if(visPairs) {
      // --- ADJUSTED column positions & panel width to avoid title cut-off ---
      int xPairName = ThirdPanelXpos + 5;      // shifted left a little
      int xGap      = ThirdPanelXpos + 85;
      int xSRDist   = ThirdPanelXpos + 140;    // moved slightly right
      int xBO       = ThirdPanelXpos + 185;    // moved to fit BO threshold info
      int xSwap = ThirdPanelXpos + (ShowSRColumn ? 385 : 230);
      
      // Header
      ObjectCreate(0,"DB3_Header",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB3_Header",OBJPROP_XDISTANCE, ThirdPanelXpos);
      ObjectSetInteger(0,"DB3_Header",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB3_Header",OBJPROP_XSIZE, w3);
      ObjectSetInteger(0,"DB3_Header",OBJPROP_YSIZE, 35);
      ObjectSetInteger(0,"DB3_Header",OBJPROP_BGCOLOR, C'200,20,20');
      ObjectSetInteger(0,"DB3_Header",OBJPROP_BORDER_COLOR, C'45,70,110');
      
      // ?? Column headers perfectly aligned with data cells ??
      int hdrY = DashboardYpos + 8;          // same vertical offset as before
      int hdrFontSize = 8;
      color hdrColor = C'255,255,255';
      
      // Pair column header
      ObjectCreate(0,"DB3_Hdr_Pair",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB3_Hdr_Pair",OBJPROP_XDISTANCE, xPairName);
      ObjectSetInteger(0,"DB3_Hdr_Pair",OBJPROP_YDISTANCE, hdrY);
      ObjectSetString(0,"DB3_Hdr_Pair",OBJPROP_TEXT,"PAIR");
      ObjectSetInteger(0,"DB3_Hdr_Pair",OBJPROP_COLOR, hdrColor);
      ObjectSetInteger(0,"DB3_Hdr_Pair",OBJPROP_FONTSIZE, hdrFontSize);
      
      // Gap column header
      ObjectCreate(0,"DB3_Hdr_Gap",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB3_Hdr_Gap",OBJPROP_XDISTANCE, xGap);
      ObjectSetInteger(0,"DB3_Hdr_Gap",OBJPROP_YDISTANCE, hdrY);
      ObjectSetString(0,"DB3_Hdr_Gap",OBJPROP_TEXT,"GAP%");
      ObjectSetInteger(0,"DB3_Hdr_Gap",OBJPROP_COLOR, hdrColor);
      ObjectSetInteger(0,"DB3_Hdr_Gap",OBJPROP_FONTSIZE, hdrFontSize);
      
      // S/R header (only if column is visible)
      if(ShowSRColumn) {
         ObjectCreate(0,"DB3_Hdr_SR",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DB3_Hdr_SR",OBJPROP_XDISTANCE, xSRDist);
         ObjectSetInteger(0,"DB3_Hdr_SR",OBJPROP_YDISTANCE, hdrY);
         ObjectSetString(0,"DB3_Hdr_SR",OBJPROP_TEXT,"S/R");
         ObjectSetInteger(0,"DB3_Hdr_SR",OBJPROP_COLOR, hdrColor);
         ObjectSetInteger(0,"DB3_Hdr_SR",OBJPROP_FONTSIZE, hdrFontSize);
      } else {
         ObjectDelete(0,"DB3_Hdr_SR");   // make sure it's removed if column is off
      }
      
      // BO header (only if BO monitor panel is shown)
      if(ShowBOMonitorPanel) {
         ObjectCreate(0,"DB3_Hdr_BO",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DB3_Hdr_BO",OBJPROP_XDISTANCE, xBO);
         ObjectSetInteger(0,"DB3_Hdr_BO",OBJPROP_YDISTANCE, hdrY);
         // Show BO(Box / Thr) to indicate both are displayed
         string boHdrText = "BO(H/L" + (EnableBOMode && BO_UseReversalEntry ? "/Thr" : "") + ")";
         ObjectSetString(0,"DB3_Hdr_BO",OBJPROP_TEXT, boHdrText);
         ObjectSetInteger(0,"DB3_Hdr_BO",OBJPROP_COLOR, hdrColor);
         ObjectSetInteger(0,"DB3_Hdr_BO",OBJPROP_FONTSIZE, hdrFontSize);
      } else {
         ObjectDelete(0,"DB3_Hdr_BO");
      }
      
      // Swap column header
      ObjectCreate(0,"DB3_Hdr_Swap",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB3_Hdr_Swap",OBJPROP_XDISTANCE, xSwap);
      ObjectSetInteger(0,"DB3_Hdr_Swap",OBJPROP_YDISTANCE, hdrY);
      ObjectSetString(0,"DB3_Hdr_Swap",OBJPROP_TEXT,"SWAP(L/S)");
      ObjectSetInteger(0,"DB3_Hdr_Swap",OBJPROP_COLOR, hdrColor);
      ObjectSetInteger(0,"DB3_Hdr_Swap",OBJPROP_FONTSIZE, hdrFontSize);

      // Create the pair rows (same loop as before, just using new x positions)
      for(int i=0; i<PairCount; i++) {
         string pairName = "DB3_PairName_"+IntegerToString(i);
         ObjectCreate(0,pairName, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,pairName, OBJPROP_XDISTANCE, xPairName);
         ObjectSetInteger(0,pairName, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
         ObjectSetString(0,pairName, OBJPROP_TEXT, "");
         ObjectSetInteger(0,pairName, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0,pairName, OBJPROP_FONTSIZE, 9);
         
         string pairGap = "DB3_PairGap_"+IntegerToString(i);
         ObjectCreate(0,pairGap, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,pairGap, OBJPROP_XDISTANCE, xGap);
         ObjectSetInteger(0,pairGap, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
         ObjectSetString(0,pairGap, OBJPROP_TEXT, "");
         ObjectSetInteger(0,pairGap, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0,pairGap, OBJPROP_FONTSIZE, 9);
         
         if(ShowSRColumn) {
            string srDist = "DB3_SRDist_"+IntegerToString(i);
            ObjectCreate(0,srDist, OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,srDist, OBJPROP_XDISTANCE, xSRDist);
            ObjectSetInteger(0,srDist, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
            ObjectSetString(0,srDist, OBJPROP_TEXT, "");
            ObjectSetInteger(0,srDist, OBJPROP_COLOR, C'200,200,200');
            ObjectSetInteger(0,srDist, OBJPROP_FONTSIZE, 9);
         }
         
         if(ShowBOMonitorPanel) {
            string boStatus = "DB3_BOStatus_"+IntegerToString(i);
            ObjectCreate(0,boStatus, OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,boStatus, OBJPROP_XDISTANCE, xBO);
            ObjectSetInteger(0,boStatus, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
            ObjectSetString(0,boStatus, OBJPROP_TEXT, "");
            ObjectSetInteger(0,boStatus, OBJPROP_COLOR, C'200,200,200');
            ObjectSetInteger(0,boStatus, OBJPROP_FONTSIZE, 9);
            
            // ---- NEW: threshold label (only when reversal mode is active) ----
            if(EnableBOMode && BO_UseReversalEntry) {
               string boThr = "DB3_BOThr_"+IntegerToString(i);
               ObjectCreate(0,boThr, OBJ_LABEL,0,0,0);
               ObjectSetInteger(0,boThr, OBJPROP_XDISTANCE, xBO + 130);   // position to the right of the box info
               ObjectSetInteger(0,boThr, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
               ObjectSetString(0,boThr, OBJPROP_TEXT, "");
               ObjectSetInteger(0,boThr, OBJPROP_COLOR, clrGray);
               ObjectSetInteger(0,boThr, OBJPROP_FONTSIZE, 9);
            }
         }
         string swapObj = "DB3_Swap_"+IntegerToString(i);
         ObjectCreate(0, swapObj, OBJ_LABEL,0,0,0);
         ObjectSetInteger(0, swapObj, OBJPROP_XDISTANCE, xSwap);
         ObjectSetInteger(0, swapObj, OBJPROP_YDISTANCE, DashboardYpos+50 + i*18);
         ObjectSetString(0, swapObj, OBJPROP_TEXT, "");
         ObjectSetInteger(0, swapObj, OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0, swapObj, OBJPROP_FONTSIZE, 9);
      }
   }

   // ========== GOLD PANEL ==========
   if(visGold) {
      ObjectCreate(0,"DB4_BG",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_BG",OBJPROP_XDISTANCE, FourthPanelXpos);
      ObjectSetInteger(0,"DB4_BG",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB4_BG",OBJPROP_XSIZE, w4);
      ObjectSetInteger(0,"DB4_BG",OBJPROP_YSIZE, h);
      ObjectSetInteger(0,"DB4_BG",OBJPROP_BGCOLOR, C'25,30,40');
      ObjectSetInteger(0,"DB4_BG",OBJPROP_BORDER_COLOR, C'25,30,40');

      ObjectCreate(0,"DB4_Header",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_Header",OBJPROP_XDISTANCE, FourthPanelXpos);
      ObjectSetInteger(0,"DB4_Header",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB4_Header",OBJPROP_XSIZE, w4);
      ObjectSetInteger(0,"DB4_Header",OBJPROP_YSIZE, 35);
      ObjectSetInteger(0,"DB4_Header",OBJPROP_BGCOLOR, C'45,70,110');
      ObjectSetInteger(0,"DB4_Header",OBJPROP_BORDER_COLOR, C'45,70,110');

      ObjectCreate(0,"DB4_Title",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_Title",OBJPROP_XDISTANCE, FourthPanelXpos+15);
      ObjectSetInteger(0,"DB4_Title",OBJPROP_YDISTANCE, DashboardYpos+10);
      ObjectSetString(0,"DB4_Title",OBJPROP_TEXT, "GOLD DASHBOARD");
      ObjectSetInteger(0,"DB4_Title",OBJPROP_COLOR, C'255,255,255');
      ObjectSetInteger(0,"DB4_Title",OBJPROP_FONTSIZE, 11);

      int goldRow = 50;
      ObjectCreate(0,"DB4_GoldEnabled",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_GoldEnabled",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_GoldEnabled",OBJPROP_YDISTANCE, DashboardYpos+goldRow);
      string goldEnabledText = TradeGold ? "Gold Trades: ON" : "Gold Trades: OFF";
      ObjectSetString(0,"DB4_GoldEnabled",OBJPROP_TEXT, goldEnabledText);
      ObjectSetInteger(0,"DB4_GoldEnabled",OBJPROP_COLOR, TradeGold ? C'0,255,0' : C'255,100,100');
      ObjectSetInteger(0,"DB4_GoldEnabled",OBJPROP_FONTSIZE, 10);
      goldRow += 22;

      ObjectCreate(0,"DB4_UsdStrength",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_UsdStrength",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_UsdStrength",OBJPROP_YDISTANCE, DashboardYpos+goldRow+10);
      ObjectSetString(0,"DB4_UsdStrength",OBJPROP_TEXT, "USD Strength: 0.0%");
      ObjectSetInteger(0,"DB4_UsdStrength",OBJPROP_COLOR, C'220,220,255');
      ObjectSetInteger(0,"DB4_UsdStrength",OBJPROP_FONTSIZE, 10);
      goldRow += 22;


      ObjectCreate(0,"DB4_GoldSpread",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_YDISTANCE, DashboardYpos+goldRow+30);
      ObjectSetString(0,"DB4_GoldSpread",OBJPROP_TEXT, "Spread: 0.0 / "+DoubleToString(MaxSpreadAU,1)+" pips");
      ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_FONTSIZE, 10);
      goldRow += 25;

      ObjectCreate(0,"DB4_GoldParamsHeader",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_GoldParamsHeader",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_GoldParamsHeader",OBJPROP_YDISTANCE, DashboardYpos+goldRow+35);
      ObjectSetString(0,"DB4_GoldParamsHeader",OBJPROP_TEXT, "RISK PARAMETERS");
      ObjectSetInteger(0,"DB4_GoldParamsHeader",OBJPROP_COLOR, C'220,240,255');
      ObjectSetInteger(0,"DB4_GoldParamsHeader",OBJPROP_FONTSIZE, 10);
      goldRow += 50;

      int labelX = FourthPanelXpos + 10;
      int valueX = FourthPanelXpos + 105;
      string paramLabels[4] = {"TP Multiplier", "SL Pips", "Max Trades", "Max Spread"};
      string paramIds[4]    = {"ProfitDollars","SLPips","MaxTrades","MaxSpread"};
      
      for(int p=0; p<4; p++) {
         ObjectCreate(0, "DB4_"+paramIds[p]+"_Lbl", OBJ_LABEL, 0,0,0);
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Lbl", OBJPROP_XDISTANCE, labelX);
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Lbl", OBJPROP_YDISTANCE, DashboardYpos+goldRow + p*16);
         ObjectSetString(0, "DB4_"+paramIds[p]+"_Lbl", OBJPROP_TEXT, paramLabels[p]+":");
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Lbl", OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Lbl", OBJPROP_FONTSIZE, 9);
         
         ObjectCreate(0, "DB4_"+paramIds[p]+"_Val", OBJ_LABEL, 0,0,0);
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Val", OBJPROP_XDISTANCE, valueX);
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Val", OBJPROP_YDISTANCE, DashboardYpos+goldRow + p*16);
         ObjectSetString(0, "DB4_"+paramIds[p]+"_Val", OBJPROP_TEXT, "");
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Val", OBJPROP_COLOR, C'200,200,200');
         ObjectSetInteger(0, "DB4_"+paramIds[p]+"_Val", OBJPROP_FONTSIZE, 9);
      }
      goldRow += 4*16 + -2;

      ObjectCreate(0,"DB4_StatusLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_StatusLabel",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_StatusLabel",OBJPROP_YDISTANCE, DashboardYpos+goldRow+45);
      ObjectSetString(0,"DB4_StatusLabel",OBJPROP_TEXT, "GOLD TRADE STATUS");
      ObjectSetInteger(0,"DB4_StatusLabel",OBJPROP_COLOR, C'220,240,255');
      ObjectSetInteger(0,"DB4_StatusLabel",OBJPROP_FONTSIZE, 10);
      goldRow += 20;

      ObjectCreate(0,"DB4_GoldTradeStatus",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_GoldTradeStatus",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_GoldTradeStatus",OBJPROP_YDISTANCE, DashboardYpos+goldRow+43);
      ObjectSetString(0,"DB4_GoldTradeStatus",OBJPROP_TEXT, "No gold trade");
      ObjectSetInteger(0,"DB4_GoldTradeStatus",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB4_GoldTradeStatus",OBJPROP_FONTSIZE, 10);
      goldRow += 18;

      ObjectCreate(0,"DB4_GoldTradePips",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_XDISTANCE, FourthPanelXpos+10);
      ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_YDISTANCE, DashboardYpos+goldRow+44);
      ObjectSetString(0,"DB4_GoldTradePips",OBJPROP_TEXT, "Profit: 0.0 pips");
      ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_FONTSIZE, 10);
   }

   // ========== SETTINGS PANEL ==========
   if(visSettings) {
      ObjectCreate(0,"DB5_BG",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BG",OBJPROP_XDISTANCE, FifthPanelXpos);
      ObjectSetInteger(0,"DB5_BG",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB5_BG",OBJPROP_XSIZE, w5);
      ObjectSetInteger(0,"DB5_BG",OBJPROP_YSIZE, h);
      ObjectSetInteger(0,"DB5_BG",OBJPROP_BGCOLOR, C'25,30,40');
      ObjectSetInteger(0,"DB5_BG",OBJPROP_BORDER_COLOR, C'25,30,40');

      ObjectCreate(0,"DB5_Header",OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_Header",OBJPROP_XDISTANCE, FifthPanelXpos);
      ObjectSetInteger(0,"DB5_Header",OBJPROP_YDISTANCE, DashboardYpos);
      ObjectSetInteger(0,"DB5_Header",OBJPROP_XSIZE, w5);
      ObjectSetInteger(0,"DB5_Header",OBJPROP_YSIZE, 35);
      ObjectSetInteger(0,"DB5_Header",OBJPROP_BGCOLOR, C'45,70,110');
      ObjectSetInteger(0,"DB5_Header",OBJPROP_BORDER_COLOR, C'45,70,110');

      ObjectCreate(0,"DB5_Title",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_Title",OBJPROP_XDISTANCE, FifthPanelXpos+15);
      ObjectSetInteger(0,"DB5_Title",OBJPROP_YDISTANCE, DashboardYpos+10);
      ObjectSetString(0,"DB5_Title",OBJPROP_TEXT, "PARAMETERS");
      ObjectSetInteger(0,"DB5_Title",OBJPROP_COLOR, C'255,255,255');
      ObjectSetInteger(0,"DB5_Title",OBJPROP_FONTSIZE, 11);

      int pY = DashboardYpos + 50;
      int pX = FifthPanelXpos + 10;
      int labelWidth = 110;
      int valueX = pX + labelWidth + 5;

      ObjectCreate(0,"DB5_TradingLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TradingLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_TradingLabel",OBJPROP_YDISTANCE, pY);
      ObjectSetString(0,"DB5_TradingLabel",OBJPROP_TEXT, "Trading:");
      ObjectSetInteger(0,"DB5_TradingLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TradingLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_TradingValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TradingValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_TradingValue",OBJPROP_YDISTANCE, pY);
      ObjectSetString(0,"DB5_TradingValue",OBJPROP_TEXT, "");
      ObjectSetInteger(0,"DB5_TradingValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TradingValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      ObjectCreate(0,"DB5_MagicLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_MagicLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_MagicLabel",OBJPROP_YDISTANCE, pY+20);
      ObjectSetString(0,"DB5_MagicLabel",OBJPROP_TEXT, "MagicNumber:");
      ObjectSetInteger(0,"DB5_MagicLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_MagicLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_MagicValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_MagicValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_MagicValue",OBJPROP_YDISTANCE, pY+20);
      ObjectSetString(0,"DB5_MagicValue",OBJPROP_TEXT, "");
      ObjectSetInteger(0,"DB5_MagicValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_MagicValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      ObjectCreate(0,"DB5_ProfitLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_ProfitLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_ProfitLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_ProfitLabel",OBJPROP_TEXT, "TP Multiplier:");
      ObjectSetInteger(0,"DB5_ProfitLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_ProfitLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_ProfitValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_ProfitValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_ProfitValue",OBJPROP_YDISTANCE, pY+40);
      SafeSetText("DB4_ProfitDollars_Val", DoubleToString(TP_Multiplier,2));
      ObjectSetInteger(0,"DB5_ProfitValue",OBJPROP_COLOR, C'200,200,200');
      pY += 20;

      ObjectCreate(0,"DB5_SLPipsLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_SLPipsLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_SLPipsLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_SLPipsLabel",OBJPROP_TEXT, "Global SL Pips:");
      ObjectSetInteger(0,"DB5_SLPipsLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_SLPipsLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_SLPipsValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_SLPipsValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_SLPipsValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_SLPipsValue",OBJPROP_TEXT, DoubleToString(GlobalSL_Pips,1));
      ObjectSetInteger(0,"DB5_SLPipsValue",OBJPROP_COLOR, C'200,200,200');
      pY += 20;

      ObjectCreate(0,"DB5_BOLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_BOLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOLabel",OBJPROP_TEXT, "BO Mode:");
      ObjectSetInteger(0,"DB5_BOLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_BOLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_BOValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_BOValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOValue",OBJPROP_TEXT, EnableBOMode ? "ON" : "OFF");
      ObjectSetInteger(0,"DB5_BOValue",OBJPROP_COLOR, EnableBOMode ? C'0,255,0' : C'255,100,100');
      ObjectSetInteger(0,"DB5_BOValue",OBJPROP_FONTSIZE, 10);
      pY += 20;


      ObjectCreate(0,"DB5_BOBlockHoursLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOBlockHoursLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_BOBlockHoursLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOBlockHoursLabel",OBJPROP_TEXT, "BO Block Hours:");
      ObjectSetInteger(0,"DB5_BOBlockHoursLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_BOBlockHoursLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_BOBlockHoursValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOBlockHoursValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_BOBlockHoursValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOBlockHoursValue",OBJPROP_TEXT, IntegerToString(BlockHours));
      ObjectSetInteger(0,"DB5_BOBlockHoursValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_BOBlockHoursValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      ObjectCreate(0,"DB5_BOSwapThresholdLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOSwapThresholdLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_BOSwapThresholdLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOSwapThresholdLabel",OBJPROP_TEXT, "BO Swap Thresh:");
      ObjectSetInteger(0,"DB5_BOSwapThresholdLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_BOSwapThresholdLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_BOSwapThresholdValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_BOSwapThresholdValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_BOSwapThresholdValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_BOSwapThresholdValue",OBJPROP_TEXT, DoubleToString(SwapEntryAbsThreshold,2));
      ObjectSetInteger(0,"DB5_BOSwapThresholdValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_BOSwapThresholdValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      ObjectCreate(0,"DB5_SwapLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_SwapLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_SwapLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_SwapLabel",OBJPROP_TEXT, "Swap Trading:");
      ObjectSetInteger(0,"DB5_SwapLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_SwapLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_SwapValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_SwapValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_SwapValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_SwapValue",OBJPROP_TEXT, EnableSwapTrading ? "ON" : "OFF");
      ObjectSetInteger(0,"DB5_SwapValue",OBJPROP_COLOR, EnableSwapTrading ? C'0,255,0' : C'255,100,100');
      ObjectSetInteger(0,"DB5_SwapValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      // Trailing Activation Pips
      ObjectCreate(0,"DB5_TrailActLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TrailActLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_TrailActLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_TrailActLabel",OBJPROP_TEXT, "Activation Pips:");
      ObjectSetInteger(0,"DB5_TrailActLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TrailActLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_TrailActValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TrailActValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_TrailActValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_TrailActLabel",OBJPROP_TEXT, "TrailingSL %:");
      ObjectSetInteger(0,"DB5_TrailActValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TrailActValue",OBJPROP_FONTSIZE, 10);
      pY += 20;


      // Trail Step
      ObjectCreate(0,"DB5_TrailStepLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TrailStepLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_TrailStepLabel",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_TrailStepLabel",OBJPROP_TEXT, "Step Pips:");
      ObjectSetInteger(0,"DB5_TrailStepLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TrailStepLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_TrailStepValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_TrailStepValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_TrailStepValue",OBJPROP_YDISTANCE, pY+40);
      ObjectSetString(0,"DB5_TrailStepValue",OBJPROP_TEXT, DoubleToString(TrailStepPips,1)+" pips");
      ObjectSetInteger(0,"DB5_TrailStepValue",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_TrailStepValue",OBJPROP_FONTSIZE, 10);
      pY += 20;

      ObjectCreate(0,"DB5_PyramidLabel",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_PyramidLabel",OBJPROP_XDISTANCE, pX);
      ObjectSetInteger(0,"DB5_PyramidLabel",OBJPROP_YDISTANCE, pY+70);
      ObjectSetString(0,"DB5_PyramidLabel",OBJPROP_TEXT, "Max per pair:");
      ObjectSetInteger(0,"DB5_PyramidLabel",OBJPROP_COLOR, C'200,200,200');
      ObjectSetInteger(0,"DB5_PyramidLabel",OBJPROP_FONTSIZE, 10);
      ObjectCreate(0,"DB5_PyramidValue",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_PyramidValue",OBJPROP_XDISTANCE, valueX);
      ObjectSetInteger(0,"DB5_PyramidValue",OBJPROP_YDISTANCE, pY+70);
      ObjectSetString(0,"DB5_PyramidValue",OBJPROP_TEXT, IntegerToString(GlobalMaxTradesPerSymbol));
      ObjectSetInteger(0,"DB5_PyramidValue",OBJPROP_COLOR, C'200,200,200');
      
      // Session indicator label (above daily reset)
      ObjectCreate(0,"DB5_Session",OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,"DB5_Session",OBJPROP_XDISTANCE, valueX -110);      // same X as daily reset
      ObjectSetInteger(0,"DB5_Session",OBJPROP_YDISTANCE, DashboardYpos+h-45); // 20px above daily reset
      ObjectSetString(0,"DB5_Session",OBJPROP_TEXT, "");
      ObjectSetInteger(0,"DB5_Session",OBJPROP_COLOR, C'255,220,100');
      ObjectSetInteger(0,"DB5_Session",OBJPROP_FONTSIZE, 9);
      
      // Daily Reset label (always visible if enabled)
      if(EnableDailyReset) {
         ObjectCreate(0,"DB5_DailyResetValue",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DB5_DailyResetValue",OBJPROP_XDISTANCE, valueX -110);
         ObjectSetInteger(0,"DB5_DailyResetValue",OBJPROP_YDISTANCE, DashboardYpos+h-25);
         ObjectSetString(0,"DB5_DailyResetValue",OBJPROP_TEXT, "");
         ObjectSetInteger(0,"DB5_DailyResetValue",OBJPROP_COLOR, C'255,220,100');
         ObjectSetInteger(0,"DB5_DailyResetValue",OBJPROP_FONTSIZE, 10);
      }
   }
   UpdateDashboard();
}

string GetSessionText()
{
   datetime serverTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int hour = dt.hour;

   bool sydney = (hour >= SESSION_SYDNEY_START && hour < SESSION_SYDNEY_END);
   bool tokyo  = (hour >= SESSION_TOKYO_START  && hour < SESSION_TOKYO_END);
   bool london = (hour >= SESSION_LONDON_START && hour < SESSION_LONDON_END);
   bool ny     = (hour >= SESSION_NY_START     && hour < SESSION_NY_END);

   string text = "Session:";
   if(sydney) text += " Sydney";
   if(tokyo)  text += " Tokyo";
   if(london) text += " London";
   if(ny)     text += " New York";
   if(!sydney && !tokyo && !london && !ny) text += " Off-peak";

   return text;
}

void UpdateDashboard() {
   if(!ShowDashboard) return;
   
   if(ShowMainPanel) {
      // Update the trading status to show if within trading hours
      string tradingHoursStatus = IsTradingHourAllowed() ? 
         StringFormat("%02d:00-%02d:00 (ACTIVE)", StartTradingHour, StopTradingHour) :
         StringFormat("%02d:00-%02d:00 (PAUSED)", StartTradingHour, StopTradingHour);
      
      SafeSetText("DB_Status", "Status: "+DynamicStatus + " | " + tradingHoursStatus);
      SafeSetText("DB_Reverse", ReverseTrades ? "Reverse: ON" : "Reverse: OFF");
      // ... rest of UpdateDashboard continues
      
      SafeSetText("DB_Reverse", ReverseTrades ? "Reverse: ON" : "Reverse: OFF");
      ObjectSetInteger(0,"DB_Reverse",OBJPROP_COLOR,ReverseTrades ? C'255,150,150' : C'150,255,150');
      
      SafeSetText("DB_GapOpenVal", DoubleToString(StrongEntryThreshold,1)+"%");
      SafeSetText("DB_GapCloseVal", DoubleToString(WeakEntryThreshold,1)+"%");

      string strongWeakDisplay = Currencies[CurrentStrongest] + " (" + DoubleToString(CurrencyStrength[CurrentStrongest],1) + "%) / " +
                                 Currencies[CurrentWeakest] + " (" + DoubleToString(CurrencyStrength[CurrentWeakest],1) + "%)";
      SafeSetText("DB_CurrGapVal", strongWeakDisplay);
      bool conditionMet = (CurrencyStrength[CurrentStrongest] >= StrongEntryThreshold &&
                           CurrencyStrength[CurrentWeakest] <= WeakEntryThreshold &&
                           CurrentGap >= MinGapEntry);
      if(conditionMet)
         ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_COLOR,C'0,255,0');
      else
         ObjectSetInteger(0,"DB_CurrGapVal",OBJPROP_COLOR,C'255,200,100');
      
      string gapInfo = DoubleToString(CurrentGap,1) + "% / " + DoubleToString(MinGapEntry,1) + "%";
      SafeSetText("DB_GapValue", gapInfo);
      color gapColor = (CurrentGap >= MinGapEntry) ? C'0,255,0' : C'255,150,150';
      ObjectSetInteger(0,"DB_GapValue",OBJPROP_COLOR,gapColor);
      
      double spreadVal = GetCurrentSpread(CurrentPair!=""?CurrentPair:Symbol());
      color spreadColor = (spreadVal <= MaxSpreadPips) ? C'0,255,0' : C'255,100,100';
      SafeSetText("DB_SpreadVal", DoubleToString(spreadVal,1)+" / "+DoubleToString(MaxSpreadPips,1)+" pips");
      ObjectSetInteger(0,"DB_SpreadVal",OBJPROP_COLOR,spreadColor);
      
      for(int i=0;i<8;i++) {
         double str = CurrencyStrength[i];
         int bw = (int)((str/100.0)*100); if(bw<0) bw=0; if(bw>100) bw=100;
         SafeSetText("DB_Curr_"+Currencies[i], Currencies[i]+": "+DoubleToString(str,1)+"%");
         if(i==CurrentStrongest) ObjectSetInteger(0,"DB_Curr_"+Currencies[i],OBJPROP_COLOR,C'100,255,100');
         else if(i==CurrentWeakest) ObjectSetInteger(0,"DB_Curr_"+Currencies[i],OBJPROP_COLOR,C'255,100,100');
         else if(str>=60) ObjectSetInteger(0,"DB_Curr_"+Currencies[i],OBJPROP_COLOR,C'100,255,100');
         else if(str>=40) ObjectSetInteger(0,"DB_Curr_"+Currencies[i],OBJPROP_COLOR,C'255,255,150');
         else ObjectSetInteger(0,"DB_Curr_"+Currencies[i],OBJPROP_COLOR,C'255,150,150');
         ObjectSetInteger(0,"DB_Bar_"+Currencies[i],OBJPROP_XSIZE,bw);
         if(str>=60) ObjectSetInteger(0,"DB_Bar_"+Currencies[i],OBJPROP_BGCOLOR,C'0,180,80');
         else if(str>=40) ObjectSetInteger(0,"DB_Bar_"+Currencies[i],OBJPROP_BGCOLOR,C'200,180,0');
         else ObjectSetInteger(0,"DB_Bar_"+Currencies[i],OBJPROP_BGCOLOR,C'200,60,60');
      }
            // Update Precious Metals Strength Bar
      if(ShowMetalsStrength) {
         double str = MetalsStrength;
         int bw = (int)((str/100.0)*100);
         if(bw < 0) bw = 0;
         if(bw > 100) bw = 100;
         SafeSetText("DB_Curr_METALS", "Metals: " + DoubleToString(str,1) + "%");
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_XSIZE, bw);
         color barColor = C'255,215,0';
         if(str >= 60)      barColor = C'0,180,80';
         else if(str >= 40) barColor = C'200,180,0';
         else               barColor = C'200,60,60';
         ObjectSetInteger(0, "DB_Bar_METALS", OBJPROP_BGCOLOR, barColor);
      }
      
      if(CurrentPair!="") {
         string clean = GetCleanSymbol(CurrentPair);
         string dp = StringSubstr(clean,0,3)+"/"+StringSubstr(clean,3);
         SafeSetText("DB_Target", "TARGET: "+dp);
      } else SafeSetText("DB_Target", "TARGET: ---");
   }

   if(ShowLivePanel) {
      for(int idx=0; idx<50; idx++) {
         uPairs[idx] = "";
         uCounts[idx] = 0;
         uGaps[idx] = 0.0;
      }
      
      string symList[100];
      int fxCount[100];
      int boCount[100];
      int xauCount[100];
      int xbCount[100];
      int swapCount[100];
      int idxCount[100];
      int btcCount[100];
      double gapList[100];
      int symTotal = 0;
      
      
      for(int i = PositionsTotal()-1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
         
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY || type == POSITION_TYPE_SELL) {
            string sym = PositionGetString(POSITION_SYMBOL);
            string cleanSym = GetCleanSymbol(sym);
            if(cleanSym == "") continue;
            
            int storedType = GetEntryType(ticket);
            bool isGold = (StringFind(sym, "XAU")>=0 || StringFind(sym, "GOLD")>=0);
            bool isBO = (storedType >= 0) ? (storedType == 3 || storedType == 4 || storedType == 5 || storedType == 6 || storedType == 8) : (StringFind(PositionGetString(POSITION_COMMENT), "BO ") >= 0);
            bool isSwap = (storedType >= 0) ? (storedType == 7) : (StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") >= 0);
            bool isBTCtrade = (storedType >= 0) ? (storedType == 8) : (StringFind(PositionGetString(POSITION_COMMENT), "BTC") >= 0);
            bool isIndex = (storedType >= 0) ? (storedType == 5) : (StringFind(PositionGetString(POSITION_COMMENT), "Index Order") >= 0);
            
            int symIdx = -1;
            for(int j=0; j<symTotal; j++) {
               if(symList[j] == cleanSym) { symIdx = j; break; }
            }
            if(symIdx == -1) {
               symIdx = symTotal;
               symList[symIdx] = cleanSym;
               fxCount[symIdx] = 0;
               boCount[symIdx] = 0;
               xauCount[symIdx] = 0;
               xbCount[symIdx] = 0;
               swapCount[symIdx] = 0;
               idxCount[symIdx] = 0;       // <-- ADDED initialisation
               btcCount[symIdx] = 0;    
               gapList[symIdx] = GetPairGap(sym);
               symTotal++;
            }
            
            if(isGold) {
               if(isBO) xbCount[symIdx]++;
               else if(isSwap) swapCount[symIdx]++;
               else if(isBTCtrade) btcCount[symIdx]++;               
               else if(isIndex) idxCount[symIdx]++;    // <-- MODIFIED: index before gold general
               else xauCount[symIdx]++;
            } else {
               if(isBO) boCount[symIdx]++;
               else if(isSwap) swapCount[symIdx]++;
               else if(isBTCtrade) btcCount[symIdx]++;
               else if(isIndex) idxCount[symIdx]++;    // <-- MODIFIED: index before forex
               else fxCount[symIdx]++;
            }
         }
      }
      
      string displayPairs[15];
      string displayGaps[15];
      string displayCounts[15];
      color  displayColors[15];
      int displayRow = 0;
      
      // Always scan for gold symbol, regardless of index 0
      for(int j = 0; j < symTotal; j++)
      {
         if(symList[j] == "XAUUSD" || StringFind(symList[j], "XAU") >= 0)
         {
            if(xauCount[j] > 0 || xbCount[j] > 0 || swapCount[j] > 0)
            {
               displayPairs[displayRow] = "XAU/USD";
               displayGaps[displayRow] = DoubleToString(gapList[j], 1) + "%";
               string countStr = "";
               if(fxCount[j]   > 0) countStr += "(FX:" + IntegerToString(fxCount[j])   + ") ";
               if(boCount[j]   > 0) countStr += "(BO:" + IntegerToString(boCount[j])   + ") ";
               if(xauCount[j]  > 0) countStr += "(XAU:" + IntegerToString(xauCount[j])  + ") ";
               if(xbCount[j]   > 0) countStr += "(XB:" + IntegerToString(xbCount[j])   + ") ";
               if(swapCount[j] > 0) countStr += "(SW:" + IntegerToString(swapCount[j]) + ") ";
               if(idxCount[j]  > 0) countStr += "(IDX:" + IntegerToString(idxCount[j]) + ") ";
               if(btcCount[j]  > 0) countStr += "(BTC:" + IntegerToString(btcCount[j]) + ") ";
               if(countStr == "") countStr = "0";
               displayCounts[displayRow] = countStr;
               displayColors[displayRow] = clrGold;
               displayRow++;
            }
            break;
         }
      }
      
      for(int i=0; i<symTotal && displayRow<15; i++) {
         if(symList[i] == "XAUUSD" || StringFind(symList[i], "XAU")>=0) continue;
         
         displayPairs[displayRow] = StringSubstr(symList[i],0,3)+"/"+StringSubstr(symList[i],3);
         displayGaps[displayRow] = DoubleToString(gapList[i],1)+"%";
         
         string countStr = "";
         if(fxCount[i] > 0) countStr += "(FX:" + IntegerToString(fxCount[i]) + ") ";
         if(boCount[i] > 0) countStr += "(BO:" + IntegerToString(boCount[i]) + ") ";
         if(xauCount[i] > 0) countStr += "(XAU:" + IntegerToString(xauCount[i]) + ") ";
         if(xbCount[i] > 0) countStr += "(XB:" + IntegerToString(xbCount[i]) + ") ";
         if(swapCount[i] > 0) countStr += "(SW:" + IntegerToString(swapCount[i]) + ") ";
         if(idxCount[i] > 0) countStr += "(IDX:" + IntegerToString(idxCount[i]) + ") ";
         if(btcCount[i] > 0) countStr += "(BTC:" + IntegerToString(btcCount[i]) + ") ";
         if(countStr == "") countStr = "0";
         displayCounts[displayRow] = countStr;
         
         if(gapList[i] >= (StrongEntryThreshold - WeakEntryThreshold) && gapList[i] >= MinGapEntry)
            displayColors[displayRow] = C'0,255,0';
         else
            displayColors[displayRow] = C'200,200,200';
         
         displayRow++;
      }
      
      // Update or delete pair display labels
      for(int i = 0; i < 15; i++) {
         string name1 = "DB2_PairName_" + IntegerToString(i);
         string name2 = "DB2_PairGap_"  + IntegerToString(i);
         string name3 = "DB2_PairCount_" + IntegerToString(i);
         
         if(i < displayRow) {
            // Update existing labels (create if missing)
            if(ObjectFind(0, name1) < 0) {
               ObjectCreate(0, name1, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, name1, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, name1, OBJPROP_XDISTANCE, SecondPanelXpos + 10);
               ObjectSetInteger(0, name1, OBJPROP_YDISTANCE, DashboardYpos + 50 + i * 12);
               ObjectSetInteger(0, name1, OBJPROP_FONTSIZE, 10);
            }
            ObjectSetString(0, name1, OBJPROP_TEXT, displayPairs[i]);
            ObjectSetInteger(0, name1, OBJPROP_COLOR, displayColors[i]);
            
            if(ObjectFind(0, name2) < 0) {
               ObjectCreate(0, name2, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, name2, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, name2, OBJPROP_XDISTANCE, SecondPanelXpos + 100);
               ObjectSetInteger(0, name2, OBJPROP_YDISTANCE, DashboardYpos + 50 + i * 12);
               ObjectSetInteger(0, name2, OBJPROP_FONTSIZE, 10);
            }
            ObjectSetString(0, name2, OBJPROP_TEXT, displayGaps[i]);
            ObjectSetInteger(0, name2, OBJPROP_COLOR, displayColors[i]);
            
            if(ObjectFind(0, name3) < 0) {
               ObjectCreate(0, name3, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, name3, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, name3, OBJPROP_XDISTANCE, SecondPanelXpos + 150);
               ObjectSetInteger(0, name3, OBJPROP_YDISTANCE, DashboardYpos + 50 + i * 12);
               ObjectSetInteger(0, name3, OBJPROP_FONTSIZE, 10);
            }
            ObjectSetString(0, name3, OBJPROP_TEXT, displayCounts[i]);
            ObjectSetInteger(0, name3, OBJPROP_COLOR, displayColors[i]);
         } else {
            // Delete unused labels to hide them completely
            ObjectDelete(0, name1);
            ObjectDelete(0, name2);
            ObjectDelete(0, name3);
         }
      }
      
      int forexCnt = CountForexTrades();
      string fxText = "Open FX Trades: " + IntegerToString(forexCnt) + " / " + IntegerToString(MaxForexTrades);
      SafeSetText("DB2_FxCounter", fxText);
      if(forexCnt >= MaxForexTrades) ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_COLOR,C'255,100,100');
      else ObjectSetInteger(0,"DB2_FxCounter",OBJPROP_COLOR,C'200,200,200');
      
      int boCnt = CountBOTrades();
      SafeSetText("DB2_BOCounter", "Open BO Trades: "+IntegerToString(boCnt)+" / "+IntegerToString(MaxBOTrades));
      if(boCnt >= MaxBOTrades) ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_BOCounter",OBJPROP_COLOR, C'200,200,200');
      
      int goldCnt = CountGoldTrades();
      SafeSetText("DB2_AuCounter", "Open XAU Trades: "+IntegerToString(goldCnt)+" / "+IntegerToString(MaxGoldTrades));
      if(goldCnt >= MaxGoldTrades) ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_COLOR,C'255,100,100');
      else ObjectSetInteger(0,"DB2_AuCounter",OBJPROP_COLOR,C'200,200,200');
      
      int boGoldCnt = CountBOGoldTrades();
      SafeSetText("DB2_BOGoldCounter", "Open BO XAU: "+IntegerToString(boGoldCnt)+" / "+IntegerToString(MaxBOGoldTrades));
      if(boGoldCnt >= MaxBOGoldTrades) ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_BOGoldCounter",OBJPROP_COLOR, C'200,200,200');
      
      int oilCnt = CountOilTrades();
      SafeSetText("DB2_OilCounter", "Open Oil Trades: "+IntegerToString(oilCnt)+" / "+IntegerToString(MaxOilTrades));
      if(oilCnt >= MaxOilTrades) ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_OilCounter",OBJPROP_COLOR, C'200,200,200');
      
      int swapCnt = CountSwapTrades();
      SafeSetText("DB2_SwapCounter", "Open Swap Trades: "+IntegerToString(swapCnt)+" / "+IntegerToString(MaxSwapTrades));
      if(swapCnt >= MaxSwapTrades) ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_SwapCounter",OBJPROP_COLOR, C'200,200,200');
      
      // ----- Index trades counter -----
      int idxCnt = CountIndexTrades();
      SafeSetText("DB2_IndexCounter", "Open Index Trades: "+IntegerToString(idxCnt)+" / "+IntegerToString(MaxIndexTrades));
      if(idxCnt >= MaxIndexTrades) ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_IndexCounter",OBJPROP_COLOR, C'200,200,200');
      
      int btcCnt = CountBTCTrades();
      SafeSetText("DB2_BTCCounter", "Open BTC Trades: "+IntegerToString(btcCnt)+" / "+IntegerToString(MaxBitcoinTrades));
      if(btcCnt >= MaxBitcoinTrades) ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_BTCCounter",OBJPROP_COLOR, C'200,200,200');
      
      int dailyGlobal = g_dailyTradeGlobalCount;
      string dailyText = "Daily Trades: " + IntegerToString(dailyGlobal) + " / " + IntegerToString(MaxDailyTradesGlobal);
      SafeSetText("DB2_DailyTradesCounter", dailyText);
      if(dailyGlobal >= MaxDailyTradesGlobal) ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_COLOR, C'255,100,100');
      else ObjectSetInteger(0,"DB2_DailyTradesCounter",OBJPROP_COLOR, C'200,200,200');
      // -------------------------------
      
      if(LastCloseTime > 0 && TimeCurrent() - LastCloseTime < 5) {
         SafeSetText("DB2_CloseStatusLabel", "Status: Closing: "+LastCloseReason);
         ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_COLOR,C'255,150,150');
      } else {
         SafeSetText("DB2_CloseStatusLabel", "Status: Waiting to close");
         ObjectSetInteger(0,"DB2_CloseStatusLabel",OBJPROP_COLOR,C'255,200,100');
      }
    }
    
   // ========== PAIRS PANEL ==========
   if(ShowPairsPanel)
   {
      int row = 0;

      // --- Forex pairs (0 .. PairCount-1) ---
      for(int i = 0; i < PairCount; i++)
      {
         string pairNameObj = "DB3_PairName_" + IntegerToString(row);
         string pairGapObj  = "DB3_PairGap_"  + IntegerToString(row);

         string sym      = Pairs[i].symbol;
         string cleanSym = GetCleanSymbol(sym);
         string displayPair = StringSubstr(cleanSym, 0, 3) + "/" + StringSubstr(cleanSym, 3);
         double pairGap = GetPairGap(sym);

         SafeSetText(pairNameObj, displayPair);
         SafeSetText(pairGapObj, DoubleToString(pairGap, 1) + "%");

         if(ShowSRColumn)
         {
            double srDist = GetNearestSRDistance(sym);
            string srText = (srDist >= 0) ? DoubleToString(srDist, 1) : "--";
            SafeSetText("DB3_SRDist_" + IntegerToString(row), srText);
            color textColor = (srDist >= 0 && srDist <= 15) ? clrCornsilk :
                             (srDist >= 15.1 && srDist <= 30.0) ? clrDodgerBlue : C'200,200,200';
            ObjectSetInteger(0, "DB3_SRDist_" + IntegerToString(row), OBJPROP_COLOR, textColor);
         }

         if(ShowBOMonitorPanel)
         {
            string boStatusObj = "DB3_BOStatus_" + IntegerToString(row);
            string boText = "";
            color boColor = clrGray;

            // Box High/Low
            bool boxReady = false;
            for(int b = 0; b < boSymbolCount; b++)
            {
               if(GetCleanSymbol(boSymbols[b]) == cleanSym)
               {
                  int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
                  if(boPrevPeriodReady[b])
                  {
                     double high = boPrevPeriodHigh[b];
                     double low  = boPrevPeriodLow[b];
                     boText = StringFormat("H:%s L:%s",
                                           DoubleToString(high, symDigits),
                                           DoubleToString(low, symDigits));
                     double bid = SymbolInfoDouble(boSymbols[b], SYMBOL_BID);
                     double ask = SymbolInfoDouble(boSymbols[b], SYMBOL_ASK);
                     boColor = (bid >= low && ask <= high) ? clrDodgerBlue : clrGray;
                     boxReady = true;
                  }
                  break;
               }
            }
            if(!boxReady) { boText = "wait"; boColor = clrDarkGray; }
            SafeSetText(boStatusObj, boText);
            ObjectSetInteger(0, boStatusObj, OBJPROP_COLOR, boColor);

            // Reversal threshold
            string boThrObj = "DB3_BOThr_" + IntegerToString(row);
            if(EnableBOMode && BO_UseReversalEntry)
            {
               int boIdx = -1;
               for(int b = 0; b < boSymbolCount; b++)
                  if(GetCleanSymbol(boSymbols[b]) == cleanSym) { boIdx = b; break; }
               if(boIdx >= 0 && boRevAvgComputed[boIdx] && boRevAvg[boIdx] > 0)
               {
                  double threshold = boRevAvg[boIdx] * BO_RevCandleMultiplier;
                  SafeSetText(boThrObj, StringFormat("Thr:%.1f", threshold));
                  color thrColor = clrGray;
                  double point = GetSymbolPoint(boSymbols[boIdx]);
                  double highArr[], lowArr[];
                  if(CopyHigh(boSymbols[boIdx], Timeframe, 0, 1, highArr) == 1 &&
                     CopyLow(boSymbols[boIdx], Timeframe, 0, 1, lowArr)  == 1)
                  {
                     double rangePoints = (highArr[0] - lowArr[0]) / point;
                     if(rangePoints >= threshold) thrColor = C'255,50,50';
                  }
                  ObjectSetInteger(0, boThrObj, OBJPROP_COLOR, thrColor);
               }
               else SafeSetText(boThrObj, "");
            }
            else SafeSetText(boThrObj, "");
         }

         // Swap column
         string swapObj = "DB3_Swap_" + IntegerToString(row);
         double swapLong  = SymbolInfoDouble(sym, SYMBOL_SWAP_LONG);
         double swapShort = SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT);
         string swapText  = (swapLong>0?"+":"") + DoubleToString(swapLong,2) + " / " + (swapShort>0?"+":"") + DoubleToString(swapShort,2);
         SafeSetText(swapObj, swapText);
         color swapColor = C'200,200,200';
         if(IsTopSwapSymbol(sym)) swapColor = clrDodgerBlue;
         else if((swapLong > 0 && MathAbs(swapLong) >= SwapEntryAbsThreshold) ||
                 (swapShort > 0 && MathAbs(swapShort) >= SwapEntryAbsThreshold))
            swapColor = C'0,255,0';
         else if(MathAbs(swapLong) >= SwapCloseAbsThreshold || MathAbs(swapShort) >= SwapCloseAbsThreshold)
            swapColor = C'255,255,100';
         ObjectSetInteger(0, swapObj, OBJPROP_COLOR, swapColor);

         row++;
      }

      // --- Extra instruments: Gold, Oil, BTC, Indices ---
      // Build a simple list
      string extraSyms[];
      string extraNames[];
      int extraCount = 0;

      if(GoldSymbol != "")      { ArrayResize(extraSyms, extraCount+1); ArrayResize(extraNames, extraCount+1); extraSyms[extraCount]=GoldSymbol; extraNames[extraCount]="XAU/USD"; extraCount++; }
      if(OilSymbol != "")       { ArrayResize(extraSyms, extraCount+1); ArrayResize(extraNames, extraCount+1); extraSyms[extraCount]=OilSymbol; extraNames[extraCount]="OIL"; extraCount++; }
      if(BTCSymbol != "")       { ArrayResize(extraSyms, extraCount+1); ArrayResize(extraNames, extraCount+1); extraSyms[extraCount]=BTCSymbol; extraNames[extraCount]="BTC"; extraCount++; }
      for(int i = 0; i < indexSymbolCount && i < 50; i++)
      {
         ArrayResize(extraSyms, extraCount+1); ArrayResize(extraNames, extraCount+1);
         extraSyms[extraCount] = indexSymbols[i];
         extraNames[extraCount] = indexSymbols[i];   // keep the raw name
         extraCount++;
      }

      for(int e = 0; e < extraCount; e++)
      {
         string sym = extraSyms[e];
         string pairNameObj = "DB3_PairName_" + IntegerToString(row);
         string pairGapObj  = "DB3_PairGap_"  + IntegerToString(row);

         // Create objects if they don't exist (matching the forex panel layout)
         if(ObjectFind(0, pairNameObj) < 0)
         {
            ObjectCreate(0, pairNameObj, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, pairNameObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, pairNameObj, OBJPROP_XDISTANCE, ThirdPanelXpos + 5);
            ObjectSetInteger(0, pairNameObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
            ObjectSetInteger(0, pairNameObj, OBJPROP_FONTSIZE, 9);
         }
         SafeSetText(pairNameObj, extraNames[e]);

         if(ObjectFind(0, pairGapObj) < 0)
         {
            ObjectCreate(0, pairGapObj, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, pairGapObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, pairGapObj, OBJPROP_XDISTANCE, ThirdPanelXpos + 85);
            ObjectSetInteger(0, pairGapObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
            ObjectSetInteger(0, pairGapObj, OBJPROP_FONTSIZE, 9);
         }
         SafeSetText(pairGapObj, "-");

         if(ShowSRColumn)
         {
            string srDistObj = "DB3_SRDist_" + IntegerToString(row);
            if(ObjectFind(0, srDistObj) < 0)
            {
               ObjectCreate(0, srDistObj, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, srDistObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, srDistObj, OBJPROP_XDISTANCE, ThirdPanelXpos + 140);
               ObjectSetInteger(0, srDistObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
               ObjectSetInteger(0, srDistObj, OBJPROP_FONTSIZE, 9);
            }
            SafeSetText(srDistObj, "-");
         }

         if(ShowBOMonitorPanel)
         {
            string boStatusObj = "DB3_BOStatus_" + IntegerToString(row);
            if(ObjectFind(0, boStatusObj) < 0)
            {
               ObjectCreate(0, boStatusObj, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, boStatusObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, boStatusObj, OBJPROP_XDISTANCE, ThirdPanelXpos + 185);
               ObjectSetInteger(0, boStatusObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
               ObjectSetInteger(0, boStatusObj, OBJPROP_FONTSIZE, 9);
            }

            string boText = "wait";
            color boColor = clrDarkGray;
            int boIdx = -1;
            for(int b = 0; b < boSymbolCount; b++)
               if(boSymbols[b] == sym) { boIdx = b; break; }
            if(boIdx >= 0 && boPrevPeriodReady[boIdx])
            {
               int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
               boText = StringFormat("H:%s L:%s",
                           DoubleToString(boPrevPeriodHigh[boIdx], symDigits),
                           DoubleToString(boPrevPeriodLow[boIdx], symDigits));
               boColor = clrGray;
            }
            SafeSetText(boStatusObj, boText);
            ObjectSetInteger(0, boStatusObj, OBJPROP_COLOR, boColor);

            string boThrObj = "DB3_BOThr_" + IntegerToString(row);
            if(ObjectFind(0, boThrObj) < 0)
            {
               ObjectCreate(0, boThrObj, OBJ_LABEL, 0, 0, 0);
               ObjectSetInteger(0, boThrObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
               ObjectSetInteger(0, boThrObj, OBJPROP_XDISTANCE, ThirdPanelXpos + 185 + 130);
               ObjectSetInteger(0, boThrObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
               ObjectSetInteger(0, boThrObj, OBJPROP_FONTSIZE, 9);
            }
            if(EnableBOMode && BO_UseReversalEntry && boIdx >= 0 && boRevAvgComputed[boIdx] && boRevAvg[boIdx] > 0)
            {
               double threshold = boRevAvg[boIdx] * BO_RevCandleMultiplier;
               SafeSetText(boThrObj, StringFormat("Thr:%.1f", threshold));
               color thrColor = clrGray;
               double point = GetSymbolPoint(sym);
               double highArr[], lowArr[];
               if(CopyHigh(sym, Timeframe, 0, 1, highArr) == 1 &&
                  CopyLow(sym, Timeframe, 0, 1, lowArr)  == 1)
               {
                  double rangePoints = (highArr[0] - lowArr[0]) / point;
                  if(rangePoints >= threshold) thrColor = C'255,50,50';
               }
               ObjectSetInteger(0, boThrObj, OBJPROP_COLOR, thrColor);
            }
            else SafeSetText(boThrObj, "");
         }

         // Swap column (not meaningful for these)
         string swapObj = "DB3_Swap_" + IntegerToString(row);
         if(ObjectFind(0, swapObj) < 0)
         {
            ObjectCreate(0, swapObj, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, swapObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, swapObj, OBJPROP_XDISTANCE, ThirdPanelXpos + (ShowSRColumn ? 385 : 230));
            ObjectSetInteger(0, swapObj, OBJPROP_YDISTANCE, DashboardYpos + 50 + row*18);
            ObjectSetInteger(0, swapObj, OBJPROP_FONTSIZE, 9);
         }
         SafeSetText(swapObj, "–");
         ObjectSetInteger(0, swapObj, OBJPROP_COLOR, C'200,200,200');

         row++;
      }

      // Clear any remaining rows (if less than previous count)
      for(int i = row; i < 50; i++)
      {
         ObjectDelete(0, "DB3_PairName_" + IntegerToString(i));
         ObjectDelete(0, "DB3_PairGap_" + IntegerToString(i));
         if(ShowSRColumn) ObjectDelete(0, "DB3_SRDist_" + IntegerToString(i));
         if(ShowBOMonitorPanel)
         {
            ObjectDelete(0, "DB3_BOStatus_" + IntegerToString(i));
            ObjectDelete(0, "DB3_BOThr_" + IntegerToString(i));
         }
         ObjectDelete(0, "DB3_Swap_" + IntegerToString(i));
      }
   }
   
   if(ShowGoldPanel && TradeGold)  {
      double usdStrength = CurrencyStrength[0];
      SafeSetText("DB4_UsdStrength", "USD Strength: "+DoubleToString(usdStrength,1)+"%");
      double goldSpread = GetCurrentSpread(GoldSymbol);
      SafeSetText("DB4_GoldSpread", "Spread: "+DoubleToString(goldSpread,1)+" / "+DoubleToString(MaxSpreadAU,1)+" pips");
      if(goldSpread<=MaxSpreadAU) ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_COLOR,C'0,255,0');
      else ObjectSetInteger(0,"DB4_GoldSpread",OBJPROP_COLOR,C'255,100,100');
      
      SafeSetText("DB4_ProfitDollars_Val", DoubleToString(TP_Multiplier,2));
      SafeSetText("DB4_SLPips_Val", DoubleToString(GlobalSL_Pips,1));
      SafeSetText("DB4_MaxTrades_Val", IntegerToString(MaxGoldTrades));
      SafeSetText("DB4_MaxSpread_Val", DoubleToString(MaxSpreadAU,1)+" pips");
      
      string goldStatus = "No gold trade";
      double goldProfitPips = 0;
      for(int i = PositionsTotal()-1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC)==MagicNumber) {
            string sym = PositionGetString(POSITION_SYMBOL);
            if((StringFind(sym, "XAU")>=0 || StringFind(sym, "GOLD")>=0) && StringFind(PositionGetString(POSITION_COMMENT), "Swap Order") < 0) {
               ENUM_POSITION_TYPE dir = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double curPrice = (dir==POSITION_TYPE_BUY) ? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK);
               double point = GetSymbolPoint(sym);
               goldProfitPips = (dir==POSITION_TYPE_BUY) ? (curPrice-openPrice)/point : (openPrice-curPrice)/point;
               goldStatus = (dir==POSITION_TYPE_BUY) ? "BUY gold (open)" : "SELL gold (open)";
               break;
            }
         }
      }
      SafeSetText("DB4_GoldTradeStatus", goldStatus);
      SafeSetText("DB4_GoldTradePips", "Profit: "+DoubleToString(goldProfitPips,1)+" pips");
      if(goldProfitPips>0) ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_COLOR,C'0,255,0');
      else if(goldProfitPips<0) ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_COLOR,C'255,100,100');
      else ObjectSetInteger(0,"DB4_GoldTradePips",OBJPROP_COLOR,C'200,200,200');
   }

   if(ShowSettingsPanel) {
      string tradingStatus = EnableTrading ? "ON" : "OFF";
      SafeSetText("DB5_TradingValue", tradingStatus);
      color tradingColor = EnableTrading ? C'0,255,0' : C'255,100,100';
      ObjectSetInteger(0,"DB5_TradingValue",OBJPROP_COLOR,tradingColor);
      SafeSetText("DB5_MagicValue", IntegerToString(MagicNumber));
      
      SafeSetText("DB5_ProfitValue", DoubleToString(TP_Multiplier,2));
      SafeSetText("DB5_SLPipsValue", DoubleToString(GlobalSL_Pips,1));
      
      SafeSetText("DB5_BOValue", EnableBOMode ? "ON" : "OFF");
      ObjectSetInteger(0,"DB5_BOValue",OBJPROP_COLOR, EnableBOMode ? C'0,255,0' : C'255,100,100');
      
      SafeSetText("DB5_BOBlockHoursValue", IntegerToString(BlockHours));
      
      SafeSetText("DB5_BOSwapThresholdValue", DoubleToString(SwapEntryAbsThreshold,2));
      
      string swapStatus = EnableSwapTrading ? "ON" : "OFF";
      SafeSetText("DB5_SwapValue", swapStatus);
      ObjectSetInteger(0,"DB5_SwapValue",OBJPROP_COLOR, EnableSwapTrading ? C'0,255,0' : C'255,100,100');
      
      string trailStatus = EnableTrailingStop ? "ON" : "OFF";
      SafeSetText("DB5_TrailingValue", trailStatus);  // keep the ON/OFF status if you still have it

      SafeSetText("DB5_TrailActValue",  DoubleToString(TrailActivationPercent,1)+"%");
      SafeSetText("DB5_TrailStepValue", DoubleToString(TrailStepPips,1)+" pips");
      
      SafeSetText("DB5_PyramidValue", IntegerToString(GlobalMaxTradesPerSymbol));
      
      SafeSetText("DB5_Session", GetSessionText());
      
      // Daily Reset status (using new close/resume times)
      if(EnableDailyReset) {
         string closeStr = StringFormat("%02d:%02d", DailyCloseHour, DailyCloseMinute);
         string resumeStr = StringFormat("%02d:%02d", DailyResumeHour, DailyResumeMinute);
         string status = g_dailyResetPauseActive ? "(PAUSED)" : "(ACTIVE)";
         SafeSetText("DB5_DailyResetValue", "Close: " + closeStr + " | Resume: " + resumeStr + " " + status);
      }
   }
   ChartRedraw();
}

void UpdateBOReversalAverages()
{
   if(!EnableBOMode || !BO_UseReversalEntry) return;

   datetime now = TimeCurrent();
   // Recalculate if more than 3600 seconds have passed
   if(now - g_lastBORevCalc < 3600) return;

   for(int i = 0; i < boSymbolCount; i++)
   {
      boRevAvg[i] = ComputeBOReversalAverage(boSymbols[i]);
      boRevAvgComputed[i] = (boRevAvg[i] > 0);
      if(VerboseLogging)
      Print("[BO-Rev] Recalculated ", boSymbols[i],
            " avg=", DoubleToString(boRevAvg[i], 1), " pts",
            " | Threshold=", DoubleToString(boRevAvg[i] * BO_RevCandleMultiplier, 1), " pts");
   }
   g_lastBORevCalc = now;
}


//+------------------------------------------------------------------+
//| Detect index symbols (add common names here)                      |
//+------------------------------------------------------------------+
void DetectIndexSymbols() {
   indexSymbolCount = 0;
   string prefixes[] = {
      "US30","DE30","GER30","EU50","ESTX50","JP225"
   };
   for(int p=0; p<ArraySize(prefixes); p++) {
      for(int i=0; i<SymbolsTotal(false); i++) {
         string sym = SymbolName(i, false);
         if(StringFind(sym, prefixes[p]) >= 0) {
            if(SymbolInfoDouble(sym, SYMBOL_BID) > 0 && SymbolInfoInteger(sym, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_DISABLED) {
               // avoid duplicates
               bool already = false;
               for(int m=0; m<indexSymbolCount; m++) {
                  if(indexSymbols[m] == sym) { already = true; break; }
               }
               if(!already && indexSymbolCount < 50) {
                  indexSymbols[indexSymbolCount] = sym;
                  indexSymbolCount++;
               }
            }
         }
      }
   }
   if(VerboseLogging) Print("Index symbols detected: ", indexSymbolCount);
}

//+------------------------------------------------------------------+
//| Get the highest high and lowest low in a given time range        |
//+------------------------------------------------------------------+
bool GetBlockRange(string symbol, datetime from, datetime to, double &high, double &low)
{
   high = -1;
   low  = 1e9;
   bool found = false;

   // Use H1 candles for consistency with other index logic
   int startBar = GetBarShift(symbol, Timeframe, from, false);
   int endBar   = GetBarShift(symbol, Timeframe, to, false);

   if(startBar < 0) startBar = 0;
   if(endBar < 0)   endBar   = 0;
   if(startBar > endBar) { int tmp = startBar; startBar = endBar; endBar = tmp; }

   for(int i = startBar; i <= endBar; i++)
   {
      datetime barTime[1];
      if(CopyTime(symbol, Timeframe, i, 1, barTime) != 1) continue;
      if(barTime[0] < from || barTime[0] >= to) continue;

      double h[1], l[1];
      if(CopyHigh(symbol, Timeframe, i, 1, h) != 1) continue;
      if(CopyLow(symbol, Timeframe, i, 1, l) != 1) continue;

      if(h[0] > high) high = h[0];
      if(l[0] < low)  low  = l[0];
      found = true;
   }

   // Fallback to daily if no H1 data found
   if(!found)
   {
      double dailyHigh[1], dailyLow[1];
      if(CopyHigh(symbol, PERIOD_D1, 1, 1, dailyHigh) == 1 &&
         CopyLow(symbol, PERIOD_D1, 1, 1, dailyLow) == 1)
      {
         high = dailyHigh[0];
         low  = dailyLow[0];
         found = true;
      }
   }
   return found;
}

//+------------------------------------------------------------------+
//| Monday open breakout – new logic: previous daily H/L, first 3 1H   |
//| candle closes outside the box trigger immediate entry             |
//+------------------------------------------------------------------+

// Helper: process one symbol for Monday special
bool ProcessMondaySymbol(string sym, int entryType, bool usePartialTP, int maxTrades,
                         double maxSpread, bool enableTP,
                         datetime mondayStart,
                         string &tradedSymbols[], int &tradedCount,
                         string &checkedCandles[], int &checkedCount)
{
   if(!IsSymbolValidForTrading(sym)) return false;
   // Already traded this Monday?
   for(int t=0; t<tradedCount; t++) if(tradedSymbols[t] == sym) return false;

   // Previous daily high/low (Friday’s data if Monday)
   double dailyHigh[1], dailyLow[1];
   if(CopyHigh(sym, PERIOD_D1, 1, 1, dailyHigh) != 1 || CopyLow(sym, PERIOD_D1, 1, 1, dailyLow) != 1)
   {
      if(VerboseLogging) Print("[Monday] ", sym, " no daily data");
      return false;
   }
   double boxHigh = dailyHigh[0];
   double boxLow  = dailyLow[0];
   if(boxHigh <= boxLow)
   {
      if(VerboseLogging) Print("[Monday] ", sym, " invalid daily range");
      return false;
   }

   datetime now = TimeCurrent();
   // Check the first three 1H candles (0 = current, 1 = last closed, 2 = before last)
   for(int candleIdx = 0; candleIdx < 3; candleIdx++)
   {
      datetime candleOpen = mondayStart + candleIdx * 3600;
      // Only check if the candle is already closed
      if(now < candleOpen + 3600) continue;

      // Prevent checking the same candle twice
      string checkKey = sym + "_" + IntegerToString(candleIdx);
      bool alreadyChecked = false;
      for(int c=0; c<checkedCount; c++) if(checkedCandles[c] == checkKey) { alreadyChecked = true; break; }
      if(alreadyChecked) continue;
      // Mark as checked
      if(checkedCount < 300) { checkedCandles[checkedCount] = checkKey; checkedCount++; }

      int barShift = iBarShift(sym, Timeframe, candleOpen, false);
      if(barShift < 0) continue;
      double closePrice = iClose(sym, Timeframe, barShift);
      if(closePrice <= 0) continue;

      if(closePrice > boxHigh || closePrice < boxLow)
      {
         // Signal! Direction: close > high → SELL, close < low → BUY
         int dir = (closePrice > boxHigh) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         
         // Shared direction filter for Monday Special
         if(DirectionFilter == DIRECTION_LONG_ONLY  && dir == ORDER_TYPE_SELL) return false;
         if(DirectionFilter == DIRECTION_SHORT_ONLY && dir == ORDER_TYPE_BUY)  return false;
         
         if(VerboseLogging) Print("[Monday] ", sym, " candle ", candleIdx, " closed outside box. Close=", closePrice,
                                  " Box[", boxLow, "/", boxHigh, "] Dir=", (dir==ORDER_TYPE_BUY?"BUY":"SELL"));

         // Spread check
         double spread = GetCurrentSpread(sym);
         if(spread > maxSpread)
         {
            if(VerboseLogging) Print("[Monday] ", sym, " spread too wide: ", spread, " > ", maxSpread);
            return false;   // don't try again this Monday
         }
         
         // Swap filter for forex Monday specials
         if(entryType == 0)
         {
            if(!IsSwapValidForThreshold(sym, (ENUM_ORDER_TYPE)dir))
            {
               if(VerboseLogging) Print("[Monday] ", sym, " rejected: swap filter failed.");
               return false;
            }
         }
         // Trade limit check
         int currentTrades = 0;
         if(entryType == 0) currentTrades = CountForexTrades();
         else if(entryType == 5) currentTrades = CountIndexTrades();
         else if(entryType == 6) currentTrades = CountOilTrades();
         else if(entryType == 2) currentTrades = CountGoldTrades();
         else if(entryType == 8) currentTrades = CountBTCTrades();
         if(currentTrades >= maxTrades)
         {
            if(VerboseLogging) Print("[Monday] ", sym, " max trades reached");
            return false;
         }

         // Execute trade
         int digits = GetDigits(sym);
         double pipSize = GetPipSize(sym);
         if(StringFind(sym, "XAU")>=0 || StringFind(sym, "GOLD")>=0) pipSize = 1.0;
         double heightPoints = (boxHigh - boxLow) / pipSize;
         double slPriceDist;
         if(UseATR_SLTP)
         {
            double atr = GetATRValue(sym);
            slPriceDist = (atr > 0) ? atr * ATR_SL_Multiplier : (boxHigh - boxLow) / 2.0;
         }
         else slPriceDist = (heightPoints / 2.0) * pipSize;
         double tpPriceDist = slPriceDist * TP_Multiplier;
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         double entry = (dir == ORDER_TYPE_BUY) ? ask : bid;
         entry = NormalizeDouble(entry, digits);
         double sl = (dir == ORDER_TYPE_BUY) ? entry - slPriceDist : entry + slPriceDist;
         double tp = (dir == ORDER_TYPE_BUY) ? entry + tpPriceDist : entry - tpPriceDist;
         sl = NormalizeDouble(sl, digits);
         tp = NormalizeDouble(tp, digits);
         if(!enableTP) tp = 0;

         double lotSize = GetRiskBasedLot(sym, slPriceDist);
         double validLot = GetValidLotSize(sym, lotSize);
         string comment;
         if(entryType == 5) comment = "Index Order Monday Special " + (dir==ORDER_TYPE_BUY?"BUY":"SELL");
         else if(entryType == 6) comment = "Oil Order Monday Special " + (dir==ORDER_TYPE_BUY?"BUY":"SELL");
         else if(entryType == 0) comment = "Forex Monday Special " + (dir==ORDER_TYPE_BUY?"BUY":"SELL");
         else if(entryType == 2) comment = "Gold Monday Special " + (dir==ORDER_TYPE_BUY?"BUY":"SELL");
         else if(entryType == 8) comment = "BTC Monday Special " + (dir==ORDER_TYPE_BUY?"BUY":"SELL");

         if(CountTradesForSymbol(sym) >= GlobalMaxTradesPerSymbol)
         {
            if(VerboseLogging) Print("[Monday] ", sym, " max positions per symbol");
            return false;
         }
         if(DailyTradeCount_Get(sym) >= MaxDailyTradesPerSymbol)
         {
            if(VerboseLogging) Print("[Monday] ", sym, " max daily trades per symbol");
            return false;
         }
         if(MaxDailyTradesGlobal > 0 && g_dailyTradeGlobalCount >= MaxDailyTradesGlobal)
         {
            if(VerboseLogging) Print("[Monday] global daily trade limit reached");
            return false;
         }

         if(VerboseLogging) Print("[Monday] ATTEMPTING ENTRY on ", sym);
         if(RetryPositionOpen(sym, (ENUM_ORDER_TYPE)dir, validLot, entry, sl, tp, comment))
         {
            SetEntryType(Trade.ResultOrder(), entryType);
            DailyTradeCount_Increment(sym);
            Log(StringFormat("[MONDAY] %s | %s | Lot=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f",
                             sym, (dir==ORDER_TYPE_BUY?"BUY":"SELL"), validLot, entry, sl, tp), true);
            if(PlaySounds && SoundFileOpen != "") PlaySound(SoundFileOpen);
            // Register for partial TP if applicable
            if(usePartialTP && TradeCount < 50)
            {
               Trades[TradeCount].ticket = Trade.ResultOrder();
               Trades[TradeCount].openPrice = entry;
               Trades[TradeCount].openTime = TimeCurrent();
               Trades[TradeCount].currentSL = sl;
               Trades[TradeCount].pairSymbol = sym;
               Trades[TradeCount].isGold = (entryType == 2 || entryType == 4);
               Trades[TradeCount].isBO = false;
               Trades[TradeCount].entryType = entryType;
               Trades[TradeCount].lastTrailStep = 0;
               Trades[TradeCount].lastTrailPrice = entry;
               Trades[TradeCount].lastTrailTime = TimeCurrent();
               Trades[TradeCount].partialDone = false;
               Trades[TradeCount].lastPartialTime = 0;
               Trades[TradeCount].originalLot = validLot;
               Trades[TradeCount].partial25Done = false;
               Trades[TradeCount].partial50Done = false;
               Trades[TradeCount].partial75Done = false;
               TradeCount++;
            }
            // Remember this symbol so we don't trade it again this Monday
            if(tradedCount < 100) { tradedSymbols[tradedCount] = sym; tradedCount++; }
            return true;
         }
         else
         {
            if(VerboseLogging) Print("[Monday] Entry failed for ", sym);
            return false;
         }
      }
      else
      {
         if(VerboseLogging) Print("[Monday] ", sym, " candle ", candleIdx, " closed inside box. Close=", closePrice,
                                  " Box[", boxLow, "/", boxHigh, "]");
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Main Monday check function                                        |
//+------------------------------------------------------------------+
void CheckMondayOpenCondition()
{
   if(!EnableIndexTrading && !TradeOil && !EnableThresholdTrading && !TradeGold && !TradeBitcoin) return;
   if(!IsTradingHourAllowed()) return; 
   if(g_allTradingPaused || g_dailyResetPauseActive) return;
   if(TimeCurrent() - g_initTime < StartupDelaySeconds) return;

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week != 1) return;   // Monday only

   datetime mondayStart = now - dt.hour * 3600 - dt.min * 60 - dt.sec;
   // Only active during the first three 1H candles (00:00 – 03:00)
   if(now >= mondayStart + 3 * 3600) return;

   // Static state arrays (reset each Monday)
   static string tradedSymbols[100];
   static int    tradedCount = 0;
   static string checkedCandles[300];
   static int    checkedCount = 0;
   static datetime lastMondayStateReset = 0;
   if(mondayStart != lastMondayStateReset)
   {
      tradedCount = 0;
      checkedCount = 0;
      lastMondayStateReset = mondayStart;
   }

   // --- Process each instrument group ---
   // Indices
   if(EnableIndexTrading)
   {
      for(int i=0; i<indexSymbolCount && i<50; i++)
         ProcessMondaySymbol(indexSymbols[i], 5, Index_UsePartialTP, MaxIndexTrades, MaxSpreadIndices, Index_EnableTP,
                             mondayStart, tradedSymbols, tradedCount, checkedCandles, checkedCount);
   }

   // Oil
   if(TradeOil && OilTradeAllowed && OilSymbol != "")
      ProcessMondaySymbol(OilSymbol, 6, OilRVI_UsePartialTP, MaxOilTrades, MaxSpreadOil, true,
                          mondayStart, tradedSymbols, tradedCount, checkedCandles, checkedCount);

   // Forex (top swap symbols)
   if(EnableThresholdTrading)
   {
      for(int i=0; i<g_topSwapCount && i<10; i++)
         ProcessMondaySymbol(g_topSwapSymbols[i], 0, true, MaxForexTrades, MaxSpreadPips, true,
                             mondayStart, tradedSymbols, tradedCount, checkedCandles, checkedCount);
   }

   // Gold
   if(TradeGold && GoldTradeAllowed && GoldSymbol != "")
      ProcessMondaySymbol(GoldSymbol, 2, true, MaxGoldTrades, MaxSpreadAU, true,
                          mondayStart, tradedSymbols, tradedCount, checkedCandles, checkedCount);

   // BTC
   if(TradeBitcoin && BTCTradeAllowed && BTCSymbol != "")
      ProcessMondaySymbol(BTCSymbol, 8, false, MaxBitcoinTrades, MaxSpreadBTC, true,
                          mondayStart, tradedSymbols, tradedCount, checkedCandles, checkedCount);
}

//+------------------------------------------------------------------+
//| Load previous block high/low for an index symbol                  |
//+------------------------------------------------------------------+
void LoadIndexBlockLevels(int idx)
{
   string symbol = indexSymbols[idx];
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int currentBlockHour = (dt.hour / BlockHours) * BlockHours;
   dt.hour = currentBlockHour; dt.min = 0; dt.sec = 0;
   datetime currentBlockStart = StructToTime(dt);
   datetime prevBlockStart = currentBlockStart - BlockHours * 3600;

   if(idxLastBlockStart[idx] == currentBlockStart && idxPrevPeriodReady[idx])
      return;

   idxLastBlockStart[idx] = currentBlockStart;
   idxPrevPeriodReady[idx] = false;
   g_breakoutUp[MAX_BO_SYMBOLS + idx]   = false;
   g_breakoutDown[MAX_BO_SYMBOLS + idx] = false;
   
   double boxHigh = -1, boxLow = 1e9;
   bool found = false;

   // First try H1
   ENUM_TIMEFRAMES tf = Timeframe;
   int startBar = GetBarShift(symbol, tf, prevBlockStart, false);
   int endBar   = GetBarShift(symbol, tf, currentBlockStart, false);
   if(startBar < 0) startBar = 0;
   if(endBar < 0)   endBar   = 0;
   if(startBar > endBar) { int tmp = startBar; startBar = endBar; endBar = tmp; }

   for(int i = startBar; i <= endBar; i++)
   {
      datetime barTime[1];
      if(CopyTime(symbol, tf, i, 1, barTime) != 1) continue;
      if(barTime[0] < prevBlockStart || barTime[0] >= currentBlockStart) continue;
      double h[1], l[1];
      if(CopyHigh(symbol, tf, i, 1, h) != 1 || CopyLow(symbol, tf, i, 1, l) != 1) continue;
      if(h[0] > boxHigh) boxHigh = h[0];
      if(l[0] < boxLow)  boxLow  = l[0];
      found = true;
   }

   // Fallback: M15
   if(!found)
   {
      tf = PERIOD_M15;
      startBar = GetBarShift(symbol, tf, prevBlockStart, false);
      endBar   = GetBarShift(symbol, tf, currentBlockStart, false);
      if(startBar < 0) startBar = 0;
      if(endBar < 0)   endBar   = 0;
      if(startBar > endBar) { int tmp = startBar; startBar = endBar; endBar = tmp; }
      for(int i = startBar; i <= endBar; i++)
      {
         datetime barTime[1];
         if(CopyTime(symbol, tf, i, 1, barTime) != 1) continue;
         if(barTime[0] < prevBlockStart || barTime[0] >= currentBlockStart) continue;
         double h[1], l[1];
         if(CopyHigh(symbol, tf, i, 1, h) != 1 || CopyLow(symbol, tf, i, 1, l) != 1) continue;
         if(h[0] > boxHigh) boxHigh = h[0];
         if(l[0] < boxLow)  boxLow  = l[0];
         found = true;
      }
   }

   // NO daily fallback – if still not found, block stays unready
   if(found)
   {
      idxBlockHigh[idx] = boxHigh;
      idxBlockLow[idx]  = boxLow;
      idxPrevPeriodReady[idx] = true;
      Log("[Index] Block loaded for " + symbol + " High=" + DoubleToString(boxHigh, _Digits) +
          " Low=" + DoubleToString(boxLow, _Digits), false);

      double close1H[1];
      if(CopyClose(symbol, Timeframe, 1, 1, close1H) == 1)
      {
         if(close1H[0] > boxHigh)         g_breakoutUp[MAX_BO_SYMBOLS + idx]   = true;
         else if(close1H[0] < boxLow)     g_breakoutDown[MAX_BO_SYMBOLS + idx] = true;
      }
   }
}

bool IsTradingHourAllowed()
{
   if(StartTradingHour == StopTradingHour) return true;   // always allowed
   
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   if(StartTradingHour < StopTradingHour)
      return (hour >= StartTradingHour && hour < StopTradingHour);
   else   // overnight window (e.g. 20 → 6)
      return (hour >= StartTradingHour || hour < StopTradingHour);
}

//+------------------------------------------------------------------+
//| CSV STATE PERSISTENCE SYSTEM                                      |
//+------------------------------------------------------------------+

// File path – stored in the terminal's common Files folder
#define STATE_FILENAME "SumtingWong_State.csv"

//+------------------------------------------------------------------+
//| Write all current state to CSV file                                |
//+------------------------------------------------------------------+
void SaveStateToCSV()
{
   static datetime lastSave = 0;
   if(TimeCurrent() - lastSave < 30) return;
   lastSave = TimeCurrent();

   string fileName = STATE_FILENAME;
   int handle = FileOpen(fileName, FILE_WRITE|FILE_CSV|FILE_COMMON, ",");
   if(handle == INVALID_HANDLE)
   {
      if(VerboseLogging) Print("[CSV] Failed to open state file for writing. Error: ", GetLastError());
      return;
   }

   datetime now = TimeCurrent();
   string today = TimeToString(now, TIME_DATE);

   // --- SECTION 1: Daily Trade Counts ---
   for(int i = 0; i < g_dailyTradeTotal; i++)
      FileWrite(handle, "DAILY_TRADES", g_dailyTrades[i].symbol, g_dailyTrades[i].count, today);
   FileWrite(handle, "DAILY_TRADES", "_GLOBAL_", g_dailyTradeGlobalCount, today);

   // --- SECTION 2: Partial TP State ---
   for(int t = 0; t < TradeCount; t++)
   {
      if(!PositionSelectByTicket(Trades[t].ticket)) continue;
      FileWrite(handle, "PARTIAL_TP",
                Trades[t].ticket,
                Trades[t].pairSymbol,
                Trades[t].partial25Done ? "TRUE" : "FALSE",
                Trades[t].partial50Done ? "TRUE" : "FALSE",
                Trades[t].partial75Done ? "TRUE" : "FALSE",
                Trades[t].breakevenPending ? "TRUE" : "FALSE",
                DoubleToString(Trades[t].breakevenSL, _Digits),
                DoubleToString(Trades[t].originalLot, 2),
                TimeToString(Trades[t].lastPartialTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   // --- SECTION 3: Trailing Stop State ---
   for(int t = 0; t < TradeCount; t++)
   {
      if(!PositionSelectByTicket(Trades[t].ticket)) continue;
      if(Trades[t].lastTrailPrice == 0) continue;
      FileWrite(handle, "TRAIL",
                Trades[t].ticket,
                DoubleToString(Trades[t].lastTrailPrice, _Digits),
                TimeToString(Trades[t].lastTrailTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   // --- SECTION 4: Daily Lenient Swap Done ---
   FileWrite(handle, "LENIENT_SWAP", today, g_dailyLenientSwapDone ? "TRUE" : "FALSE");

   // --- SECTION 5: Swap Group Leader Ticket ---
   if(g_swapGroupLeaderTicket != 0 && PositionSelectByTicket(g_swapGroupLeaderTicket))
      FileWrite(handle, "SWAP_LEADER", g_swapGroupLeaderTicket, today);

   // --- SECTION 6: BO Reversal Averages ---
   for(int i = 0; i < boSymbolCount; i++)
   {
      if(boRevAvgComputed[i])
         FileWrite(handle, "BO_REV_AVG",
                   boSymbols[i],
                   DoubleToString(boRevAvg[i], 1),
                   boRevAvgComputed[i] ? "TRUE" : "FALSE",
                   TimeToString(g_lastBORevCalc, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   // --- SECTION 7: Stop‑loss backup for paused surviving trades ---
   for(int i = 0; i < g_slBackupCount; i++)
   {
      if(PositionSelectByTicket(g_slBackup[i].ticket))
         FileWrite(handle, "SL_BACKUP",
                   g_slBackup[i].ticket,
                   DoubleToString(g_slBackup[i].originalSL, _Digits));
   }

   // --- SECTION 8: Daily Close Done Flag ---
   FileWrite(handle, "DAILY_CLOSE_DONE", today, g_dailyCloseDone ? "TRUE" : "FALSE");

   // --- SECTION 9: Daily Pause Resume Time ---
   if(g_dailyResetPauseActive)
      FileWrite(handle, "DAILY_PAUSE", TimeToString(g_dailyResumeTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));

   // --- SECTION 10: JPY Block Triggered Today ---
   FileWrite(handle, "JPY_BLOCK", today, g_jpyBlockTriggeredToday ? "TRUE" : "FALSE");

   // --- SECTION 11: Auto Profit Stop Trading ---
   FileWrite(handle, "AUTO_PROFIT_STOP", today, g_profitStopTrading ? "TRUE" : "FALSE");

   // --- SECTION 12: Swap Candle Lock Times ---
   for(int i = 0; i < boSymbolCount; i++)
   {
      if(g_swapSignalCandleTime[i] != 0)
         FileWrite(handle, "SWAP_CANDLE",
                   boSymbols[i],
                   TimeToString(g_swapSignalCandleTime[i], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   // --- SECTION 13: Entry Type Map ---
   for(int i = 0; i < g_typeMapCount; i++)
   {
      if(PositionSelectByTicket(g_typeMap[i].ticket))
         FileWrite(handle, "ENTRY_TYPE", g_typeMap[i].ticket, g_typeMap[i].entryType);
   }

   // --- SECTION 14: BO Reversal Trade Allowed ---
   for(int i = 0; i < boSymbolCount; i++)
   {
      FileWrite(handle, "BO_REV_ALLOWED",
                boSymbols[i],
                boRevTradeAllowed[i] ? "TRUE" : "FALSE",
                TimeToString(boLastCandleTime[i], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   }

   FileClose(handle);
   
   static datetime s_lastCsvPrint = 0;
   if(VerboseLogging && TimeCurrent() - s_lastCsvPrint >= 300)
   {
      Print("[CSV] State saved to ", fileName, " at ", TimeToString(now, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
      s_lastCsvPrint = TimeCurrent();
   }
}

void RebuildDailyCountsFromOpenTrades()
{
   string today = TimeToString(TimeCurrent(), TIME_DATE);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(TimeToString(openTime, TIME_DATE) != today) continue;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      
      // Check if already counted by LoadStateFromCSV
      bool alreadyCounted = false;
      for(int j = 0; j < g_dailyTradeTotal; j++)
      {
         if(g_dailyTrades[j].symbol == sym && g_dailyTrades[j].count > 0)
         {
            alreadyCounted = true;
            break;
         }
      }
      if(alreadyCounted) continue;
      
      g_dailyTradeGlobalCount++;
      
      bool found = false;
      for(int j = 0; j < g_dailyTradeTotal; j++)
      {
         if(g_dailyTrades[j].symbol == sym)
         {
            g_dailyTrades[j].count++;
            found = true;
            break;
         }
      }
      if(!found && g_dailyTradeTotal < 100)
      {
         g_dailyTrades[g_dailyTradeTotal].symbol = sym;
         g_dailyTrades[g_dailyTradeTotal].count = 1;
         g_dailyTradeTotal++;
      }
   }
}

//+------------------------------------------------------------------+
//| Load state from CSV file (called once in OnInit)                   |
//+------------------------------------------------------------------+
void LoadStateFromCSV()
{
   string fileName = STATE_FILENAME;
   
   if(!FileIsExist(fileName, FILE_COMMON))
   {
      if(VerboseLogging) Print("[CSV] No state file found. Starting fresh.");
      return;
   }

   g_slBackupCount = 0;

   int handle = FileOpen(fileName, FILE_READ|FILE_CSV|FILE_COMMON, ",");
   if(handle == INVALID_HANDLE)
   {
      if(VerboseLogging) Print("[CSV] Failed to open state file for reading. Error: ", GetLastError());
      return;
   }

   string today = TimeToString(TimeCurrent(), TIME_DATE);
   int loadedCount = 0;

   while(!FileIsEnding(handle))
   {
      string section = FileReadString(handle);
      
      // --- DAILY_TRADES ---
      if(section == "DAILY_TRADES")
      {
         string sym   = FileReadString(handle);
         int count    = (int)FileReadNumber(handle);
         string date  = FileReadString(handle);
         
         if(date == today)
         {
            if(sym == "_GLOBAL_")
               g_dailyTradeGlobalCount = count;
            else if(g_dailyTradeTotal < 100)
            {
               g_dailyTrades[g_dailyTradeTotal].symbol = sym;
               g_dailyTrades[g_dailyTradeTotal].count  = count;
               g_dailyTradeTotal++;
            }
            loadedCount++;
         }
      }
      
      // --- PARTIAL_TP ---
      else if(section == "PARTIAL_TP")
      {
         ulong ticket        = (ulong)FileReadNumber(handle);
         string sym          = FileReadString(handle);
         string p25          = FileReadString(handle);
         string p50          = FileReadString(handle);
         string p75          = FileReadString(handle);
         string bePending    = FileReadString(handle);
         double beSL         = FileReadNumber(handle);
         double origLot      = FileReadNumber(handle);
         string lastPartTime = FileReadString(handle);
         
         if(TradeCount < 50 && PositionSelectByTicket(ticket))
         {
            Trades[TradeCount].ticket           = ticket;
            Trades[TradeCount].pairSymbol       = sym;
            Trades[TradeCount].partial25Done    = (p25 == "TRUE");
            Trades[TradeCount].partial50Done    = (p50 == "TRUE");
            Trades[TradeCount].partial75Done    = (p75 == "TRUE");
            Trades[TradeCount].breakevenPending = (bePending == "TRUE");
            Trades[TradeCount].breakevenSL      = beSL;
            Trades[TradeCount].originalLot      = origLot;
            Trades[TradeCount].lastPartialTime  = StringToTime(lastPartTime);
            TradeCount++;
            loadedCount++;
         }
      }
      
      // --- TRAIL ---
      else if(section == "TRAIL")
      {
         ulong ticket      = (ulong)FileReadNumber(handle);
         double trailPrice = FileReadNumber(handle);
         string trailTime  = FileReadString(handle);
         
         int idx = -1;
         for(int t = 0; t < TradeCount; t++)
            if(Trades[t].ticket == ticket) { idx = t; break; }
         if(idx >= 0)
         {
            Trades[idx].lastTrailPrice = trailPrice;
            Trades[idx].lastTrailTime  = StringToTime(trailTime);
         }
         else if(TradeCount < 50 && PositionSelectByTicket(ticket))
         {
            Trades[TradeCount].ticket         = ticket;
            Trades[TradeCount].lastTrailPrice = trailPrice;
            Trades[TradeCount].lastTrailTime  = StringToTime(trailTime);
            TradeCount++;
         }
         loadedCount++;
      }
      
      // --- LENIENT_SWAP ---
      else if(section == "LENIENT_SWAP")
      {
         string date = FileReadString(handle);
         string val  = FileReadString(handle);
         if(date == today)
         {
            g_dailyLenientSwapDone = (val == "TRUE");
            loadedCount++;
         }
      }
      
      // --- SWAP_LEADER ---
      else if(section == "SWAP_LEADER")
      {
         ulong ticket = (ulong)FileReadNumber(handle);
         string date  = FileReadString(handle);
         if(date == today && PositionSelectByTicket(ticket))
         {
            g_swapGroupLeaderTicket = ticket;
            loadedCount++;
         }
      }
      
      // --- BO_REV_AVG ---
      else if(section == "BO_REV_AVG")
      {
         string sym       = FileReadString(handle);
         double avg       = FileReadNumber(handle);
         string computed  = FileReadString(handle);
         string calcTime  = FileReadString(handle);
         
         for(int i = 0; i < boSymbolCount; i++)
         {
            if(boSymbols[i] == sym)
            {
               boRevAvg[i]         = avg;
               boRevAvgComputed[i] = (computed == "TRUE");
               g_lastBORevCalc     = StringToTime(calcTime);
               loadedCount++;
               break;
            }
         }
      }
      
      // --- SWAP_CANDLE ---
      else if(section == "SWAP_CANDLE")
      {
         string sym      = FileReadString(handle);
         string timeStr  = FileReadString(handle);
         datetime candleTime = StringToTime(timeStr);
         
         if(TimeCurrent() - candleTime < 86400)
         {
            for(int i = 0; i < boSymbolCount; i++)
            {
               if(boSymbols[i] == sym)
               {
                  g_swapSignalCandleTime[i] = candleTime;
                  loadedCount++;
                  break;
               }
            }
         }
      }
      
      // --- ENTRY_TYPE ---
      else if(section == "ENTRY_TYPE")
      {
         ulong ticket   = (ulong)FileReadNumber(handle);
         int entryType  = (int)FileReadNumber(handle);
         
         if(PositionSelectByTicket(ticket) && g_typeMapCount < 100)
         {
            g_typeMap[g_typeMapCount].ticket    = ticket;
            g_typeMap[g_typeMapCount].entryType = entryType;
            g_typeMapCount++;
            loadedCount++;
         }
      }
      
      // --- BO_REV_ALLOWED ---
      else if(section == "BO_REV_ALLOWED")
      {
         string sym      = FileReadString(handle);
         string allowed  = FileReadString(handle);
         string timeStr  = FileReadString(handle);
         datetime lastCandle = StringToTime(timeStr);
         
         for(int i = 0; i < boSymbolCount; i++)
         {
            if(boSymbols[i] == sym)
            {
               boRevTradeAllowed[i] = (allowed == "TRUE");
               boLastCandleTime[i]  = lastCandle;
               loadedCount++;
               break;
            }
         }
      }

      // --- AUTO_PROFIT_STOP ---
      else if(section == "AUTO_PROFIT_STOP")
      {
         string date = FileReadString(handle);
         string val  = FileReadString(handle);
         if(date == today)
         {
            g_profitStopTrading = (val == "TRUE");
            loadedCount++;
         }
      }

      // --- SL_BACKUP ---
      else if(section == "SL_BACKUP")
      {
         ulong ticket    = (ulong)FileReadNumber(handle);
         double origSL   = FileReadNumber(handle);
         
         if(PositionSelectByTicket(ticket) && g_slBackupCount < 50)
         {
            g_slBackup[g_slBackupCount].ticket     = ticket;
            g_slBackup[g_slBackupCount].originalSL = origSL;
            g_slBackupCount++;
            loadedCount++;
         }
      }

      // --- DAILY_CLOSE_DONE ---
      else if(section == "DAILY_CLOSE_DONE")
      {
         string date = FileReadString(handle);
         string val  = FileReadString(handle);
         if(date == today)
            g_dailyCloseDone = (val == "TRUE");
      }

      // --- DAILY_PAUSE ---
      else if(section == "DAILY_PAUSE")
      {
         string resumeTimeStr = FileReadString(handle);
         datetime loadedResumeTime = StringToTime(resumeTimeStr);
         if(loadedResumeTime > TimeCurrent())
         {
            g_dailyResetPauseActive = true;
            g_dailyResumeTime       = loadedResumeTime;
            if(!g_dailyCloseDone) g_dailyCloseDone = true;
         }
         loadedCount++;
      }
      
      // Skip unknown sections
      else
      {
         while(!FileIsEnding(handle) && !FileIsLineEnding(handle))
            FileReadString(handle);
      }
   }

   FileClose(handle);
   
   if(g_slBackupCount > 0)
      ReapplySLForSurvivingTrades();

   if(VerboseLogging)
      Print("[CSV] State loaded. ", loadedCount, " records restored from ", fileName);
}

//+------------------------------------------------------------------+
//| Clean old entries from CSV (optional – called periodically)        |
//+------------------------------------------------------------------+
void CleanStateCSV()
{
   // Run once per hour to remove entries for closed trades and old dates
   static datetime lastClean = 0;
   if(TimeCurrent() - lastClean < 3600) return;
   lastClean = TimeCurrent();
   
   // Simply re-save – the save function only writes current state
   SaveStateToCSV();
}

void CheckAutoProfitClose()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(UseVirtualBalance && VirtualBalance > 0 && balance >= VirtualBalance)
      balance = VirtualBalance;
   if(balance <= 0) return;

   double totalOpenProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         totalOpenProfit += PositionGetDouble(POSITION_PROFIT);
   }

   double profitPct = (totalOpenProfit / balance) * 100.0;

   if(AutoCloseEnable)
   {
      if(profitPct >= AutoClosePercentage && !g_profitThresholdTriggered)
      {
         g_profitThresholdTriggered = true;
         Log(StringFormat("[AUTO-CLOSE] Profit reached %.2f%%. Closing all trades.", profitPct), true);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
               Trade.PositionClose(ticket);
         }
         if(AutoCloseStopForDay)
         {
            g_profitStopTrading = true;
            Log("[AUTO-CLOSE] Stopping trading for the rest of the day.", true);
         }
         if(PlaySounds && ProfitAlertSound != "")
            PlaySound(ProfitAlertSound);
      }
      if(PositionsTotal() == 0)
         g_profitThresholdTriggered = false;
   }
   else
   {
      if(profitPct >= AutoClosePercentage && !g_profitAlertTriggered)
      {
         g_profitAlertTriggered = true;
         string msg = StringFormat("Profits reached %.1f%% (Threshold: %.1f%%) – Recommended to take profit.",
                                    profitPct, AutoClosePercentage);
         Print(msg);   // <<< Replaced Alert() with Print() – no system sound
         Log(msg, true);
         if(AutoCloseStopForDay)
         {
            g_profitStopTrading = true;
            Log("[ALERT] Stopping trading for the rest of the day.", true);
         }
         if(PlaySounds && ProfitAlertSound != "")
            PlaySound(ProfitAlertSound);
      }
      if(profitPct < AutoClosePercentage - 0.1 && g_profitAlertTriggered)
         g_profitAlertTriggered = false;
   }
}

//+------------------------------------------------------------------+
//| OnInit, OnDeinit, OnTick                                         |
//+------------------------------------------------------------------+
int OnInit() {
    ApplyBlackoutMode();
   
    if(Passkey != "poopyface94")
   {
      Alert("Invalid passkey. EA will not run.");
      return(INIT_FAILED);
   }
   g_initTime = TimeCurrent();
      // Inside OnInit() after initializations:
   g_allTradingPaused = false;
   g_profitStopTrading = false;
   g_swapGroupLeaderTicket = 0;
   g_dailyResumeTime = 0;
   DashboardXpos = DashboardX;
   DashboardYpos = DashboardY;
   DeleteDashboard();
   DetectGoldSymbol();
   DetectOilSymbol();
   DetectMetalSymbols();
   DetectIndexSymbols();
   DetectBitcoinSymbol();

   if(AutoDetectPairs) AutoDetect();
   else {
      int totalPairs = ArraySize(PossiblePairs);
      PairCount = totalPairs;
      for(int i=0;i<totalPairs && i<50;i++) Pairs[i].symbol = GetFullSymbol(PossiblePairs[i]);
   }
   if(PairCount == 0) return INIT_FAILED;

   for(int i = 0; i < indexSymbolCount && i < 50; i++)
   {
      mondayActive[i] = false;
      mondayFirstCandleProcessed[i] = false;
   }
   for(int i = 0; i < 50; i++) idxRVICloseBarTime[i] = 0;
   DetectUSDJPYSymbol();
   InitSymbolCache();
   
   for(int i=0; i<PairCount; i++) {
      string sym = Pairs[i].symbol;
      rsiHandles[i] = iRSI(sym, PERIOD_M1, 14, PRICE_CLOSE);
      ma20Handles[i] = iMA(sym, PERIOD_M1, 20, 0, MODE_SMA, PRICE_CLOSE);
      ma50Handles[i] = iMA(sym, PERIOD_M1, 50, 0, MODE_SMA, PRICE_CLOSE);
   }
   
   CalculateStrength();
   CheckAllLimits();
   BO_InitializeSymbols();
   if(SR_DrawLines) CalculateSRLevelsForSymbol(Symbol());
   if(ShowDashboard) CreateDashboard();
   ArrayInitialize(g_swapReEntryTaken, false);
   ArrayInitialize(g_breakoutUp, false);
   ArrayInitialize(g_breakoutDown, false);
      // Initialize index blocks
   for(int i=0; i < indexSymbolCount && i < 50; i++) {
      idxPrevPeriodReady[i] = false;
      idxLastBlockStart[i] = 0;
      idxSignalCandleTime[i] = 0;
      g_breakoutUp[MAX_BO_SYMBOLS + i]      = false;
      g_breakoutDown[MAX_BO_SYMBOLS + i]    = false;
   }
   for(int i=0; i<boSymbolCount; i++) g_swapSignalCandleTime[i] = 0;
   for(int i=0; i<boSymbolCount; i++) swapFB_RVIBarTime[i] = 0;
   for(int i=0; i < indexSymbolCount && i < 50; i++) idxFB_RVIBarTime[i] = 0;
   BO_LoadAllPreviousPeriodLevels();   // always needed for swap/index blocks
   for(int i=0; i<MathMin(5, boSymbolCount); i++) {
      Print("BO Init: ", boSymbols[i], " Ready=", boPrevPeriodReady[i], 
            " High=", DoubleToString(boPrevPeriodHigh[i], (int)SymbolInfoInteger(boSymbols[i], SYMBOL_DIGITS)),
            " Low=", DoubleToString(boPrevPeriodLow[i], (int)SymbolInfoInteger(boSymbols[i], SYMBOL_DIGITS)));
   }
   
   if(EnableDailyReset) {
      g_currentDailyBlockStart = GetCurrentDailyBlockStart();
      g_nextDailyResetStr = TimeToString(g_currentDailyBlockStart + 86400, TIME_DATE);
      Log("Daily reset enabled. Next reset at: " + g_nextDailyResetStr, true);
   }
   
   DynamicStatus = "Waiting for signal";
   DailyTradeCount_Reset();
   LoadStateFromCSV();
   RebuildDailyCountsFromOpenTrades(); 
   if(ShowDashboard) UpdateDashboard();
   // --- Restore daily pause if one was active at shutdown ---
   if(g_dailyResetPauseActive)
   {
      Log("Daily pause restored – trading paused until " + TimeToString(g_dailyResumeTime, TIME_DATE|TIME_MINUTES), true);
      RemoveSLForSurvivingTrades();
   }
   
   // -- NEW: initialise the reliable time references
   g_lastKnownServerTime = TimeCurrent();
   g_lastTickCount = GetTickCount();
   
   EventSetTimer(3);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   DeleteDashboard();
   SaveStateToCSV();
   EventKillTimer();
   ObjectDelete(0, "MarketStatus");
   for(int i=0; i<PairCount; i++) {
      if(rsiHandles[i] != INVALID_HANDLE) IndicatorRelease(rsiHandles[i]);
      if(ma20Handles[i] != INVALID_HANDLE) IndicatorRelease(ma20Handles[i]);
      if(ma50Handles[i] != INVALID_HANDLE) IndicatorRelease(ma50Handles[i]);
   }
}

void OnTick() {
   dotAnimStep = (dotAnimStep + 1) % 3;
   ApplySLTPToNewBOTrades();
   ManageTrades();
   UpdateAllBreakoutFlags();
   CheckRVIClose();
   CheckAndManageSwapTrades();
   CheckBOMode();
   CheckIndicesRVIMode();
   CheckFalseBreakoutRVI();
   CheckMondayOpenCondition();
   CheckGoldRVIMode();
   CheckOilRVIMode();
   CheckBTCRVIMode();
   CheckAndPerformDailyReset();
   
   // ---------- USDJPY block (Tokyo hours only) ----------
   if(g_usdjpySymbol != "" && !g_jpyBlockTriggeredToday)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      int serverHour = dt.hour;
      // Tokyo session: 3:00 to 12:00 server time
      if(serverHour >= 3 && serverHour < 12)
      {
         double usdjpyBid = SymbolInfoDouble(g_usdjpySymbol, SYMBOL_BID);
         if(usdjpyBid >= JPY_BlockThresh)
         {
            g_jpyBlockTriggeredToday = true;
            g_allTradingPaused = true;
            // Set Tokyo pause end time to 12:00 today
            dt.hour = 12; dt.min = 0; dt.sec = 0;
            g_tokyoPauseEndTime = StructToTime(dt);

            Log("[JPY-Block] USDJPY reached " + DoubleToString(JPY_BlockThresh, 2)+
                " during Tokyo hours. Pausing trading until 12:00, pausing all entries, placing gold buy order", true);

            // Open gold buy swap
            if(GoldTradeAllowed && GoldSymbol != "")
            {
               double pipSize = 1.0;
               double slPips = GlobalSL_Pips * SwapRiskMultiplier * GoldPipMultiplier;
               double slPriceDist = slPips * pipSize;
               double goldLot = GetRiskBasedLot(GoldSymbol, slPriceDist);
               OpenSwapTrade(GoldSymbol, ORDER_TYPE_BUY, goldLot, "Swap Order", "JPY block gold");
            }
            else
            {
               Log("[JPY-Block] Gold symbol not available – swap order skipped.", true);
            }

            // Place sell stop orders for top N swap symbols at previous period low
            int maxStops = MathMin(TopSwapCount, g_topSwapCount);
            for(int s = 0; s < maxStops; s++)
            {
               string sym = g_topSwapSymbols[s];
               int symIdx = -1;
               for(int b = 0; b < boSymbolCount; b++) if(boSymbols[b] == sym) { symIdx = b; break; }
               if(symIdx < 0 || !boPrevPeriodReady[symIdx]) continue;

               double blockLow = boPrevPeriodLow[symIdx];
               double bid = SymbolInfoDouble(sym, SYMBOL_BID);
               // Only place if current price is above the low (sell stop must be below market)
               if(bid > blockLow)
               {
                  double halfBlockHeight = GetHalfBlockHeight(sym);
                  if(halfBlockHeight <= 0)
                     halfBlockHeight = GlobalSL_Pips * SwapRiskMultiplier * GetPipSize(sym);
                  double tpDist = halfBlockHeight * TP_Multiplier;
                  int digits = GetDigits(sym);
                  double entryPrice = NormalizeDouble(blockLow, digits);
                  double slPrice = entryPrice + halfBlockHeight;
                  slPrice = NormalizeDouble(slPrice, digits);
                  double tpPrice = entryPrice - tpDist;
                  tpPrice = NormalizeDouble(tpPrice, digits);

                  double lotSize = GetRiskBasedLot(sym, halfBlockHeight);
                  double validLot = GetValidLotSize(sym, lotSize);

                  Trade.SetExpertMagicNumber(MagicNumber);
                  if(Trade.SellStop(validLot, entryPrice, sym, slPrice, tpPrice, ORDER_TIME_GTC, 0, "JPY Block Sell Stop"))
                  {
                     Log("[JPY-Block] Placed sell stop at " + DoubleToString(entryPrice, digits) + " on " + sym, true);
                  }
               }
            }
         }
      }
   }

   // Clear Tokyo pause after 12:00
   if(g_allTradingPaused && g_jpyBlockTriggeredToday && TimeCurrent() >= g_tokyoPauseEndTime)
   {
      // Delete all pending sell stop orders placed by the JPY block
      for(int o = OrdersTotal() - 1; o >= 0; o--)
      {
         ulong orderTicket = OrderGetTicket(o);
         if(orderTicket == 0) continue;
         if(OrderSelect(orderTicket))
         {
            if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
               StringFind(OrderGetString(ORDER_COMMENT), "JPY Block Sell Stop") >= 0)
            {
               Trade.OrderDelete(orderTicket);
               Log("[JPY-Block] Deleted sell stop order " + IntegerToString(orderTicket), false);
            }
         }
      }

      g_allTradingPaused = false;
      Log("[JPY-Block] Tokyo session ended – trading resumed.", true);
   }
   
   UpdateDashboard();
   SaveStateToCSV();
   CleanStateCSV();
   
   CheckAutoProfitClose();
   RetryReapplySL();
   if(SR_DrawLines && TimeCurrent() - lastSRCalcDraw > 3600) {
      CalculateSRLevelsForSymbol(Symbol());
      lastSRCalcDraw = TimeCurrent();
   }
   
    if(EnableThresholdTrading) {
      // Add trading hours check here before processing any signals
      if(!IsTradingHourAllowed()) {
         // Clear any pending signals if outside trading hours
         if(g_pendingSignal) {
            g_pendingSignal = false;
            g_signalLocked = false;
         }
         if(g_goldPendingSignal) {
            g_goldPendingSignal = false;
            g_goldSignalLocked = false;
         }
      }
      else if(UseOneHourCloseConfirmation) {
         // ----- Release forex lock when entry conditions are no longer met -----
         if(g_signalLocked && !IsEntryAllowed()) {
            g_signalLocked = false;
         }
         // ----- Release gold lock when entry conditions are no longer met -----
         if(g_goldSignalLocked) {
            int dummy;
            if(!IsGoldEntryAllowed(dummy)) {
               g_goldSignalLocked = false;
            }
         }

         // ----- Process a pending forex signal -----
         if(g_pendingSignal) {
            datetime currentCandleOpen = iTime(g_signalSymbol, Timeframe, 0);
            if(currentCandleOpen != g_signalCandleOpen) {
               double closeArr[1];
               if(CopyClose(g_signalSymbol, Timeframe, 1, 1, closeArr) > 0) {
                  double closePrice = closeArr[0];
                  bool confirmed = false;

                  if(!ReverseTrades)
                  {
                     if(g_signalDirection == ORDER_TYPE_BUY  && closePrice > g_signalPrice)
                        confirmed = true;
                     else if(g_signalDirection == ORDER_TYPE_SELL && closePrice < g_signalPrice)
                        confirmed = true;
                  }
                  else
                  {
                     if(g_signalDirection == ORDER_TYPE_BUY  && closePrice < g_signalPrice)
                        confirmed = true;
                     else if(g_signalDirection == ORDER_TYPE_SELL && closePrice > g_signalPrice)
                        confirmed = true;
                  }

                  if(confirmed) {
                     if(IsEntryAllowed()) {
                        OpenTradeConfirmed(g_signalSymbol, g_signalDirection, closePrice);
                        g_signalLocked = true;
                     }
                  }
                  g_pendingSignal = false;
               }
            }
         }
         // ----- Check for a new forex signal -----
         else if(!g_signalLocked && IsEntryAllowed()) {
            string symbol = CurrentPair;
            int dir = GetTradeDirection();
            if(dir != -1) {
               g_signalSymbol     = symbol;
               g_signalDirection  = dir;
               g_signalPrice      = (dir == ORDER_TYPE_BUY) ?
                                    SymbolInfoDouble(symbol, SYMBOL_ASK) :
                                    SymbolInfoDouble(symbol, SYMBOL_BID);
               g_signalCandleOpen = iTime(symbol, Timeframe, 0);
               g_pendingSignal    = true;
               g_signalLocked     = true;
               DynamicStatus = "Signal pending 1H close confirmation";
               if(ShowDashboard) UpdateDashboard();
            }
         }

         // ----- Gold pending signal handling -----
         if(g_goldPendingSignal) {
            datetime currentCandleOpen = iTime(GoldSymbol, Timeframe, 0);
            if(currentCandleOpen != g_goldSignalCandleOpen) {
               double closeArr[1];
               if(CopyClose(GoldSymbol, Timeframe, 1, 1, closeArr) > 0) {
                  double closePrice = closeArr[0];
                  bool confirmed = false;

                  if(!ReverseTrades) {
                     if(g_goldSignalDirection == ORDER_TYPE_BUY  && closePrice > g_goldSignalPrice)
                        confirmed = true;
                     else if(g_goldSignalDirection == ORDER_TYPE_SELL && closePrice < g_goldSignalPrice)
                        confirmed = true;
                  } else {
                     if(g_goldSignalDirection == ORDER_TYPE_BUY  && closePrice < g_goldSignalPrice)
                        confirmed = true;
                     else if(g_goldSignalDirection == ORDER_TYPE_SELL && closePrice > g_goldSignalPrice)
                        confirmed = true;
                  }

                  if(confirmed) {
                     int dirCheck;
                     if(IsGoldEntryAllowed(dirCheck) && dirCheck == g_goldSignalDirection) {
                        OpenTradeConfirmed(GoldSymbol, g_goldSignalDirection, closePrice);
                        g_goldSignalLocked = true;
                     }
                  }
                  g_goldPendingSignal = false;
               }
            }
         }
         // ----- Check for a new gold signal -----
         else if(!g_goldSignalLocked) {
            int goldDir;
            if(IsGoldEntryAllowed(goldDir)) {
               g_goldSignalDirection = goldDir;
               g_goldSignalPrice     = (goldDir == ORDER_TYPE_BUY) ?
                                       SymbolInfoDouble(GoldSymbol, SYMBOL_ASK) :
                                       SymbolInfoDouble(GoldSymbol, SYMBOL_BID);
               g_goldSignalCandleOpen = iTime(GoldSymbol, Timeframe, 0);
               g_goldPendingSignal   = true;
               g_goldSignalLocked    = true;
               DynamicStatus = "Gold signal pending 1H close confirmation";
               if(ShowDashboard) UpdateDashboard();
            }
         }
      }
      else {
         // ----- Original immediate entry (unchanged when confirmation is off) -----
         if(IsTradingHourAllowed() && IsEntryAllowed() && !TradeReady) {
            TradeReady = true;
            DynamicStatus = "Threshold met: " + Currencies[CurrentStrongest] + ">=" + DoubleToString(StrongEntryThreshold,1) + "% & " + Currencies[CurrentWeakest] + "<=" + DoubleToString(WeakEntryThreshold,1) + "%";
            if(ShowDashboard) UpdateDashboard();
            OpenTrade();
            TradeReady = false;
         }
   
         int goldDir;
         if(IsTradingHourAllowed() && IsGoldEntryAllowed(goldDir)) {
            DynamicStatus = "Gold signal: " + (goldDir==ORDER_TYPE_BUY?"BUY":"SELL");
            if(ShowDashboard) UpdateDashboard();
            OpenGoldTrade(goldDir);
         }
      }
   }
   
   if(DrawHLLines) {
   }
}
void OnTimer() {
   CalculateStrength();
   UpdateBOReversalAverages();  
   //Print("[TIMER] Tick at ", TimeCurrent());  
   CheckAndPerformDailyReset();   
   if(ShowDashboard) UpdateDashboard();
      // Periodic state save
   SaveStateToCSV();
}
//+------------------------------------------------------------------+