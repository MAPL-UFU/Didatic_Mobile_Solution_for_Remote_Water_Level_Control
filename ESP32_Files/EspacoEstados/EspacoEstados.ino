#include <Arduino.h>
#include <WiFi.h>
#include "esp_wifi.h"
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "freertos/semphr.h"
#include <math.h>


// ==========================================================
// == CONFIGURAÇÃO DE SEGURANÇA E CONSTANTES
// ==========================================================
#define BLE_AUTH_KEY "LAB_CONTROLE_UFU_2025"

// --- Tópicos MQTT ---
#define MQTT_ID_TOPIC_IN "entradaid"
#define MQTT_HEARTBEAT_TOPIC_OUT "bancada/heartbeat"

// ==========================================================
// == CONFIGURAÇÃO DOS PINOS
// ==========================================================
// --- Sensor de Nível ---
#define echoPin 18
#define trigPin 5
// --- Bomba (Motor A) ---
#define PUMP_PWM_PIN 23
#define IN1 16
#define IN2 17
// --- Fita de LED (Motor B) ---
#define LED_PWM_PIN 25
#define LED_IN3 26
#define LED_IN4 27

// ==========================================================
// == CONFIGURAÇÃO BLE (UUIDs devem ser iguais aos do app)
// ==========================================================
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_RX "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHARACTERISTIC_UUID_TX "cba1d466-344c-4be3-ab3f-189f80dd7518"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristicTX = NULL;
bool deviceConnected = false;
bool bleClientAuthenticated = false;

// ==========================================================
// == ESTRUTURAS E VARIÁVEIS GLOBAIS
// ==========================================================

// --- Estrutura para os parâmetros de controle ---
typedef struct {
  float ref, nu, nx, k, ke;
} ControlParams;
ControlParams controlParams;
// --- Máquina de Estados Simplificada ---
enum SystemState {
  STATE_UNCONFIGURED,
  STATE_IDLE,
  STATE_READY,
  STATE_RUNNING,
  STATE_PAUSED
};
volatile SystemState systemState = STATE_UNCONFIGURED;

// --- Variáveis de Controle e Sensor ---
double x_chap = 0.0, u = 0.0;
float current_water_level_cm = 0.0;
const long INTERVAL_CONTROL = 100;
const long INTERVAL_COMMS = 500;
const float H_total = 37;
const byte qtdMedidas = 20;
float lectures[qtdMedidas];
byte lecture_index = 0;
float led_angle = 0;

// --- Variáveis de Conexão (Wi-Fi e MQTT) ---
WiFiClient espClient;
PubSubClient client(espClient);
bool brokerConfigured = false;
char saved_mqtt_ip[16];
int saved_mqtt_port;
char saved_mqtt_user[64], saved_mqtt_pass[64];
unsigned long lastMqttReconnectAttempt = 0;

// --- Variável para o Aluno Atual ---
char currentStudentID[20] = "";

// --- RTOS ---
TaskHandle_t controlTaskHandle;
TaskHandle_t commsTaskHandle;
SemaphoreHandle_t sharedDataMutex;

// ==========================================================
// == PROTÓTIPOS DE FUNÇÕES
// ==========================================================
void processJsonCommand(String json);
void connectToWifi(const char* ssid, const char* pass);
void connectToMqttBroker(const char* ip, int port, const char* user, const char* pass);
void mqtt_callback(char* topic, byte* payload, unsigned int length);
void sendJsonToClient(JsonDocument& doc);
void sendFeedbackToClient(const char* msg, bool success = true);
void subscribeToStudentTopics(const char* studentID);
void unsubscribeFromStudentTopics(const char* studentID);
void resetExperimentState();
void sendWifiFeedbackToClient(const char* msg, bool success = true);
void sendBrokerFeedbackToClient(const char* msg, bool success = true);
float readUltrasonicDistance();

