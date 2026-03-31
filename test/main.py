from ultralytics import YOLO
import cv2
import mediapipe as mp
import urllib.request
import os
from collections import deque

# =========================
# DOWNLOAD MEDIAPIPE MODEL
# =========================
model_path = "hand_landmarker.task"

if not os.path.exists(model_path):
    print("Downloading hand landmarker model...")
    url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
    urllib.request.urlretrieve(url, model_path)
    print("Download complete.")

# =========================
# LOAD YOLO MODEL
# =========================
model = YOLO("best.pt")

# =========================
# MEDIAPIPE HAND LANDMARKER
# =========================
BaseOptions = mp.tasks.BaseOptions
HandLandmarker = mp.tasks.vision.HandLandmarker
HandLandmarkerOptions = mp.tasks.vision.HandLandmarkerOptions
VisionRunningMode = mp.tasks.vision.RunningMode

options = HandLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=model_path),
    running_mode=VisionRunningMode.VIDEO,
    num_hands=1,
    min_hand_detection_confidence=0.7
)

# =========================
# SMOOTHING BUFFER
# =========================
history = deque(maxlen=10)

# =========================
# START CAMERA
# =========================
cap = cv2.VideoCapture(0)
timestamp_ms = 0

with HandLandmarker.create_from_options(options) as landmarker:

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # 🔥 NEW: track if hand exists
        hand_detected = False

        h, w, _ = frame.shape

        # Convert to RGB
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        timestamp_ms += 33
        result = landmarker.detect_for_video(mp_image, timestamp_ms)

        best_label = None
        best_conf = 0

        # =========================
        # HAND DETECTION
        # =========================
        if result.hand_landmarks:
            hand_detected = True   # 🔥 NEW

            for hand_landmarks in result.hand_landmarks:

                # Get bounding box
                x_coords = [lm.x * w for lm in hand_landmarks]
                y_coords = [lm.y * h for lm in hand_landmarks]

                x_min, x_max = int(min(x_coords)), int(max(x_coords))
                y_min, y_max = int(min(y_coords)), int(max(y_coords))

                # Padding
                pad = 80
                x_min = max(0, x_min - pad)
                y_min = max(0, y_min - pad)
                x_max = min(w, x_max + pad)
                y_max = min(h, y_max + pad)

                hand_crop = frame[y_min:y_max, x_min:x_max]

                if hand_crop.size != 0:

                    hand_crop = cv2.resize(hand_crop, (640, 640))

                    results = model(hand_crop, conf=0.25)

                    # Best prediction
                    for r in results:
                        for box in r.boxes:
                            cls_id = int(box.cls[0])
                            conf = float(box.conf[0])
                            label = model.names[cls_id]

                            if conf > best_conf:
                                best_conf = conf
                                best_label = label

                # Draw bounding box
                cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), (0,255,0), 2)

        else:
            # 🔥 NEW: clear old predictions
            history.clear()

        # =========================
        # SMOOTHING + DISPLAY
        # =========================
        if best_label and best_conf > 0.5:
            history.append(best_label)

        # 🔥 NEW: only show if hand exists
        if hand_detected and len(history) > 0:
            final_label = max(set(history), key=history.count)

            cv2.putText(frame, final_label,
                        (50, 80),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        2,
                        (0,255,0),
                        4)

        # =========================
        # DISPLAY
        # =========================
        cv2.imshow("ASL Detection", frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

cap.release()
cv2.destroyAllWindows()