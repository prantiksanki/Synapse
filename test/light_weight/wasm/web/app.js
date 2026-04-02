const LANDMARK_DIM = 126;
const VIDEO_W = 640;
const VIDEO_H = 480;
const NORM_PATH = "../../normalization.json";

const DEFAULT_STABLE_MS = 2000;
const DEFAULT_MIN_CONFIDENCE = 0.5;
const WS_RECONNECT_DELAY_MS = 1500;

const videoEl = document.getElementById("video");
const backendEl = document.getElementById("backend");
const predictionEl = document.getElementById("prediction");
const confidenceEl = document.getElementById("confidence");
const fpsEl = document.getElementById("fps");
const handsEl = document.getElementById("hands");
const statusEl = document.getElementById("status");
const wsUrlEl = document.getElementById("wsUrl");
const stableWindowEl = document.getElementById("stableWindow");
const minConfidenceEl = document.getElementById("minConfidence");
const connectWsBtn = document.getElementById("connectWsBtn");
const disconnectWsBtn = document.getElementById("disconnectWsBtn");
const connectionDotEl = document.getElementById("connectionDot");
const connectionTextEl = document.getElementById("connectionText");
const lockLabelEl = document.getElementById("lockLabel");
const lockProgressEl = document.getElementById("lockProgress");

let normMean = null;
let normStd = null;
let handsDetector = null;
let latestHandsResult = null;
let handsBusy = false;
let websocket = null;
let cameraStarted = false;
let manualDisconnect = false;
let reconnectTimer = null;

let stableWindowMs = DEFAULT_STABLE_MS;
let minConfidence = DEFAULT_MIN_CONFIDENCE;

let shownLabel = "-";
let shownConfidence = 0;
let pendingLabel = null;
let pendingSinceMs = 0;

let frameCount = 0;
let fpsStart = performance.now();

const Hands = window.Hands;

function setStatus(message, kind = "") {
  statusEl.textContent = message;
  statusEl.className = `status ${kind}`.trim();
}

function setConnectionState(stateText, dotKind = "") {
  connectionTextEl.textContent = stateText;
  connectionDotEl.className = `dot ${dotKind}`.trim();
}

function parseStableWindowMs() {
  const value = Number(stableWindowEl.value);
  if (!Number.isFinite(value)) return DEFAULT_STABLE_MS;
  return Math.max(200, Math.round(value));
}

function parseMinConfidence() {
  const value = Number(minConfidenceEl.value);
  if (!Number.isFinite(value)) return DEFAULT_MIN_CONFIDENCE;
  return Math.min(1, Math.max(0, value));
}

function resetPendingLock(message = "Waiting for a stable symbol...") {
  pendingLabel = null;
  pendingSinceMs = 0;
  lockLabelEl.textContent = message;
  lockProgressEl.style.width = "0%";
}

function setButtonsConnected(connected) {
  connectWsBtn.disabled = connected;
  disconnectWsBtn.disabled = !connected;
}

function closeSocket() {
  if (!websocket) return;
  websocket.onopen = null;
  websocket.onclose = null;
  websocket.onerror = null;
  websocket.onmessage = null;
  websocket.close();
  websocket = null;
}

function scheduleReconnect() {
  if (manualDisconnect || reconnectTimer) return;
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null;
    connectWs();
  }, WS_RECONNECT_DELAY_MS);
}

function updateStablePrediction(incomingLabel, incomingConfidence) {
  const nowMs = Date.now();
  const label = String(incomingLabel || "-").trim() || "-";
  const confidence = Number(incomingConfidence ?? 0);

  if (confidence < minConfidence) {
    resetPendingLock(`Confidence too low (${confidence.toFixed(3)} < ${minConfidence.toFixed(2)}).`);
    confidenceEl.textContent = confidence.toFixed(3);
    return;
  }

  if (label === shownLabel) {
    resetPendingLock("Symbol locked.");
    shownConfidence = confidence;
    predictionEl.textContent = shownLabel;
    confidenceEl.textContent = shownConfidence.toFixed(3);
    return;
  }

  if (pendingLabel !== label) {
    pendingLabel = label;
    pendingSinceMs = nowMs;
    lockLabelEl.textContent = `Stabilizing "${label}"...`;
    lockProgressEl.style.width = "0%";
    confidenceEl.textContent = confidence.toFixed(3);
    return;
  }

  const elapsedMs = nowMs - pendingSinceMs;
  const progress = Math.min(1, elapsedMs / stableWindowMs);
  lockProgressEl.style.width = `${(progress * 100).toFixed(1)}%`;
  lockLabelEl.textContent = `Stabilizing "${label}": ${Math.ceil(Math.max(0, stableWindowMs - elapsedMs) / 100) / 10}s`;
  confidenceEl.textContent = confidence.toFixed(3);

  if (elapsedMs >= stableWindowMs) {
    shownLabel = label;
    shownConfidence = confidence;
    predictionEl.textContent = shownLabel;
    confidenceEl.textContent = shownConfidence.toFixed(3);
    resetPendingLock(`Locked "${shownLabel}".`);
  }
}