// ==========================================================
// == CALLBACKS BLE
// ==========================================================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    bleClientAuthenticated = false;
    Serial.println(">>> [BLE] Cliente conectado!");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    bleClientAuthenticated = false;
    Serial.println(">>> [BLE] Cliente desconectado!");
    BLEDevice::startAdvertising();
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String rxValue = pCharacteristic->getValue().c_str();

    if (rxValue.length() > 0) {
      rxValue.trim();
      Serial.print(">>> [BLE] Dados Recebidos: ");
      Serial.println(rxValue);


      if (!bleClientAuthenticated) {
        StaticJsonDocument<256> doc;
        deserializeJson(doc, rxValue);
        const char* type = doc["tipo"];
        if (type && strcmp(type, "auth") == 0) {
          const char* key = doc["chave"];
          if (key && strcmp(key, BLE_AUTH_KEY) == 0) {
            bleClientAuthenticated = true;
            Serial.println(">>> [AUTH] Cliente BLE autenticado com sucesso.");
            sendFeedbackToClient("Autenticado com sucesso!");
          } else {
            Serial.println(">>> [AUTH] Chave de autenticação inválida.");
            sendFeedbackToClient("Chave de autenticacao invalida.", false);
            pServer->disconnect(pServer->getConnId());
          }
        }
      } else {

        processJsonCommand(rxValue);
      }
    }
  }
};

// ==========================================================
// == FUNÇÕES DE COMUNICAÇÃO E FEEDBACK BLE
// ==========================================================
void sendJsonToClient(JsonDocument& doc) {
  if (deviceConnected && bleClientAuthenticated) {
    String jsonString;
    serializeJson(doc, jsonString);
    jsonString += "\n";
    pCharacteristicTX->setValue(jsonString.c_str());
    pCharacteristicTX->notify();
  }
}

void sendFeedbackToClient(const char* msg, bool success) {
  StaticJsonDocument<256> doc;
  doc["tipo"] = "feedback";
  doc["sucesso"] = success;
  doc["mensagem"] = msg;
  sendJsonToClient(doc);
}

// --- ADICIONADO: Novas funções de feedback específico ---
void sendWifiFeedbackToClient(const char* msg, bool success) {
  StaticJsonDocument<256> doc;
  doc["tipo"] = "wifi_feedback";
  doc["sucesso"] = success;
  doc["mensagem"] = msg;
  sendJsonToClient(doc);
}

void sendBrokerFeedbackToClient(const char* msg, bool success) {
  StaticJsonDocument<256> doc;
  doc["tipo"] = "broker_feedback";
  doc["sucesso"] = success;
  doc["mensagem"] = msg;
  sendJsonToClient(doc);
}

// ==========================================================
// == LÓGICA MQTT
// ==========================================================
void mqtt_callback(char* topic, byte* payload, unsigned int length) {

  char message[length + 1];
  memcpy(message, payload, length);
  message[length] = '\0';
  String topicStr = String(topic);

  Serial.printf(">>> [MQTT] Mensagem recebida! Tópico: %s | Payload: %s\n", topic, message);


  if (topicStr == MQTT_ID_TOPIC_IN && systemState == STATE_IDLE) {
    if (strlen(currentStudentID) == 0) {
      if (xSemaphoreTake(sharedDataMutex, portMAX_DELAY) == pdTRUE) {
        strncpy(currentStudentID, message, sizeof(currentStudentID) - 1);
        systemState = STATE_READY;
        Serial.printf(">>> [MQTT] Bancada reservada para o aluno: %s\n", currentStudentID);
        subscribeToStudentTopics(currentStudentID);
        client.publish(MQTT_HEARTBEAT_TOPIC_OUT, "Bancada Pronta");

        xSemaphoreGive(sharedDataMutex);
      }
    }
    return;
  }

  if (strlen(currentStudentID) > 0 && topicStr.startsWith(currentStudentID)) {
    String subTopic = topicStr.substring(strlen(currentStudentID) + 1);

    if (xSemaphoreTake(sharedDataMutex, portMAX_DELAY) == pdTRUE) {
      if (subTopic == "ref") controlParams.ref = atof(message);
      else if (subTopic == "k") controlParams.k = atof(message);
      else if (subTopic == "ke") controlParams.ke = atof(message);
      else if (subTopic == "nx") controlParams.nx = atof(message);
      else if (subTopic == "nu") controlParams.nu = atof(message);
      else if (subTopic == "comando") {
        if (strcmp(message, "iniciar") == 0 && systemState == STATE_READY) {
          x_chap = 0;
          systemState = STATE_RUNNING;
        } else if (strcmp(message, "pausar") == 0 && systemState == STATE_RUNNING) {
          systemState = STATE_PAUSED;
        } else if (strcmp(message, "iniciar") == 0 && systemState == STATE_PAUSED) {
          systemState = STATE_RUNNING;
        } else if (strcmp(message, "parar") == 0) {
          resetExperimentState();
        }
      }
      xSemaphoreGive(sharedDataMutex);
    }
  }
}

