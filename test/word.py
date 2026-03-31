import mediapipe as mp
import numpy as np

# ==========================================
# Load your trained YOLO model
# ==========================================
# Replace with the path of your trained model
model = YOLO("best_word.pt")

# ==========================================
# Initialize MediaPipe Hands
# ==========================================
mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils

hands = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=1,
    min_detection_confidence=0.6,
    min_tracking_confidence=0.6
)

# ==========================================
# Open webcam
# ==========================================
cap = cv2.VideoCapture(0)

# Optional: set camera size
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

predicted_label = ""

while True:
    ret, frame = cap.read()
    if not ret:
        break

    frame = cv2.flip(frame, 1)
    h, w, _ = frame.shape

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    result = hands.process(rgb)

    # --------------------------------------
    # If a hand is detected
    # --------------------------------------
    if result.multi_hand_landmarks:
        for hand_landmarks in result.multi_hand_landmarks:

            # Draw landmarks
            mp_draw.draw_landmarks(
                frame,
                hand_landmarks,
                mp_hands.HAND_CONNECTIONS,
                mp_draw.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2),
                mp_draw.DrawingSpec(color=(255, 255, 255), thickness=2)
            )

            # Get bounding box from landmarks
            x_list = []
            y_list = []

            for lm in hand_landmarks.landmark:
                x_list.append(int(lm.x * w))
                y_list.append(int(lm.y * h))

            x_min = max(min(x_list) - 30, 0)
            y_min = max(min(y_list) - 30, 0)
            x_max = min(max(x_list) + 30, w)
            y_max = min(max(y_list) + 30, h)

            # Draw hand bounding box
            cv2.rectangle(frame, (x_min, y_min), (x_max, y_max), (255, 0, 255), 2)

            # Crop hand
            hand_crop = frame[y_min:y_max, x_min:x_max]

            if hand_crop.size != 0:
                # Run YOLO prediction on cropped hand
                results = model.predict(
                    source=hand_crop,
                    conf=0.5,
                    verbose=False
                )

                if len(results) > 0:
                    boxes = results[0].boxes

                    if boxes is not None and len(boxes) > 0:
                        # Take highest confidence prediction
                        confs = boxes.conf.cpu().numpy()
                        class_ids = boxes.cls.cpu().numpy().astype(int)

                        best_index = np.argmax(confs)
                        best_class = class_ids[best_index]
                        best_conf = confs[best_index]

                        predicted_label = f"{model.names[best_class]}  {best_conf:.2f}"

                        # Show prediction above hand
                        cv2.rectangle(
                            frame,
                            (x_min, y_min - 40),
                            (x_max, y_min),
                            (255, 0, 255),
                            -1
                        )

                        cv2.putText(
                            frame,
                            predicted_label,
                            (x_min + 5, y_min - 10),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.8,
                            (255, 255, 255),
                            2
                        )

    else:
        predicted_label = "No Hand Detected"
        cv2.putText(
            frame,
            predicted_label,
            (20, 50),
            cv2.FONT_HERSHEY_SIMPLEX,
            1,
            (0, 0, 255),
            2
        )

    cv2.imshow("Real-Time Sign Language Detection", frame)

    key = cv2.waitKey(1)
    if key == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()