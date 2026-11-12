import processing.serial.*;

// ============================================================
// CLASE: SensorMAX
// Gestiona el puerto serie, la lectura de IR/RED y el envío de comandos.
// ============================================================
class SensorMAX {
  Serial puerto;
  boolean activo = true;
  float ir = 0;
  float red = 0;
  float umbralDedo = 10000;
  boolean dedoDetectado = false;

  SensorMAX(PApplet app, int indicePuerto, int baudRate) {
    puerto = new Serial(app, Serial.list()[indicePuerto], baudRate);
    puerto.bufferUntil('\n');
  }

  void actualizarDatos(float nuevoIR, float nuevoRed) {
    ir = nuevoIR;
    red = nuevoRed;
    dedoDetectado = (ir > umbralDedo);
  }

  void enviar(String comando) {
    if (puerto != null) puerto.write(comando + "\n");
  }

  void encender() {
    activo = true;
    enviar("SENSOR:ON");
  }

  void apagar() {
    activo = false;
    enviar("SENSOR:OFF");
    enviar("BUZZER:OFF");
  }
}

// ============================================================
// CLASE: DetectorBPM
// Detecta picos por cambio de pendiente y calcula BPM sin suavizado.
// ============================================================
class DetectorBPM {
  float bpm = 0;
  long ultimoLatido = 0;
  float anterior = 0;
  float pendienteAnterior = 0;
  float[] bufferFiltro = new float[3];
  int posFiltro = 0;
  int llenadoFiltro = 0;

  SensorMAX sensor;

  DetectorBPM(SensorMAX sensor) {
    this.sensor = sensor;
  }

  void reset() {
    bpm = 0;
    ultimoLatido = 0;
    anterior = 0;
    pendienteAnterior = 0;
    llenadoFiltro = 0;
    posFiltro = 0;
  }

  void procesar(float ir, boolean dedoDetectado) {
    if (!dedoDetectado) {
      reset();
      return;
    }

    bufferFiltro[posFiltro] = ir;
    posFiltro = (posFiltro + 1) % bufferFiltro.length;
    if (llenadoFiltro < bufferFiltro.length) llenadoFiltro++;

    float suma = 0;
    for (int i = 0; i < llenadoFiltro; i++) suma += bufferFiltro[i];
    float filtrado = suma / llenadoFiltro;

    float pendiente = filtrado - anterior;

    if (pendienteAnterior > 0 && pendiente <= 0) {
      long ahora = millis();
      if (ultimoLatido > 0) {
        long delta = ahora - ultimoLatido;
        if (delta > 300 && delta < 2000) {
          bpm = 60000.0 / delta;  // sin suavizado
          sensor.enviar("LATIDO");
        }
      }
      ultimoLatido = ahora;
    }

    pendienteAnterior = pendiente;
    anterior = filtrado;
  }
}

// ============================================================
// CLASE: CalculadorSpO2
// Calcula SpO2 a partir de IR y RED (relación R simplificada).
// ============================================================
class CalculadorSpO2 {
  float spo2 = 0;
  float[] bufferIR = new float[50];
  float[] bufferRed = new float[50];
  int pos = 0;
  int llenado = 0;

  void reset() {
    spo2 = 0;
    llenado = 0;
    pos = 0;
  }

  void procesar(float ir, float red, boolean dedoDetectado) {
    if (!dedoDetectado) {
      reset();
      return;
    }

    bufferIR[pos] = ir;
    bufferRed[pos] = red;
    pos = (pos + 1) % bufferIR.length;
    if (llenado < bufferIR.length) llenado++;
    if (llenado < bufferIR.length) return;

    float irDC = 0, redDC = 0;
    for (int i = 0; i < llenado; i++) { irDC += bufferIR[i]; redDC += bufferRed[i]; }
    irDC /= llenado; redDC /= llenado;

    float irAC = 0, redAC = 0;
    for (int i = 0; i < llenado; i++) {
      irAC += abs(bufferIR[i] - irDC);
      redAC += abs(bufferRed[i] - redDC);
    }
    irAC /= llenado; redAC /= llenado;

    if (irDC == 0 || irAC == 0) return;

    float R = (redAC / redDC) / (irAC / irDC);
    float s = 104 - 17 * R;
    s = constrain(s, 70, 100);
    spo2 = spo2 * 0.8 + s * 0.2;
  }
}

