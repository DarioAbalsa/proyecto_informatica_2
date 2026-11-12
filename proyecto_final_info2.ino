#include <Wire.h>
#include "MAX30105.h"

MAX30105 particleSensor;

#define BUZZER_PIN 8
#define BEEP_FREQ 1000
#define BEEP_DURATION 50

bool buzzerHabilitado = false;
bool sensorHabilitado = true;
String bufferSerial = "";
unsigned long ultimoLatido = 0;

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 no encontrado. Revisa conexiones.");
    while (1);
  }

  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x1F);
  particleSensor.setPulseAmplitudeGreen(0);

  Serial.println("Sensor listo. Coloca el dedo.");
}

void loop() {
  // --- Lectura NO bloqueante de comandos desde Processing ---
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n') {
      bufferSerial.trim();

      if (bufferSerial == "BUZZER:ON") {
        buzzerHabilitado = true;
      } 
      else if (bufferSerial == "BUZZER:OFF") {
        buzzerHabilitado = false;
        noTone(BUZZER_PIN);
      } 
      else if (bufferSerial == "LATIDO") {
        ultimoLatido = millis();
        if (buzzerHabilitado && sensorHabilitado) {
          tone(BUZZER_PIN, BEEP_FREQ, BEEP_DURATION);
        }
      } 
      else if (bufferSerial == "SENSOR:ON") {
        sensorHabilitado = true;
      } 
      else if (bufferSerial == "SENSOR:OFF") {
        sensorHabilitado = false;
        noTone(BUZZER_PIN);
        buzzerHabilitado = false;
      }

      bufferSerial = "";
    } else {
      bufferSerial += c;
    }
  }

  // --- Seguridad: si pasan > 2 s sin LATIDO, apaga el buzzer ---
  if (buzzerHabilitado && millis() - ultimoLatido > 2000) {
    noTone(BUZZER_PIN);
  }

  // --- Envío de IR y RED solo si el sensor está habilitado ---
  if (sensorHabilitado) {
    long irValue = particleSensor.getIR();
    long redValue = particleSensor.getRed();

    Serial.print(irValue);
    Serial.print(",");
    Serial.println(redValue);
  }

  delay(10);
}
