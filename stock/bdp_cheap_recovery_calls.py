import ib_insync as ib
from datetime import datetime
import pandas as pd
import numpy as np
import time
from colorama import Fore, init

# Initialize colorama for colored console output
init(autoreset=True)

def print_banner():
    banner = f"""
{Fore.YELLOW}🚀============================================================🚀
   {Fore.GREEN}🏆  BILLION DOLLAR PLAN  🏆
   {Fore.CYAN}Cheap Pullback Recovery Call Scanner
   {Fore.MAGENTA}Looking for the Best Cheap Option Calls...
{Fore.YELLOW}🚀============================================================🚀
"""
    print(banner)


class PullbackRecoveryScanner:
    def __init__(
        self,
        host='127.0.0.1',
        port=7496,
        client_id=4,
        # Daily ATR filters
        min_atr_pct=2.0,            # require daily ATR >= 2% of price
        min_abs_atr=None,           # optional $ floor for all symbols
        # Extra $-ATR floor only for low-priced names:
        low_price_threshold=10.0,   # “<$10 stocks”
        min_abs_atr_low_price=0.25, # enforce ATR >= $0.25 if price < $10
        # Intraday ATR gate (today’s volatility)
        use_intraday_atr=True,
        intraday_bar='30 mins',
        intraday_period=20,         # ~one trading day of 30m bars
        intraday_min_atr_pct=0.8,   # raise to 1.0 on choppy days
        # Quality filter params for cheap calls
        min_volume=100,
        max_spread_pct=12.0,        # tighten/loosen as desired
        min_open_interest=50,       # NEW: avoid dead contracts
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

        # Quality filters (configurable)
        self.min_volume = int(min_volume)
        self.max_spread_pct = float(max_spread_pct)
        self.min_open_interest = int(min_open_interest)

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

            # live price (SNAPSHOT: lighter on pacing; no cancel needed)
            t = self.ib.reqMktData(contract, '', snapshot=True)
            self.ib.sleep(1.5)
            price = t.marketPrice() or t.last
            if not price or price <= 0:
                return None, None, None, None, None

            # daily bars for ATR + 5D hi/lo
            bars = self._fetch_daily_bars(contract, days='60 D')
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
        """Daily ATR% and absolute floors (including <$10 special)."""
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
        """30m ATR% gate for 'today's volatility'."""
        if not self.use_intraday_atr:
            return True, "Intraday gate disabled", None, None
        try:
            intrabars = self._fetch_intraday_bars(contract, duration='2 D', bar=self.intraday_bar)
            if len(intrabars) < self.intraday_period + 1:
                return True, "Not enough intraday bars; skipping gate", None, None
            iatr = self._wilder_atr(intrabars, period=self.intraday_period)
            iatr_pct = self._atr_pct(iatr, price)
            if iatr_pct is None or iatr_pct < self.intraday_min_atr_pct:
                return False, f"Intraday ATR% {0 if iatr_pct is None else iatr_pct:.2f}% < {self.intraday_min_atr_pct:.2f}%", iatr, iatr_pct
            return True, f"Intraday ATR: ${iatr:.2f} ({iatr_pct:.2f}%) ≥ {self.intraday_min_atr_pct:.2f}%", iatr, iatr_pct
        except Exception as e:
            return True, f"Intraday ATR gate skipped (error: {e})", None, None

    # ---------- Strategy logic ----------
    def is_pullback_recovery_candidate(self, price, high_5d, low_5d):
        if not all([price, high_5d, low_5d]):
            return False, "No data"
        pullback = ((high_5d - price) / high_5d) * 100
        recovery = ((price - low_5d) / low_5d) * 100
        if 3 <= pullback <= 15 and recovery >= 1:
            return True, f"Pullback {pullback:.1f}%, Recovery {recovery:.1f}%"
        return False, f"Pullback {pullback:.1f}%, Recovery {recovery:.1f}%"

    def find_target_expiration(self, expirations):
        now = datetime.now()
        choices = []
        for s in expirations:
            try:
                d = datetime.strptime(s, '%Y%m%d')
            except ValueError:
                continue
            days = (d - now).days
            if 7 <= days <= 14:
                choices.append((s, days))
        if not choices:
            return None
        return min(choices, key=lambda x: abs(x[1] - 10))[0]

    def get_nearby_strikes(self, strikes, price):
        ss = sorted([s for s in strikes if s is not None])
        if not ss:
            return []
        atm = min(ss, key=lambda x: abs(x - price))
        i = ss.index(atm)
        out = []
        for off in range(-3, 4):
            j = i + off
            if 0 <= j < len(ss):
                out.append(ss[j])
        return sorted(out)  # predictable order

    def get_option_prices(self, symbol, expiration, strikes, price, high_5d, low_5d):
        try:
            print("📊 Getting option prices...")
            contracts = [ib.Option(symbol, expiration, k, 'C', 'SMART') for k in strikes]
            qualified = self.ib.qualifyContracts(*contracts)

            # Request volume (100) and open interest (101); snapshot is lighter-weight
            tickers = [self.ib.reqMktData(c, genericTickList='100,101', snapshot=True) for c in qualified]
            self.ib.sleep(2)

            rows = []
            for t in tickers:
                try:
                    c = t.contract
                    bid = t.bid if t.bid and t.bid > 0 else 0.0
                    ask = t.ask if t.ask and t.ask > 0 else 0.0
                    vol = t.volume or 0
                    oi = getattr(t, 'optOpenInterest', None) or 0
                    if bid > 0 and ask > 0:
                        mid = (bid + ask) / 2
                        # Cheap calls band
                        if 0.05 <= mid <= 0.50:
                            breakeven = c.strike + mid
                            breakeven_vs_high = ((breakeven - high_5d) / high_5d) * 100 if high_5d else np.nan
                            profit_at_high = max(0.0, (high_5d - c.strike - mid)) if high_5d else 0.0
                            profit_at_high_pct = (profit_at_high / mid * 100.0) if mid > 0 else 0.0
                            spread = ask - bid
                            spread_pct = (spread / mid * 100.0) if mid > 0 else 0.0
                            rows.append({
                                'symbol': symbol,
                                'strike': c.strike,
                                'expiration': expiration,
                                'bid': bid,
                                'ask': ask,
                                'mid_price': mid,
                                'volume': vol,
                                'open_interest': oi,
                                'current_price': price,
                                'high_5d': high_5d,
                                'low_5d': low_5d,
                                'breakeven': breakeven,
                                'breakeven_vs_high': breakeven_vs_high,
                                'profit_at_high': profit_at_high,
                                'profit_at_high_pct': profit_at_high_pct,
                                'spread': spread,
                                'spread_pct': spread_pct
                            })
                except Exception:
                    continue

            # No need to cancel snapshots; if you switch to snapshot=False, cancel here.

            return pd.DataFrame(rows) if rows else None
        except Exception as e:
            print(f"❌ Option pricing error: {e}")
            return None

    def get_recovery_options(self, symbol):
        print(f"\n🔍 ANALYZING {symbol} FOR RECOVERY PLAY")
        print("-" * 50)
        price, high_5d, low_5d, bars, contract = self.get_stock_data(symbol)
        if not price:
            print(f"❌ Could not get price data for {symbol}")
            return None
        print(f"📈 Current: ${price:.2f}")
        if high_5d and low_5d:
            print(f"📊 5D High: ${high_5d:.2f}, Low: ${low_5d:.2f}")

        # Daily ATR filters
        if not bars:
            print("❌ No daily bars for ATR")
            return None
        atr = self._wilder_atr(bars, period=14)
        ok_daily, daily_reason, atr_pct = self.passes_daily_atr_filters(atr, price)
        print(f"📐 Daily ATR check: {daily_reason}")
        if not ok_daily:
            print("❌ Fails daily ATR filters")
            return None

        # Intraday ATR gate
        ok_intraday, intraday_msg, iatr, iatr_pct = self.passes_intraday_atr_gate(contract, price)
        print(f"⚡ {intraday_msg}")
        if not ok_intraday:
            print("❌ Fails intraday ATR gate")
            return None

        # Pullback/Recovery structure
        pullback_ok, reason = self.is_pullback_recovery_candidate(price, high_5d, low_5d)
        print(f"📋 Structure: {reason}")
        if not pullback_ok:
            print("❌ Not a recovery candidate")
            return None
        print("✅ Structure good; proceeding to options")

        # Options selection
        chains = self.ib.reqSecDefOptParams(symbol, '', 'STK', contract.conId)
        if not chains:
            print(f"❌ No option chains for {symbol}")
            return None
        # Pick the "richest" chain (most strikes)
        chain = max(chains, key=lambda c: len(c.strikes) if c.strikes else 0)

        exp = self.find_target_expiration(chain.expirations)
        if not exp:
            print("❌ No 1-2 week expirations")
            return None
        print(f"📅 Target expiration: {exp}")

        strikes = self.get_nearby_strikes(chain.strikes, price)
        if not strikes:
            print("❌ No suitable strikes")
            return None
        print(f"🎯 Target strikes: {strikes}")

        df = self.get_option_prices(symbol, exp, strikes, price, high_5d, low_5d)
        if df is not None and not df.empty:
            df['atr'] = atr
            df['atr_pct'] = atr_pct
            df['iatr'] = iatr
            df['iatr_pct'] = iatr_pct

            # QUALITY FILTER (uses configurable params; now includes OI)
            df = df[
                (df['profit_at_high_pct'] > 0) &                 # must profit at 5D high
                (df['spread_pct'] <= self.max_spread_pct) &      # keep spreads tight
                (df['volume'] >= self.min_volume) &              # minimum liquidity
                (df['open_interest'] >= self.min_open_interest)  # NEW: avoid dead contracts
            ]

            if df.empty:
                print(f"ℹ️ All candidates filtered out (profit>0, spread<={self.max_spread_pct:.0f}%, "
                      f"vol>={self.min_volume}, OI>={self.min_open_interest}).")
                return None
        return df

    def show_recovery_results(self, df, symbol):
        if df is None or df.empty:
            return
        print(f"\n💎 RECOVERY OPTIONS FOR {symbol}  (Focus: $0.05-$0.50 premium)")
        print("=" * 80)
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

        # Safer BE% calc (avoid inf/NaN issues)
        be_move = (df['breakeven'] / df['current_price'] - 1) * 100
        be_move = be_move.replace([pd.NA, pd.NaT], 0).fillna(0)
        be_move = be_move.replace([np.inf, -np.inf], 0)

        df_sorted = df.assign(
            breakeven_move_needed_pct=be_move
        ).sort_values(
            ['breakeven_move_needed_pct', 'breakeven_vs_high', 'spread_pct', 'profit_at_high_pct', 'volume'],
            ascending=[True, True, True, False, False]
        )

        print("\n🚀 BEST CHEAP RECOVERY CALL OPTIONS:")
        print("           (Focus: $0.05 - $0.50 premium)")
        print("Strike | Price | Volume | OI | Breakeven | BE Move% | Profit@High | Spread%")
        print("-" * 90)
        for _, r in df_sorted.head(5).iterrows():
            print(f"${r['strike']:5.1f} | ${r['mid_price']:4.2f} | {r['volume']:6.0f} | {int(r.get('open_interest', 0)):4d} | "
                  f"${r['breakeven']:6.2f} | {r['breakeven_move_needed_pct']:7.2f}% | "
                  f"{r['profit_at_high_pct']:7.1f}% | {r['spread_pct']:5.1f}%")

        best = df_sorted.iloc[0]
        print("\n💡 BEST OPPORTUNITY:")
        print(f"   {symbol} ${best['strike']:.1f}C @ ${best['mid_price']:.2f} exp {best['expiration']}")
        print(f"   If recovers to ${hi:.2f}: {best['profit_at_high_pct']:.1f}%")
        print(f"   Breakeven ${best['breakeven']:.2f} ({((best['breakeven']/cur-1)*100):+.1f}%) | "
              f"Vol {best['volume']:.0f} | OI {int(best.get('open_interest', 0))}")

    def scan_watchlist_for_recovery(self, symbols):
        print("\n🎯 SCANNING FOR PULLBACK RECOVERY OPPORTUNITIES")
        print("=" * 70)

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
        print("📉 Pullback 3-15% | 📈 Recovery ≥ 1% | 💰 $0.05-$0.50 | 🎯 ±3 strikes | ⏰ 1-2 weeks")
        print("=" * 70)

        found = {}
        for symbol in symbols:
            try:
                df = self.get_recovery_options(symbol)
                if df is not None and not df.empty:
                    found[symbol] = df
                    self.show_recovery_results(df, symbol)
                    ts = datetime.now().strftime('%Y%m%d_%H%M')
                    fn = f"recovery_cheap_{symbol}_{ts}.csv"  # renamed to avoid collisions
                    df.to_csv(fn, index=False)
                    print(f"💾 Saved: {fn}")
                time.sleep(1)
            except Exception as e:
                print(f"❌ {symbol} error: {e}")
                continue

        if found:
            print("\n🏆 RECOVERY SUMMARY")
            print("=" * 50)
            for sym, df in found.items():
                be_move = (df['breakeven'] / df['current_price'] - 1) * 100
                be_move = be_move.replace([pd.NA, pd.NaT], 0).fillna(0)
                be_move = be_move.replace([np.inf, -np.inf], 0)

                best = df.assign(
                    breakeven_move_needed_pct=be_move
                ).sort_values(
                    ['breakeven_move_needed_pct', 'breakeven_vs_high', 'spread_pct', 'profit_at_high_pct', 'volume'],
                    ascending=[True, True, True, False, False]
                ).iloc[0]
                print(f"{sym}: ${best['strike']:.1f}C @ ${best['mid_price']:.2f} exp {best['expiration']} "
                      f"({best['profit_at_high_pct']:.1f}% potential) | "
                      f"BE Move {best['breakeven_move_needed_pct']:.2f}% | "
                      f"Spread {best['spread_pct']:.1f}% | Vol {best['volume']:.0f} | "
                      f"OI {int(best.get('open_interest', 0))}")
        else:
            print("\n❌ No recovery candidates found.")
        return found

    def disconnect(self):
        self.ib.disconnect()
        print("\n👋 Disconnected from TWS")


def main():
    print_banner()
    scanner = None
    try:
        # Bump intraday_min_atr_pct to 1.0 on choppy low-vol days
        scanner = PullbackRecoveryScanner(
            port=7496, client_id=5,
            min_atr_pct=2.0,
            min_abs_atr=None,
            low_price_threshold=10.0,
            min_abs_atr_low_price=0.25,
            use_intraday_atr=True,
            intraday_bar='30 mins',
            intraday_period=20,
            intraday_min_atr_pct=0.8,   # ← set to 1.0 on choppy days
            min_volume=100,
            max_spread_pct=12.0,
            min_open_interest=50,       # NEW: pass OI filter
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
        results = scanner.scan_watchlist_for_recovery(watchlist)
        print("\n🎉 SCAN COMPLETE!")
        print(f"Found recovery opportunities in {len(results)} symbols")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        if scanner:
            scanner.disconnect()

if __name__ == "__main__":
    main()