function showNoHand() {
  shownLabel = "No hand";
  shownConfidence = 0;
  predictionEl.textContent = shownLabel;
  confidenceEl.textContent = "0.000";
  resetPendingLock("Show your hand inside the frame.");
}

function connectWs() {
  const url = wsUrlEl.value.trim();
  if (!url) {
    setStatus("WebSocket URL is required.", "warn");
    return;
  }

  manualDisconnect = false;
  if (reconnectTimer) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  closeSocket();
  setConnectionState("Connecting", "warn");
  setStatus(`Connecting to ${url}...`);

  websocket = new WebSocket(url);

  websocket.onopen = () => {
    backendEl.textContent = "python-bridge";
    setButtonsConnected(true);
    setConnectionState("Connected", "ok");
    setStatus(`Connected to ${url}`, "ok");
  };

  websocket.onclose = () => {
    setButtonsConnected(false);
    setConnectionState("Disconnected", manualDisconnect ? "" : "warn");
    if (manualDisconnect) {
      setStatus("Disconnected.");
      return;
    }
    setStatus("Connection lost. Reconnecting...", "warn");
    scheduleReconnect();
  };

  websocket.onerror = () => {
    setStatus("WebSocket connection error.", "error");
  };

  websocket.onmessage = (event) => {
    try {
      const payload = JSON.parse(event.data);
      if (payload.event === "prediction" && payload.data) {
        updateStablePrediction(payload.data.label, payload.data.confidence);
        return;
      }
      if (payload.event === "error") {
        setStatus(`Bridge error: ${payload.message || "Unknown error"}`, "error");
      }
    } catch (_) {
      setStatus("Received malformed WebSocket payload.", "warn");
    }
  };
}

function disconnectWs() {
  manualDisconnect = true;
  if (reconnectTimer) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  closeSocket();
  setButtonsConnected(false);
  setConnectionState("Disconnected");
  setStatus("Disconnected.");
}

function toFeatureVector(result) {
  if (!result?.multiHandLandmarks?.length) return null;

  let left = new Float32Array(63);
  let right = new Float32Array(63);

  for (let i = 0; i < result.multiHandLandmarks.length; i += 1) {
    const hand = result.multiHandLandmarks[i];
    const handInfo = result.multiHandedness?.[i];
    const label = handInfo?.label || "Right";

    if (!hand || hand.length !== 21) continue;

    const wrist = hand[0];
    const coords = new Float32Array(63);
    for (let j = 0; j < 21; j += 1) {
      const base = j * 3;
      coords[base] = hand[j].x - wrist.x;
      coords[base + 1] = hand[j].y - wrist.y;
      coords[base + 2] = hand[j].z - wrist.z;
    }

    if (label === "Left") {
      left = coords;
    } else {
      right = coords;
    }
  }

  const hasLeft = left.some((value) => value !== 0);
  const hasRight = right.some((value) => value !== 0);
  if (!hasLeft && !hasRight) return null;

  if (!hasLeft && hasRight) {
    left = right;
    right = new Float32Array(63);
  }

  const out = new Float32Array(LANDMARK_DIM);
  out.set(left, 0);
  out.set(right, 63);
  return out;
}

function normalize(features) {
  const out = new Float32Array(features.length);
  for (let i = 0; i < features.length; i += 1) {
    const std = normStd[i] > 1e-6 ? normStd[i] : 1e-6;
    out[i] = (features[i] - normMean[i]) / std;
  }
  return out;
}

