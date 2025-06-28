#include <WiFi.h>
#include <PubSubClient.h>
#include "wifi_password.h" 

#define PIN_PUMP_SPEED 25      
#define PIN_PUMP_DIR_1 26      
#define PIN_PUMP_DIR_2 27      
#define PIN_ULTRASONIC_TRIG 13 
#define PIN_ULTRASONIC_ECHO 12 
#define PWM_FREQUENCY 5000  
#define PWM_CHANNEL 0       
#define PWM_RESOLUTION 8    
#define TOPIC_REGULADOR "reguladorK"
#define TOPIC_OBSERVADOR "observadorKe"
#define TOPIC_NX "nx"
#define TOPIC_NU "nu"
#define TOPIC_REFERENCIA "referencia_app" 
#define TOPIC_ENCERRA "encerraExperimento"
#define TOPIC_NIVEL "nivel"
#define TOPIC_ESTIMADO "estimado"
#define TOPIC_TENSAO "tensao"
#define TOPIC_TEMPO "tempo"
#define TOPIC_STATEWIFI "estadoESPWifi"
#define TOPIC_STATEBROKER "estadoESPBroker"
#define TOPIC_STATEEXPERIMENT "estadoExperimento"

WiFiClient espClient;
PubSubClient client(espClient);

double K = 50.4975;
double Ke = 9.9948;
double Nx = 1.0;
double Nu = 0.264;
double rss = 10.0; 
double u = 0.0;         
double y = 0.0;         
double x_chap = 0.0;    
double tini;


unsigned long lastControlTime = 0;
const long dt = 10; 
bool experimentRunning = false;

float calcularDistancia() {
    const float H_total = 20.0; 
    const int qtdMedidas = 5;  
    float soma = 0;

    for (int i = 0; i < qtdMedidas; i++) {
        digitalWrite(PIN_ULTRASONIC_TRIG, LOW);
        delayMicroseconds(2);
        digitalWrite(PIN_ULTRASONIC_TRIG, HIGH);
        delayMicroseconds(10);
        digitalWrite(PIN_ULTRASONIC_TRIG, LOW);

        long duracao = pulseIn(PIN_ULTRASONIC_ECHO, HIGH, 25000); 
        soma += (duracao / 58.0);
        delay(2); 
    }

    float distancia_sensor = soma / qtdMedidas;
    return H_total - distancia_sensor; 
}

void processarMensagemMQTT(char* topic, byte* payload, unsigned int length) {
    char mensagem_char[length + 1];
    memcpy(mensagem_char, payload, length);
    mensagem_char[length] = '\0';
    String mensagem = String(mensagem_char);
    String topico = String(topic);

    if (topico.equals(TOPIC_REGULADOR)) K = mensagem.toDouble();
    else if (topico.equals(TOPIC_OBSERVADOR)) Ke = mensagem.toDouble();
    else if (topico.equals(TOPIC_NX)) Nx = mensagem.toDouble();
    else if (topico.equals(TOPIC_NU)) Nu = mensagem.toDouble();
    else if (topico.equals(TOPIC_REFERENCIA)) {
        rss = mensagem.toDouble();
        if (!experimentRunning) {
            experimentRunning = true;
            tini = millis(); 
            client.publish(TOPIC_STATEEXPERIMENT, "Running");
        }
    } else if (topico.equals(TOPIC_ENCERRA) && mensagem.equals("ENCERRAR")) {
        experimentRunning = false;
        u = 0;
        ledcWrite(PWM_CHANNEL, 0); 
        client.publish(TOPIC_STATEEXPERIMENT, "Stopped");
    }
}

void conectarWiFi() {
    Serial.print("Connecting to Wi-Fi...");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD); 
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi connected!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());
}

void reconnectMQTT() {
    while (!client.connected()) {
        Serial.print("Attempting MQTT connection...");
        String clientId = "ESP32-Controlador";
        if (client.connect(clientId.c_str())) {
            Serial.println("connected");
            client.publish(TOPIC_STATEBROKER, "Connected");
            
            client.subscribe(TOPIC_REGULADOR);
            client.subscribe(TOPIC_OBSERVADOR);
            client.subscribe(TOPIC_NX);
            client.subscribe(TOPIC_NU);
            client.subscribe(TOPIC_REFERENCIA);
            client.subscribe(TOPIC_ENCERRA);
        } else {
            Serial.print("failed, rc=");
            Serial.print(client.state());
            Serial.println(" try again in 5 seconds");
            client.publish(TOPIC_STATEBROKER, "Disconnected");
            delay(5000);
        }
    }
}

void setup() {
    Serial.begin(115200);
    
    
    pinMode(PIN_ULTRASONIC_TRIG, OUTPUT);
    pinMode(PIN_ULTRASONIC_ECHO, INPUT);
    pinMode(PIN_PUMP_DIR_1, OUTPUT);
    pinMode(PIN_PUMP_DIR_2, OUTPUT);

    
    digitalWrite(PIN_PUMP_DIR_1, HIGH);
    digitalWrite(PIN_PUMP_DIR_2, LOW);

    
    ledcSetup(PWM_CHANNEL, PWM_FREQUENCY, PWM_RESOLUTION);
    ledcAttachPin(PIN_PUMP_SPEED, PWM_CHANNEL);

    
    conectarWiFi();
    client.setServer(MQTT_SERVER, MQTT_PORT); 
    client.setCallback(processarMensagemMQTT);
    
    client.publish(TOPIC_STATEWIFI, WiFi.localIP().toString().c_str());
    client.publish(TOPIC_STATEEXPERIMENT, "Idle");
}

void loop() {
    if (!client.connected()) {
        reconnectMQTT();
    }
    client.loop(); 

    
    if (millis() - lastControlTime >= dt) {
        lastControlTime = millis();

        if (experimentRunning) {
            
            y = calcularDistancia();

            
            double xss = Nx * rss;
            double uss = Nu * rss;

            
            u = uss - K * (x_chap - xss);
            u = constrain(u, 0, 100); 

            
            
            
            double x_chap_dot = (-0.0052 * x_chap) + (0.0197 * u) + Ke * (y - x_chap); 
            x_chap += x_chap_dot * (dt / 1000.0);

            
            ledcWrite(PWM_CHANNEL, (int)map(u, 0, 100, 0, 255));
            
            
            char buffer[10];
            
            dtostrf(y, 4, 2, buffer);
            client.publish(TOPIC_NIVEL, buffer);
            
            dtostrf(x_chap, 4, 2, buffer);
            client.publish(TOPIC_ESTIMADO, buffer);

            
            double tensao = u * (12.0 / 100.0);
            dtostrf(tensao, 4, 2, buffer);
            client.publish(TOPIC_TENSAO, buffer);
            
            double tempo_seg = (millis() - tini) / 1000.0;
            dtostrf(tempo_seg, 4, 2, buffer);
            client.publish(TOPIC_TEMPO, buffer);
        }
    }
}
