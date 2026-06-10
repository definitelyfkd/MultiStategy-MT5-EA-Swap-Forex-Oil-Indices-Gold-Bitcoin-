# MultiStategy-MT5-EA-Swap-Forex-Oil-Indices-Gold-Bitcoin-
Sumting Wong EA 
===============================================================================
                SumtingWong? EA v1.40 – User Guide & Summary
===============================================================================

1. OVERVIEW
-----------
This Expert Advisor automatically manages multiple trading strategies:
  - Currency Strength Threshold (Forex & Gold)
  - Breakout/Reversal (BO) Mode on Forex, Gold, Oil, Indices, Bitcoin
  - Swap Carry Trading (top positive‑swap pairs)
  - RVI‑based close & false breakout entries
  - Monday Special breakouts (first 3 hours of Monday)
  - Daily reset, trading pause, risk management
  - Live dashboard & CSV state persistence

2. INSTALLATION & QUICK START
-----------------------------
1. Attach the EA to any chart (M5 or higher).
2. Set the Passkey input exactly to: poopyface94
3. Ensure EnableTrading = true and AutoTrading is on.
4. Set a unique MagicNumber to avoid interference with other EAs.
5. The EA auto‑detects symbols; you can adjust SymbolPrefix/Suffix.
6. Configure StartTradingHour / StopTradingHour to your desired window.
7. Adjust risk settings (RiskPercent, TP_Multiplier, GlobalSL_Pips, etc.)
8. The dashboard will appear – adjust position and visible panels as needed.

3. INPUT PARAMETERS (by group)
------------------------------

--- General Options ---
Passkey                 Must be "poopyface94"
EnableTrading           Master switch
MagicNumber             Unique ID for EA orders (default: 04011994)
ReverseTrades           Reverse all signal directions (default: true)
StartupDelaySeconds     Wait before first trade (10)
Timeframe               Main analysis timeframe (default: H1)
BlockHours              Length of each block period (12)
StartTradingHour        Server hour to allow new trades (0)
StopTradingHour         Server hour to stop opening new trades (24 = always)
RVIPeriod               Period for RVI indicator (10)

--- Risk Management ---
TP_Multiplier           TP distance = SL pips × multiplier (2.0)
RiskPercent             Risk per trade as % of balance (0.50)
UseVirtualBalance       Use a fixed balance for risk calculation (true)
VirtualBalance          Virtual balance amount (100000.0)
PostEntrySLTP           Place SL/TP after trade opens (false)
GlobalSL_Pips           Fixed SL in pips if ATR off (25)
GlobalMaxTradesPerSymbol Max open positions per symbol (1)
MaxDailyTradesPerSymbol Max trades per symbol per day (2)
MaxDailyTradesGlobal    Max total daily trades across all symbols (10)

--- Auto Profit Close ---
AutoCloseEnable         Close all trades at profit threshold (true)
AutoClosePercentage     Profit % of balance to trigger close (1.0)
AutoCloseStopForDay     Stop trading for day after trigger (true)

--- Partial Take Profit ---
UsePartialTP            Enable multi‑tier partial closing (true)
BreakEvenAfterPartial   Move SL to breakeven after 25% TP (true)
BEPercentofTP           SL offset as % of TP distance (5.0)

--- Stop Loss Options ---
UseATR_SLTP             Use ATR for SL/TP (true)
ATR_SL_Period           ATR period (14)
ATR_SL_Multiplier       SL = ATR × multiplier (3.0)
EnableTrailingStop      Activate trailing stop (true)
TrailStepPips           Minimum step before SL moves (1)
TrailActivationPercent  Profit % of TP to start trailing (20.0)

--- Entry Threshold (Forex) ---
EnableThresholdTrading  Enable strength‑based entries (true)
Threshold_UseSwapFilter Only trade positive‑swap pairs (true)
UseOneHourCloseConfirm  Wait for 1H close to confirm signal (true)
MaxForexTrades          Max simultaneous threshold trades (3)
StrongEntryThreshold    Min strength for strongest currency (60.0)
WeakEntryThreshold      Max strength for weakest currency (40.0)
MinGapEntry             Minimum gap between strong/weak (20.0)
MinGapDurationSeconds   (unused in code)
MaxSpreadPips           Max allowed spread in pips (3.0)

--- BO Mode (Reversal) ---
EnableBOMode            Enable BO reversal strategy (true)
MaxBOTrades             Max BO forex trades (3)
BO_ReverseTrades        Reverse BO signal direction (false)
BO_UseSwapFilter        Apply swap filter to BO entries (true)
BO_UseReversalEntry     Use historical reversal averages (true)
BO_RevLookbackDays      History days for average (28)
BO_RevTopCount          Top N biggest reversal candles (21)
BO_RevCandleMultiplier  Entry threshold = avg × multiplier (1.5)
BO_RevReversalMinutes   Price must cross candle open within X min (30)
BO_RevImmediateEntry    Enter immediately when candle reaches size (false)
BO_RevMinBodyPercent    Min body % of range for close‑confirm (5.0)
BO_MultiCandleLookback  Combine range over N candles (3)

