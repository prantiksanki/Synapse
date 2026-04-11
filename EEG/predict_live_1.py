import torch, numpy as np, time, threading, collections
import tkinter as tk
from tkinter import font as tkfont

# ── CONFIG ────────────────────────────────────────────────────────────────────
MODEL_PATH     = r'C:\eeg_demo\my_model.pt'
N_CHANNELS     = 8
SFREQ          = 250
WINDOW_SAMPLES = 750
STEP_SEC       = 0.5
TEMPERATURE    = 1.5
SMOOTH_WINDOW  = 3

# ── SET THIS TO True TO USE HARDCODED FALLBACK (no board, no model file) ──────
USE_HARDCODED_FALLBACK = True
FALLBACK_HOLD_SEC      = 5.0   # seconds between word changes
# ─────────────────────────────────────────────────────────────────────────────

# Bar flicker config
BAR_TICK_MS  = 120   # redraw every N ms
BAR_NOISE    = 0.04  # ± jitter amplitude added to each bar each tick

WORD_COLORS = {
    "YES":"#00FF88","NO":"#FF4444",
    "LEFT":"#FFD700","RIGHT":"#44AAFF","---":"#333333",
}

FALLBACK_SEQUENCE = [
    ("YES",   [0.82, 0.05, 0.07, 0.06]),
    ("LEFT",  [0.06, 0.09, 0.79, 0.06]),
    ("RIGHT", [0.05, 0.07, 0.08, 0.80]),
    ("NO",    [0.04, 0.84, 0.06, 0.06]),
    ("LEFT",  [0.07, 0.05, 0.81, 0.07]),
    ("YES",   [0.85, 0.05, 0.05, 0.05]),
    ("RIGHT", [0.06, 0.06, 0.07, 0.81]),
    ("NO",    [0.05, 0.83, 0.06, 0.06]),
]
FALLBACK_WORDS = ["YES", "NO", "LEFT", "RIGHT"]

# ── Model definition — MUST match train_mine.py exactly ───────────────────────
class EEG_Model(torch.nn.Module):
    def __init__(self, n_ch=8, n_cls=4):
        super().__init__()
        self.cnn = torch.nn.Sequential(
            torch.nn.Conv1d(n_ch, 64, kernel_size=7, padding=3),
            torch.nn.BatchNorm1d(64), torch.nn.ELU(), torch.nn.Dropout(0.4),
            torch.nn.Conv1d(64, 128, kernel_size=5, padding=2),
            torch.nn.BatchNorm1d(128), torch.nn.ELU(), torch.nn.Dropout(0.4),
            torch.nn.AvgPool1d(kernel_size=2),
        )
        self.bilstm = torch.nn.LSTM(128, 128, batch_first=True,
                                    bidirectional=True, num_layers=2, dropout=0.3)
        self.gru    = torch.nn.GRU(256, 128, batch_first=True, num_layers=2, dropout=0.3)
        self.fc = torch.nn.Sequential(
            torch.nn.Linear(128, 64), torch.nn.ELU(), torch.nn.Dropout(0.4),
            torch.nn.Linear(64,  32), torch.nn.ELU(), torch.nn.Dropout(0.3),
            torch.nn.Linear(32, n_cls)
        )

    def forward(self, x):
        x = self.cnn(x)
        x = x.permute(0, 2, 1)
        x, _ = self.bilstm(x)
        x, _ = self.gru(x)
        return self.fc(x[:, -1, :])

def preprocess(eeg):
    eeg = eeg - eeg.mean(axis=0)
    eeg = eeg / (eeg.std(axis=0) + 1e-6)
    return eeg.T

def connect_board():
    from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds
    params = BrainFlowInputParams()
    params.serial_port = 'COM5'
    board_id = BoardIds.CYTON_BOARD
    board = BoardShim(board_id, params)
    board.prepare_session()
    board.start_stream()
    return board, board_id

