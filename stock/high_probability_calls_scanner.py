import ib_insync as ib
from datetime import datetime
import pandas as pd
import time
from math import erf, sqrt, log, exp
from collections import deque
import requests

try:
    from config import SLACK_WEBHOOK_URL
except ImportError:
    print("⚠️ Warning: config.py not found. Slack notifications disabled.")
    SLACK_WEBHOOK_URL = None

def send_to_slack(scanner_name, found_dict, filename=None):
    """Send scanner results to Slack"""
    if not SLACK_WEBHOOK_URL:
        return

    webhook_url = SLACK_WEBHOOK_URL

    if not found_dict:
        # No results found
        message = {
            "text": f"🎯 {scanner_name}",
            "attachments": [{
                "color": "warning",
                "text": "No high probability opportunities found in current market conditions",
                "footer": datetime.now().strftime('%Y-%m-%d %H:%M ET')
            }]
        }
    else:
        # Format ALL opportunities with expanded details
        summary_lines = []
        for symbol, df in list(found_dict.items())[:20]:  # Limit to 20 for Slack readability
            best = df.iloc[0]
            prob = best.get('prob_itm', 0) * 100
            exp_date = best['expiration']
            # Format expiration date if it's in YYYYMMDD format
            if len(str(exp_date)) == 8:
                exp_date = f"{str(exp_date)[4:6]}/{str(exp_date)[6:]}"  # MM/DD format
            
            summary_lines.append(
                f"• {symbol} ${best['strike']:.0f}C @ ${best['mid_price']:.2f} | "
                f"Exp: {exp_date} | {prob:.0f}% ITM | "
                f"BE: ${best['breakeven']:.2f} ({best['breakeven_move_needed_pct']:.1f}% move) | "
                f"Score: {best['score']:.2f}"
            )
        
        # Create the message with all results
        results_text = "\n".join(summary_lines)
        
        # If there are more than 20, add a note
        if len(found_dict) > 20:
            results_text += f"\n\n... and {len(found_dict) - 20} more in the CSV file"
        
        message = {
            "text": f"🎯 {scanner_name} - Found {len(found_dict)} high probability plays",
            "attachments": [{
                "color": "good",
                "text": results_text,
                "footer": f"File: {filename}" if filename else datetime.now().strftime('%Y-%m-%d %H:%M ET')
            }]
        }

    try:
        response = requests.post(webhook_url, json=message)
        if response.status_code == 200:
            print("📨 Results sent to Slack")
        else:
            print(f"⚠️ Slack notification failed: {response.status_code}")
    except Exception as e:
        print(f"⚠️ Could not send to Slack: {e}")

