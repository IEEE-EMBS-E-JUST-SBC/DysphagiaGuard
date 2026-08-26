/*
  DysphagiaGuard — CONTINUOUS RAW IMU STREAMING firmware for the MYOSA Mini kit
  ---------------------------------------------------------------------------
  DEBUG BUILD: adds verbose logging around the status string and buzzer
  state so we can find out WHY the buzzer only ever does one thing
  regardless of status. Once confirmed, strip the extra Serial prints.

  Two most likely causes (see comments marked >>> BUG CANDIDATE):
   1) BUZZER_ACTIVE_LOW polarity mismatch for your specific buzzer module.
   2) The string coming back from Firebase isn't a clean "Normal" — it may
      have quotes, whitespace, or a totally different value than you think,
      which means equalsIgnoreCase("Normal") never matches.
  ---------------------------------------------------------------------------
*/

#include <Wire.h>
#include <AccelAndGyro.h>
#include <oled.h>

#include <WiFi.h>
#include <FirebaseESP32.h>

// ---------------------------------------------------------------------------
// Objects
// ---------------------------------------------------------------------------
AccelAndGyro imu;
oLed display(SCREEN_WIDTH, SCREEN_HEIGHT);

FirebaseData   fbdo;
FirebaseAuth   fbAuth;
FirebaseConfig fbConfig;
bool firebaseReady = false;

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const uint8_t BUZZER_PIN = 12;
const uint16_t BUZZER_BLINK_INTERVAL_MS = 1000;

// >>> BUG CANDIDATE #1: polarity.
// If the buzzer rings when it should be silent (Normal) and stays silent /
// stuck when it should alert, flip this to true and re-flash.
const bool BUZZER_ACTIVE_LOW = false;

inline void buzzerWrite(bool on) {
  bool pinState = (on != BUZZER_ACTIVE_LOW);
  digitalWrite(BUZZER_PIN, pinState ? HIGH : LOW);
  // Debug: confirm what's actually being written to the pin
  Serial.print("[BUZZER] logical on=");
  Serial.print(on ? "TRUE" : "FALSE");
  Serial.print(" -> pin=");
  Serial.println(pinState ? "HIGH" : "LOW");
}

const uint16_t SAMPLE_INTERVAL_MS = 10;  // ~100 Hz, must match feature_stats.json
const uint16_t STATUS_POLL_INTERVAL_MS = 500;

// ---------------------------------------------------------------------------
// WiFi / Firebase config
// ---------------------------------------------------------------------------
#define WIFI_SSID          "ESP32Test"
#define WIFI_PASSWORD      "00000000"
#define FIREBASE_HOST      "https://abdelrahman-wael-default-rtdb.firebaseio.com/"

// NOTE: this looks like a Firebase database secret, not a user ID token.
// Treat it as compromised now that it's been shared in plaintext — rotate
// it in the Firebase console (Project Settings > Service Accounts / Database
// Secrets) once you're done debugging.
#define FIREBASE_AUTH_TOKEN "iKHCscSADXAKlz6S6lVaOPyXUgAGU4n9TVGPYAge"

#define DEVICE_ID          "dysphagiaguard-01"
#define FB_LIVE_PATH        "/devices/" DEVICE_ID "/live"
#define FB_STATUS_PATH       "/devices/" DEVICE_ID "/status"

const uint16_t WIFI_CONNECT_TIMEOUT_MS = 15000;

// ---------------------------------------------------------------------------
// Debug switch: set to true to bypass Firebase entirely and cycle through
// statuses locally every few seconds. Use this FIRST to confirm the buzzer
// hardware + buzzerWrite() logic works correctly in isolation.
// ---------------------------------------------------------------------------
#define LOCAL_STATUS_TEST_MODE false
const unsigned long LOCAL_TEST_CYCLE_MS = 5000;
unsigned long lastLocalCycleMs = 0;
uint8_t localCycleIndex = 0;
const char* localCycleStatuses[] = {"Normal", "Aspiration", "Delayed"};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
unsigned long lastSampleMs = 0;
unsigned long sampleCounter = 0;

