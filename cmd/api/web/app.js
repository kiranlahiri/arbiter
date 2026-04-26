const signalsBody = document.getElementById("signals-body");
const apiStatus = document.getElementById("api-status");
const wsStatus = document.getElementById("ws-status");
const lastUpdated = document.getElementById("last-updated");
const statRoute = document.getElementById("stat-route");
const statBestSpread = document.getElementById("stat-best-spread");
const statLatestGap = document.getElementById("stat-latest-gap");
const statOldestAge = document.getElementById("stat-oldest-age");
const loadMoreButton = document.getElementById("load-more-button");

const state = {
  signals: [],
  oldestId: null,
  loadingMore: false,
};

function formatMoney(value) {
  return Number(value).toFixed(2);
}

function formatMs(value) {
  return `${value}ms`;
}

function formatTime(value) {
  return new Date(value).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function setPill(element, label, className) {
  element.textContent = label;
  element.className = `pill ${className}`;
}

function updateSummary() {
  if (state.signals.length === 0) {
    statRoute.textContent = "-";
    statBestSpread.textContent = "-";
    statLatestGap.textContent = "-";
    statOldestAge.textContent = "-";
    return;
  }

  const bestSpread = state.signals.reduce((max, signal) => Math.max(max, signal.spread), Number.NEGATIVE_INFINITY);
  const latest = state.signals[0];
  statRoute.textContent = `${latest.buy_exchange} → ${latest.sell_exchange}`;

  statBestSpread.textContent = `$${formatMoney(bestSpread)}`;
  statLatestGap.textContent = formatMs(latest.quote_gap_ms);
  statOldestAge.textContent = formatMs(latest.oldest_quote_age_ms);
}

function routeMarkup(signal) {
  return `
    <div class="route">
      <div><strong>Buy</strong> ${signal.buy_exchange} @ ${formatMoney(signal.buy_price)}</div>
      <div><strong>Sell</strong> ${signal.sell_exchange} @ ${formatMoney(signal.sell_price)}</div>
    </div>
  `;
}

function rowMarkup(signal) {
  return `
    <tr data-id="${signal.id}">
      <td>${formatTime(signal.timestamp_opportunity)}</td>
      <td>${signal.symbol}</td>
      <td>${routeMarkup(signal)}</td>
      <td class="metric-hot">$${formatMoney(signal.spread)}</td>
      <td class="metric-cool">${formatMs(signal.quote_gap_ms)}</td>
      <td>${formatMs(signal.buy_quote_age_ms)}</td>
      <td>${formatMs(signal.sell_quote_age_ms)}</td>
      <td>${formatMs(signal.oldest_quote_age_ms)}</td>
    </tr>
  `;
}

function renderSignals() {
  if (state.signals.length === 0) {
    signalsBody.innerHTML = `
      <tr class="placeholder-row">
        <td colspan="8">No persisted signals yet.</td>
      </tr>
    `;
    updateSummary();
    return;
  }

  signalsBody.innerHTML = state.signals.map(rowMarkup).join("");
  updateSummary();
}

function setSignals(signals) {
  state.signals = signals;
  state.oldestId = signals.length > 0 ? signals[signals.length - 1].id : null;
  renderSignals();
}

function prependSignal(signal) {
  if (state.signals.some((existing) => existing.id === signal.id)) {
    return;
  }

  state.signals.unshift(signal);
  if (state.oldestId === null || signal.id < state.oldestId) {
    state.oldestId = signal.id;
  }
  renderSignals();
}

function appendOlderSignals(signals) {
  if (!signals || signals.length === 0) {
    return 0;
  }

  const existingIds = new Set(state.signals.map((signal) => signal.id));
  const newSignals = signals.filter((signal) => !existingIds.has(signal.id));
  state.signals = state.signals.concat(newSignals);
  state.oldestId = state.signals.length > 0 ? state.signals[state.signals.length - 1].id : null;
  renderSignals();
  return newSignals.length;
}

async function loadHealth() {
  try {
    const response = await fetch("/health");
    if (!response.ok) {
      throw new Error(`health request failed: ${response.status}`);
    }

    const payload = await response.json();
    setPill(apiStatus, payload.status === "ok" ? "Healthy" : "Error", payload.status === "ok" ? "pill-live" : "pill-warn");
  } catch (error) {
    console.error(error);
    setPill(apiStatus, "Offline", "pill-warn");
  }
}

async function loadSignals() {
  try {
    const response = await fetch("/signals?limit=50");
    if (!response.ok) {
      throw new Error(`signals request failed: ${response.status}`);
    }

    const payload = await response.json();
    setSignals(payload.signals || []);
    lastUpdated.textContent = new Date().toLocaleTimeString();
  } catch (error) {
    console.error(error);
    signalsBody.innerHTML = `
      <tr class="placeholder-row">
        <td colspan="8">Failed to load signals.</td>
      </tr>
    `;
  }
}

async function loadOlderSignals() {
  if (state.loadingMore || !state.oldestId) {
    return;
  }

  state.loadingMore = true;
  loadMoreButton.disabled = true;
  loadMoreButton.textContent = "Loading...";

  try {
    const response = await fetch(`/signals?limit=50&before_id=${state.oldestId}`);
    if (!response.ok) {
      throw new Error(`older signals request failed: ${response.status}`);
    }

    const payload = await response.json();
    const added = appendOlderSignals(payload.signals || []);
    if (added === 0) {
      loadMoreButton.textContent = "No More Signals";
      loadMoreButton.disabled = true;
      state.loadingMore = false;
      return;
    }
  } catch (error) {
    console.error(error);
  }

  state.loadingMore = false;
  loadMoreButton.disabled = false;
  loadMoreButton.textContent = "Load Older Signals";
}

function connectWebSocket() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(`${protocol}//${window.location.host}/ws/signals`);

  socket.addEventListener("open", () => {
    setPill(wsStatus, "Live", "pill-live");
  });

  socket.addEventListener("message", (event) => {
    const payload = JSON.parse(event.data);
    if (payload.type === "signal" && payload.signal) {
      prependSignal(payload.signal);
      lastUpdated.textContent = new Date().toLocaleTimeString();
    }
  });

  socket.addEventListener("close", () => {
    setPill(wsStatus, "Reconnecting", "pill-muted");
    window.setTimeout(connectWebSocket, 1500);
  });

  socket.addEventListener("error", () => {
    setPill(wsStatus, "Stream Error", "pill-warn");
    socket.close();
  });
}

async function bootstrap() {
  await Promise.all([loadHealth(), loadSignals()]);
  connectWebSocket();
  window.setInterval(loadHealth, 10000);
}

loadMoreButton.addEventListener("click", loadOlderSignals);

bootstrap();