void subscribeToStudentTopics(const char* studentID) {
  if (strlen(studentID) == 0) return;
  Serial.printf(">>> [MQTT] Inscrevendo-se nos tópicos do aluno: %s\n", studentID);

  char topicBuffer[50];
  sprintf(topicBuffer, "%s/ref", studentID);
  client.subscribe(topicBuffer);
  sprintf(topicBuffer, "%s/k", studentID);
  client.subscribe(topicBuffer);
  sprintf(topicBuffer, "%s/ke", studentID);
  client.subscribe(topicBuffer);
  sprintf(topicBuffer, "%s/nx", studentID);
  client.subscribe(topicBuffer);
  sprintf(topicBuffer, "%s/nu", studentID);
  client.subscribe(topicBuffer);
  sprintf(topicBuffer, "%s/comando", studentID);
  client.subscribe(topicBuffer);
}

void unsubscribeFromStudentTopics(const char* studentID) {
  if (strlen(studentID) == 0) return;
  Serial.printf(">>> [MQTT] Cancelando inscrição dos tópicos do aluno: %s\n", studentID);

  char topicBuffer[50];
  sprintf(topicBuffer, "%s/ref", studentID);
  client.unsubscribe(topicBuffer);
  sprintf(topicBuffer, "%s/k", studentID);
  client.unsubscribe(topicBuffer);
  sprintf(topicBuffer, "%s/ke", studentID);
  client.unsubscribe(topicBuffer);
  sprintf(topicBuffer, "%s/nx", studentID);
  client.unsubscribe(topicBuffer);
  sprintf(topicBuffer, "%s/nu", studentID);
  client.unsubscribe(topicBuffer);
  sprintf(topicBuffer, "%s/comando", studentID);
  client.unsubscribe(topicBuffer);
}


void resetExperimentState() {
  if (xSemaphoreTake(sharedDataMutex, portMAX_DELAY) == pdTRUE) {
    systemState = STATE_IDLE;
    analogWrite(PUMP_PWM_PIN, 0);
    u = 0;
    xSemaphoreGive(sharedDataMutex);
  }
  Serial.println(">>> [ESTADO] Experimento finalizado. Bancada liberada e aguardando novo aluno.");
  unsubscribeFromStudentTopics(currentStudentID);
  strcpy(currentStudentID, "");
}

