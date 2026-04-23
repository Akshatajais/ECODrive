#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include "DHT.h"
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>
#include <PubSubClient.h>   // ADDED

// ===== OPTIONAL ESP32-CAM SUPPORT =====
// Enable only when compiling for an ESP32-CAM board (e.g., AI Thinker).
// Note: ESP32-CAM pinout conflicts with many GPIOs used for LCD/DHT on standard ESP32 dev boards.
// Build with: -DENABLE_CAMERA (PlatformIO) or add `#define ENABLE_CAMERA` below.
// #define ENABLE_CAMERA
#ifdef ENABLE_CAMERA
#include "esp_camera.h"
#include <WebServer.h>

// AI Thinker ESP32-CAM pin map
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

static WebServer cameraServer(81);
static WiFiServer streamServer(82); // MJPEG stream

static void handleCapture() {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    cameraServer.send(500, "text/plain", "camera capture failed");
    return;
  }
  cameraServer.sendHeader("Content-Type", "image/jpeg");
  cameraServer.sendHeader("Content-Disposition", "inline; filename=capture.jpg");
  cameraServer.sendHeader("Content-Length", String(fb->len));
  cameraServer.send(200);
  WiFiClient client = cameraServer.client();
  client.write(fb->buf, fb->len);
  esp_camera_fb_return(fb);
}

// Simple MJPEG multipart stream (works with many browser/clients)
static void handleStream() {
  WiFiClient client = streamServer.available();
  if (!client) return;

  client.setTimeout(5);
  // Read and ignore the HTTP request (minimal parsing)
  while (client.connected() && client.available()) {
    String line = client.readStringUntil('\n');
    if (line == "\r") break;
  }

  client.print(
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
    "Cache-Control: no-cache\r\n"
    "Connection: close\r\n\r\n"
  );

  while (client.connected()) {
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) break;

    client.print("--frame\r\n");
    client.print("Content-Type: image/jpeg\r\n");
    client.print("Content-Length: " + String(fb->len) + "\r\n\r\n");
    client.write(fb->buf, fb->len);
    client.print("\r\n");

    esp_camera_fb_return(fb);
    delay(80); // ~12 fps target
  }
  client.stop();
}

static bool initCamera() {
  camera_config_t c;
  c.ledc_channel = LEDC_CHANNEL_0;
  c.ledc_timer = LEDC_TIMER_0;
  c.pin_d0 = Y2_GPIO_NUM;
  c.pin_d1 = Y3_GPIO_NUM;
  c.pin_d2 = Y4_GPIO_NUM;
  c.pin_d3 = Y5_GPIO_NUM;
  c.pin_d4 = Y6_GPIO_NUM;
  c.pin_d5 = Y7_GPIO_NUM;
  c.pin_d6 = Y8_GPIO_NUM;
  c.pin_d7 = Y9_GPIO_NUM;
  c.pin_xclk = XCLK_GPIO_NUM;
  c.pin_pclk = PCLK_GPIO_NUM;
  c.pin_vsync = VSYNC_GPIO_NUM;
  c.pin_href = HREF_GPIO_NUM;
  c.pin_sccb_sda = SIOD_GPIO_NUM;
  c.pin_sccb_scl = SIOC_GPIO_NUM;
  c.pin_pwdn = PWDN_GPIO_NUM;
  c.pin_reset = RESET_GPIO_NUM;
  c.xclk_freq_hz = 20000000;
  c.pixel_format = PIXFORMAT_JPEG;

  c.frame_size = FRAMESIZE_VGA;
  c.jpeg_quality = 12;
  c.fb_count = 1;

  const esp_err_t err = esp_camera_init(&c);
  return err == ESP_OK;
}
#endif

// ===== LCD =====
LiquidCrystal_I2C lcd(0x27, 16, 2);

// ===== MQ7 =====
#define MQ7_PIN 34

// ===== DHT =====
#define DHTPIN 4
#define DHTTYPE DHT22
DHT dht(DHTPIN, DHTTYPE);

// ===== WIFI =====
#define WIFI_SSID "Galaxy"
#define WIFI_PASSWORD "ecodrive"

// ===== MQTT =====
const char* mqtt_server = "broker.hivemq.com";
const int mqtt_port = 1883;
const char* mqtt_topic = "ecodrive/pollution";

WiFiClient espClient;
PubSubClient mqttClient(espClient);

// ===== FIREBASE =====
#define API_KEY "AIzaSyBjlXZlC8fQiNmSLMzmQF-m5PjUxkxLWlc"
#define DATABASE_URL "https://ecodrive-85155-default-rtdb.firebaseio.com/"
#define USER_EMAIL "ecodrive@test.com"
#define USER_PASSWORD "test1234"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

unsigned long lastUpdate = 0;
int interval = 5000;

// ===== MQ7 CALIBRATION =====
int cleanAir = 140;
int maxSmoke = 600;

