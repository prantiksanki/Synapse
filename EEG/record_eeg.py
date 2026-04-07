import numpy as np
import time
import threading
import tkinter as tk
from tkinter import font as tkfont
from scipy.signal import butter, filtfilt
import brainflow
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds
import pickle
import random

WORDS         = ["YES", "NO", "LEFT", "RIGHT"]
TRIALS        = 50          # per word
TRIAL_SEC     = 3
REST_SEC      = 2
SAVE_PATH     = r'C:\eeg_demo\my_eeg_data.pkl'
N_CHANNELS    = 8
SFREQ         = 250
USE_SYNTHETIC = False
SERIAL_PORT   = 'COM5'

class RecordingApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("EEG Recording")
        self.root.geometry("640x400")
        self.root.configure(bg="#0d0d0d")
        self.root.resizable(False, False)
        title_font = tkfont.Font(family="Helvetica", size=13)
        word_font  = tkfont.Font(family="Helvetica", size=80, weight="bold")
        small_font = tkfont.Font(family="Helvetica", size=10)
        tk.Label(self.root, text="THINK THIS WORD:",
                 font=title_font, bg="#0d0d0d", fg="#444444").pack(pady=(28,0))
        self.word_var = tk.StringVar(value="READY")
        self.word_label = tk.Label(self.root, textvariable=self.word_var,
                                   font=word_font, bg="#0d0d0d", fg="#00FF88")
        self.word_label.pack(pady=4)
        self.status_var = tk.StringVar(value="Starting up...")
        tk.Label(self.root, textvariable=self.status_var,
                 font=title_font, bg="#0d0d0d", fg="#555555").pack()
        self.progress_var = tk.StringVar(value="")
        tk.Label(self.root, textvariable=self.progress_var,
                 font=small_font, bg="#0d0d0d", fg="#333333").pack(pady=(8,0))
        self.word_colors = {
            "YES":"#00FF88","NO":"#FF4444",
            "LEFT":"#FFD700","RIGHT":"#44AAFF",
            "REST":"#333333","READY":"#00FF88","DONE":"#00FF88",
        }

    def set_word(self, word):
        self.word_var.set(word)
        self.word_label.configure(fg=self.word_colors.get(word, "#FFFFFF"))

    def set_status(self, msg):
        self.status_var.set(msg)

    def set_progress(self, msg):
        self.progress_var.set(msg)

    def run(self):
        self.root.mainloop()

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

def preprocess(eeg):
    eeg = eeg - eeg.mean(axis=0)
    eeg = eeg / (eeg.std(axis=0) + 1e-6)
    return eeg

def record_worker(app):
    all_data = []
    try:
        app.root.after(0, app.set_status, "Connecting to board...")
        board, board_id = connect_board()
        eeg_channels = BoardShim.get_eeg_channels(board_id)[:N_CHANNELS]

        # Build fully randomised trial list — e.g. YES, RIGHT, NO, LEFT, YES, ...
        trial_list = []
        for label, word in enumerate(WORDS):
            trial_list += [(label, word)] * TRIALS
        random.shuffle(trial_list)  # randomise order completely

        total = len(trial_list)
        app.root.after(0, app.set_status, "Connected! Starting in 3 seconds...")
        time.sleep(3)

        for i, (label, word) in enumerate(trial_list):
            # REST period
            app.root.after(0, app.set_word, "REST")
            app.root.after(0, app.set_status, "Relax...")
            app.root.after(0, app.set_progress,
                f"Trial {i+1}/{total}  |  Next: {word}")
            time.sleep(REST_SEC)

            # Clear buffer before recording
            board.get_board_data()

            # Show word — think/whisper now
            app.root.after(0, app.set_word, word)
            app.root.after(0, app.set_status, "Whisper this word now!")
            time.sleep(TRIAL_SEC)

            # Collect data
            data = board.get_board_data()
            if data.shape[1] < SFREQ:
                print(f"Trial {i+1} skipped — not enough samples")
                continue

            eeg = data[eeg_channels, :int(TRIAL_SEC * SFREQ)].T
            all_data.append((eeg, label))

        board.stop_stream()
        board.release_session()

        with open(SAVE_PATH, 'wb') as f:
            pickle.dump({'data': all_data, 'words': WORDS}, f)

        app.root.after(0, app.set_word, "DONE")
        app.root.after(0, app.set_status,
            f"Saved {len(all_data)} trials to {SAVE_PATH}")
        app.root.after(0, app.set_progress,
            "Now run: python C:\\eeg_demo\\train_mine.py")

    except Exception as e:
        app.root.after(0, app.set_status, f"Error: {e}")
        print(f"Error: {e}")

if __name__ == "__main__":
    app = RecordingApp()
    t = threading.Thread(target=record_worker, args=(app,), daemon=True)
    t.start()
    app.run()
