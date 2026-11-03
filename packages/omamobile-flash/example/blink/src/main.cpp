// SPDX-License-Identifier: MIT
// Blink the DevKit's LED (GPIO 2) and say so on the serial port, so an
// upload from Flash shows both on the board and in the Serial tab.
#include <Arduino.h>

static const int LED = 2;

void setup() {
  Serial.begin(115200);
  pinMode(LED, OUTPUT);
  Serial.println("blink: hello from the phone");
}

void loop() {
  static unsigned long n = 0;
  digitalWrite(LED, n % 2 ? LOW : HIGH);
  Serial.printf("blink %lu\n", n++);
  delay(500);
}