// ==========================================================
// == PROCESSAMENTO DE COMANDOS BLE
// ==========================================================
void processJsonCommand(String json) {
  StaticJsonDocument<512> doc;
  deserializeJson(doc, json);
  const char* type = doc["tipo"];
  if (!type) return;

  String typeStr = String(type);
  if (typeStr == "scan_wifi") {
    int n = WiFi.scanNetworks();
    StaticJsonDocument<1024> responseDoc;
    responseDoc["tipo"] = "wifi_scan_result";
    JsonArray redes = responseDoc.createNestedArray("redes");
    for (int i = 0; i < n && i < 10; ++i) {
      JsonObject rede = redes.createNestedObject();
      rede["ssid"] = WiFi.SSID(i);
      rede["rssi"] = WiFi.RSSI(i);
    }
    sendJsonToClient(responseDoc);
  } else if (typeStr == "wifi_creds") {
    connectToWifi(doc["ssid"], doc["senha"]);
  } else if (typeStr == "broker_creds") {
    connectToMqttBroker(doc["ip"], doc["porta"], doc["usuario"], doc["senha"]);
  }
}

// ==========================================================
// == FUNÇÕES DE CONEXÃO
// ==========================================================
void connectToWifi(const char* ssid, const char* pass) {
  sendWifiFeedbackToClient("Recebidas credenciais Wi-Fi. Conectando...");
  WiFi.disconnect(true);
  delay(100);
  WiFi.begin(ssid, pass);
}

void connectToMqttBroker(const char* ip, int port, const char* user, const char* pass) {
  sendBrokerFeedbackToClient("Recebidas credenciais do Broker. Conectando...");
  strncpy(saved_mqtt_ip, ip, sizeof(saved_mqtt_ip) - 1);
  saved_mqtt_port = port;

  if (user && strlen(user) > 0) {
    strncpy(saved_mqtt_user, user, sizeof(saved_mqtt_user) - 1);
    strncpy(saved_mqtt_pass, pass, sizeof(saved_mqtt_pass) - 1);
  } else {
    strcpy(saved_mqtt_user, "");
    strcpy(saved_mqtt_pass, "");
  }

  client.setServer(saved_mqtt_ip, saved_mqtt_port);
  client.setCallback(mqtt_callback);
  brokerConfigured = true;
}

float readUltrasonicDistance() {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);


  long duration = pulseIn(echoPin, HIGH, 50000);

  if (duration > 0) {
    float distance = duration * 0.034 / 2;
    return distance;
  }
  return -1.0;
}

