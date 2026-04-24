#include "esp_camera.h"
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <mbedtls/base64.h>
#include <time.h>
#include <memory>

// 🔑 Replace with your WiFi credentials
const char* ssid = "Galaxy";
const char* password = "ecodrive";

// ===== FIREBASE (same project as main.cpp) =====
#define API_KEY "AIzaSyBjlXZlC8fQiNmSLMzmQF-m5PjUxkxLWlc"
#define DATABASE_URL "https://ecodrive-85155-default-rtdb.firebaseio.com/"
#define USER_EMAIL "ecodrive@test.com"
#define USER_PASSWORD "test1234"

static FirebaseData fbdo;
static FirebaseAuth auth;
static FirebaseConfig firebaseConfig;

static const char* kEmissionScorePath = "/carEmissions/liveData/emissionScore";
static const char* kCaptureRootPath = "/carEmissions/alerts";

static const int kThreshold = 400;
static const unsigned long kPollIntervalMs = 2500;
static const unsigned long kCaptureCooldownMs = 30000;

static unsigned long lastPollMs = 0;
static unsigned long lastCaptureMs = 0;

// 📌 Select camera model
#define CAMERA_MODEL_AI_THINKER

// 📷 Pin configuration for AI Thinker ESP32-CAM
#if defined(CAMERA_MODEL_AI_THINKER)
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22
#endif

#include "esp_http_server.h"

// HTTP server handles
httpd_handle_t stream_httpd = NULL;

static String getIST() {
  time_t now = time(nullptr);
  struct tm timeinfo;
  localtime_r(&now, &timeinfo);

  char buffer[32];
  sprintf(buffer, "%04d-%02d-%02d %02d:%02d:%02d",
          timeinfo.tm_year + 1900,
          timeinfo.tm_mon + 1,
          timeinfo.tm_mday,
          timeinfo.tm_hour,
          timeinfo.tm_min,
          timeinfo.tm_sec);
  return String(buffer);
}

static String base64EncodeToString(const uint8_t* data, size_t len) {
  const size_t outLen = 4 * ((len + 2) / 3) + 1;
  std::unique_ptr<unsigned char[]> out(new unsigned char[outLen]);
  size_t olen = 0;

  const int rc = mbedtls_base64_encode(out.get(), outLen, &olen, data, len);
  if (rc != 0) return String();

  out[olen] = '\0';
  return String(reinterpret_cast<const char*>(out.get()));
}

static bool readEmissionScore(int& outScore) {
  if (!Firebase.ready()) return false;
  if (!Firebase.RTDB.getInt(&fbdo, kEmissionScorePath)) return false;
  if (fbdo.dataType() != "int") return false;
  outScore = fbdo.intData();
  return true;
}

static bool uploadCaptureToFirebase(camera_fb_t* fb, int emissionScore) {
  if (!fb || fb->len == 0) return false;

  const String ts = getIST();
  String alertId = ts;
  alertId.replace(" ", "_");
  alertId.replace(":", "-");

  const String path = String(kCaptureRootPath) + "/" + alertId;

  FirebaseJson payload;
  payload.set("timestamp", ts);
  payload.set("emissionScore", emissionScore);
  payload.set("message", "High emission snapshot (ESP32-CAM)");
  payload.set("imageFormat", "jpg");
  payload.set("imageBytes", (int)fb->len);
  payload.set("imagePath", path + "/image");

  // Avoid huge JSON (Base64) payloads: they frequently break TLS on ESP32-CAM.
  // Store metadata as JSON and the JPEG bytes as an RTDB blob.
  const bool metaOk = Firebase.RTDB.setJSON(&fbdo, path.c_str(), &payload);
  if (!metaOk) return false;

  return Firebase.RTDB.setBlob(&fbdo, (path + "/image").c_str(), fb->buf, fb->len);
}