// ================= MQTT RECONNECT =================
void reconnectMQTT() {
  while (!mqttClient.connected()) {
    Serial.print("Connecting MQTT...");
    if (mqttClient.connect("EcoDriveESP32")) {
      Serial.println("connected");
    } else {
      Serial.print("failed rc=");
      Serial.println(mqttClient.state());
      delay(2000);
    }
  }
}

// ================= TIME =================
String getIST() {
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

String getDateOnly() {
  time_t now = time(nullptr);
  struct tm t;
  localtime_r(&now, &t);

  char buffer[16];
  sprintf(buffer, "%04d-%02d-%02d",
          t.tm_year + 1900,
          t.tm_mon + 1,
          t.tm_mday);
  return String(buffer);
}

String getTimeOnly() {
  time_t now = time(nullptr);
  struct tm t;
  localtime_r(&now, &t);

  char buffer[16];
  sprintf(buffer, "%02d-%02d-%02d",
          t.tm_hour,
          t.tm_min,
          t.tm_sec);
  return String(buffer);
}

// ================= MQ7 SCORE =================
int calculateEmissionScore(int rawGas) {
  int score = map(rawGas, cleanAir, maxSmoke, 50, 500);
  return constrain(score, 50, 500);
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);

  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("Starting...");

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
  }

  dht.begin();

  configTime(19800, 0, "pool.ntp.org", "time.nist.gov");

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  mqttClient.setServer(mqtt_server, mqtt_port);   // ADDED

#ifdef ENABLE_CAMERA
  if (initCamera()) {
    cameraServer.on("/capture", HTTP_GET, handleCapture);
    cameraServer.begin();
    streamServer.begin();

    const String ip = WiFi.localIP().toString();
    const String streamUrl = "http://" + ip + ":82";
    FirebaseJson camJson;
    camJson.set("streamUrl", streamUrl);
    camJson.set("captureUrl", "http://" + ip + ":81/capture");
    camJson.set("timestamp", getIST());
    Firebase.RTDB.setJSON(&fbdo, "/carEmissions/camera", &camJson);

    Serial.print("Camera capture: http://");
    Serial.print(ip);
    Serial.println(":81/capture");
    Serial.print("Camera stream:  ");
    Serial.print(ip);
    Serial.println(":82");
  } else {
    Serial.println("Camera init failed");
  }
#endif

  lcd.clear();
}

// ================= LOOP =================
void loop() {

  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();

#ifdef ENABLE_CAMERA
  cameraServer.handleClient();
  handleStream();
#endif

  if (Firebase.ready() && millis() - lastUpdate > interval) {
    lastUpdate = millis();

    int rawGas = analogRead(MQ7_PIN);
    float temperature = dht.readTemperature();
    float humidity = dht.readHumidity();

    if (isnan(temperature) || isnan(humidity)) return;

    int emissionScore = calculateEmissionScore(rawGas);

    String fullTime = getIST();
    String dateFolder = getDateOnly();
    String timeKey = getTimeOnly();

    // ===== LCD =====
    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print("Em:");
    lcd.print(emissionScore);
    lcd.print(" T:");
    lcd.print(temperature, 0);

    lcd.setCursor(0, 1);
    lcd.print("Gas:");
    lcd.print(rawGas);

    // ===== FIREBASE =====
    FirebaseJson json;
    json.set("rawGas", rawGas);
    json.set("temperature", temperature);
    json.set("humidity", humidity);
    json.set("emissionScore", emissionScore);
    json.set("timestamp", fullTime);

    Firebase.RTDB.setJSON(&fbdo, "/carEmissions/liveData", &json);

    String historyPath = "/carEmissions/history/" + dateFolder + "/" + timeKey;
    Firebase.RTDB.setJSON(&fbdo, historyPath.c_str(), &json);

    if (emissionScore >= 400) {
      FirebaseJson alertJson;
      alertJson.set("emissionScore", emissionScore);
      alertJson.set("message", "High emission event");
      alertJson.set("timestamp", fullTime);

      String alertId = dateFolder + "_" + timeKey;
      Firebase.RTDB.setJSON(&fbdo, ("/carEmissions/alerts/" + alertId).c_str(), &alertJson);
    }

    // ===== MQTT =====
    String mqttPayload = "{";
    mqttPayload += "\"rawGas\":" + String(rawGas) + ",";
    mqttPayload += "\"temperature\":" + String(temperature, 2) + ",";
    mqttPayload += "\"humidity\":" + String(humidity, 2) + ",";
    mqttPayload += "\"emissionScore\":" + String(emissionScore) + ",";
    mqttPayload += "\"timestamp\":\"" + fullTime + "\"";
    mqttPayload += "}";

    bool ok = mqttClient.publish(mqtt_topic, mqttPayload.c_str());

    if (ok) {
      Serial.println("MQTT sent");
    } else {
      Serial.println("MQTT failed");
    }

    Serial.print("Gas: ");
    Serial.print(rawGas);
    Serial.print(" Score: ");
    Serial.println(emissionScore);
  }
}