# FinanceIsland

**Your money and your trades under the MacBook notch.**
Live currency, crypto and stock prices, a long-term portfolio compared with the S&P 500 and BTC, watch-only wallets on four
chains, a trader's journal with paper trading and real-time charts. Native Swift, everything computed on your Mac.

**© 2026 marcalecs. All rights reserved.** Source available for reading; see [LICENSE](LICENSE). macOS 14+ · Apple Silicon and Intel.

> FinanceIsland shows market data and your own records. It gives no trading signals and no financial advice,
> and it never places orders.

---

## What it does

Hover the camera notch and a "dynamic island" drops down. Four tabs:

### Rates
Your currencies and coins as cards with sparklines. Click a card for its chart (1H · 24H · 1W · 1M · ALL),
drag across it to measure a move, or open it in a full **chart window**. Edit mode (✏️) reorders and removes cards.

### Markets
Any currency, coin, stock, ETF or index with one search field (⌘K) that also finds your portfolio positions and
journal trades. An asset page shows the price, the 24 h change, a **volatility estimate (not a forecast)**, price
alerts, headlines and, for US stocks, **pre-market and after-hours** prices where Yahoo reports them.
Exchange hours for New York, London, Frankfurt, Tokyo and Hong Kong count down to the next open or close.

### 💼 Long-Term
Your holdings, synced from your wallets and Binance or added by hand, with live PnL against your entry:

* **Comparison with the S&P 500 and BTC** over 1M · 3M · 1Y · since start (today's holdings at each day's close).
* **Headlines** for your biggest positions: title, source and time; a click opens the article.
* Per holding: time held, a sparkline since entry, rule checks against your own entry price, portfolio weight and an
  over-concentration warning.

### Journal
Notes and trades with entry, stop, target and size; results in R and money after fees, win rate and equity curve.
* **Paper trading** on public Binance quotes (PAPER), with an offline generator when there's no network (SIMULATED).
  Volume is sized from your risk and the stop including both fees. No orders, no exchange keys.
* **Manual trades in two clicks** from the collapsed island, with a stop ↔ target bar under the notch and a
  notification when the price reaches your stop or target.
* **Tilt Guard** (Pro): daily loss limit, trades per day, losing streak and a pause after a stop block new entries.
* **Analytics and trader mirror** (Pro): R by hour, weekday, asset, side, setup and mistake tags.

### Also
* **No custody**: FinanceIsland never holds funds, seed phrases or private keys. Wallets are watch-only; a Binance key is accepted only read-only and stays in the Keychain.
* **Wallet page**: Ethereum, Bitcoin, Solana and TON addresses (watch-only) and a Binance account through a
  **read-only** API key (keys that can trade or withdraw are refused; stored in the Keychain).
* **Chart window**: candles from 1m to 1D, zoom / pan with the trackpad, crosshair with OHLC, MA / EMA / Bollinger /
  RSI / MACD / volume, horizontal and trend lines, real-time updates (Binance stream, Yahoo every 15 s).
* **Collapsed island**: an open trade, then alerts and exchange events, otherwise a calm rotation or a ticker tape.
  Menu bar mode shows up to three pinned values next to the icon.
* Liquid Glass and colour themes, four languages (English, 中文, Español, Deutsch), energy modes, an app log
  and storage overview (Settings ▸ Logs).

### Free and Pro
Free: rates, charts, wallets, portfolio, the journal with basic statistics, manual trades, 3 price alerts and
20 paper trades a month. Pro: Tilt Guard, the trader mirror, extended statistics, unlimited paper trading and
alerts. One subscription covers up to 2 Macs.

---

## Data sources

Every request goes through a fallback chain; hosts that rate-limit are skipped for a while, stale data counts as a failure.

| What | Sources |
|---|---|
| Currencies | Yahoo Finance → Federal Reserve (FRED) → ECB → ExchangeRate-API |
| Crypto | Binance (REST + WebSocket) → Coinbase → Kraken → Yahoo Finance → CoinGecko |
| Stocks, indices, commodities | Yahoo Finance → Nasdaq |
| Wallet balances | public Ethereum nodes, mempool.space, Solana RPC, toncenter |
| Macro risk card | FRED (high-yield spread), Yahoo Finance (USD/JPY, VIX), Binance (BTC funding, open interest) |

Your portfolio, wallets, exchange keys and journal never leave the Mac, and the app talks to no developer server.
Pro is unlocked by an offline licence from the Telegram bot [@FinanceIsland_agent](https://t.me/FinanceIsland_agent).

---

## Install

1. Download `FinanceIsland-1.0-beta-universal.dmg` from [Releases](https://github.com/marcalecs/FinanceIsland-free/releases) and drag the app to Applications.
2. The beta is not notarized yet, so the first time right-click the app ▸ **Open** ▸ **Open**.

macOS 14+ · Apple Silicon and Intel.

---

## Data on your Mac

| What | Where |
|---|---|
| Settings | app preferences |
| Price history, journal, reports | `~/Library/Application Support/FinanceIsland/` |
| App log | `~/Library/Logs/FinanceIsland/` |
| API keys | macOS Keychain |

Settings ▸ Logs shows each folder and its size; Settings ▸ About ▸ Withdraw consent erases everything.

---

**FinanceIsland** — made by marcalecs. © 2026 marcalecs. All rights reserved.
