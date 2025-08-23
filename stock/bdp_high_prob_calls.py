import ib_insync as ib
from datetime import datetime
import pandas as pd
import time
from math import erf, sqrt
from colorama import Fore, init
import random  # ← added for tiny pacing jitter

# Initialize colorama for colored console output
init(autoreset=True)

def print_banner():
    banner = f"""
{Fore.YELLOW}🚀============================================================🚀
   {Fore.GREEN}🏆  BILLION DOLLAR PLAN  🏆
   {Fore.CYAN}High-Probability Pullback Recovery Call Scanner
   {Fore.MAGENTA}Looking for the Best Option Calls...
{Fore.YELLOW}🚀============================================================🚀
"""
    print(banner)

class PullbackRecoveryScannerV2:
    """
    Scans a watchlist of stocks to find high-probability call option trades.

    This scanner:
    • Checks price volatility using ATR (Average True Range) filters
    • Looks for a pullback of 3-15% from recent highs with at least 1% recovery
    • Picks a target expiration date within a short-term window
    • Examines strike prices near the current stock price
    • Scores and ranks call options based on:
        - Probability of finishing in the money (ITM)
        - Trading volume and open interest (liquidity)
        - Bid-ask spread (trade cost efficiency)
    • Returns the single best contract per symbol

    Probability calculation:
    • If model greeks (implied volatility) are available, uses N(d2)
      to estimate the chance of finishing ITM at expiration.
    • If IV is not available, uses |delta| as a quick probability proxy.
    """

    def __init__(
        self,
        host='127.0.0.1',
        port=7496,
        client_id=44,
        # Daily ATR filters
        min_atr_pct=2.0,
        min_abs_atr=None,
        low_price_threshold=10.0,
        min_abs_atr_low_price=0.25,
        # Intraday ATR gate
        use_intraday_atr=True,
        intraday_bar='30 mins',
        intraday_period=20,
        intraday_min_atr_pct=0.8,
        # Options quality & probability settings
        target_expiry_min_days=7,
        target_expiry_max_days=14,
        strikes_window=12,            # number of strikes around ATM (±window)
        min_volume=100,
        min_open_interest=50,
        max_spread_pct=20.0,
        prefer_delta_min=0.30,
        prefer_delta_max=0.60,
        weight_prob=0.55,
        weight_liquidity=0.25,
        weight_spread=0.20,
    ):
        self.ib = ib.IB()
        self.host = host
        self.port = port
        self.client_id = client_id

        self.min_atr_pct = float(min_atr_pct) if min_atr_pct is not None else None
        self.min_abs_atr = float(min_abs_atr) if min_abs_atr is not None else None
        self.low_price_threshold = float(low_price_threshold)
        self.min_abs_atr_low_price = float(min_abs_atr_low_price)

        self.use_intraday_atr = use_intraday_atr
        self.intraday_bar = intraday_bar
        self.intraday_period = int(intraday_period)
        self.intraday_min_atr_pct = float(intraday_min_atr_pct)

        # Option prefs
        self.target_expiry_min_days = int(target_expiry_min_days)
        self.target_expiry_max_days = int(target_expiry_max_days)
        self.strikes_window = int(strikes_window)
        self.min_volume = int(min_volume)
        self.min_open_interest = int(min_open_interest)
        self.max_spread_pct = float(max_spread_pct)
        self.prefer_delta_min = float(prefer_delta_min)
        self.prefer_delta_max = float(prefer_delta_max)

        # Scoring weights
        self.weight_prob = float(weight_prob)
        self.weight_liquidity = float(weight_liquidity)
        self.weight_spread = float(weight_spread)

        self.connect()

    def connect(self):
        print("🔌 Connecting to TWS...")
        try:
            self.ib.connect(self.host, self.port, clientId=self.client_id)
            print("✅ Connected to TWS")
        except Exception as e:
            print(f"❌ Could not connect to TWS/IB Gateway on {self.host}:{self.port} (clientId={self.client_id}).")
            print(f"   Error: {e}")
            raise

    # ---------- Data helpers ----------
    def _fetch_daily_bars(self, contract, days='60 D'):
        return self.ib.reqHistoricalData(
            contract, endDateTime='', durationStr=days,
            barSizeSetting='1 day', whatToShow='TRADES', useRTH=True
        )

    def _fetch_intraday_bars(self, contract, duration='2 D', bar='30 mins'):
        return self.ib.reqHistoricalData(
            contract, endDateTime='', durationStr=duration,
            barSizeSetting=bar, whatToShow='TRADES', useRTH=True
        )

    @staticmethod
    def _wilder_atr(bars, period=14):
        if len(bars) < period + 1:
            return None
        trs = []
        for i in range(1, len(bars)):
            high = bars[i].high
            low = bars[i].low
            prev_close = bars[i-1].close
            tr = max(high - low, abs(high - prev_close), abs(low - prev_close))
            trs.append(tr)
        if len(trs) < period:
            return None
        atr = sum(trs[:period]) / period
        for tr in trs[period:]:
            atr = (atr * (period - 1) + tr) / period
        return atr

    @staticmethod
    def _atr_pct(atr, price):
        return (atr / price) * 100.0 if atr and price else None

    def get_stock_data(self, symbol):
        """Current price, 5D hi/lo, daily bars (for ATR)."""
        try:
            contract = ib.Stock(symbol, 'SMART', 'USD')
            self.ib.qualifyContracts(contract)

            # Snapshot to reduce pacing; wait briefly for a tick
            t = self.ib.reqMktData(contract, '', snapshot=True)
            price = None
            for _ in range(6):  # up to ~3s
                self.ib.sleep(0.5)
                price = t.marketPrice() or t.last
                if price and price > 0:
                    break

            # daily bars for ATR + 5D hi/lo
            bars = self._fetch_daily_bars(contract, days='60 D')

            # Fallback: if snapshot didn't populate, use most recent daily close
            if (not price or price <= 0) and bars:
                price = bars[-1].close

            if not price or price <= 0:
                return None, None, None, None, None

            if len(bars) < 15:
                return price, None, None, None, contract

            last5 = bars[-5:]
            high_5d = max(b.high for b in last5)
            low_5d = min(b.low for b in last5)

            return price, high_5d, low_5d, bars, contract
        except Exception as e:
            print(f"❌ {symbol} data error: {e}")
            return None, None, None, None, None

    # ---------- Filters ----------
    def passes_daily_atr_filters(self, atr, price):
        if atr is None or price is None or price <= 0:
            return False, "No ATR", None
        reasons = []
        ok = True

        atr_pct = self._atr_pct(atr, price)
        if self.min_atr_pct is not None:
            if (atr_pct or 0) < self.min_atr_pct:
                ok = False
                reasons.append(f"ATR% {atr_pct:.2f}% < {self.min_atr_pct:.2f}%")
            else:
                reasons.append(f"ATR% {atr_pct:.2f}% ≥ {self.min_atr_pct:.2f}%")
        else:
            if (atr_pct or 0) < 2.0:
                ok = False
                reasons.append(f"(default) ATR% {atr_pct:.2f}% < 2.00%")
            else:
                reasons.append(f"(default) ATR% {atr_pct:.2f}% ≥ 2.00%")

        if self.min_abs_atr is not None:
            if atr < self.min_abs_atr:
                ok = False
                reasons.append(f"ATR ${atr:.2f} < ${self.min_abs_atr:.2f}")
            else:
                reasons.append(f"ATR ${atr:.2f} ≥ ${self.min_abs_atr:.2f}")

        if price < self.low_price_threshold:
            if atr < self.min_abs_atr_low_price:
                ok = False
                reasons.append(
                    f"Low-price floor: ATR ${atr:.2f} < ${self.min_abs_atr_low_price:.2f} (price ${price:.2f})"
                )
            else:
                reasons.append(
                    f"Low-price floor passed: ATR ${atr:.2f} ≥ ${self.min_abs_atr_low_price:.2f} (price ${price:.2f})"
                )

        return ok, "; ".join(reasons), atr_pct

    def passes_intraday_atr_gate(self, contract, price):
        if not self.use_intraday_atr:
            return True, "Intraday gate disabled", None, None
        try:
            intrabars = self._fetch_intraday_bars(contract, duration='2 D', bar=self.intraday_bar)
            # Clearer message when there aren't enough bars
            if len(intrabars) < self.intraday_period + 1:
                return True, f"Intraday gate skipped: only {len(intrabars)} bars (< {self.intraday_period + 1})", None, None
            iatr = self._wilder_atr(intrabars, period=self.intraday_period)
            iatr_pct = self._atr_pct(iatr, price)
            if iatr_pct is None or iatr_pct < self.intraday_min_atr_pct:
                return False, f"Intraday ATR% {0 if iatr_pct is None else iatr_pct:.2f}% < {self.intraday_min_atr_pct:.2f}%", iatr, iatr_pct
            return True, f"Intraday ATR: ${iatr:.2f} ({iatr_pct:.2f}%) ≥ {self.intraday_min_atr_pct:.2f}%", iatr, iatr_pct
        except Exception as e:
            return True, f"Intraday ATR gate skipped (error: {e})", None, None

    # ---------- Structure ----------
    def is_pullback_recovery_candidate(self, price, high_5d, low_5d):
        if not all([price, high_5d, low_5d]):
            return False, "No data"
        pullback = ((high_5d - price) / high_5d) * 100
        recovery = ((price - low_5d) / low_5d) * 100
        if 3 <= pullback <= 15 and recovery >= 1:
            return True, f"Pullback {pullback:.1f}%, Recovery {recovery:.1f}%"
        return False, f"Pullback {pullback:.1f}%, Recovery {recovery:.1f}%"

    # ---------- Options helpers ----------
    def _target_expiration(self, expirations):
        now = datetime.now()
        best = None
        best_diff = 999
        for s in expirations:
            try:
                d = datetime.strptime(s, '%Y%m%d')
            except ValueError:
                continue
            days = (d - now).days
            if self.target_expiry_min_days <= days <= self.target_expiry_max_days:
                diff = abs(days - (self.target_expiry_min_days + self.target_expiry_max_days)//2)
                if diff < best_diff:
                    best = s
                    best_diff = diff
        return best

    def _nearby_strikes(self, strikes, price):
        ss = sorted([s for s in strikes if s is not None])
        if not ss:
            return []
        atm = min(ss, key=lambda x: abs(x - price))
        i = ss.index(atm)
        out = []
        for off in range(-self.strikes_window, self.strikes_window + 1):
            j = i + off
            if 0 <= j < len(ss):
                out.append(ss[j])
        return sorted(set(out))

    @staticmethod
    def _norm_cdf(x):
        return 0.5 * (1.0 + erf(x / sqrt(2.0)))

    def _prob_itm_from_iv(self, S, K, T_years, iv):
        """Rough probability stock > K at expiry under lognormal (drift≈0)."""
        try:
            if not (S and K and T_years and iv and iv > 0):
                return None
            import math
            d2 = (math.log(S / K) - 0.5 * (iv ** 2) * T_years) / (iv * math.sqrt(T_years))
            # For calls, P(ITM) ~ N(d2)
            return self._norm_cdf(d2)
        except Exception:
            return None

    def _fetch_option_tickers(self, contracts):
        # Ask for model greeks (106), option OI (101), option volume (100)
        tickers = [self.ib.reqMktData(c, genericTickList='100,101,106', snapshot=False, regulatorySnapshot=False) for c in contracts]
        self.ib.sleep(3)
        return tickers

    def get_option_candidates(self, symbol, price, high_5d, low_5d, chain, exp):
        strikes = self._nearby_strikes(chain.strikes, price)
        if not strikes:
            print("❌ No suitable strikes")
            return None
        contracts = [ib.Option(symbol, exp, k, 'C', 'SMART') for k in strikes]
        qualified = self.ib.qualifyContracts(*contracts)
        tickers = self._fetch_option_tickers(qualified)

        rows = []
        for t in tickers:
            try:
                c = t.contract
                bid = t.bid if t.bid and t.bid > 0 else 0
                ask = t.ask if t.ask and t.ask > 0 else 0
                last = t.last if t.last and t.last > 0 else None
                vol = (t.volume or 0)
                oi = getattr(t, 'optOpenInterest', None) or 0
                mid = (bid + ask) / 2 if bid > 0 and ask > 0 else (last or 0)
                if mid <= 0:
                    continue

                spread = (ask - bid) if (bid > 0 and ask > 0) else None
                spread_pct = ((spread / mid) * 100.0) if (spread is not None and mid > 0) else 100.0

                mg = t.modelGreeks
                delta = abs(mg.delta) if (mg and mg.delta is not None) else None
                iv = mg.impliedVol if (mg and mg.impliedVol and mg.impliedVol > 0) else None

                dtexp = datetime.strptime(c.lastTradeDateOrContractMonth, '%Y%m%d')
                T_years = max((dtexp - datetime.now()).days, 0) / 365.0

                prob_delta = delta if delta is not None else 0
                prob_iv = self._prob_itm_from_iv(price, c.strike, T_years, iv) if iv else None
                prob = prob_iv if prob_iv is not None else prob_delta

                breakeven = c.strike + mid
                breakeven_move_needed_pct = ((breakeven / price - 1) * 100)
                profit_at_high = max(0.0, high_5d - c.strike - mid)
                profit_at_high_pct = (profit_at_high / mid * 100.0) if mid > 0 else 0.0
                be_vs_high = ((breakeven - high_5d) / high_5d) * 100.0

                rows.append({
                    'symbol': symbol,
                    'strike': c.strike,
                    'expiration': c.lastTradeDateOrContractMonth,
                    'bid': bid,
                    'ask': ask,
                    'mid_price': mid,
                    'volume': vol,
                    'open_interest': oi,
                    'delta': delta,
                    'iv': iv,
                    'prob_itm': prob,
                    'current_price': price,
                    'high_5d': high_5d,
                    'low_5d': low_5d,
                    'breakeven': breakeven,
                    'breakeven_move_needed_pct': breakeven_move_needed_pct,
                    'breakeven_vs_high': be_vs_high,
                    'profit_at_high': profit_at_high,
                    'profit_at_high_pct': profit_at_high_pct,
                    'spread': spread if spread is not None else 0.0,
                    'spread_pct': spread_pct,
                })
            except Exception:
                continue

        for t in tickers:
            try:
                self.ib.cancelMktData(t.contract)
            except Exception:
                pass

        df = pd.DataFrame(rows) if rows else None
        return df

    def _score_contracts(self, df):
        if df is None or df.empty:
            return df

        vol_max = max(df['volume'].max(), 1)
        oi_series = df['open_interest'].fillna(0)
        oi_max = max(oi_series.max(), 1)

        vol_norm = (df['volume'] / vol_max).clip(0, 1)
        oi_norm = (oi_series / oi_max).clip(0, 1)
        liquidity = 0.7 * vol_norm + 0.3 * oi_norm

        prob_raw = df['prob_itm'].fillna(df['delta'].fillna(0)).clip(0, 1)

        spread_penalty = (1.0 - (df['spread_pct'] / self.max_spread_pct)).clip(0, 1)

        delta_mid = (self.prefer_delta_min + self.prefer_delta_max) / 2.0
        delta_half = (self.prefer_delta_max - self.prefer_delta_min) / 2.0 or 0.15
        delta_pref = df['delta'].fillna(0).apply(lambda d: max(0.0, 1.0 - abs((d - delta_mid) / delta_half)))

        df = df.assign(
            prob_component=prob_raw,
            liquidity_component=liquidity,
            spread_component=spread_penalty,
            delta_preference=delta_pref,
        )
        df['score'] = (
            self.weight_prob * (0.7 * df['prob_component'] + 0.3 * df['delta_preference']) +
            self.weight_liquidity * df['liquidity_component'] +
            self.weight_spread * df['spread_component']
        )
        return df

    def get_high_probability_calls(self, symbol):
        print(f"\n🔍 ANALYZING {symbol} (high-probability calls)")
        print("-" * 60)
        price, high_5d, low_5d, bars, contract = self.get_stock_data(symbol)
        if not price:
            print(f"❌ Could not get price data for {symbol}")
            return None
        print(f"📈 Current: ${price:.2f}")
        if high_5d and low_5d:
            print(f"📊 5D High: ${high_5d:.2f}, Low: ${low_5d:.2f}")

        if not bars:
            print("❌ No daily bars for ATR")
            return None
        atr = self._wilder_atr(bars, period=14)
        ok_daily, daily_reason, atr_pct = self.passes_daily_atr_filters(atr, price)
        print(f"📐 Daily ATR check: {daily_reason}")
        if not ok_daily:
            print("❌ Fails daily ATR filters")
            return None

        ok_intraday, intraday_msg, iatr, iatr_pct = self.passes_intraday_atr_gate(contract, price)
        print(f"⚡ {intraday_msg}")
        if not ok_intraday:
            print("❌ Fails intraday ATR gate")
            return None

        pullback_ok, reason = self.is_pullback_recovery_candidate(price, high_5d, low_5d)
        print(f"📋 Structure: {reason}")
        if not pullback_ok:
            print("❌ Not a recovery candidate")
            return None
        print("✅ Structure good; proceeding to options")

        chains = self.ib.reqSecDefOptParams(symbol, '', 'STK', contract.conId)
        if not chains:
            print(f"❌ No option chains for {symbol}")
            return None
        # Choose the richest chain (most strikes)
        chain = max(chains, key=lambda c: len(c.strikes) if c.strikes else 0)

        exp = self._target_expiration(chain.expirations)
        if not exp:
            print("❌ No target expirations in desired window")
            return None

        exp_dt = datetime.strptime(exp, "%Y%m%d").strftime("%Y-%m-%d")
        print(f"📅 Target expiration: {exp} ({exp_dt})")

        df = self.get_option_candidates(symbol, price, high_5d, low_5d, chain, exp)
        if df is None or df.empty:
            print("❌ No option candidates fetched")
            return None

        df = df[
            (df['volume'] >= self.min_volume) &
            (df['open_interest'] >= self.min_open_interest) &
            (df['spread_pct'] <= self.max_spread_pct)
        ]
        if df.empty:
            print("ℹ️ All candidates filtered out by liquidity/spread/OI.")
            return None

        df['atr'] = atr
        df['atr_pct'] = atr_pct
        df['iatr'] = iatr
        df['iatr_pct'] = iatr_pct

        df = self._score_contracts(df)
        if df is None or df.empty:
            print("❌ Scoring failed or empty")
            return None

        df_sorted = df.sort_values(['score', 'breakeven_move_needed_pct', 'spread_pct'], ascending=[False, True, True])
        return df_sorted

    def show_results(self, df, symbol, top_n=5):
        if df is None or df.empty:
            return
        print(f"\n💎 HIGH-PROBABILITY CALLS FOR {symbol}")
        print("=" * 92)
        cur = df['current_price'].iloc[0]
        hi = df['high_5d'].iloc[0]
        lo = df['low_5d'].iloc[0]
        atr = df.get('atr', pd.Series([None])).iloc[0]
        atr_pct = df.get('atr_pct', pd.Series([None])).iloc[0]
        iatr = df.get('iatr', pd.Series([None])).iloc[0]
        iatr_pct = df.get('iatr_pct', pd.Series([None])).iloc[0]
        extra = ""
        if atr and atr_pct is not None:
            extra += f" | ATR(d): ${atr:.2f} ({atr_pct:.2f}%)"
        if iatr and iatr_pct is not None:
            extra += f" | ATR(30m): ${iatr:.2f} ({iatr_pct:.2f}%)"
        print(f"📈 Current: ${cur:.2f} | 5D High: ${hi:.2f} | 5D Low: ${lo:.2f}{extra}")

        print("\n🚀 BEST CONTRACTS (probability-weighted):")
        print("Strike | Mid | Vol | OI | Δ | IV | Prob(ITM) | BE | BE Move% | Profit@High% | Spread% | Score")
        print("-" * 120)
        for _, r in df.head(top_n).iterrows():
            print(
                f"${r['strike']:6.2f} | ${r['mid_price']:5.2f} | {int(r['volume']):5d} | {int(r['open_interest']):5d} | "
                f"{(r['delta'] if pd.notna(r['delta']) else 0):.2f} | {(r['iv'] if pd.notna(r['iv']) else 0):.2f} | "
                f"{(r['prob_itm'] if pd.notna(r['prob_itm']) else r['delta']):.2f} | ${r['breakeven']:7.2f} | "
                f"{r['breakeven_move_needed_pct']:7.2f}% | {r['profit_at_high_pct']:8.1f}% | {r['spread_pct']:6.1f}% | {r['score']:5.3f}"
            )

        best = df.iloc[0]
        print("\n💡 BEST OPPORTUNITY:")
        print(f"   {symbol} ${best['strike']:.2f}C @ ${best['mid_price']:.2f} exp {best['expiration']}")
        print(f"   Prob(ITM): {(best['prob_itm'] if pd.notna(best['prob_itm']) else best['delta']):.2f} | Δ {best['delta']:.2f} | IV {(best['iv'] if pd.notna(best['iv']) else 0):.2f}")
        print(f"   BE ${best['breakeven']:.2f} ({best['breakeven_move_needed_pct']:.2f}%) | Spread {best['spread_pct']:.1f}% | Vol {int(best['volume'])} | OI {int(best['open_interest'])}")

    def scan_watchlist(self, symbols):
        print("\n🎯 SCANNING WATCHLIST (High-Probability Version)")
        print("=" * 80)

        # Normalize and dedupe while preserving order
        symbols = list(dict.fromkeys(s.strip().upper() for s in symbols))
        print("🧾 Final watchlist:", ", ".join(symbols))
        
        atr_line = []
        if self.min_atr_pct is not None:
            atr_line.append(f"Daily ATR% ≥ {self.min_atr_pct:.2f}%")
        if self.min_abs_atr is not None:
            atr_line.append(f"ATR ≥ ${self.min_abs_atr:.2f}")
        atr_line.append(f"(<${self.low_price_threshold:.0f}: ATR ≥ ${self.min_abs_atr_low_price:.2f})")
        if self.use_intraday_atr:
            atr_line.append(f"Intraday(30m) ATR% ≥ {self.intraday_min_atr_pct:.2f}%")
        print("🔊 Volatility gates: " + " | ".join(atr_line))
        print("📉 Pullback 3-15% | 📈 Recovery ≥ 1% | 🎯 ±{0} strikes | ⏰ {1}-{2} days".format(
            self.strikes_window, self.target_expiry_min_days, self.target_expiry_max_days))
        print("=" * 80)

        found = {}
        summary_rows = []  # collect top pick per symbol for summary CSV

        for symbol in symbols:
            try:
                df = self.get_high_probability_calls(symbol)
                if df is not None and not df.empty:
                    found[symbol] = df
                    self.show_results(df, symbol)

                    # Save full results per symbol (timestamped)
                    ts = datetime.now().strftime('%Y%m%d_%H%M')
                    fn = f"recovery_hp_{symbol}_{ts}.csv"
                    df.to_csv(fn, index=False)
                    print(f"💾 Saved: {fn}")

                    # Capture this symbol's top pick for the summary CSV
                    best = df.iloc[0]
                    try:
                        exp_human = datetime.strptime(str(best['expiration']), "%Y%m%d").strftime("%Y-%m-%d")
                    except Exception:
                        exp_human = str(best['expiration'])

                    summary_rows.append({
                        "symbol": symbol,
                        "expiration": best['expiration'],
                        "expiration_human": exp_human,
                        "strike": float(best['strike']),
                        "mid_price": float(best['mid_price']),
                        "prob_itm_or_delta": float(best['prob_itm'] if pd.notna(best.get('prob_itm')) else best.get('delta', 0) or 0),
                        "delta": float(best['delta'] if pd.notna(best.get('delta')) else 0),
                        "iv": float(best['iv'] if pd.notna(best.get('iv')) else 0),
                        "breakeven": float(best['breakeven']),
                        "breakeven_move_needed_pct": float(best['breakeven_move_needed_pct']),
                        "profit_at_high_pct": float(best['profit_at_high_pct']),
                        "spread_pct": float(best['spread_pct']),
                        "volume": int(best['volume']),
                        "open_interest": int(best['open_interest']),
                        "score": float(best['score']),
                        "current_price": float(best['current_price']),
                        "high_5d": float(best['high_5d']),
                        "low_5d": float(best['low_5d']),
                        "atr_pct": float(best.get('atr_pct') if pd.notna(best.get('atr_pct')) else 0),
                        "iatr_pct": float(best.get('iatr_pct') if pd.notna(best.get('iatr_pct')) else 0),
                    })

                # Tiny pacing jitter to be gentle on IB pacing limits
                time.sleep(0.35 + random.random() * 0.45)

            except Exception as e:
                print(f"❌ {symbol} error: {e}")
                # still jitter even on errors
                time.sleep(0.35 + random.random() * 0.45)
                continue

        # Print console summary
        if found:
            print("\n🏆 SUMMARY (Top Pick per Symbol)")
            print("=" * 60)
            for sym, df in found.items():
                best = df.iloc[0]
                print(f"{sym}: ${best['strike']:.2f}C @ ${best['mid_price']:.2f} exp {best['expiration']} | "
                      f"Prob {(best['prob_itm'] if pd.notna(best['prob_itm']) else best['delta']):.2f} | "
                      f"BE Move {best['breakeven_move_needed_pct']:.2f}% | Spread {best['spread_pct']:.1f}% | "
                      f"Vol {int(best['volume'])}")

            # Write combined summary CSV (top picks)
            if summary_rows:
                ts_sum = datetime.now().strftime('%Y%m%d_%H%M')
                summary_df = pd.DataFrame(summary_rows)
                sum_fn = f"recovery_hp_summary_{ts_sum}.csv"
                summary_df.to_csv(sum_fn, index=False)
                print(f"\n💾 Summary saved: {sum_fn}")
        else:
            print("\n❌ No candidates found.")

        return found

    def disconnect(self):
        self.ib.disconnect()
        print("\n👋 Disconnected from TWS")


def main():
    print_banner()

    scanner = None
    try:
        scanner = PullbackRecoveryScannerV2(
            port=7496, client_id=45,
            min_atr_pct=2.0,
            min_abs_atr=None,
            low_price_threshold=10.0,
            min_abs_atr_low_price=0.25,
            use_intraday_atr=True,
            intraday_bar='30 mins',
            intraday_period=20,
            intraday_min_atr_pct=0.8,
            # Options prefs
            target_expiry_min_days=7,
            target_expiry_max_days=14,
            strikes_window=12,
            min_volume=100,
            min_open_interest=50,
            max_spread_pct=20.0,
            prefer_delta_min=0.30,
            prefer_delta_max=0.60,
        )

        watchlist = [
            'SPY', 'QQQ', 'TQQQ',
            'AAPL', 'GOOGL', 'AMZN', 'NVDA', 'TSLA', 'AMD', 'PLTR', 'AVGO',
            'META', 'MSFT', 'CRM', 'ORCL', 'CRWV', 'RDDT', 'SMCI', 'MU', 'NBIS',
            'QCOM', 'HOOD', 'ROKU', 'TEM', 'OKLO', 'SMR', 'SOFI', 'ON',
            'PYPL', 'UBER', 'HIMS', 'INTC', 'AMAT', 'PDD', 'AUR', 'TSM',
            'CELH', 'BABA', 'APLD', 'CAVA', 'AFRM', 'PANW', 'KMI', 'RMBS',
            'MARA', 'AEHR', 'PLAB', 'MXL', 'NNE', 'IONQ', 'RGTI', 'ARQQ',
            'QUBT', 'QBTS', 'BA', 'JPM', 'WMT', 'PG', 'JNJ', 'V', 'MA',
            'UNH', 'HD', 'PFE', 'KO', 'PEP', 'XOM', 'CVX', 'T', 'VZ',
            'MRK', 'ABT', 'DIS', 'LYFT', 'ZM', 'SHOP', 'SPOT', 'DOCU',
            'CRWD', 'SNOW', 'DDOG', 'ARKK', 'COIN', 'TGT', 'BULL', 'RKLB',
            'RBLX', 'AI', 'ENPH', 'CAT', 'GS', 'DAL', 'AAL', 'OPEN', 'MDB',
            'ZS', 'MNDY', 'ETSY', 'WBA', 'SBUX', 'NKE', 'LOW', 'CVS', 'GM',
            'LULU',
        ]

        print(f"🔍 Scanning {len(watchlist)} symbols...")
        results = scanner.scan_watchlist(watchlist)
        print("\n🎉 SCAN COMPLETE!")
        print(f"Found candidates in {len(results)} symbols")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        if scanner:
            scanner.disconnect()


if __name__ == "__main__":
    main()
