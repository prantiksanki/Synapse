import torch, numpy as np, time, threading, collections
import tkinter as tk
from tkinter import font as tkfont
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

MODEL_PATH     = r'C:\eeg_demo\my_model.pt'
N_CHANNELS     = 8
SFREQ          = 250
WINDOW_SAMPLES = 750   # 3 seconds at 250Hz — matches TRIAL_SEC in record_eeg.py
STEP_SEC       = 0.5
USE_SYNTHETIC  = False
SERIAL_PORT    = 'COM5'
TEMPERATURE    = 1.5
SMOOTH_WINDOW  = 3

WORD_COLORS = {
    "YES":"#00FF88","NO":"#FF4444",
    "LEFT":"#FFD700","RIGHT":"#44AAFF","---":"#333333",
}

# ── MUST match train_mine.py exactly ──────────────────────────────────────────
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

# ── Preprocessing — same as train_mine.py normalize() ─────────────────────────
def preprocess(eeg):
    """eeg: (time, channels) raw -> normalised -> (channels, time)"""
    eeg = eeg - eeg.mean(axis=0)
    eeg = eeg / (eeg.std(axis=0) + 1e-6)
    return eeg.T  # (channels, time)

def connect_board():
    params = BrainFlowInputParams()
    if USE_SYNTHETIC:
        params.ip_address = "225.1.1.1"
        params.ip_port    = 6677
        board_id = BoardIds.SYNTHETIC_BOARD
    else:
        params.serial_port = SERIAL_PORT
        board_id = BoardIds.CYTON_BOARD
    board = BoardShim(board_id, params)
    board.prepare_session()
    board.start_stream()
    return board, board_id

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
        for word in ["YES","NO","LEFT","RIGHT"]:
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

    def update_prediction(self, word, probs, words):
        self.word_var.set(word)
        self.word_label.configure(fg=WORD_COLORS.get(word, "#FFFFFF"))
        for i, w in enumerate(words):
            p = float(probs[i])
            canvas = self.conf_bars[w]
            canvas.delete("all")
            bar_h = int(p * 120)
            canvas.create_rectangle(0, 120-bar_h, 40, 120,
                                    fill=WORD_COLORS[w], outline="")
            self.conf_labels[w].configure(text=f"{int(p*100)}%")
        self._history.append(word)
        self.history_var.set("  ->  ".join(self._history))

    def set_status(self, msg):
        self.status_var.set(msg)

    def run(self):
        self.root.mainloop()

def predict_worker(app, model, words):
    try:
        app.root.after(0, app.set_status, "Connecting to board...")
        board, board_id = connect_board()
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
                eeg_chunk = chunk[eeg_channels, :].T  # (time, channels)
                ring.extend(eeg_chunk.tolist())
                if len(ring) < WINDOW_SAMPLES:
                    app.root.after(0, app.set_status,
                        f"Buffering... {len(ring)}/{WINDOW_SAMPLES}")
                    continue

                window = preprocess(np.array(ring))                          # (8, 750)
                x      = torch.tensor(window, dtype=torch.float32).unsqueeze(0)  # (1, 8, 750)

                logits = model(x).squeeze() / TEMPERATURE
                probs  = torch.softmax(logits, dim=-1).numpy()

                prob_buffer.append(probs)
                smoothed_probs = np.mean(prob_buffer, axis=0)

                word = words[int(np.argmax(smoothed_probs))]
                app.root.after(0, app.update_prediction, word, smoothed_probs, words)

    except Exception as e:
        app.root.after(0, app.set_status, f"Error: {e}")
        print(f"Error: {e}")

if __name__ == "__main__":
    ckpt  = torch.load(MODEL_PATH, map_location='cpu', weights_only=False)
    words = ckpt['words']
    model = EEG_Model(n_cls=len(words))
    model.load_state_dict(ckpt['model_state'])
    model.eval()
    print(f"Model loaded. Words: {words}")
    app = PredictApp()
    t = threading.Thread(target=predict_worker, args=(app, model, words), daemon=True)
    t.start()
    app.run()