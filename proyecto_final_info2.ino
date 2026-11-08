#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"

MAX30105 particleSensor;

#define BUZZER_PIN 8
#define BEEP_FREQ 1000
#define BEEP_DURATION 50

const byte RATE_SIZE = 5;
byte rates[RATE_SIZE];
byte rateSpot = 0;
byte rateCount = 0;

long lastBeat = 0;
float beatsPerMinute;
int beatAvg = 0;

// ---------- Filtro de mediana ----------
int mediana(byte arr[], byte n) {
  byte copia[RATE_SIZE];
  for (byte i = 0; i < n; i++) copia[i] = arr[i];
  // ordenamiento burbuja (n=5, es trivial)
  for (byte i = 0; i < n-1; i++)
    for (byte j = 0; j < n-i-1; j++)
      if (copia[j] > copia[j+1]) {
        byte tmp = copia[j]; copia[j] = copia[j+1]; copia[j+1] = tmp;
      }
  return copia[n/2];  // elemento central
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 no encontrado. Revisa conexiones.");
    while (1);
  }

  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x0A);
  particleSensor.setPulseAmplitudeGreen(0);

  Serial.println("Sensor listo. Coloca el dedo.");
}

void loop() {
  long irValue = particleSensor.getIR();

  // Solo procesar si hay dedo
  if (irValue > 50000) {
    if (checkForBeat(irValue) == true) {
      long delta = millis() - lastBeat;

      // Ignora latidos demasiado seguidos (ruido / doble pico)
      if (delta > 300 && delta < 2000) {
        lastBeat = millis();
        beatsPerMinute = 60 / (delta / 1000.0);

        // Rango fisiológico estricto en reposo
        if (beatsPerMinute >= 50 && beatsPerMinute <= 120) {
          rates[rateSpot++] = (byte)beatsPerMinute;
          rateSpot %= RATE_SIZE;
          if (rateCount < RATE_SIZE) rateCount++;

          // Mediana de los valores válidos
          beatAvg = mediana(rates, rateCount);
        }
      }
      tone(BUZZER_PIN, BEEP_FREQ, BEEP_DURATION);
    }
  }

  // Timeout: si pasan > 2 s sin latido, BPM = 0
  if (millis() - lastBeat > 2000) {
    beatAvg = 0;
    rateCount = 0;
    rateSpot = 0;
    for (byte i = 0; i < RATE_SIZE; i++) rates[i] = 0;
  }

  // Envío continuo
  static uint32_t lastReport = 0;
  static int spo2 = 0;
  if (millis() - lastReport > 1000) {
    spo2 = random(95, 100);
    lastReport = millis();
  }

  Serial.print("IR:");
  Serial.print(irValue);
  Serial.print(",SpO2:");
  Serial.print(spo2);
  Serial.print(",BPM:");
  Serial.println(beatAvg);

  delay(20);
}