// ============================================================
// CLASE: Grafica
// Buffer circular, Catmull-Rom, ejes y rango ajustable.
// ============================================================
class Grafica {
  ArrayList<Float> valores = new ArrayList<Float>();
  int maxPuntos;
  float minY = 0;
  float maxY = 150000;
  float pasoY = 5000;

  float[] bufferCircular = new float[5];
  int posBuffer = 0;
  int llenado = 0;

  boolean dedoDetectado = false;

  Grafica(int maxPuntos) {
    this.maxPuntos = maxPuntos;
  }

  void reset() {
    synchronized (valores) { valores.clear(); }
    llenado = 0;
    posBuffer = 0;
  }

  void agregar(float ir) {
    bufferCircular[posBuffer] = ir;
    posBuffer = (posBuffer + 1) % bufferCircular.length;
    if (llenado < bufferCircular.length) llenado++;

    float suma = 0;
    for (int i = 0; i < llenado; i++) suma += bufferCircular[i];
    float suavizado = suma / llenado;

    synchronized (valores) {
      valores.add(suavizado);
      if (valores.size() > maxPuntos) valores.remove(0);
    }
  }

  void dibujar() {
    ArrayList<Float> copia;
    synchronized (valores) {
      copia = new ArrayList<Float>(valores);
    }

    dibujarEjes();
    if (copia.size() < 2) return;

    strokeWeight(2);
    stroke(dedoDetectado ? color(255, 80, 80) : color(120, 120, 120));
    dibujarCatmullRom(copia);
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

  void dibujarCatmullRom(ArrayList<Float> pts) {
    noFill(); beginShape();
    for (int i = 0; i < pts.size(); i++) {
      float x0 = xDe(i-1, pts.size());
      float y0 = map(pts.get(max(0, i-1)), minY, maxY, height-1, 0);
      float x1 = xDe(i, pts.size());
      float y1 = map(pts.get(i), minY, maxY, height-1, 0);
      float x2 = xDe(i+1, pts.size());
      float y2 = map(pts.get(min(pts.size()-1, i+1)), minY, maxY, height-1, 0);
      float x3 = xDe(i+2, pts.size());
      float y3 = map(pts.get(min(pts.size()-1, i+2)), minY, maxY, height-1, 0);
      for (int t = 0; t <= 10; t++) {
        float tt = t / 10.0;
        vertex(catmullRom(x0, x1, x2, x3, tt), catmullRom(y0, y1, y2, y3, tt));
      }
    }
    endShape();
  }

  float catmullRom(float p0, float p1, float p2, float p3, float t) {
    float t2 = t*t, t3 = t2*t;
    return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3);
  }

  float xDe(int i, int total) { return map(i, 0, total-1, 0, width); }

  float ultimoValor() {
    synchronized (valores) {
      if (valores.isEmpty()) return 0;
      return valores.get(valores.size()-1);
    }
  }

  void ajustarRango(float delta) {
    maxY += delta;
    if (maxY <= minY + pasoY) maxY = minY + pasoY;
  }

  void resetRango() {
    minY = 0;
    maxY = 150000;
  }
}

// ============================================================
// CLASE: Boton
// Botón reutilizable con estado ON/OFF y colores.
// ============================================================
class Boton {
  float x, y, w, h;
  String etiquetaON, etiquetaOFF;
  boolean estado;
  color colorON, colorOFF;
  boolean sobre = false;

  Boton(float x, float y, float w, float h, String etiquetaON, String etiquetaOFF,
        boolean estadoInicial, color colorON, color colorOFF) {
    this.x = x; this.y = y; this.w = w; this.h = h;
    this.etiquetaON = etiquetaON; this.etiquetaOFF = etiquetaOFF;
    this.estado = estadoInicial;
    this.colorON = colorON; this.colorOFF = colorOFF;
  }

  void dibujar() {
    sobre = mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
    fill(estado ? (sobre ? colorON : color(colorON, 180))
                : (sobre ? colorOFF : color(colorOFF, 180)));
    stroke(200); strokeWeight(1);
    rect(x, y, w, h, 8);
    fill(255); textAlign(CENTER, CENTER); textSize(14);
    text(estado ? etiquetaON : etiquetaOFF, x + w/2, y + h/2);
  }

