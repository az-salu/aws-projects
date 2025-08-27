import ib_insync as ib
from datetime import datetime
import pandas as pd
import time
from math import erf, sqrt, log
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
        return  # Skip if no webhook configured
    
    webhook_url = SLACK_WEBHOOK_URL
    
    if not found_dict:
        # No results found
        message = {
            "text": f"🎲 {scanner_name}",
            "attachments": [{
                "color": "warning",
                "text": "No opportunities found in current market conditions",
                "footer": datetime.now().strftime('%Y-%m-%d %H:%M ET')
            }]
        }
    else:
        # Format top opportunities
        summary_lines = []
        for symbol, df in list(found_dict.items())[:5]:  # Top 5 symbols
            best = df.iloc[0]
            prob = best.get('prob_itm', 0) * 100
            
            summary_lines.append(
                f"• {symbol} ${best['strike']:.0f}C @ ${best['mid_price']:.2f} "
                f"({prob:.0f}% prob, {best['risk_reward']:.1f}x R/R, {best['tier']})"
            )
        
        message = {
            "text": f"🎲 {scanner_name} - Found {len(found_dict)} opportunities",
            "attachments": [{
                "color": "good",
                "text": "\n".join(summary_lines),
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

class CheapOptionsScanner:
    """
    Enhanced scanner for finding cheap call options with high reward potential.
    Combines pullback-recovery patterns with probability calculations and risk/reward analysis.
    """
    
    def __init__(
        self,
        host='127.0.0.1',
        port=7496,
        client_id=4,
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
        # Option price constraints - EXPANDED RANGE
        min_option_price=0.05,
        max_option_price=1.00,  # Expanded from 0.50 to 1.00
        # Quality filters for cheap options - DYNAMIC
        min_volume_base=25,     # Will be adjusted based on option price
        min_dollar_volume=2500,  # Minimum dollar volume traded
        min_open_interest=25,    
        max_spread_pct=25.0,     
        # Probability and scoring - ADJUSTED
        min_probability=0.10,    # Lowered to 10% for true lottery tickets
        min_risk_reward=5.0,     # At least 5:1 payoff
        risk_free_rate=0.045,    # For Black-Scholes
        # Scoring weights for cheap options
        weight_risk_reward=0.30,  # Emphasize asymmetric payoffs
        weight_liquidity=0.25,
        weight_spread=0.20,
        weight_probability=0.15,  # Lower weight for cheap options
        weight_breakeven=0.10,
        # Rate limiting
        respect_rate_limits=True,
        hist_requests_per_10min=60,
        delay_between_symbols=1.0, # 1 seconds between each symbol
        delay_after_hist_batch=5.0, # 5 second pause after 30 requests
        hist_batch_size=30, # pause after every 30 historical requests
    ):
        self.ib = ib.IB()
        self.host = host
        self.port = port
        self.client_id = client_id

        # ATR filters
        self.min_atr_pct = float(min_atr_pct) if min_atr_pct is not None else None
        self.min_abs_atr = float(min_abs_atr) if min_abs_atr is not None else None
        self.low_price_threshold = float(low_price_threshold)
        self.min_abs_atr_low_price = float(min_abs_atr_low_price)

        self.use_intraday_atr = use_intraday_atr
        self.intraday_bar = intraday_bar
        self.intraday_period = int(intraday_period)
        self.intraday_min_atr_pct = float(intraday_min_atr_pct)

        # Option constraints
        self.min_option_price = float(min_option_price)
        self.max_option_price = float(max_option_price)
        
        # Quality filters
        self.min_volume_base = int(min_volume_base)
        self.min_dollar_volume = float(min_dollar_volume)
        self.min_open_interest = int(min_open_interest)
        self.max_spread_pct = float(max_spread_pct)
        self.min_probability = float(min_probability)
        self.min_risk_reward = float(min_risk_reward)
        self.risk_free_rate = float(risk_free_rate)
        
        # Scoring weights
        self.weight_risk_reward = float(weight_risk_reward)
        self.weight_liquidity = float(weight_liquidity)
        self.weight_spread = float(weight_spread)
        self.weight_probability = float(weight_probability)
        self.weight_breakeven = float(weight_breakeven)
        
        # Rate limiting
        self.respect_rate_limits = respect_rate_limits
        self.hist_requests_per_10min = hist_requests_per_10min
        self.delay_between_symbols = delay_between_symbols
        self.delay_after_hist_batch = delay_after_hist_batch
        self.hist_batch_size = hist_batch_size
        
        # Track historical data requests
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
        
        # Check batch limit
        if self.hist_request_count > 0 and self.hist_request_count % self.hist_batch_size == 0:
            print(f"⏸️  Rate limit pause: {self.delay_after_hist_batch:.1f}s after {self.hist_request_count} requests")
            time.sleep(self.delay_after_hist_batch)
        
        # Check 10-minute window
        now = time.time()
        while self.hist_request_times and (now - self.hist_request_times[0]) > 600:
            self.hist_request_times.popleft()
        
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

    @staticmethod
    def _norm_cdf(x):
        """Cumulative distribution function for standard normal distribution"""
        return 0.5 * (1.0 + erf(x / sqrt(2.0)))

    def _prob_itm_from_iv(self, S, K, T_years, iv, r=None):
        """
        Calculate probability of call being ITM at expiry using Black-Scholes.
        For cheap OTM options, this will typically be low (15-35%).
        """
        try:
            if not all([S, K, T_years, iv]) or S <= 0 or K <= 0 or T_years <= 0 or iv <= 0:
                return None
            
            if r is None:
                r = self.risk_free_rate
            
            # Black-Scholes d1 and d2
            d1 = (log(S / K) + (r + 0.5 * iv ** 2) * T_years) / (iv * sqrt(T_years))
            d2 = d1 - iv * sqrt(T_years)
            
            # For call options: P(ITM) = N(d2)
            return self._norm_cdf(d2)
            
        except Exception as e:
            return None

    def get_stock_data(self, symbol):
        """Current price, 5D hi/lo, daily bars (for ATR)."""
        try:
            contract = ib.Stock(symbol, 'SMART', 'USD')
            self.ib.qualifyContracts(contract)

            # Live price
            t = self.ib.reqMktData(contract, '', False, False)
            self.ib.sleep(2)
            price = t.marketPrice() or t.last
            self.ib.cancelMktData(contract)
            if not price or price <= 0:
                return None, None, None, None, None

            # Daily bars for ATR + 5D hi/lo
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

        if self.min_abs_atr is not None:
            if atr < self.min_abs_atr:
                ok = False
                reasons.append(f"ATR ${atr:.2f} < ${self.min_abs_atr:.2f}")

        if price < self.low_price_threshold:
            if atr < self.min_abs_atr_low_price:
                ok = False
                reasons.append(f"Low-price floor: ATR ${atr:.2f} < ${self.min_abs_atr_low_price:.2f}")

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
        """Get strikes around ATM for cheap options"""
        ss = sorted([s for s in strikes if s is not None])
        if not ss:
            return []
        atm = min(ss, key=lambda x: abs(x - price))
        i = ss.index(atm)
        out = []
        for off in range(-3, 4):  # ±3 strikes for cheap options
            j = i + off
            if 0 <= j < len(ss):
                out.append(ss[j])
        return out

    def get_dynamic_min_volume(self, option_price):
        """Dynamic volume threshold based on option price tier"""
        if option_price < 0.25:
            return 25  # Ultra-cheap: lower volume acceptable
        elif option_price < 0.50:
            return 50  # Cheap: moderate volume
        else:
            return 100  # Budget ($0.50-$1.00): need better liquidity
    
    def classify_option_tier(self, option_price, prob, risk_reward):
        """Classify option into tier based on characteristics"""
        if prob >= 0.25 and risk_reward >= 5:
            return "HIGH_PROB_CHEAP"  # Best of both worlds
        elif prob >= 0.15 and risk_reward >= 7:
            return "BALANCED"  # Good balance
        elif prob >= 0.10 and risk_reward >= 10:
            return "PURE_LOTTERY"  # True lottery ticket
        else:
            return "SPECULATIVE"  # High risk speculation

    def get_option_prices_with_probability(self, symbol, expiration, strikes, price, high_5d, low_5d):
        """Enhanced option pricing with probability calculations"""
        try:
            print("📊 Getting option prices and calculating probabilities...")
            contracts = [ib.Option(symbol, expiration, k, 'C', 'SMART') for k in strikes]
            qualified = self.ib.qualifyContracts(*contracts)
            
            # Request market data with greeks
            tickers = [self.ib.reqMktData(c, genericTickList='106', snapshot=False, regulatorySnapshot=False) for c in qualified]
            self.ib.sleep(3)

            rows = []
            for t in tickers:
                try:
                    c = t.contract
                    bid = t.bid if t.bid and t.bid > 0 else 0
                    ask = t.ask if t.ask and t.ask > 0 else 0
                    vol = t.volume or 0
                    oi = getattr(t, 'optOpenInterest', None) or 0
                    
                    if bid > 0 and ask > 0:
                        mid = (bid + ask) / 2
                        
                        # Check price constraints for cheap options
                        if self.min_option_price <= mid <= self.max_option_price:
                            # Get greeks for probability
                            mg = t.modelGreeks
                            delta = abs(mg.delta) if (mg and mg.delta is not None) else None
                            iv = mg.impliedVol if (mg and mg.impliedVol and mg.impliedVol > 0) else None
                            
                            # Calculate time to expiry
                            dtexp = datetime.strptime(c.lastTradeDateOrContractMonth, '%Y%m%d')
                            T_years = max((dtexp - datetime.now()).days, 0) / 365.0
                            
                            # Calculate probability
                            prob_iv = self._prob_itm_from_iv(price, c.strike, T_years, iv) if iv else None
                            prob = prob_iv if prob_iv is not None else delta
                            
                            # Calculate key metrics
                            breakeven = c.strike + mid
                            breakeven_move_pct = ((breakeven / price - 1) * 100)
                            profit_at_high = max(0, high_5d - c.strike - mid)
                            profit_at_high_pct = (profit_at_high / mid * 100) if mid > 0 else 0
                            
                            # Risk/Reward ratio
                            risk_reward = profit_at_high / mid if mid > 0 else 0
                            
                            # 10-bagger calculation
                            ten_bagger_price = c.strike + (mid * 10)
                            ten_bagger_move_pct = ((ten_bagger_price / price - 1) * 100)
                            
                            # Dollar volume for liquidity check
                            dollar_volume = vol * mid * 100  # 100 shares per contract
                            
                            # Get dynamic volume threshold
                            min_vol_for_price = self.get_dynamic_min_volume(mid)
                            
                            # Classify the option tier
                            tier = self.classify_option_tier(mid, prob, risk_reward)
                            
                            rows.append({
                                'symbol': symbol,
                                'strike': c.strike,
                                'expiration': expiration,
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
                                'breakeven_move_pct': breakeven_move_pct,
                                'profit_at_high': profit_at_high,
                                'profit_at_high_pct': profit_at_high_pct,
                                'risk_reward': risk_reward,
                                'ten_bagger_price': ten_bagger_price,
                                'ten_bagger_move_pct': ten_bagger_move_pct,
                                'dollar_volume': dollar_volume,
                                'min_vol_required': min_vol_for_price,
                                'tier': tier,
                                'spread': ask - bid,
                                'spread_pct': ((ask - bid) / mid * 100) if mid > 0 else 0
                            })
                except:
                    continue
                    
            # Cancel market data
            for t in tickers:
                try:
                    self.ib.cancelMktData(t.contract)
                except:
                    pass
                    
            return pd.DataFrame(rows) if rows else None
        except Exception as e:
            print(f"❌ Option pricing error: {e}")
            return None

    def score_cheap_options(self, df):
        """Score options based on risk/reward and lottery ticket potential"""
        if df is None or df.empty:
            return df
        
        # Normalize components for scoring
        # Risk/Reward component (higher is better)
        rr_norm = (df['risk_reward'] / df['risk_reward'].max()).clip(0, 1) if df['risk_reward'].max() > 0 else 0
        
        # Liquidity component (volume + OI)
        vol_norm = (df['volume'] / df['volume'].max()).clip(0, 1) if df['volume'].max() > 0 else 0
        oi_norm = (df['open_interest'] / df['open_interest'].max()).clip(0, 1) if df['open_interest'].max() > 0 else 0
        liquidity = 0.7 * vol_norm + 0.3 * oi_norm
        
        # Spread quality (tighter is better)
        spread_score = (1.0 - (df['spread_pct'] / self.max_spread_pct)).clip(0, 1)
        
        # Probability component (even low prob has some value)
        prob_score = df['prob_itm'].fillna(0).clip(0, 1)
        
        # Breakeven proximity (closer is better)
        be_score = (1.0 - (df['breakeven_move_pct'] / 20)).clip(0, 1)  # Normalize to 20% max move
        
        # Composite score for cheap options
        df['score'] = (
            self.weight_risk_reward * rr_norm +
            self.weight_liquidity * liquidity +
            self.weight_spread * spread_score +
            self.weight_probability * prob_score +
            self.weight_breakeven * be_score
        )
        
        return df

    def get_cheap_recovery_options(self, symbol):
        print(f"\n🎲 ANALYZING {symbol} FOR CHEAP OPTIONS")
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
        chain = chains[0]
        exp = self.find_target_expiration(chain.expirations)
        if not exp:
            print("❌ No 7-14 day expirations")
            return None
        print(f"📅 Target expiration: {exp}")

        strikes = self.get_nearby_strikes(chain.strikes, price)
        if not strikes:
            print("❌ No suitable strikes")
            return None

        # Get options with probability calculations
        df = self.get_option_prices_with_probability(symbol, exp, strikes, price, high_5d, low_5d)
        
        if df is not None and not df.empty:
            df['atr'] = atr
            df['atr_pct'] = atr_pct
            df['iatr'] = iatr
            df['iatr_pct'] = iatr_pct

            # Apply quality filters with dynamic volume thresholds
            df = df[
                (df['volume'] >= df['min_vol_required']) &  # Dynamic volume threshold
                (df['dollar_volume'] >= self.min_dollar_volume) &  # Dollar volume check
                (df['spread_pct'] <= self.max_spread_pct) &
                (df['risk_reward'] >= self.min_risk_reward)
            ]

            if not df.empty:
                # Score the options
                df = self.score_cheap_options(df)
                # Sort by score
                df = df.sort_values(['score', 'risk_reward', 'breakeven_move_pct'], 
                                  ascending=[False, False, True])

        return df

    def show_cheap_options_results(self, df, symbol):
        if df is None or df.empty:
            return
        print(f"\n💎 CHEAP OPTIONS FOR {symbol}")
        print("=" * 95)
        
        cur = df['current_price'].iloc[0]
        hi = df['high_5d'].iloc[0]
        lo = df['low_5d'].iloc[0]
        
        print(f"📈 Current: ${cur:.2f} | 5D High: ${hi:.2f} | 5D Low: ${lo:.2f}")
        print(f"💰 Price Range: ${self.min_option_price:.2f}-${self.max_option_price:.2f}")
        
        print("\n🎯 TOP LOTTERY TICKETS:")
        print("Strike | Price | Prob% | R/R | BE Move% | MaxGain% | Vol | $Vol | Tier | Score")
        print("-" * 95)
        
        for _, r in df.head(5).iterrows():
            prob_display = (r['prob_itm'] * 100) if pd.notna(r['prob_itm']) else 0
            dollar_vol_k = r['dollar_volume'] / 1000  # Show in thousands
            print(f"${r['strike']:5.1f} | ${r['mid_price']:4.2f} | {prob_display:4.0f}% | "
                  f"{r['risk_reward']:4.1f}x | {r['breakeven_move_pct']:6.1f}% | "
                  f"{r['profit_at_high_pct']:7.0f}% | {r['volume']:4.0f} | "
                  f"${dollar_vol_k:5.1f}k | {r['tier'][:4]} | {r['score']:.3f}")
        
        best = df.iloc[0]
        print("\n🎲 BEST CHEAP OPTION:")
        print(f"   {symbol} ${best['strike']:.1f}C @ ${best['mid_price']:.2f} ({best['tier']})")
        prob_display = (best['prob_itm'] * 100) if pd.notna(best['prob_itm']) else 0
        print(f"   Probability: {prob_display:.0f}% | Risk/Reward: {best['risk_reward']:.1f}x")
        print(f"   If hits 5D high (${hi:.2f}): {best['profit_at_high_pct']:.0f}% gain")
        print(f"   10-bagger at ${best['ten_bagger_price']:.2f} ({best['ten_bagger_move_pct']:.1f}% move)")

    def scan_watchlist(self, symbols):
        print("\n🎲 CHEAP CALLS SCANNER")
        print("=" * 70)
        print(f"🔊 Volatility: ATR ≥ {self.min_atr_pct}% | Intraday ≥ {self.intraday_min_atr_pct}%")
        print(f"📉 Setup: Pullback 3-15% | Recovery ≥ 1%")
        print(f"💰 Price: ${self.min_option_price:.2f}-${self.max_option_price:.2f} (expanded range)")
        print(f"🎯 Filters: R/R ≥ {self.min_risk_reward}x | Dynamic volume | $Vol ≥ ${self.min_dollar_volume}")
        print(f"📊 Tiers: HIGH_PROB (25%+), BALANCED (15%+), LOTTERY (10%+)")
        print(f"⚡ Rate limiting: {'ENABLED' if self.respect_rate_limits else 'DISABLED'}")
        
        if self.respect_rate_limits:
            est_time = len(symbols) * (self.delay_between_symbols + 5)
            print(f"⏱️  Estimated time: {est_time/60:.1f} minutes")
        print("=" * 70)

        found = {}
        all_candidates = []
        
        for i, symbol in enumerate(symbols, 1):
            try:
                print(f"\n[{i}/{len(symbols)}]", end=" ")
                df = self.get_cheap_recovery_options(symbol)
                if df is not None and not df.empty:
                    found[symbol] = df
                    self.show_cheap_options_results(df, symbol)
                    
                    # Keep best option for consolidated output
                    best = df.iloc[0]
                    if best['score'] > 0.3:  # Minimum score threshold
                        all_candidates.append(df.head(1))
                        print(f"✅ {symbol} added to watchlist")
                
                # Rate limiting
                if self.respect_rate_limits and i < len(symbols):
                    time.sleep(self.delay_between_symbols)
                    
            except Exception as e:
                print(f"❌ {symbol} error: {e}")
                continue

        # Create consolidated output
        if all_candidates:
            consolidated_df = pd.concat(all_candidates, ignore_index=True)
            consolidated_df = consolidated_df.sort_values(['score', 'risk_reward'], ascending=[False, False])
            
            # Format expiration dates
            def format_expiration(exp_str):
                try:
                    return f"{exp_str[:4]}-{exp_str[4:6]}-{exp_str[6:]}"
                except:
                    return exp_str
            
            # Create output dataframe
            output_df = pd.DataFrame({
                'Symbol': consolidated_df['symbol'],
                'Strike': consolidated_df['strike'],
                'Exp': consolidated_df['expiration'].apply(format_expiration),
                'Price': consolidated_df['mid_price'].round(2),
                'Prob%': (consolidated_df['prob_itm'] * 100).round(0),
                'R/R': consolidated_df['risk_reward'].round(1),
                'BE': consolidated_df['breakeven'].round(2),
                'Move%': consolidated_df['breakeven_move_pct'].round(1),
                'MaxGain%': consolidated_df['profit_at_high_pct'].round(0),
                'Tier': consolidated_df['tier'],
                'Spread%': consolidated_df['spread_pct'].round(1),
                'Vol': consolidated_df['volume'].astype(int),
                '$Vol': (consolidated_df['dollar_volume'] / 1000).round(1),  # in thousands
                'Stock': consolidated_df['current_price'].round(2),
            })
            
            # Save consolidated results
            timestamp = datetime.now()
            filename = f"cheap_calls_{timestamp.strftime('%Y%m%d_%H%M')}.csv"
            
            with open(filename, 'w') as f:
                f.write("# CHEAP CALLS SCANNER\n")
                f.write(f"# Scan Date: {timestamp.strftime('%Y-%m-%d')}\n")
                f.write(f"# Scan Time: {timestamp.strftime('%H:%M:%S')}\n")
                f.write("#\n")
                f.write("# Settings:\n")
                f.write(f"#   Price Range: ${self.min_option_price:.2f}-${self.max_option_price:.2f}\n")
                f.write(f"#   Min Probability: {self.min_probability*100:.0f}%\n")
                f.write(f"#   Min Risk/Reward: {self.min_risk_reward}x\n")
                f.write(f"#   Min Dollar Volume: ${self.min_dollar_volume}\n")
                f.write("#\n")
                f.write("# Tier Classifications:\n")
                f.write("#   HIGH_PROB_CHEAP: 25%+ prob, 5x+ R/R (best of both)\n")
                f.write("#   BALANCED: 15%+ prob, 7x+ R/R (good balance)\n")
                f.write("#   PURE_LOTTERY: 10%+ prob, 10x+ R/R (true lottery)\n")
                f.write("#   SPECULATIVE: Below thresholds (high risk)\n")
                f.write("#\n")
                f.write("# Column Definitions:\n")
                f.write("#   Symbol: Stock ticker\n")
                f.write("#   Strike: Option strike price\n")
                f.write("#   Exp: Expiration date\n")
                f.write("#   Price: Option price (per contract)\n")
                f.write("#   Prob%: Probability of finishing ITM\n")
                f.write("#   R/R: Risk/Reward ratio\n")
                f.write("#   BE: Breakeven price\n")
                f.write("#   Move%: Required move to breakeven\n")
                f.write("#   MaxGain%: Gain if hits 5D high\n")
                f.write("#   Tier: Option classification\n")
                f.write("#   Spread%: Bid-ask spread\n")
                f.write("#   Vol: Option volume today\n")
                f.write("#   $Vol: Dollar volume in thousands\n")
                f.write("#   Stock: Current stock price\n")
                f.write("#\n")
                
                output_df.to_csv(f, index=False)
            
            print(f"\n💾 CONSOLIDATED RESULTS SAVED: {filename}")
            print(f"   Total opportunities: {len(output_df)}")
            print(f"   From {len(found)} symbols")
            
            # Send to Slack if webhook is configured
            send_to_slack("Cheap Calls Scanner", found, filename)
            
            # Show tier breakdown
            tier_counts = output_df['Tier'].value_counts()
            print("\n📊 Tier Breakdown:")
            for tier, count in tier_counts.items():
                print(f"   {tier}: {count}")

        if found:
            print("\n🏆 TOP CHEAP CALLS")
            print("=" * 70)
            print("Symbol | Strike | Price | Prob% | R/R | MaxGain% | Tier")
            print("-" * 70)
            for sym, df in found.items():
                best = df.iloc[0]
                prob_display = (best['prob_itm'] * 100) if pd.notna(best['prob_itm']) else 0
                print(f"{sym:6} | ${best['strike']:5.1f} | ${best['mid_price']:4.2f} | "
                      f"{prob_display:4.0f}% | {best['risk_reward']:4.1f}x | "
                      f"{best['profit_at_high_pct']:6.0f}% | {best['tier']}")
        else:
            print("\n❌ No cheap options found meeting criteria")
            send_to_slack("Cheap Calls Scanner", {})
            
        print(f"\nTotal historical requests: {self.hist_request_count}")
        return found

    def disconnect(self):
        self.ib.disconnect()
        print("\n👋 Disconnected from TWS")

def main():
    scanner = None
    try:
        scanner = CheapOptionsScanner(
            port=7496,
            client_id=5,
            # ATR settings
            min_atr_pct=2.0,
            min_abs_atr=None,
            low_price_threshold=10.0,
            min_abs_atr_low_price=0.25,
            use_intraday_atr=True,
            intraday_bar='30 mins',
            intraday_period=20,
            intraday_min_atr_pct=0.8,
            # Cheap option settings - UPDATED WITH RECOMMENDATIONS
            min_option_price=0.05,
            max_option_price=1.00,      # Expanded from 0.50 to 1.00
            min_volume_base=25,          # Dynamic volume based on price
            min_dollar_volume=2500,      # $2.5k minimum dollar volume
            min_open_interest=25,
            max_spread_pct=25.0,
            min_probability=0.10,        # Lowered from 0.15 to 0.10
            min_risk_reward=5.0,
            # Rate limiting
            respect_rate_limits=True,
            delay_between_symbols=2.0,
        )

        # Load watchlist from file
        try:
            with open('watchlist.txt', 'r') as f:
                watchlist = [
                    line.strip().upper() 
                    for line in f 
                    if line.strip() and not line.strip().startswith('#')
                ]
            print(f"📋 Loaded {len(watchlist)} symbols from watchlist.txt")
        except FileNotFoundError:
            print("⚠️ watchlist.txt not found, using default symbols")
            watchlist = [
                'SPY', 'QQQ', 'TQQQ',
                'AAPL', 'GOOGL', 'AMZN', 'NVDA', 'TSLA', 'AMD', 'PLTR',
                'META', 'MSFT', 'HOOD', 'SOFI', 'COIN', 'MARA',
            ]

        print(f"🔍 Scanning {len(watchlist)} symbols for cheap options...")
        results = scanner.scan_watchlist(watchlist)
        print("\n🎉 SCAN COMPLETE!")
        print(f"Found cheap options in {len(results)} symbols")
        
    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        if scanner:
            scanner.disconnect()


if __name__ == "__main__":
    main()