--- Swap Trading ---
EnableSwapTrading       Enable carry trade strategy (true)
SwapMasterMode          Lenient / Moderate / Strict (Strict)
MaxSwapTrades           Max simultaneous swap trades (3)
TopSwapCount            How many pairs to hold (3)
SwapEntryAbsThreshold   Min positive swap to enter (2.5)
SwapCloseAbsThreshold   Close if swap drops below this (0.5)
SwapRiskMultiplier      Multiply SL pips for swap trades (1.0)
TradeWithTopNSwap       Group all top N when leader enters/closes (false)
BOTopSwapCount          Used in group logic (3)
SwapStrict_WaitClose    Wait for 1H close in Strict mode (true)
StrictSwap_UseDynamicCandleSize Use BO‑average candle size filter (true)
StrictSwap_CandleAvgMultiplier  Multiplier for candle size (1.0)

--- Direction Filter ---
DirectionFilter         Applies to Oil/Indices/Gold/BTC (DIRECTION_DEFAULT)

--- Gold Trading ---
TradeGold               Enable gold trading (true)
MaxGoldTrades           Max gold threshold trades (1)
MaxBOGoldTrades         Max gold BO trades (1)
MaxSpreadAU             Max spread for gold (5.0)
GoldPipMultiplier       Multiply SL/TP pips for gold (1.0)
GoldRVI_UsePartialTP    Allow partial TP for gold RVI trades (true)

--- Oil / Index / Bitcoin ---
Similar parameters for spread limits, trade limits, partial TP controls.

--- Daily Reset (24h block) ---
EnableDailyReset        Enable daily close & pause (true)
DailyResetHour          Hour when 24h block starts (0)
DailyCloseHour          Server hour to close trades (23)
DailyCloseMinute        Server minute to close trades (55)
DailyResumeHour         Server hour to resume trading (2)
DailyResumeMinute       Server minute to resume trading (0)
Bypass flags: Monday, Forex Threshold, Swap, Forex BO, Gold Thresh., Oil,
             Gold BO, Index, BTC – set to true to keep trades during close.
DailyClose_SkipCandleAgrees   Don't close if last 1H candle agrees with trade
DailyClose_SwapProfitPercent  Close swap trades if profit % of SL >= (25.0)

--- RVI Close Filter ---
RVI_CloseEnabled        Enable RVI close (true)
MondaySpecial_RVIBypass Skip Monday trades (true)
RVISwapCloseBypass      Skip Swap trades (true)
ForexBO_RVIBypass       Skip Forex BO (true)
GoldBO_RVIBypass        Skip Gold BO (false)
OilBO_RVIBypass         Skip Oil BO (false)
IndexBO_RVIBypass       Skip Index BO (false)
RVI_BTCBypass           Skip Bitcoin trades (false)
RVI_OpenOpposite        Open opposite trade on close (false)

--- False Breakout RVI Entry ---
EnableFalseBreakoutRVI  Enter on RVI cross when breakout flag active (true)

--- S/R Detection (cosmetic only) ---
SR_DrawLines, SR_Accuracy, etc.

--- Dashboard ---
ShowDashboard           Enable dashboard (true)
ShowMainPanel, ShowLivePanel, ShowPairsPanel, ShowGoldPanel, ShowSettingsPanel
DashboardX, DashboardY  Position (10, 30)

--- Blackout Mode, Metals Strength, Logging ---
BlackoutMode            Hide chart elements (true)
ShowMetalsStrength      Show metals bar (true)
VerboseLogging          Detailed logging (true)

--- Audio ---
PlaySounds, SoundFileOpen, SoundFileClose, etc.

4. STRATEGY DETAILS
-------------------

4.1 Currency Strength Threshold (Forex)
  - Strengths (0‑100) are calculated every 3 sec from RSI, Momentum, MAs.
  - Strongest currency must be >= StrongEntryThreshold,
    Weakest <= WeakEntryThreshold, gap >= MinGapEntry.
  - Direction is derived from the pair with strongest base/weak quote,
    reversed if ReverseTrades = true.
  - Optional 1H candle filter and swap filter.
  - With UseOneHourCloseConfirmation, a signal is locked at candle open
    and the trade is taken only if the close confirms the expected breakout.

4.2 Gold Trading
  - Uses Metals Strength (average of XAU, XAG, etc.) and USD strength.
  - BUY: Metals >= StrongEntryThreshold AND USD <= WeakEntryThreshold.
  - SELL: Metals <= WeakEntryThreshold AND USD >= StrongEntryThreshold.
  - Direction is affected by ReverseTrades.
  - Same candle filter and trading hour rules apply.