async function setupPreprocessing() {
  const response = await fetch(NORM_PATH);
  const norm = await response.json();
  normMean = norm.mean;
  normStd = norm.std;

  if (!Array.isArray(normMean) || !Array.isArray(normStd) || normMean.length !== LANDMARK_DIM) {
    throw new Error("Invalid normalization.json format.");
  }
}

async function setupLandmarker() {
  handsDetector = new Hands({
    locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`,
  });

  handsDetector.setOptions({
    maxNumHands: 2,
    modelComplexity: 0,
    minDetectionConfidence: 0.5,
    minTrackingConfidence: 0.5,
  });

  handsDetector.onResults((results) => {
    latestHandsResult = results;
  });
}

async function setupCamera() {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("Browser does not support camera access (getUserMedia).");
  }

  let stream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: {
        width: { ideal: VIDEO_W },
        height: { ideal: VIDEO_H },
        facingMode: "user",
      },
      audio: false,
    });
  } catch (_) {
    stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
  }

  videoEl.srcObject = stream;
  videoEl.muted = true;
  videoEl.playsInline = true;
  videoEl.autoplay = true;

  await new Promise((resolve, reject) => {
    let done = false;

    const ok = () => {
      if (done) return;
      done = true;
      resolve();
    };

    const fail = () => {
      if (done) return;
      done = true;
      reject(new Error("Camera metadata did not load."));
    };

    videoEl.onloadedmetadata = ok;
    setTimeout(fail, 4000);
  });

  await videoEl.play();
  cameraStarted = true;
}

function updateFps() {
  frameCount += 1;
  const now = performance.now();
  const elapsed = now - fpsStart;
  if (elapsed >= 1000) {
    fpsEl.textContent = ((frameCount * 1000) / elapsed).toFixed(1);
    frameCount = 0;
    fpsStart = now;
  }
}

function sendFeatures(normalized, handCount) {
  if (!websocket || websocket.readyState !== WebSocket.OPEN) return;
  websocket.send(
    JSON.stringify({
      event: "features",
      features: Array.from(normalized),
      timestamp_ms: Date.now(),
      hands: handCount,
      source: "browser_landmarks",
    })
  );
}

function inferLoop() {
  stableWindowMs = parseStableWindowMs();
  minConfidence = parseMinConfidence();

  if (!handsDetector || videoEl.readyState < 2) {
    requestAnimationFrame(inferLoop);
    return;
  }

  if (!handsBusy) {
    handsBusy = true;
    handsDetector
      .send({ image: videoEl })
      .catch(() => {})
      .finally(() => {
        handsBusy = false;
      });
  }

  const result = latestHandsResult;
  const handCount = result?.multiHandLandmarks?.length || 0;
  handsEl.textContent = String(handCount);

  const features = toFeatureVector(result);
  if (!features) {
    showNoHand();
    updateFps();
    requestAnimationFrame(inferLoop);
    return;
  }

  const normalized = normalize(features);
  sendFeatures(normalized, handCount);

  updateFps();
  requestAnimationFrame(inferLoop);
}

async function main() {
  connectWsBtn.addEventListener("click", connectWs);
  disconnectWsBtn.addEventListener("click", disconnectWs);

  setButtonsConnected(false);
  setConnectionState("Disconnected");
  showNoHand();

  try {
    if (!Hands) throw new Error("MediaPipe Hands failed to load.");

    backendEl.textContent = "python-bridge";
    setStatus("Loading preprocessing data...");
    await setupPreprocessing();

    setStatus("Loading hand tracker...");
    await setupLandmarker();

    setStatus("Opening webcam...");
    await setupCamera();

    setStatus("Camera ready. Connecting to bridge...", "ok");
    connectWs();
    requestAnimationFrame(inferLoop);

    setTimeout(() => {
      if (!cameraStarted) return;
      if (videoEl.readyState < 2 || videoEl.videoWidth === 0 || videoEl.videoHeight === 0) {
        setStatus("Camera stream is not rendering. Close other camera apps/tabs and reload.", "warn");
      }
    }, 5000);
  } catch (error) {
    console.error(error);
    setStatus(`Startup failed: ${error?.message || error}`, "error");
  }
}

main();