unsigned long lastStatusPollMs = 0;
String currentStatus = "Normal";
bool statusChanged = true;

unsigned long lastBuzzerToggleMs = 0;
bool buzzerOn = false;

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Wire.begin();

  pinMode(BUZZER_PIN, OUTPUT);
  buzzerWrite(false);

  bool imuOk = imu.begin();
  bool oledOk = display.begin();

  Serial.print("IMU: ");    Serial.println(imuOk  ? "OK" : "NOT FOUND");
  Serial.print("OLED: ");   Serial.println(oledOk ? "OK" : "NOT FOUND");
  Serial.println("Buzzer: Initialized via Direct GPIO");
  Serial.print("BUZZER_ACTIVE_LOW = ");
  Serial.println(BUZZER_ACTIVE_LOW ? "true" : "false");
  Serial.print("LOCAL_STATUS_TEST_MODE = ");
  Serial.println(LOCAL_STATUS_TEST_MODE ? "true" : "false");

  if (oledOk) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("DysphagiaGuard");
    display.setCursor(0, 16);
    display.print(imuOk ? "Streaming..." : "IMU MISSING");
    display.display();
  }

#if !LOCAL_STATUS_TEST_MODE
  connectWiFi();
  setupFirebase();
#else
  Serial.println("LOCAL TEST MODE: skipping WiFi/Firebase, cycling statuses locally.");
#endif
}

// ---------------------------------------------------------------------------
// WiFi connect (blocking, with timeout)
// ---------------------------------------------------------------------------
void connectWiFi() {
  Serial.print("Connecting to WiFi");
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < WIFI_CONNECT_TIMEOUT_MS) {
    delay(250);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("WiFi OK, IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi FAILED (will retry in loop)");
  }
}

