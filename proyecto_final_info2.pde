import processing.serial.*;

Serial puerto;
ArrayList<Float> irVals = new ArrayList<Float>();

int maxPuntos;

// Rango fijo del eje Y (ajustable con teclas)
float minY = 0;
float maxY = 150000;
float pasoY = 5000;   // cuánto cambia cada pulsación

int indicePuerto = 0;
int baudRate = 115200;

float spo2Actual = 0;
float bpmActual = 0;

void setup() {
  size(800, 400);
  maxPuntos = width;
  println(Serial.list());
  puerto = new Serial(this, Serial.list()[indicePuerto], baudRate);
  puerto.bufferUntil('\n');
}

void draw() {
  background(30);
  ArrayList<Float> copia;
  synchronized (irVals) {
    copia = new ArrayList<Float>(irVals);
  }

  dibujarEjes();

  if (copia.isEmpty()) {
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(16);
    text("Esperando datos IR...", width/2, height/2);
    dibujarAyuda();
    return;
  }

  strokeWeight(2);
  stroke(255, 80, 80);
  noFill();
  for (int i = 0; i < copia.size()-1; i++) {
    float x1 = i, x2 = i+1;
    float y1 = map(copia.get(i), minY, maxY, height-1, 0);
    float y2 = map(copia.get(i+1), minY, maxY, height-1, 0);
    line(x1, y1, x2, y2);
  }

  fill(255);
  textAlign(LEFT, CENTER);
  textSize(16);
  text("IR: " + nf(copia.get(copia.size()-1), 0, 0), 20, 20);
  text("SpO2: " + nf(spo2Actual, 1, 1) + " %", 20, 45);
  text("BPM: " + nf(bpmActual, 1, 0), 20, 70);

  dibujarAyuda();
}

void dibujarEjes() {
  stroke(80);
  for (float f = 0; f <= 1; f += 0.2) {
    float y = map(f, 0, 1, height-1, 0);
    line(0, y, width, y);
    fill(200); textSize(10); textAlign(RIGHT, CENTER);
    text(nf(minY + f*(maxY-minY), 0, 0), width-10, y);
  }
}

void dibujarAyuda() {
  fill(150);
  textSize(11);
  textAlign(LEFT, BOTTOM);
  text("+/-: maxY   W/S: minY   R: reset   [minY=" +
       nf(minY,0,0) + " maxY=" + nf(maxY,0,0) + "]", 10, height-8);
}

void keyPressed() {
  if (key == '+' || key == '=') {
    maxY += pasoY;
  } else if (key == '-') {
    maxY -= pasoY;
    if (maxY <= minY + pasoY) maxY = minY + pasoY;
  } else if (key == 'w' || key == 'W') {
    minY += pasoY;
    if (minY >= maxY - pasoY) minY = maxY - pasoY;
  } else if (key == 's' || key == 'S') {
    minY -= pasoY;
  } else if (key == 'r' || key == 'R') {
    minY = 0;
    maxY = 150000;
  }
}

void serialEvent(Serial p) {
  if (p == null) return;
  try {
    String linea = p.readStringUntil('\n');
    if (linea == null) return;
    linea = trim(linea);
    if (linea.equals("")) return;
    if (!linea.startsWith("IR:")) return;

    String[] partes = split(linea, ',');
    for (String parte : partes) {
      if (parte.startsWith("IR:")) {
        float ir = float(parte.substring(3));
        synchronized (irVals) {
          irVals.add(ir);
          if (irVals.size() > maxPuntos) irVals.remove(0);
        }
      } else if (parte.startsWith("SpO2:")) {
        spo2Actual = float(parte.substring(5));
      } else if (parte.startsWith("BPM:")) {
        bpmActual = float(parte.substring(4));
      }
    }
  } catch (Exception e) {
    println("Error parseando: " + e.getMessage());
  }
}
