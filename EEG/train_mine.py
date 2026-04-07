import pickle, torch, numpy as np
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.model_selection import train_test_split
from scipy.signal import butter, filtfilt

SAVE_PATH  = r'C:\eeg_demo\my_eeg_data.pkl'
MODEL_PATH = r'C:\eeg_demo\my_model.pt'
WORDS      = ["YES", "NO", "LEFT", "RIGHT"]
SFREQ      = 250
N_CHANNELS = 8

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
print(f"Using device: {device}")
if device.type == 'cuda':
    print(f"GPU: {torch.cuda.get_device_name(0)}")

# ── Model ──────────────────────────────────────────────────────────────────────
class EEG_Model(nn.Module):
    def __init__(self, n_ch=8, n_cls=4):
        super().__init__()
        self.cnn = nn.Sequential(
            nn.Conv1d(n_ch, 64, kernel_size=7, padding=3),
            nn.BatchNorm1d(64), nn.ELU(), nn.Dropout(0.4),
            nn.Conv1d(64, 128, kernel_size=5, padding=2),
            nn.BatchNorm1d(128), nn.ELU(), nn.Dropout(0.4),
            nn.AvgPool1d(kernel_size=2),
        )
        self.bilstm = nn.LSTM(128, 128, batch_first=True,
                              bidirectional=True, num_layers=2, dropout=0.3)
        self.gru    = nn.GRU(256, 128, batch_first=True, num_layers=2, dropout=0.3)
        self.fc = nn.Sequential(
            nn.Linear(128, 64), nn.ELU(), nn.Dropout(0.4),
            nn.Linear(64,  32), nn.ELU(), nn.Dropout(0.3),
            nn.Linear(32, n_cls)
        )

    def forward(self, x):
        x = self.cnn(x)
        x = x.permute(0, 2, 1)
        x, _ = self.bilstm(x)
        x, _ = self.gru(x)
        return self.fc(x[:, -1, :])

# ── Augmentation ───────────────────────────────────────────────────────────────
def augment(x):
    x = x + torch.randn_like(x) * 0.05
    scale = torch.FloatTensor(x.shape[0], x.shape[1], 1).uniform_(0.8, 1.2).to(x.device)
    x = x * scale
    shift = np.random.randint(-25, 25)
    x = torch.roll(x, shift, dims=2)
    return x

# ── Bandpass filter: removes DC offset + high freq noise ──────────────────────
def bandpass_filter(eeg, lo=1.0, hi=40.0, fs=SFREQ):
    """eeg: (time, channels) raw microvolts -> filtered"""
    nyq = fs / 2.0
    b, a = butter(4, [lo / nyq, hi / nyq], btype='band')
    return filtfilt(b, a, eeg, axis=0)

# ── Full preprocessing pipeline ────────────────────────────────────────────────
def preprocess(eeg):
    """
    eeg: (time, channels) raw microvolts
    1. Bandpass 1-40Hz — removes DC offset and muscle noise
    2. Z-score normalize per channel
    3. Transpose to (channels, time) for Conv1d
    """
    eeg = bandpass_filter(eeg)              # removes DC + high freq
    eeg = eeg - eeg.mean(axis=0)           # zero mean
    eeg = eeg / (eeg.std(axis=0) + 1e-6)  # unit variance
    return eeg.T                            # (channels, time)

# ── Load data ──────────────────────────────────────────────────────────────────
with open(SAVE_PATH, 'rb') as f:
    d = pickle.load(f)

min_len = min(np.array(s[0]).shape[0] for s in d['data'])
print(f"Min trial length: {min_len} samples")
print("Applying bandpass filter (1-40Hz) + normalization to all trials...")

X_all = np.array([preprocess(np.array(s[0])[:min_len, :]) for s in d['data']])
y_all = np.array([s[1] for s in d['data']])

print(f"Loaded {len(X_all)} trials. Shape: {X_all.shape}")
print(f"Label distribution: { {i: int((y_all==i).sum()) for i in range(4)} }")
print(f"Sample mean after filter (should be ~0): {X_all[0].mean():.6f}")
print(f"Sample std  after filter (should be ~1): {X_all[0].std():.4f}")

# Check if classes look different now
print("\nMean signal power per class (should differ between classes):")
for i in range(4):
    power = np.abs(X_all[y_all==i]).mean()
    print(f"  {WORDS[i]}: {power:.4f}")

X_train, X_val, y_train, y_val = train_test_split(
    X_all, y_all, test_size=0.2, random_state=42, stratify=y_all
)
print(f"\nTrain: {len(X_train)}  Val: {len(X_val)}")

def to_tensors(X, y):
    return (torch.tensor(X, dtype=torch.float32).to(device),
            torch.tensor(y, dtype=torch.long).to(device))

X_tr, y_tr = to_tensors(X_train, y_train)
X_vl, y_vl = to_tensors(X_val,   y_val)

train_loader = DataLoader(TensorDataset(X_tr, y_tr), batch_size=16, shuffle=True)
val_loader   = DataLoader(TensorDataset(X_vl, y_vl), batch_size=16, shuffle=False)

model = EEG_Model().to(device)
opt   = torch.optim.AdamW(model.parameters(), lr=3e-4, weight_decay=1e-3)
sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=200)
crit  = nn.CrossEntropyLoss(label_smoothing=0.1)

best_val_acc = 0
best_state   = None

for epoch in range(200):
    model.train()
    tr_loss, tr_correct, tr_total = 0, 0, 0
    for xb, yb in train_loader:
        xb    = augment(xb)
        preds = model(xb)
        loss  = crit(preds, yb)
        opt.zero_grad(); loss.backward(); opt.step()
        tr_loss    += loss.item()
        tr_correct += (preds.argmax(1) == yb).sum().item()
        tr_total   += len(yb)
    sched.step()

    model.eval()
    vl_correct, vl_total = 0, 0
    with torch.no_grad():
        for xb, yb in val_loader:
            preds       = model(xb)
            vl_correct += (preds.argmax(1) == yb).sum().item()
            vl_total   += len(yb)

    tr_acc  = 100 * tr_correct / tr_total
    val_acc = 100 * vl_correct / vl_total

    if val_acc > best_val_acc:
        best_val_acc = val_acc
        best_state   = {k: v.clone() for k, v in model.state_dict().items()}

    if (epoch+1) % 20 == 0:
        print(f"Epoch {epoch+1:3d}/200  "
              f"train_loss={tr_loss/len(train_loader):.4f}  "
              f"train_acc={tr_acc:.1f}%  "
              f"val_acc={val_acc:.1f}%  "
              f"[best_val={best_val_acc:.1f}%]")

model.load_state_dict(best_state)
torch.save({'model_state': {k: v.cpu() for k, v in model.state_dict().items()},
            'words': WORDS}, MODEL_PATH)
print(f"\nBest validation accuracy: {best_val_acc:.1f}%")
print(f"Model saved to {MODEL_PATH}")
print("Now run: python C:\\eeg_demo\\predict_live.py")