// Stream handler
static esp_err_t stream_handler(httpd_req_t *req){
  camera_fb_t * fb = NULL;
  esp_err_t res = ESP_OK;

  res = httpd_resp_set_type(req, "multipart/x-mixed-replace; boundary=frame");

  while(true){
    fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("Camera capture failed");
      return ESP_FAIL;
    }

    res = httpd_resp_send_chunk(req, "--frame\r\n", strlen("--frame\r\n"));
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, "Content-Type: image/jpeg\r\n\r\n",
                                  strlen("Content-Type: image/jpeg\r\n\r\n"));
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char *)fb->buf, fb->len);
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, "\r\n", strlen("\r\n"));
    }

    esp_camera_fb_return(fb);

    if(res != ESP_OK){
      break;
    }
  }
  return res;
}

// Start server
void startCameraServer(){
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();

  httpd_uri_t stream_uri = {
    .uri       = "/",
    .method    = HTTP_GET,
    .handler   = stream_handler,
    .user_ctx  = NULL
  };

  if (httpd_start(&stream_httpd, &config) == ESP_OK) {
    httpd_register_uri_handler(stream_httpd, &stream_uri);
  }
}

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);

  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

  if(psramFound()){
    // Default stream size; upload capture will temporarily switch smaller.
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.frame_size = FRAMESIZE_QVGA;
    config.jpeg_quality = 12;
    config.fb_count = 2;
  } else {
    config.fb_location = CAMERA_FB_IN_DRAM;
    config.frame_size = FRAMESIZE_QQVGA;
    config.jpeg_quality = 14;
    config.fb_count = 1;
  }

  // Initialize camera
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed 0x%x", err);
    return;
  }

  // Connect WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connected!");

  // Time (IST) for readable alert IDs/timestamps
  configTime(19800, 0, "pool.ntp.org", "time.nist.gov");

  // Firebase init
  firebaseConfig.api_key = API_KEY;
  firebaseConfig.database_url = DATABASE_URL;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;
  Firebase.begin(&firebaseConfig, &auth);
  Firebase.reconnectWiFi(true);
  // Reduce SSL failures on constrained devices (ESP32-CAM).
  fbdo.setBSSLBufferSize(4096, 1024);  // rx, tx
  fbdo.setResponseSize(4096);

  startCameraServer();

  Serial.print("📸 Open camera: http://");
  Serial.println(WiFi.localIP());
}

void loop() {
  // Poll Firebase for current emission score
  const unsigned long now = millis();
  if (now - lastPollMs >= kPollIntervalMs) {
    lastPollMs = now;

    int score = -1;
    if (readEmissionScore(score)) {
      Serial.print("Firebase emissionScore: ");
      Serial.println(score);

      const bool over = score > kThreshold;
      const bool cooldownOk = (now - lastCaptureMs) >= kCaptureCooldownMs;

      if (over && cooldownOk) {
        Serial.println("Threshold exceeded; capturing & uploading snapshot...");

        // Temporarily switch to a smaller frame for upload reliability.
        sensor_t* s = esp_camera_sensor_get();
        framesize_t prev = FRAMESIZE_INVALID;
        if (s) {
          prev = s->status.framesize;
          s->set_framesize(s, FRAMESIZE_QQVGA);
          s->set_quality(s, 18);  // higher = more compression
        }

        camera_fb_t* fb = esp_camera_fb_get();
        if (!fb) {
          Serial.println("Camera capture failed");
        } else {
          const bool ok = uploadCaptureToFirebase(fb, score);
          esp_camera_fb_return(fb);

          // Restore stream quality/size after upload.
          if (s) {
            if (prev != FRAMESIZE_INVALID) s->set_framesize(s, prev);
            s->set_quality(s, 12);
          }

          if (ok) {
            lastCaptureMs = now;
            Serial.println("Snapshot uploaded to Firebase alerts.");
          } else {
            Serial.print("Upload failed: ");
            Serial.println(fbdo.errorReason());
          }
        }
      }
    } else if (Firebase.ready()) {
      Serial.print("Failed to read emissionScore: ");
      Serial.println(fbdo.errorReason());
    }
  }

  delay(10);
}