class PullbackRecoveryScannerV2:
    """
    Variant of the original scanner that:
      • Keeps the same price/ATR/pullback-recovery gates
      • Drops the 5-50¢ option price band entirely
      • Scores and returns the *highest-probability* call contracts instead
        of only cheap lottos

    Probability proxy: uses |delta| as a quick estimator for P(ITM at expiry).
    We also calculate a simple z-score probability using IV if model greeks are
    available. Then we score by a blend of probability, liquidity and spread.
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
        risk_free_rate=0.045,  # Added: current risk-free rate (~4.5% for US Treasury)
        # Rate limiting parameters
        respect_rate_limits=True,
        hist_requests_per_10min=60,
        delay_between_symbols=2.0,  # seconds between each symbol
        delay_after_hist_batch=10.0,  # seconds to wait after every N historical requests
        hist_batch_size=20,  # number of hist requests before pausing
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
        
        # Risk-free rate for Black-Scholes
        self.risk_free_rate = float(risk_free_rate)
        
        # Rate limiting
        self.respect_rate_limits = respect_rate_limits
        self.hist_requests_per_10min = hist_requests_per_10min
        self.delay_between_symbols = delay_between_symbols
        self.delay_after_hist_batch = delay_after_hist_batch
        self.hist_batch_size = hist_batch_size
        
        # Track historical data requests for rate limiting
        self.hist_request_times = deque(maxlen=hist_requests_per_10min)
        self.hist_request_count = 0

        self.connect()

    def connect(self):
        print("🔌 Connecting to TWS...")
        self.ib.connect(self.host, self.port, clientId=self.client_id)
        print("✅ Connected to TWS")

    def _check_hist_rate_limit(self):
        """Check if we need to pause for rate limiting"""
        if not self.respect_rate_limits:
            return
        
        # Check if we've made too many requests in a batch
        if self.hist_request_count > 0 and self.hist_request_count % self.hist_batch_size == 0:
            print(f"⏸️  Rate limit pause: {self.delay_after_hist_batch:.1f}s after {self.hist_request_count} historical requests")
            time.sleep(self.delay_after_hist_batch)
        
        # Check 10-minute rolling window
        now = time.time()
        # Remove requests older than 10 minutes
        while self.hist_request_times and (now - self.hist_request_times[0]) > 600:
            self.hist_request_times.popleft()
        
        # If we're at the limit, wait until the oldest request expires
        if len(self.hist_request_times) >= self.hist_requests_per_10min - 1:
            wait_time = 600 - (now - self.hist_request_times[0]) + 1
            if wait_time > 0:
                print(f"⏸️  Rate limit reached: waiting {wait_time:.1f}s")
                time.sleep(wait_time)

    # ---------- Data helpers ----------
    def _fetch_daily_bars(self, contract, days='60 D'):
        self._check_hist_rate_limit()
        bars = self.ib.reqHistoricalData(
            contract, endDateTime='', durationStr=days,
            barSizeSetting='1 day', whatToShow='TRADES', useRTH=True
        )
        self.hist_request_times.append(time.time())
        self.hist_request_count += 1
        return bars

    def _fetch_intraday_bars(self, contract, duration='2 D', bar='30 mins'):
        self._check_hist_rate_limit()
        bars = self.ib.reqHistoricalData(
            contract, endDateTime='', durationStr=duration,
            barSizeSetting=bar, whatToShow='TRADES', useRTH=True
        )
        self.hist_request_times.append(time.time())
        self.hist_request_count += 1
        return bars

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

            # live price
            t = self.ib.reqMktData(contract, '', False, False)
            self.ib.sleep(2)
            price = t.marketPrice() or t.last
            self.ib.cancelMktData(contract)
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
            if len(intrabars) < self.intraday_period + 1:
                return True, "Not enough intraday bars; skipping gate", None, None
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
        """Cumulative distribution function for standard normal distribution"""
        return 0.5 * (1.0 + erf(x / sqrt(2.0)))

    def _prob_itm_from_iv(self, S, K, T_years, iv, r=None):
        """
        CORRECTED: Calculate probability of call being ITM at expiry using Black-Scholes.
        
        For a call option:
        - P(ITM) = P(S_T > K) = N(d2)
        
        Where:
        - d1 = [ln(S/K) + (r + σ²/2)T] / (σ√T)
        - d2 = d1 - σ√T
        - N() is the cumulative normal distribution
        
        Parameters:
        - S: Current stock price
        - K: Strike price
        - T_years: Time to expiration in years
        - iv: Implied volatility (annualized)
        - r: Risk-free rate (annualized)
        """
        try:
            # Validation
            if not all([S, K, T_years, iv]) or S <= 0 or K <= 0 or T_years <= 0 or iv <= 0:
                return None
            
            # Use instance risk-free rate if not provided
            if r is None:
                r = self.risk_free_rate
            
            # Calculate d1 and d2 using proper Black-Scholes formula
            d1 = (log(S / K) + (r + 0.5 * iv ** 2) * T_years) / (iv * sqrt(T_years))
            d2 = d1 - iv * sqrt(T_years)
            
            # For call options: P(ITM) = N(d2)
            prob_itm = self._norm_cdf(d2)
            
            return prob_itm
            
        except Exception as e:
            print(f"Probability calculation error: {e}")
            return None

    def _prob_itm_simplified(self, S, K, T_years, iv):
        """
        Alternative simplified calculation assuming risk-free rate ≈ 0.
        This is reasonable for short-term options when rates are low.
        """
        try:
            if not all([S, K, T_years, iv]) or S <= 0 or K <= 0 or T_years <= 0 or iv <= 0:
                return None
            
            # Simplified d2 with r = 0
            d2 = (log(S / K) - 0.5 * iv ** 2 * T_years) / (iv * sqrt(T_years))
            
            # For call options: P(ITM) = N(d2)
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
                oi = getattr(t, 'optOpenInterest', None) or 0  # will often be 0 intraday; keep soft
                mid = (bid + ask) / 2 if bid > 0 and ask > 0 else (last or 0)
                if mid <= 0:
                    continue

                spread = (ask - bid) if (bid > 0 and ask > 0) else None
                spread_pct = ((spread / mid) * 100.0) if (spread is not None and mid > 0) else 100.0

                mg = t.modelGreeks
                delta = abs(mg.delta) if (mg and mg.delta is not None) else None
                iv = mg.impliedVol if (mg and mg.impliedVol and mg.impliedVol > 0) else None

                # time to expiry
                dtexp = datetime.strptime(c.lastTradeDateOrContractMonth, '%Y%m%d')
                T_years = max((dtexp - datetime.now()).days, 0) / 365.0

                # CORRECTED probability calculations
                # Use IV-based calculation if available, otherwise use delta as proxy
                prob_iv = self._prob_itm_from_iv(price, c.strike, T_years, iv) if iv else None
                prob_delta = delta if delta is not None else None
                
                # Prefer IV-based probability if available, otherwise use delta
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
                    'prob_itm_iv': prob_iv,  # Store IV-based prob separately for debugging
                    'prob_itm_delta': prob_delta,  # Store delta proxy separately
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

        # Cancel market data
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

        # Liquidity score: combine volume and (if present) open interest
        vol_norm = (df['volume'] / (df['volume'].max() if df['volume'].max() > 0 else 1)).clip(0, 1)
        oi_norm = (df.get('open_interest', pd.Series(0)) / (df.get('open_interest', pd.Series(0)).max() if df.get('open_interest', pd.Series(0)).max() > 0 else 1)).clip(0, 1)
        liquidity = 0.7 * vol_norm + 0.3 * oi_norm

        # Probability term: normalize prob_itm in [0,1]
        prob_raw = df['prob_itm'].fillna(0).clip(0, 1)

        # Spread penalty: convert to [0,1] with 0% spread = 1, >= max_spread_pct = 0
        spread_penalty = (1.0 - (df['spread_pct'] / self.max_spread_pct)).clip(0, 1)

        # Bonus for preferred delta range (roughly 0.30-0.60): bell around midpoint
        mid = (self.prefer_delta_min + self.prefer_delta_max) / 2.0
        width = (self.prefer_delta_max - self.prefer_delta_min) / 2.0 or 0.15
        delta_pref = df['delta'].fillna(0).apply(lambda d: max(0.0, 1.0 - abs((d - mid) / (width))))

        # Compose score
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
        chain = chains[0]
        exp = self._target_expiration(chain.expirations)
        if not exp:
            print("❌ No target expirations in desired window")
            return None
        print(f"📅 Target expiration: {exp}")

        df = self.get_option_candidates(symbol, price, high_5d, low_5d, chain, exp)
        if df is None or df.empty:
            print("❌ No option candidates fetched")
            return None

        # Quality filters (liquidity + spreads); no price band
        df = df[(df['volume'] >= self.min_volume) & (df['spread_pct'] <= self.max_spread_pct)]

        if df.empty:
            print("ℹ️ All candidates filtered out by liquidity/spread.")
            return None

        df['atr'] = atr
        df['atr_pct'] = atr_pct
        df['iatr'] = iatr
        df['iatr_pct'] = iatr_pct

        df = self._score_contracts(df)
        if df is None or df.empty:
            print("❌ Scoring failed or empty")
            return None

        # Rank: highest score, then lowest breakeven move% and spread
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
            prob_display = r['prob_itm'] if pd.notna(r['prob_itm']) else 0
            print(
                f"${r['strike']:6.2f} | ${r['mid_price']:5.2f} | {int(r['volume']):5d} | {int(r['open_interest']):5d} | "
                f"{(r['delta'] if pd.notna(r['delta']) else 0):.2f} | {(r['iv'] if pd.notna(r['iv']) else 0):.2f} | "
                f"{prob_display:.2f} | ${r['breakeven']:7.2f} | "
                f"{r['breakeven_move_needed_pct']:7.2f}% | {r['profit_at_high_pct']:8.1f}% | {r['spread_pct']:6.1f}% | {r['score']:5.3f}"
            )

        best = df.iloc[0]
        print("\n💡 BEST OPPORTUNITY:")
        print(f"   {symbol} ${best['strike']:.2f}C @ ${best['mid_price']:.2f} exp {best['expiration']}")
        prob_display = best['prob_itm'] if pd.notna(best['prob_itm']) else 0
        print(f"   Prob(ITM): {prob_display:.2f} | Δ {best['delta']:.2f} | IV {(best['iv'] if pd.notna(best['iv']) else 0):.2f}")
        print(f"   BE ${best['breakeven']:.2f} ({best['breakeven_move_needed_pct']:.2f}%) | Spread {best['spread_pct']:.1f}% | Vol {int(best['volume'])} | OI {int(best['open_interest'])}")
        
        # Debug info for probability calculation
        if pd.notna(best.get('prob_itm_iv')) and pd.notna(best.get('prob_itm_delta')):
            print(f"   [Debug] P(ITM) from IV: {best['prob_itm_iv']:.3f}, from Delta: {best['prob_itm_delta']:.3f}")

    def scan_watchlist(self, symbols):
        print("\n🎯 HIGH PROBABILITY CALLS SCANNER")
        print("=" * 80)
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
        print(f"💰 Risk-free rate: {self.risk_free_rate:.2%}")
        print("=" * 80)

        found = {}
        all_candidates = []  # Store all candidates for consolidated CSV
        
        for i, symbol in enumerate(symbols, 1):
            try:
                print(f"\n[{i}/{len(symbols)}]", end=" ")  # Progress indicator
                df = self.get_high_probability_calls(symbol)
                if df is not None and not df.empty:
                    found[symbol] = df
                    self.show_results(df, symbol)
                    
                    # Keep only the BEST option per symbol if it meets quality thresholds
                    best = df.iloc[0]
                    if (best['score'] > 0.4 and 
                        best['prob_itm'] > 0.35 and 
                        best['breakeven_move_needed_pct'] < 10):
                        all_candidates.append(df.head(1))
                        print(f"✅ {symbol} added to consolidated watchlist")
                    else:
                        print(f"⚠️ {symbol} best option doesn't meet quality thresholds")
                
                # Rate limiting between symbols
                if self.respect_rate_limits and i < len(symbols):
                    time.sleep(self.delay_between_symbols)
                    
            except Exception as e:
                print(f"❌ {symbol} error: {e}")
                continue

        # Create consolidated CSV with all results
        if all_candidates:
            consolidated_df = pd.concat(all_candidates, ignore_index=True)
            
            # Sort by score, then by breakeven move needed
            consolidated_df = consolidated_df.sort_values(
                ['score', 'breakeven_move_needed_pct', 'spread_pct'], 
                ascending=[False, True, True]
            )
            
            # Format expiration dates to be human-readable
            def format_expiration(exp_str):
                # Convert from '20250905' to '2025-09-05'
                try:
                    return f"{exp_str[:4]}-{exp_str[4:6]}-{exp_str[6:]}"
                except:
                    return exp_str
            
            # Simplified output format
            output_df = pd.DataFrame({
                'Symbol': consolidated_df['symbol'],
                'Strike': consolidated_df['strike'],
                'Exp': consolidated_df['expiration'].apply(format_expiration),
                'Price': consolidated_df['mid_price'].round(2),
                'Prob%': (consolidated_df['prob_itm'] * 100).round(0),
                'BE': consolidated_df['breakeven'].round(2),
                'Move%': consolidated_df['breakeven_move_needed_pct'].round(1),
                'Spread%': consolidated_df['spread_pct'].round(1),
                'Vol': consolidated_df['volume'].astype(int),
                'Stock': consolidated_df['current_price'].round(2),
            })
            
            # Save consolidated results with header
            timestamp = datetime.now()
            filename = f"high_probability_calls_{timestamp.strftime('%Y%m%d_%H%M')}.csv"
            
            # Write with header information
            with open(filename, 'w') as f:
                # Write header info
                f.write("# HIGH PROBABILITY CALLS SCANNER\n")
                f.write(f"# Scan Date: {timestamp.strftime('%Y-%m-%d')}\n")
                f.write(f"# Scan Time: {timestamp.strftime('%H:%M:%S')}\n")
                f.write("#\n")
                f.write("# Column Definitions:\n")
                f.write("#   Symbol: Stock ticker\n")
                f.write("#   Strike: Option strike price\n")
                f.write("#   Exp: Expiration date\n")
                f.write("#   Price: Option price per contract\n")
                f.write("#   Prob%: Probability of profit at expiration\n")
                f.write("#   BE: Breakeven price\n")
                f.write("#   Move%: Required move to breakeven\n")
                f.write("#   Spread%: Bid-ask spread percentage\n")
                f.write("#   Vol: Option volume today\n")
                f.write("#   Stock: Current stock price\n")
                f.write("#\n")
                
                # Write the data
                output_df.to_csv(f, index=False)
            
            print(f"\n💾 CONSOLIDATED RESULTS SAVED: {filename}")
            print(f"   Total opportunities found: {len(output_df)}")
            print(f"   From {len(found)} symbols")
            print(f"   Scan time: {timestamp.strftime('%Y-%m-%d %H:%M:%S')}")

            # Send to Slack if webhook is configured
            send_to_slack("High Probability Calls Scanner", found, filename)

        if found:
            print("\n🏆 SUMMARY (Top Pick per Symbol)")
            print("=" * 60)
            for sym, df in found.items():
                best = df.iloc[0]
                prob_display = best['prob_itm'] if pd.notna(best['prob_itm']) else 0
                print(f"{sym}: ${best['strike']:.2f}C @ ${best['mid_price']:.2f} exp {best['expiration']} | "
                      f"Prob {prob_display:.2f} | "
                      f"BE Move {best['breakeven_move_needed_pct']:.2f}% | Spread {best['spread_pct']:.1f}% | Vol {int(best['volume'])}")
        else:
            print("\n❌ No candidates found.")
            send_to_slack("High Probability Calls Scanner", {})
        return found

    def disconnect(self):
        self.ib.disconnect()
        print("\n👋 Disconnected from TWS")


def main():
    scanner = None
    try:
        scanner = PullbackRecoveryScannerV2(
            port=7496, 
            client_id=45,
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
            risk_free_rate=0.045,  # Current US Treasury rate ~4.5%
            # Rate limiting settings
            respect_rate_limits=True,
            delay_between_symbols=1.0,  # 1 seconds between each symbol
            delay_after_hist_batch=5.0,  # 5 second pause after 30 requests
            hist_batch_size=30,  # pause after every 30 historical requests
        )

        # Load watchlist from file
        try:
            with open('watchlist.txt', 'r') as f:
                # Read symbols, strip whitespace, ignore empty lines and comments
                watchlist = [
                    line.strip().upper() 
                    for line in f 
                    if line.strip() and not line.strip().startswith('#')
                ]
            print(f"📋 Loaded {len(watchlist)} symbols from watchlist.txt")
        except FileNotFoundError:
            print("⚠️ watchlist.txt not found, using default symbols")
            # Fallback to default watchlist if file doesn't exist
            watchlist = [
                'SPY', 'QQQ', 'TQQQ',
                'AAPL', 'GOOGL', 'AMZN', 'NVDA', 'TSLA', 'AMD', 'PLTR', 'AVGO',
                'META', 'MSFT', 'CRM', 'ORCL', 'CRWV', 'RDDT', 'SMCI', 'MU', 'NBIS', 
            ]
        except Exception as e:
            print(f"❌ Error loading watchlist: {e}")
            print("Using default symbols instead")
            watchlist = ['SPY', 'QQQ', 'AAPL', 'NVDA', 'TSLA']

        print(f"🔍 Scanning {len(watchlist)} symbols...")
        print(f"⚡ Rate limiting: {'ENABLED' if scanner.respect_rate_limits else 'DISABLED'}")
        if scanner.respect_rate_limits:
            est_time = len(watchlist) * (scanner.delay_between_symbols + 5)  # rough estimate
            print(f"⏱️  Estimated scan time: {est_time/60:.1f} minutes")
        
        results = scanner.scan_watchlist(watchlist)
        print("\n🎉 SCAN COMPLETE!")
        print(f"Found candidates in {len(results)} symbols")
        print(f"Total historical requests made: {scanner.hist_request_count}")
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        if scanner:
            scanner.disconnect()


if __name__ == "__main__":
    main()