# ── UI ────────────────────────────────────────────────────────────────────────
class PredictApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("EEG Live Prediction")
        self.root.geometry("640x500")
        self.root.configure(bg="#0d0d0d")
        self.root.resizable(False, False)

        big_font   = tkfont.Font(family="Helvetica", size=80, weight="bold")
        label_font = tkfont.Font(family="Helvetica", size=13)
        small_font = tkfont.Font(family="Helvetica", size=10)

        tk.Label(self.root, text="DETECTED THOUGHT:",
                 font=label_font, bg="#0d0d0d", fg="#444444").pack(pady=(28,0))
        self.word_var = tk.StringVar(value="---")
        self.word_label = tk.Label(self.root, textvariable=self.word_var,
                                   font=big_font, bg="#0d0d0d", fg="#333333")
        self.word_label.pack(pady=4)

        bar_frame = tk.Frame(self.root, bg="#0d0d0d")
        bar_frame.pack(pady=(10,0))
        self.conf_bars   = {}
        self.conf_labels = {}
        for word in FALLBACK_WORDS:
            col = tk.Frame(bar_frame, bg="#0d0d0d")
            col.pack(side=tk.LEFT, padx=18)
            tk.Label(col, text=word, font=small_font,
                     bg="#0d0d0d", fg=WORD_COLORS[word]).pack()
            canvas = tk.Canvas(col, width=40, height=120,
                               bg="#111111", highlightthickness=0)
            canvas.pack()
            self.conf_bars[word] = canvas
            lbl = tk.Label(col, text="0%", font=small_font,
                           bg="#0d0d0d", fg="#555555")
            lbl.pack()
            self.conf_labels[word] = lbl

        self.status_var = tk.StringVar(value="Connecting...")
        tk.Label(self.root, textvariable=self.status_var,
                 font=small_font, bg="#0d0d0d", fg="#444444").pack(pady=(18,0))
        self.history_var = tk.StringVar(value="")
        tk.Label(self.root, textvariable=self.history_var,
                 font=small_font, bg="#0d0d0d", fg="#333333").pack()
        self._history = collections.deque(maxlen=5)

        # current "true" probabilities that bars jitter around
        self._base_probs = {w: 0.25 for w in FALLBACK_WORDS}
        self._current_word = "---"

        self._tick_bars()   # start the flicker loop

    # ── bar flicker loop (runs on main thread via after()) ────────────────────
    def _tick_bars(self):
        noisy = {}
        for w in FALLBACK_WORDS:
            v = self._base_probs[w] + np.random.uniform(-BAR_NOISE, BAR_NOISE)
            noisy[w] = max(0.01, min(0.99, v))

        # renormalise so bars always sum to 1
        total = sum(noisy.values())
        noisy = {w: v / total for w, v in noisy.items()}

        for w in FALLBACK_WORDS:
            p      = noisy[w]
            canvas = self.conf_bars[w]
            canvas.delete("all")
            bar_h  = int(p * 120)
            canvas.create_rectangle(0, 120 - bar_h, 40, 120,
                                    fill=WORD_COLORS[w], outline="")
            self.conf_labels[w].configure(text=f"{int(p * 100)}%")

        self.root.after(BAR_TICK_MS, self._tick_bars)

    def update_prediction(self, word, probs, words):
        """Called by the worker thread to set a new true prediction."""
        self._current_word = word
        self.word_var.set(word)
        self.word_label.configure(fg=WORD_COLORS.get(word, "#FFFFFF"))
        # update the base the bars jitter around
        for i, w in enumerate(words):
            self._base_probs[w] = float(probs[i])
        self._history.append(word)
        self.history_var.set("  ->  ".join(self._history))

    def set_status(self, msg):
        self.status_var.set(msg)

    def run(self):
        self.root.mainloop()

# ── HARDCODED FALLBACK WORKER ─────────────────────────────────────────────────
def hardcoded_worker(app):
    app.root.after(0, app.set_status, "[DEMO] Hardcoded fallback — no board connected")
    time.sleep(1.0)
    idx = 0
    while True:
        word, probs = FALLBACK_SEQUENCE[idx % len(FALLBACK_SEQUENCE)]
        app.root.after(0, app.update_prediction, word, probs, FALLBACK_WORDS)
        time.sleep(FALLBACK_HOLD_SEC)
        idx += 1

# ── REAL PREDICT WORKER ───────────────────────────────────────────────────────
def predict_worker(app, model, words):
    try:
        app.root.after(0, app.set_status, "Connecting to board...")
        board, board_id = connect_board()
        from brainflow.board_shim import BoardShim
        eeg_channels = BoardShim.get_eeg_channels(board_id)[:N_CHANNELS]
        ring         = collections.deque(maxlen=WINDOW_SAMPLES)
        prob_buffer  = collections.deque(maxlen=SMOOTH_WINDOW)

        app.root.after(0, app.set_status,
            f"Streaming — predicting every {STEP_SEC}s")
        model.eval()
        with torch.no_grad():
            while True:
                time.sleep(STEP_SEC)
                chunk = board.get_board_data()
                if chunk.shape[1] == 0:
                    continue
                eeg_chunk = chunk[eeg_channels, :].T
                ring.extend(eeg_chunk.tolist())
                if len(ring) < WINDOW_SAMPLES:
                    app.root.after(0, app.set_status,
                        f"Buffering... {len(ring)}/{WINDOW_SAMPLES}")
                    continue

                window = preprocess(np.array(ring))
                x      = torch.tensor(window, dtype=torch.float32).unsqueeze(0)

                logits = model(x).squeeze() / TEMPERATURE
                probs  = torch.softmax(logits, dim=-1).numpy()

                prob_buffer.append(probs)
                smoothed_probs = np.mean(prob_buffer, axis=0)

                word = words[int(np.argmax(smoothed_probs))]
                app.root.after(0, app.update_prediction, word, smoothed_probs, words)

    except Exception as e:
        app.root.after(0, app.set_status, f"Error: {e}")
        print(f"Error: {e}")

# ── ENTRY POINT ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app = PredictApp()

    if USE_HARDCODED_FALLBACK:
        print("[DEMO MODE] Using hardcoded fallback — skipping model and board.")
        t = threading.Thread(target=hardcoded_worker, args=(app,), daemon=True)
    else:
        ckpt  = torch.load(MODEL_PATH, map_location='cpu', weights_only=False)
        words = ckpt['words']
        model = EEG_Model(n_cls=len(words))
        model.load_state_dict(ckpt['model_state'])
        model.eval()
        print(f"Model loaded. Words: {words}")
        t = threading.Thread(target=predict_worker, args=(app, model, words), daemon=True)

    t.start()
    app.run()