  boolean click() {
    if (mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h) {
      estado = !estado;
      return true;
    }
    return false;
  }
}

// ============================================================
// PROGRAMA PRINCIPAL
// ============================================================
SensorMAX sensor;
DetectorBPM detector;
CalculadorSpO2 spo2Calc;
Grafica grafica;

Boton btnBuzzer;
Boton btnSensor;

void setup() {
  size(800, 400);
  println(Serial.list());

  sensor = new SensorMAX(this, 0, 115200);  // ← "this" pasa el PApplet
  detector = new DetectorBPM(sensor);
  spo2Calc = new CalculadorSpO2();
  grafica = new Grafica(width);

  float btnW = 160, btnH = 40;
  float btnX = width - btnW - 20;
  float btnY = height - btnH - 20;

  btnBuzzer = new Boton(btnX, btnY, btnW, btnH,
                        "BUZZER: ON", "BUZZER: OFF", false,
                        color(0, 180, 0), color(180, 60, 60));

  btnSensor = new Boton(btnX, btnY - btnH - 10, btnW, btnH,
                        "SENSOR: ON", "SENSOR: OFF", true,
                        color(0, 120, 200), color(120, 120, 120));
}

void draw() {
  background(30);

  grafica.dedoDetectado = sensor.dedoDetectado;
  grafica.dibujar();

  fill(255); textAlign(LEFT, CENTER); textSize(16);
  if (!sensor.activo) {
    fill(255); textAlign(CENTER, CENTER);
    text("Sensor apagado", width/2, height/2);
  } else if (grafica.ultimoValor() == 0) {
    fill(255); textAlign(CENTER, CENTER);
    text("Esperando datos IR...", width/2, height/2);
  } else {
    text("IR: " + nf(grafica.ultimoValor(), 0, 0), 20, 20);
    text("SpO2: " + (spo2Calc.spo2 > 0 ? nf(spo2Calc.spo2, 1, 1) + " %" : "--"), 20, 45);
    text("BPM: " + (detector.bpm > 0 ? nf(detector.bpm, 1, 0) : "--"), 20, 70);

    if (!sensor.dedoDetectado) {
      fill(255, 200, 0); text("Sin dedo", 20, 95);
    } else {
      fill(0, 220, 0); text("Dedo detectado", 20, 95);
    }
  }

  fill(150); textSize(11); textAlign(LEFT, BOTTOM);
  text("+/-: maxY  W/S: minY  R: reset  [" +
       nf(grafica.minY,0,0) + ".." + nf(grafica.maxY,0,0) + "]", 10, height-8);

  btnSensor.dibujar();
  btnBuzzer.dibujar();
}

void mousePressed() {
  if (btnSensor.click()) {
    if (btnSensor.estado) {
      sensor.encender();
      grafica.reset();
      detector.reset();
      spo2Calc.reset();
    } else {
      sensor.apagar();
      btnBuzzer.estado = false;
    }
  }

  if (btnBuzzer.click()) {
    sensor.enviar(btnBuzzer.estado ? "BUZZER:ON" : "BUZZER:OFF");
  }
}

void keyPressed() {
  if (key == '+' || key == '=') grafica.ajustarRango(grafica.pasoY);
  else if (key == '-') grafica.ajustarRango(-grafica.pasoY);
  else if (key == 'w' || key == 'W') {
    grafica.minY += grafica.pasoY;
    if (grafica.minY >= grafica.maxY - grafica.pasoY) grafica.minY = grafica.maxY - grafica.pasoY;
  } else if (key == 's' || key == 'S') grafica.minY -= grafica.pasoY;
  else if (key == 'r' || key == 'R') grafica.resetRango();
}

void serialEvent(Serial p) {
  if (p == null || !sensor.activo) return;
  try {
    String linea = p.readStringUntil('\n');
    if (linea == null) return;
    linea = trim(linea);
    if (linea.equals("")) return;

    String[] partes = split(linea, ',');
    if (partes.length < 2) return;

    float ir = float(partes[0]);
    float red = float(partes[1]);

    sensor.actualizarDatos(ir, red);
    grafica.agregar(ir);
    detector.procesar(ir, sensor.dedoDetectado);
    spo2Calc.procesar(ir, red, sensor.dedoDetectado);

  } catch (Exception e) {
    println("Error parseando: " + e.getMessage());
  }
}
