#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include "DHT.h"
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <time.h>
#include <PubSubClient.h>   // MQTT ADDED

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

// ===== MQTT FIRST BLOCK ADDED =====
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
int cleanAir = 200;
int maxSmoke = 700;

// ===== MQTT CONNECT FUNCTION =====
void reconnectMQTT() {
  while (!mqttClient.connected()) {
    if (mqttClient.connect("EcoDriveESP32")) {
      Serial.println("MQTT Connected");
    } else {
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

  byte heart[8] = {
  0b00000,
  0b01010,
  0b11111,
  0b11111,
  0b11111,
  0b01110,
  0b00100,
  0b00000
};

  lcd.createChar(0, heart);

  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();

  lcd.clear();

  lcd.setCursor(2, 0);
  lcd.write(byte(0));
  lcd.print(" Eco Drive");
  delay(2000);

  lcd.setCursor(2, 1);
  lcd.print("Starting...");
  delay(3000);

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

  mqttClient.setServer(mqtt_server, mqtt_port);   // MQTT ADDED

  lcd.clear();
}

// ================= LOOP =================
void loop() {

  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();

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

    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print("Em:");
    lcd.print(emissionScore);
    lcd.print(" T:");
    lcd.print(temperature, 0);

    lcd.setCursor(0, 1);
    lcd.print("Gas:");
    lcd.print(rawGas);

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

    // MQTT SEND
    String payload = "{";
    payload += "\"rawGas\":" + String(rawGas) + ",";
    payload += "\"temperature\":" + String(temperature) + ",";
    payload += "\"humidity\":" + String(humidity) + ",";
    payload += "\"emissionScore\":" + String(emissionScore);
    payload += "}";

    mqttClient.publish(mqtt_topic, payload.c_str());

    Serial.print("Gas: "); Serial.print(rawGas);
    Serial.print(" Score: "); Serial.println(emissionScore);
  }
}