4.3 BO Reversal Mode
  - Identifies "reversal" candles (large range, open later crossed).
  - Computes average range of top N reversals over lookback days.
  - Triggers when a candle (or multi‑candle) range exceeds:
      average range × BO_RevCandleMultiplier.
  - Immediate mode: enters as soon as current candle hits threshold.
  - Close‑confirm mode: waits for candle close, checks min body %,
    enters in opposite direction of the candle.
  - BO_ReverseTrades flips the direction.
  - Swap filter applies to forex BO trades.

4.4 Swap Trading
  - Builds list of TopSwapCount pairs with highest positive swap.
  - Modes:
    • Lenient: opens immediately once per day.
    • Moderate: opens when an RVI crossover aligns with swap direction.
    • Strict: requires threshold strength + swap filter + candle size/close.
  - Gold fallback: if no forex pair has positive swap, opens up to 3 XAUUSD buys.
  - TradeWithTopNSwap: all top N pairs enter/exit together with the leader.
  - Close threshold: positions closed if swap drops below SwapCloseAbsThreshold.

4.5 RVI Close & False Breakout
  - Once per new 1H bar, if RVI crosses against the trade, the position is closed.
    Bypasses protect certain trade types.
  - False Breakout: when a trade is closed by RVI and a breakout flag is active,
    an opposite trade is opened immediately (forex as swap trade, indices as index trade).

4.6 Monday Special
  - Only on Monday, 00:00 – 03:00 server time.
  - Uses previous daily high/low (Friday) as a box.
  - If any of the first three 1H candles closes outside the box, enters a trade.
  - Includes Forex (with swap filter), Indices, Oil, Gold, BTC.

4.7 Daily Reset & Pause
  - DailyResetHour defines when the 24‑hour block restarts.
  - DailyCloseHour:Minute – all non‑protected trades are closed.
  - DailyResumeHour:Minute – new entries are blocked until this time.
  - Supports overnight pauses (e.g., close 23:55, resume 02:00).
  - Friday close removes all positions and orders.
  - Surviving trades have SL removed during pause and reapplied at resume.

5. RISK & MONEY MANAGEMENT
---------------------------
  - Lot size: risk‑based (balance * RiskPercent) converted via tick size/value.
  - SL/TP: ATR‑based or fixed pips, with multipliers per instrument.
  - Partial TP:
      • 25% TP → move SL to breakeven + offset (after candle close confirmation).
      • 50% TP → close 25% of original lot.
      • 75% TP → close another 25% (remaining 50% runs to full TP).
  - Trailing Stop: activates after TrailActivationPercent of TP,
    step size = TrailStepPips, distance shrinks as TP approaches.
  - Auto Profit Close: close all trades when total profit % of balance is reached.

6. DASHBOARD
------------
  Five panels display:
    • Main: strength bars, strongest/weakest, gap, target pair.
    • Live Trades: counters for each trade type and daily total.
    • Pairs: forex pair list with gap%, S/R, BO levels, reversal threshold, swap rates.
    • Gold: gold status, USD strength, risk parameters, profit.
    • Settings: key parameters, session, daily close/resume times.
  All panels are individually configurable.

7. CSV STATE PERSISTENCE
-------------------------
  - File: SumtingWong_State.csv in the common Files folder.
  - Saves daily trade counts, partial TP/trailing state, swap leader, BO averages,
    pause status, entry types, candle locks.
  - On restart, state is reloaded. Daily pause survives restarts.

8. JPY INTERVENTION BLOCK (TOKYO)
----------------------------------
  - If USDJPY bid >= JPY_BlockThresh (161.0) between 03:00‑12:00 server time:
      • All new entries paused.
      • A gold buy swap order is placed.
      • Sell stop orders are placed at the previous block low of top N swap pairs.
  - At 12:00 Tokyo time, sell stops are deleted and trading resumes.

9. IMPORTANT NOTES
------------------
  - Passkey MUST be "poopyface94".
  - All times use broker's server time.
  - MagicNumber should be unique per EA instance.
  - For indices/oil/btc, ensure your broker offers those symbols.
  - VerboseLogging can be turned off to reduce log size.
  - Deleting the CSV file resets daily counts and states.

10. TROUBLESHOOTING
-------------------
  "Invalid passkey"    → Check passkey input.
  No trades opening     → Check EnableTrading, trading hours, pause, spread limits.
  Wrong symbol names    → Adjust SymbolPrefix/SymbolSuffix or disable auto-detect.
  Dashboard not visible → Ensure ShowDashboard = true, chart window large enough.
  CSV errors            → Delete SumtingWong_State.csv to reset.

===============================================================================
                            End of User Guide
===============================================================================