// ==========================================================
// == TAREFAS DO FREERTOS
// ==========================================================
void controlTask(void* pvParameters) {
  Serial.println(">>> [RTOS] Tarefa de Controle iniciada no Core " + String(xPortGetCoreID()));
  unsigned long last_time_control = 0;

  const byte qtdMedidas = 20;
  float lectures[qtdMedidas] = { 0 };
  byte lecture_index = 0;
  float y_distancia_sensor = 0.0;

  for (;;) {
    if (millis() - last_time_control >= INTERVAL_CONTROL) {
      last_time_control = millis();

      float nova_leitura_dist = readUltrasonicDistance();

      if (nova_leitura_dist > 0) {
        lectures[lecture_index] = nova_leitura_dist;
        lecture_index = (lecture_index + 1) % qtdMedidas;

        float distancia_filtrada = 0;
        for (int i = 0; i < qtdMedidas; i++) {
          distancia_filtrada += lectures[i];
        }
        distancia_filtrada /= qtdMedidas;

        float altura_agua_cm = H_total - distancia_filtrada;
        if (altura_agua_cm < 0) altura_agua_cm = 0;

        if (xSemaphoreTake(sharedDataMutex, portMAX_DELAY) == pdTRUE) {
          current_water_level_cm = altura_agua_cm;

          if (systemState == STATE_RUNNING) {
            double xss = controlParams.nx * controlParams.ref;
            double uss = controlParams.nu * controlParams.ref;
            u = uss - controlParams.k * (x_chap - xss);
            u = constrain(u, 0, 100);
            analogWrite(PUMP_PWM_PIN, map(u, 0, 100, 0, 255));

            double y_obs = x_chap;
            double x_chap_p = (-0.0052 * x_chap) + (0.0197 * u) + controlParams.ke * (current_water_level_cm - y_obs);
            x_chap += x_chap_p * (INTERVAL_CONTROL / 1000.0);

            static unsigned long last_log_time = 0;
            if (millis() - last_log_time > 1000) {
              last_log_time = millis();
              Serial.printf(">>> [CONTROLE] Ref: %.2f | Nivel: %.2f | Dist Filt: %.2f | Acao (u): %.2f\n", controlParams.ref, current_water_level_cm, distancia_filtrada, u);
            }
          } else {
            u = 0;
            analogWrite(PUMP_PWM_PIN, 0);
          }
          xSemaphoreGive(sharedDataMutex);
        }
      }
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void commsTask(void* pvParameters) {
  Serial.println(">>> [RTOS] Tarefa de Comunicação iniciada no Core " + String(xPortGetCoreID()));
  unsigned long lastWifiCheck = 0;
  unsigned long lastMqttDataPublish = 0;

  for (;;) {
    if (WiFi.status() != WL_CONNECTED && brokerConfigured) {
      if (millis() - lastWifiCheck > 10000) {
        Serial.println(">>> [WIFI] Wi-Fi desconectado. Tentando reconectar...");
        WiFi.reconnect();
        lastWifiCheck = millis();
      }
    }

    // --- Gerenciamento da Conexão MQTT ---
    if (brokerConfigured && WiFi.status() == WL_CONNECTED) {
      if (!client.connected()) {
        if (millis() - lastMqttReconnectAttempt > 5000) {
          lastMqttReconnectAttempt = millis();
          Serial.println(">>> [MQTT] Tentando conectar ao Broker...");

          char clientID[30];
          uint8_t mac[6];
          esp_wifi_get_mac(WIFI_IF_STA, mac);
          sprintf(clientID, "ESP32_Bancada_%02X%02X", mac[4], mac[5]);

          bool connected = (strlen(saved_mqtt_user) > 0)
                             ? client.connect(clientID, saved_mqtt_user, saved_mqtt_pass)
                             : client.connect(clientID);

          if (connected) {
            Serial.println(">>> [MQTT] Conectado ao Broker com sucesso!");
            if (strlen(currentStudentID) > 0) {
              Serial.printf(">>> [MQTT] Reconectado. Re-inscrevendo nos tópicos do aluno %s\n", currentStudentID);
              subscribeToStudentTopics(currentStudentID);
            } else {
              client.subscribe(MQTT_ID_TOPIC_IN);
            }

            if (systemState == STATE_UNCONFIGURED) {
              systemState = STATE_IDLE;
            }
          } else {
            Serial.printf(">>> [MQTT] Falha na conexão, rc=%d. Tentando novamente em 5s\n", client.state());
          }
        }
      } else {
        client.loop();
        /
      }
    }


    if (client.connected() && (systemState == STATE_RUNNING || systemState == STATE_PAUSED) && (millis() - lastMqttDataPublish >= INTERVAL_COMMS)) {
      lastMqttDataPublish = millis();
      if (xSemaphoreTake(sharedDataMutex, portMAX_DELAY) == pdTRUE) {

        char topicBuffer[50];
        char valueBuffer[20];

        Serial.printf(">>> [MQTT-PUB] Estado: %d, Conectado: Sim. Publicando dados...\n", systemState);

        const char* statusStr = (systemState == STATE_RUNNING) ? "Online" : "Pausado";
        sprintf(topicBuffer, "bancada/%s/status", currentStudentID);
        client.publish(topicBuffer, statusStr);

        dtostrf(current_water_level_cm, 4, 2, valueBuffer);
        sprintf(topicBuffer, "bancada/%s/nivelagua", currentStudentID);
        client.publish(topicBuffer, valueBuffer);

        dtostrf(u, 4, 2, valueBuffer);
        sprintf(topicBuffer, "bancada/%s/tensao", currentStudentID);
        client.publish(topicBuffer, valueBuffer);

        dtostrf(millis() / 1000.0, 6, 2, valueBuffer);
        sprintf(topicBuffer, "bancada/%s/tempo", currentStudentID);
        client.publish(topicBuffer, valueBuffer);

        xSemaphoreGive(sharedDataMutex);
      }
    }

    /***********************************************************
     * * Lógica de Controle do LED de Status
     ***********************************************************/
    int dutyCycle = 0;
    switch (systemState) {
      case STATE_UNCONFIGURED:
        if (millis() % 2000 < 200) {
          dutyCycle = 40;
        } else {
          dutyCycle = 0;
        }
        break;
      case STATE_IDLE:
        led_angle += 0.02;
        dutyCycle = 100 + 40 * sin(led_angle);
        break;
      case STATE_READY:
        led_angle += 0.05;
        dutyCycle = 100 + 40 * sin(led_angle);
        break;
      case STATE_RUNNING:
        if (abs(current_water_level_cm - controlParams.ref) < 1.0) {
          if (millis() % 1000 < 500) {
            dutyCycle = 204;
          } else {
            dutyCycle = 0;
          }
        } else {
          led_angle += 0.08;
          dutyCycle = 180 + 60 * sin(led_angle);
        }
        break;
      case STATE_PAUSED:
        dutyCycle = 128;
        break;
    }

    analogWrite(LED_PWM_PIN, dutyCycle);

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

// ==========================================================
// == SETUP
// ==========================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n>>> [SETUP] Iniciando a Bancada de Controle (V2 Final)...");

  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);
  pinMode(PUMP_PWM_PIN, OUTPUT);
  pinMode(IN1, OUTPUT);
  digitalWrite(IN1, HIGH);
  pinMode(IN2, OUTPUT);
  digitalWrite(IN2, LOW);
  analogWrite(PUMP_PWM_PIN, 0);
  pinMode(LED_IN3, OUTPUT);
  pinMode(LED_IN4, OUTPUT);
  digitalWrite(LED_IN3, HIGH);
  digitalWrite(LED_IN4, LOW);
  analogWrite(LED_PWM_PIN, 0);

  /***********************************************************
   * * NOVO: Inicialização do Filtro de Média Móvel
   ***********************************************************/
  Serial.println(">>> [SETUP] Calibrando sensor e inicializando filtro...");
  for (int i = 0; i < qtdMedidas + 5; i++) {
    float leitura_inicial = readUltrasonicDistance();
    if (i >= 5 && leitura_inicial > 0) {
      lectures[i - 5] = leitura_inicial;
    }
    delay(50);
  }
  Serial.println(">>> [SETUP] Filtro inicializado com sucesso.");


  // --- Setup do BLE ---
  BLEDevice::init("Bancada_Controle_UFU");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService* pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic* pCharacteristicRX = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pCharacteristicRX->setCallbacks(new MyCharacteristicCallbacks());

  pCharacteristicTX = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pCharacteristicTX->addDescriptor(new BLE2902());

  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  BLEDevice::startAdvertising();
  Serial.println(">>> [SETUP] Servidor BLE iniciado.");

  // --- Setup do RTOS ---
  sharedDataMutex = xSemaphoreCreateMutex();
  if (sharedDataMutex != NULL) {
    Serial.println(">>> [RTOS] Mutex criado com sucesso.");
  } else {
    Serial.println(">>> [RTOS] ERRO ao criar o Mutex.");
  }

  xTaskCreatePinnedToCore(controlTask, "ControlTask", 4096, NULL, 2, &controlTaskHandle, 0);
  xTaskCreatePinnedToCore(commsTask, "CommsTask", 8192, NULL, 1, &commsTaskHandle, 1);

  Serial.println(">>> [SETUP] Configuração finalizada. Tarefas iniciadas.");
}

// ==========================================================
// == LOOP PRINCIPAL (vazio)
// ==========================================================
void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}