#define DIR_A 12
#define DIR_B 13
#define BRAKE_A 9
#define BRAKE_B 8
#define PWM_A 3
#define PWM_B 11


int pwmSpeed = 200; // Default forward/backward speed (0–255)
int turnSpeed = 255; // Max speed for turning
String currentCommand = ""; // Track last command
unsigned long lastCommandTime = 0;
const unsigned long commandTimeout = 9000; // stop if no new command in 9000ms


void setup() {
  Serial.begin(9600);
  pinMode(DIR_A, OUTPUT);
  pinMode(DIR_B, OUTPUT);
  pinMode(BRAKE_A, OUTPUT);
  pinMode(BRAKE_B, OUTPUT);
  pinMode(PWM_A, OUTPUT);
  pinMode(PWM_B, OUTPUT);


  digitalWrite(BRAKE_A, LOW);
  digitalWrite(BRAKE_B, LOW);
  stopMotors();
  Serial.println("✅ Ready. Awaiting commands...");
}


void loop() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    lastCommandTime = millis();  // reset timeout timer


    if (command == "forward") {
      currentCommand = "forward";
      Serial.println("OK: forward");
    }
    else if (command == "backward") {
      currentCommand = "backward";
      Serial.println("OK: backward");
    }
    else if (command == "left") {
      currentCommand = "left";
      Serial.println("OK: left");
    }
    else if (command == "right") {
      currentCommand = "right";
      Serial.println("OK: right");
    }
    else if (command == "stop") {
      currentCommand = "";
      stopMotors();
      Serial.println("OK: stop");
    }
    else if (command.startsWith("pwm:")) {
      int value = command.substring(4).toInt();
      if (value >= 0 && value <= 255) {
        pwmSpeed = value;
        Serial.print("OK: pwm ");
        Serial.println(pwmSpeed);
      } else {
        Serial.println("ERROR: PWM must be 0–255");
      }
    }
    else {
      Serial.println("ERROR: Unknown command");
    }
  }


  // If no new command within timeout, stop
  if (millis() - lastCommandTime > commandTimeout) {
    stopMotors();
    currentCommand = "";
  } else {
    // Keep performing the current command
    if (currentCommand == "forward") {
      moveForward();
    } else if (currentCommand == "backward") {
      moveBackward();
    } else if (currentCommand == "left") {
      turnLeft();
    } else if (currentCommand == "right") {
      turnRight();
    }
  }
}


void moveForward() {
  digitalWrite(DIR_A, HIGH);
  digitalWrite(DIR_B, HIGH);
  digitalWrite(BRAKE_A, LOW);
  digitalWrite(BRAKE_B, LOW);
  analogWrite(PWM_A, pwmSpeed);
  analogWrite(PWM_B, pwmSpeed);
}


void moveBackward() {
  digitalWrite(DIR_A, LOW);
  digitalWrite(DIR_B, LOW);
  digitalWrite(BRAKE_A, LOW);
  digitalWrite(BRAKE_B, LOW);
  analogWrite(PWM_A, pwmSpeed);
  analogWrite(PWM_B, pwmSpeed);
}


void turnLeft() {
  digitalWrite(DIR_A, HIGH);
  digitalWrite(DIR_B, LOW);
  digitalWrite(BRAKE_A, LOW);
  digitalWrite(BRAKE_B, LOW);
  analogWrite(PWM_A, turnSpeed);
  analogWrite(PWM_B, turnSpeed);
}


void turnRight() {
  digitalWrite(DIR_A, LOW);
  digitalWrite(DIR_B, HIGH);
  digitalWrite(BRAKE_A, LOW);
  digitalWrite(BRAKE_B, LOW);
  analogWrite(PWM_A, turnSpeed);
  analogWrite(PWM_B, turnSpeed);
}


void stopMotors() {
  digitalWrite(BRAKE_A, HIGH);
  digitalWrite(BRAKE_B, HIGH);
  analogWrite(PWM_A, 0);
  analogWrite(PWM_B, 0);
}