// ---------------------------------------------------------------------------
// Firebase Realtime Database setup
// ---------------------------------------------------------------------------
void setupFirebase() {
  fbConfig.database_url = FIREBASE_HOST;
  fbConfig.signer.tokens.legacy_token = FIREBASE_AUTH_TOKEN;

  Firebase.begin(&fbConfig, &fbAuth);
  Firebase.reconnectWiFi(true);

  firebaseReady = true;
  Serial.println("Firebase initialized");
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------
void loop() {
  unsigned long now = millis();

#if LOCAL_STATUS_TEST_MODE
  // Bypass Firebase: cycle through statuses locally to isolate hardware/logic bugs
  if (now - lastLocalCycleMs >= LOCAL_TEST_CYCLE_MS) {
    lastLocalCycleMs = now;
    localCycleIndex = (localCycleIndex + 1) % 3;
    String newStatus = String(localCycleStatuses[localCycleIndex]);
    if (newStatus != currentStatus) {
      currentStatus = newStatus;
      statusChanged = true;
      Serial.print(">>> LOCAL TEST: switching status to [");
      Serial.print(currentStatus);
      Serial.println("]");
    }
  }
#else
  // -- IMU sampling (~100 Hz) --
  if (now - lastSampleMs >= SAMPLE_INTERVAL_MS) {
    lastSampleMs = now;

    if (imu.ping()) {
      float ax = imu.getAccelX(false);
      float ay = imu.getAccelY(false);
      float az = imu.getAccelZ(false);
      float gx = imu.getGyroX(false);
      float gy = imu.getGyroY(false);
      float gz = imu.getGyroZ(false);

      sendSampleToFirebase(ax, ay, az, gx, gy, gz, now);
      sampleCounter++;
    }
  }

  // -- Status polling (~500ms) --
  if (now - lastStatusPollMs >= STATUS_POLL_INTERVAL_MS) {
    lastStatusPollMs = now;
    pollStatusFromFirebase();
  }
#endif

  // -- Buzzer pattern --
  updateBuzzerBlink(now);

  // -- OLED refresh --
  if (statusChanged || sampleCounter % 100 == 0) {
    showStatusOnOled();
    statusChanged = false;
  }
}

// ---------------------------------------------------------------------------
// Firebase send (IMU live samples)
// ---------------------------------------------------------------------------
void sendSampleToFirebase(float ax, float ay, float az,
                          float gx, float gy, float gz,
                          unsigned long timestampMs) {
  if (!firebaseReady || WiFi.status() != WL_CONNECTED) return;

  FirebaseJson json;
  json.set("ax", ax);
  json.set("ay", ay);
  json.set("az", az);
  json.set("gx", gx);
  json.set("gy", gy);
  json.set("gz", gz);
  json.set("t", (double)timestampMs);

  if (!Firebase.setJSON(fbdo, FB_LIVE_PATH, json)) {
    Serial.print("Firebase write failed: ");
    Serial.println(fbdo.errorReason());
  }
}

// ---------------------------------------------------------------------------
// Firebase read (status: Normal / Aspiration / Delayed)
// ---------------------------------------------------------------------------
void pollStatusFromFirebase() {
  if (!firebaseReady || WiFi.status() != WL_CONNECTED) return;

  if (Firebase.getString(fbdo, FB_STATUS_PATH)) {
    String newStatus = fbdo.stringData();

    // >>> BUG CANDIDATE #2: inspect the raw value. If RTDB stores this leaf
    // as a JSON-quoted string, or there's stray whitespace, the comparison
    // against "Normal" will silently fail forever and shouldAlert will
    // always be true (or always false, depending on what leaks through).
    Serial.print("[FIREBASE] raw status = [");
    Serial.print(newStatus);
    Serial.print("] length=");
    Serial.println(newStatus.length());

    newStatus.trim();
    newStatus.replace("\"", "");  // strip stray JSON quoting defensively

    if (newStatus.length() > 0 && newStatus != currentStatus) {
      Serial.print("[FIREBASE] status changed: [");
      Serial.print(currentStatus);
      Serial.print("] -> [");
      Serial.print(newStatus);
      Serial.println("]");
      currentStatus = newStatus;
      statusChanged = true;
    }
  } else {
    Serial.print("Firebase status read failed: ");
    Serial.println(fbdo.errorReason());
  }
}

// ---------------------------------------------------------------------------
// Buzzer logic — Normal: silent. Anything else: ring 1s / silent 1s.
// ---------------------------------------------------------------------------
void updateBuzzerBlink(unsigned long now) {
  currentStatus.trim();

  bool shouldAlert = !currentStatus.equalsIgnoreCase("Normal");

  // Debug: print once per loop pass so you can see exactly what decision
  // is being made and why, alongside the [BUZZER] pin logs from buzzerWrite().
  static unsigned long lastDebugPrintMs = 0;
  if (now - lastDebugPrintMs >= 1000) {
    lastDebugPrintMs = now;
    Serial.print("[LOGIC] currentStatus=[");
    Serial.print(currentStatus);
    Serial.print("] shouldAlert=");
    Serial.println(shouldAlert ? "TRUE" : "FALSE");
  }

  if (!shouldAlert) {
    if (buzzerOn) buzzerWrite(false);  // only write on actual state change
    buzzerOn = false;
    lastBuzzerToggleMs = now;
    return;
  }

  if (now - lastBuzzerToggleMs >= BUZZER_BLINK_INTERVAL_MS) {
    lastBuzzerToggleMs = now;
    buzzerOn = !buzzerOn;
    buzzerWrite(buzzerOn);
  }
}

// ---------------------------------------------------------------------------
// OLED Status display
// ---------------------------------------------------------------------------
void showStatusOnOled() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("DysphagiaGuard");

  display.setCursor(0, 16);
  display.print("Status: ");
  display.print(currentStatus);

  display.setCursor(0, 32);
  display.print("Samples: ");
  display.print(sampleCounter);

  display.display();
}
