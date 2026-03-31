import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

MODEL_PATH = r'E:\Project\Synapse\best_model\models\hand_landmarker.task'

# ── Landmark drawing helpers (Tasks API replacement for mp.solutions.drawing_utils) ──
HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),
    (0,5),(5,6),(6,7),(7,8),
    (0,9),(9,10),(10,11),(11,12),
    (0,13),(13,14),(14,15),(15,16),
    (0,17),(17,18),(18,19),(19,20),
    (5,9),(9,13),(13,17),
]

def draw_landmarks(frame, landmarks, h, w):
    pts = [(int(lm.x * w), int(lm.y * h)) for lm in landmarks]
    for a, b in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], (0, 200, 0), 2)
    for x, y in pts:
        cv2.circle(frame, (x, y), 4, (255, 255, 255), -1)
        cv2.circle(frame, (x, y), 4, (0, 150, 255), 1)


# ── ASL A–Z + 0–9 rule-based classifier ──────────────────────────────────────
def classify_gesture(landmarks):
    if not landmarks:
        return 'Unknown'

    lm = landmarks

    def finger_extended(tip, pip):
        return lm[tip].y < lm[pip].y

    index_ext  = finger_extended(8, 6)
    middle_ext = finger_extended(12, 10)
    ring_ext   = finger_extended(16, 14)
    pinky_ext  = finger_extended(20, 18)
    thumb_ext  = lm[4].x > lm[3].x

    def dist(a, b):
        return np.hypot(lm[a].x - lm[b].x, lm[a].y - lm[b].y)

    ref = dist(0, 9) or 1.0

    # ---- A ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[4].y > lm[3].y and lm[4].y < lm[6].y):
        return 'A'

    # ---- B ----
    if (index_ext and middle_ext and ring_ext and pinky_ext
            and lm[4].x < lm[3].x):
        return 'B'

    # ---- C ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and 0.2 < dist(8, 4) / ref < 0.5):
        return 'C'

    # ---- D ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext
            and dist(4, 12) / ref < 0.15):
        return 'D'

    # ---- E ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[4].y > lm[2].y):
        return 'E'

    # ---- F ----
    if (middle_ext and ring_ext and pinky_ext and not index_ext
            and dist(4, 8) / ref < 0.12):
        return 'F'

    # ---- G ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].y - lm[6].y) < 0.05 and lm[8].x > lm[6].x):
        return 'G'

    # ---- H ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].y - lm[5].y) < 0.08):
        return 'H'

    # ---- J ---- (check before I: pinky + thumb)
    if (not index_ext and not middle_ext and not ring_ext and pinky_ext and thumb_ext):
        return 'J'

    # ---- I ----
    if (not index_ext and not middle_ext and not ring_ext and pinky_ext):
        return 'I'

    # ---- K ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and lm[4].y < lm[6].y):
        return 'K'

    # ---- L ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext and thumb_ext):
        return 'L'

    # ---- M ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[4].y > lm[2].y
            and lm[8].y > lm[5].y and lm[12].y > lm[9].y and lm[16].y > lm[13].y):
        return 'M'

    # ---- N ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[8].y > lm[5].y and lm[12].y > lm[9].y and lm[16].y < lm[13].y):
        return 'N'

    # ---- O ----
    if (dist(4, 8) / ref < 0.12 and dist(4, 12) / ref < 0.15
            and dist(4, 16) / ref < 0.18 and dist(4, 20) / ref < 0.20):
        return 'O'

    # ---- P ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and lm[8].y > lm[5].y):
        return 'P'

    # ---- Q ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[8].y > lm[6].y and lm[8].x > lm[6].x):
        return 'Q'

    # ---- R ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].x - lm[12].x) / ref < 0.08):
        return 'R'

    # ---- S ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[4].x > lm[8].x):
        return 'S'

    # ---- T ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[4].y < lm[8].y and lm[4].x < lm[8].x):
        return 'T'

    # ---- U ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].x - lm[12].x) / ref < 0.12):
        return 'U'

    # ---- V ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].x - lm[12].x) / ref >= 0.12):
        return 'V'

    # ---- W ----
    if (index_ext and middle_ext and ring_ext and not pinky_ext):
        return 'W'

    # ---- X ----
    if (not index_ext and not middle_ext and not ring_ext and not pinky_ext
            and lm[8].y < lm[5].y and lm[8].y > lm[6].y):
        return 'X'

    # ---- Y ----
    if (thumb_ext and pinky_ext and not index_ext and not middle_ext and not ring_ext):
        return 'Y'

    # ---- Z ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext
            and not thumb_ext and lm[8].x > lm[6].x):
        return 'Z'

    # ---- 0 ----
    if (dist(4, 8) / ref < 0.13 and dist(4, 12) / ref < 0.16
            and dist(4, 16) / ref < 0.19 and dist(4, 20) / ref < 0.21
            and not thumb_ext):
        return '0'

    # ---- 1 ----
    if (index_ext and not middle_ext and not ring_ext and not pinky_ext
            and not thumb_ext):
        return '1'

    # ---- 2 ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext
            and abs(lm[8].x - lm[12].x) / ref >= 0.12 and not thumb_ext):
        return '2'

    # ---- 3 ----
    if (index_ext and middle_ext and not ring_ext and not pinky_ext and thumb_ext):
        return '3'

    # ---- 4 ----
    if (index_ext and middle_ext and ring_ext and pinky_ext and not thumb_ext):
        return '4'

    # ---- 5 ----
    if (index_ext and middle_ext and ring_ext and pinky_ext and thumb_ext):
        return '5'

    # ---- 6 ----
    if (index_ext and middle_ext and ring_ext and not pinky_ext
            and dist(4, 20) / ref < 0.13):
        return '6'

    # ---- 7 ----
    if (index_ext and middle_ext and not ring_ext and pinky_ext
            and dist(4, 16) / ref < 0.13):
        return '7'

    # ---- 8 ----
    if (index_ext and not middle_ext and ring_ext and pinky_ext
            and dist(4, 12) / ref < 0.13):
        return '8'

    # ---- 9 ----
    if (middle_ext and ring_ext and pinky_ext and not index_ext
            and dist(4, 8) / ref < 0.13):
        return '9'

    return 'Unknown'


# ── MediaPipe Tasks: HandLandmarker setup ─────────────────────────────────────
base_options = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
options = vision.HandLandmarkerOptions(
    base_options=base_options,
    num_hands=1,
    min_hand_detection_confidence=0.7,
    min_hand_presence_confidence=0.7,
    min_tracking_confidence=0.5,
)
detector = vision.HandLandmarker.create_from_options(options)

# ── Main loop ─────────────────────────────────────────────────────────────────
cap = cv2.VideoCapture(0)

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    frame = cv2.flip(frame, 1)
    h, w, _ = frame.shape

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = detector.detect(mp_image)

    gesture = 'No hand detected'
    if result.hand_landmarks:
        for hand_lms in result.hand_landmarks:
            draw_landmarks(frame, hand_lms, h, w)
            gesture = classify_gesture(hand_lms)

    cv2.putText(frame, f'Sign: {gesture}', (10, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
    cv2.imshow('Sign Language Recognition', frame)

    if cv2.waitKey(1) & 0xFF == 27:
        break

cap.release()
cv2.destroyAllWindows()
