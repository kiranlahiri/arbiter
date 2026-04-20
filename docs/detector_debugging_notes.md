# Detector Debugging Notes

## Summary

We reached a point where:

- Coinbase ingestion was working
- Kraken ingestion was working
- both exchanges were being normalized into the same canonical symbol (`BTC-USD`)
- the detector service was running

But we were **not consistently seeing arbitrage signals**, even though the prices suggested there should be cross-exchange differences worth detecting.

This document explains what was going wrong, how we investigated it, and what changes fixed the issue.

## The Symptom

The main symptom was:

- the detector appeared to run, but no clear signals were showing up in the expected Kafka signal topic during our early tests

At first glance, that looked like one of these possibilities:

- there were no real spreads worth signaling
- the detector math was wrong
- the detector was not seeing both exchanges at the same time
- the local development workflow was making live validation unreliable

## What We Found

The issue was **not** primarily that arbitrage was impossible or that the detector design was fundamentally wrong.

The bigger issue was that our validation path kept getting contaminated by **stale topic history** and **slow short-lived startup behavior**.

More specifically:

### 1. Short-lived Compose runs were noisy

We were often using one-off commands like:

```bash
docker compose run --rm <service>
```

That caused a few problems:

- each container spent time starting up
- early runs spent time downloading Go dependencies
- services were not staying alive long enough to behave like a real warm pipeline

This made it hard for the ingestors, normalizers, and detector to all see fresh live traffic at the same time.

### 2. Shared Kafka topics contained old messages

We were reusing the same development topics repeatedly:

- `raw.ticks.coinbase`
- `raw.ticks.kraken`
- `normalized.ticks`
- `arbitrage.signals`

Those topics already contained old records from earlier experiments and debugging runs.

When we started fresh consumers against those reused topics, even with careful group settings, the pipeline could still end up processing old records during validation.

### 3. The detector correctly rejects stale quotes

The detector intentionally filters out stale quotes before comparing exchanges.

That is the right behavior for a market-data pipeline: a stale quote should not be trusted as a basis for a live arbitrage signal.

So stale data was causing log output like:

- quote skipped as stale
- `active_exchanges=0`
- `active_exchanges=1`
- not enough active quotes to compare

That meant the detector often never reached a clean state where both exchanges were simultaneously active for the same symbol.

### 4. The normalizer preserved the original ingestor receive time

This was also correct behavior, but important to understand.

The `NormalizedTick` keeps the original ingestor receive time from the raw event. That means:

- even if the normalizer publishes a message "now"
- the detector still sees the message as old if the original tick itself is old

So replaying older raw data into the normalizer was guaranteed to produce normalized ticks that the detector would consider stale.

## How We Investigated It

We debugged this in several steps.

### Added detector debug logging

We updated the detector so it could log:

- when a quote was skipped as stale
- when there were not enough active exchanges
- per-pair spread evaluations
- reasons a signal was skipped

This showed us that many quotes were being rejected before pairwise comparison even happened.

### Added configurable start offsets

We added `KAFKA_START_OFFSET` support to:

- the detector
- the normalizer

That allowed us to control whether a service should:

- replay from the beginning
- or consume only the latest data

This made it easier to distinguish backlog-related issues from live-flow issues.

### Switched from one-off runs toward long-lived services

We improved the Docker Compose workflow so the pipeline could be run as long-lived services instead of many isolated short-lived commands.

That made local behavior more realistic:

- ingestors stay connected
- normalizers stay warm
- detector state stays warm

### Added Go module/build caches for Compose services

We added shared cache volumes for:

- Go module downloads
- Go build artifacts

That reduced repeated startup delay and made the local pipeline much less wasteful.

### Isolated validation into clean `.live` topics

This was the most important fix for reliable signal validation.

We introduced a separate clean-room topic set:

- `raw.ticks.coinbase.live`
- `raw.ticks.kraken.live`
- `normalized.ticks.live`
- `arbitrage.signals.live`

These topics let us validate the live pipeline without old historical records polluting the test.

## The Actual Fix

The core fix was:

1. support configurable topic names in Compose
2. create isolated live-validation topics
3. run the long-lived pipeline against those fresh topics

That gave us a true live-only validation path.

Once we did that, the detector began producing real signals.

## What Changed In The Repo

### Detector improvements

We updated the detector to support:

- debug logging for quote rejection and signal decisions
- configurable Kafka start offset

### Normalizer improvements

We updated the normalizer to support:

- configurable Kafka start offset
- better alignment with live-only validation flows

### Compose improvements

We updated `docker-compose.yml` to support:

- shared Go module and build caches
- overridable topic names and group IDs
- long-lived pipeline services

### Makefile improvements

We added workflows for:

- creating normal dev topics
- creating isolated live-validation topics
- starting the full pipeline as long-lived services
- starting the full pipeline against isolated `.live` topics

## The Successful Validation Path

The clean validation workflow became:

```bash
make up-minimal
make create-topics-live
make compose-up-pipeline-live
make logs-pipeline-live
```

Using that path, we confirmed:

- Coinbase live data was flowing
- Kraken live data was flowing
- both feeds normalized to `BTC-USD`
- the detector reached `active_exchanges=2`
- the detector published signals to `arbitrage.signals.live`

## Example Outcome

During successful live validation, the detector produced signals like:

- `buy=kraken`
- `sell=coinbase`
- positive spreads such as `2.15`, `5.01`, `6.46`, and `7.28`

That confirmed the full live cross-exchange pipeline was working.

## Final Takeaway

The failure mode was mostly a **validation and orchestration problem**, not a fundamental logic failure.

The detector was doing the right thing by rejecting stale data, but our local workflow made it too easy to feed the detector stale records during testing.

The fix was to:

- keep services warm
- reduce startup churn
- isolate live validation from old topic history

Once we did that, the arbitrage signal path worked as expected.
