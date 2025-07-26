#!/bin/bash
set -e

# --- Helper: Check Internet ---
check_internet() {
  echo "🌐 Checking internet connectivity..."
  if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ Internet detected."
    return 0
  else
    echo "⚠️  No internet detected. Skipping package installation."
    return 1
  fi
}

echo "📂 Creating project directory..."
mkdir -p ~/motor_cam_web/templates

echo "📝 Writing Flask app (app.py)..."
cat << 'EOF' > ~/motor_cam_web/app.py
#!/usr/bin/env python3
from flask import Flask, render_template, Response, request, jsonify, send_from_directory
import time
import threading
import cv2
from picamera2 import Picamera2
import serial
import os
import serial.tools.list_ports

app = Flask(__name__)

# -------------------
# GLOBALS
# -------------------
arduino = None
serial_enabled = False
serial_lock = threading.Lock()

# -------------------
# TRY TO CONNECT SERIAL
# -------------------
def try_connect_serial():
    global arduino, serial_enabled
    try:
        # look for first ACM device
        ports = list(serial.tools.list_ports.comports())
        for p in ports:
            if "ACM" in p.device or "ttyUSB" in p.device:
                print("🔌 Found serial device:", p.device)
                arduino = serial.Serial(p.device, 9600, timeout=1)
                time.sleep(2)
                serial_enabled = True
                return
        serial_enabled = False
    except Exception as e:
        print("⚠️ Serial connect error:", e)
        arduino = None
        serial_enabled = False

# -------------------
# MONITOR SERIAL IN BACKGROUND
# -------------------
def monitor_serial():
    global arduino, serial_enabled
    while True:
        with serial_lock:
            if arduino:
                # check if port file still exists
                if not os.path.exists(arduino.port):
                    print("⚠️ Serial device removed:", arduino.port)
                    try:
                        arduino.close()
                    except:
                        pass
                    arduino = None
                    serial_enabled = False
            else:
                try_connect_serial()
        time.sleep(2)

# start monitor thread
threading.Thread(target=monitor_serial, daemon=True).start()

# -------------------
# CAMERA SETUP
# -------------------
picam2 = Picamera2()
camera_config = picam2.create_video_configuration(
    main={
        "size": (1152, 648),
        "format": "RGB888"
    },
    controls={
        "AfMode": 2,       # continuous autofocus
        "AwbEnable": True, # auto white balance
    }
)
picam2.configure(camera_config)
picam2.start()

current_controls = {
    "ColourGains": (1.0, 1.0),
    "Contrast": 1.0,
    "Sharpness": 1.0
}
control_lock = threading.Lock()

def gen_frames():
    while True:
        frame = picam2.capture_array()
        _, buffer = cv2.imencode('.jpg', frame)
        yield (b'--frame\r\n'
               b'Content-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')

# -------------------
# ROUTES
# -------------------
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/serial_status')
def serial_status():
    # return live serial state
    with serial_lock:
        return jsonify(serial_enabled=serial_enabled)

@app.route('/video_feed')
def video_feed():
    return Response(gen_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/control', methods=['POST'])
def control():
    with serial_lock:
        if not serial_enabled or not arduino:
            return 'Serial not available', 400
        direction = request.form['direction']
        if direction in ['forward', 'backward', 'left', 'right', 'stop']:
            try:
                arduino.write((direction + '\n').encode())
                return 'OK'
            except Exception as e:
                return f'Write error: {e}', 500
        return 'Invalid', 400

@app.route('/pwm', methods=['POST'])
def pwm():
    with serial_lock:
        if not serial_enabled or not arduino:
            return 'Serial not available', 400
        try:
            value = int(request.form['value'])
            if 1 <= value <= 255:
                arduino.write((f'pwm:{value}\n').encode())
                return 'PWM sent'
            else:
                return 'Value out of range', 400
        except ValueError:
            return 'Invalid value', 400

@app.route('/camera_control', methods=['POST'])
def camera_control():
    data = request.json
    red_gain = float(data.get('red_gain', 1.0))
    blue_gain = float(data.get('blue_gain', 1.0))
    contrast = float(data.get('contrast', 1.0))
    sharpness = float(data.get('sharpness', 1.0))
    with control_lock:
        current_controls["ColourGains"] = (red_gain, blue_gain)
        current_controls["Contrast"] = contrast
        current_controls["Sharpness"] = sharpness
        picam2.set_controls({
            "AwbEnable": False,
            "ColourGains": (red_gain, blue_gain),
            "Contrast": contrast,
            "Sharpness": sharpness
        })
    return jsonify(success=True)

@app.route('/capture', methods=['POST'])
def capture():
    # Capture current frame and save it
    frame = picam2.capture_array()
    ts = int(time.time())
    filename = f"capture_{ts}.jpg"
    cv2.imwrite(os.path.join("/home/raspi/motor_cam_web", filename), frame)
    return jsonify(success=True, file=filename)

@app.route('/camera_reset', methods=['POST'])
def camera_reset():
    with control_lock:
        current_controls["ColourGains"] = (1.0, 1.0)
        current_controls["Contrast"] = 1.0
        current_controls["Sharpness"] = 1.0
        # Re-enable AWB
        picam2.set_controls({"AwbEnable": True})
    return jsonify(success=True)


@app.route('/<path:filename>')
def download_file(filename):
    # Serve captured files from the motor_cam_web directory
    return send_from_directory('/home/raspi/motor_cam_web', filename)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)


EOF

echo "📝 Writing HTML template (index.html)..."
cat << 'EOF' > ~/motor_cam_web/templates/index.html
<!doctype html>
<html>
<head>
  <title>Robot Motor Control + Camera</title>
  <style>
    body {
      font-family: sans-serif;
      margin: 0;
      padding: 0;
      background: #f4f4f4;
    }
    h1 {
      text-align: center;
      margin: 20px 0;
    }
    .main-container {
      display: flex;
      flex-direction: row;
      justify-content: space-between;
      align-items: flex-start;
      gap: 10px;
      padding: 20px;
      flex-wrap: wrap;
    }

    .controls-section {
      flex: 1;
      max-width: 30%;
      background: #ffffff;
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }

    .video-section {
      flex: 1;
      max-width: 70%;
      background: #ffffff;
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
      display: flex;
      justify-content: center;
      align-items: center;
    }

    /* 👉 On screens narrower than 1280px: stack vertically */
    @media (max-width: 1280px) {
      .main-container {
        flex-direction: column;
      }
      .controls-section,
      .video-section {
        max-width: 100%;
      }
    }

    .adjustments-container{
      display: flex;
      flex-direction: row;
      justify-content: space-between;
      align-items: flex-start;
      gap: 10px;
      padding: 20px;
      flex-wrap: wrap;
    }

    .sliders-section{
      flex: 1;
      max-width: 100%;
      background: #ffffff;
      border-radius: 12px;
      padding: 20px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }

    button {
      width: 80px;
      height: 80px;
      font-size: 20px;
      margin: 5px;
      border-radius: 12px;
      border: none;
      background: #2196f3;
      color: white;
      box-shadow: 0 4px 6px rgba(0,0,0,0.2);
      cursor: pointer;
      transition: background 0.2s;
    }
    button:hover { background: #0b7dda; }
    button:active { background: #005fa3; }
    .stop-btn {
      background: #f44336;
    }
    .stop-btn:hover { background: #d32f2f; }
    .grid {
      display: grid;
      grid-template-columns: 100px 100px 100px;
      grid-template-rows: 100px 100px 100px;
      justify-content: center;
      align-items: center;
      margin-bottom: 20px;
    }
    input[type=range] {
      width: 100%;
    }
    #pwmValue {
      display: inline-block;
      margin-left: 10px;
      font-weight: bold;
    }
  </style>
</head>
<body>
  <!-- <h1>Control the Robot</h1> -->

  <div class="main-container">
   <!-- Video Section -->
    <div class="video-section">
      <img src="{{ url_for('video_feed') }}" width="100%" style="border-radius:8px;">
    </div>
    <!-- Controls Section -->
    <div class="controls-section">
      <h2>Controls</h2>
      <div id="controls-enabled">
        <div class="grid">
          <div></div>
          <button onclick="sendCommand('forward')">⬆️</button>
          <div></div>
          <button onclick="sendCommand('left')">⬅️</button>
          <button class="stop-btn" onclick="sendCommand('stop')">⏹️</button>
          <button onclick="sendCommand('right')">➡️</button>
          <div></div>
          <button onclick="sendCommand('backward')">⬇️</button>
          <div></div>
        </div>
        <button style="width:100%;height:50px;font-size:16px;margin-top:10px;"onclick="capturePhoto()">📸 Capture Photo</button>
        <h3>Speed Control (PWM)</h3>
        <input type="range" min="1" max="255" value="128" id="pwmSlider" oninput="sendPWM(this.value)">
        <span id="pwmValue">128</span>
      </div>
      <div id="controls-disabled" style="display:none;">
        <p style="color:red;">Serial not detected. Controls disabled.</p>
      </div>
    </div>
  </div>
  <div class="adjustments-container">
   <!-- Camera Adjustments Section -->
    <div class="sliders-section">
        <h3>Camera Adjustments</h3>
        <div class="slider-group">
          <label>Red Gain:</label>
          <input type="range" id="red_gain" min="0.5" max="2.5" step="0.1" value="1.0">
          <span id="red_gain_val">1.0</span>
        </div>
        <div class="slider-group">
          <label>Blue Gain:</label>
          <input type="range" id="blue_gain" min="0.5" max="2.5" step="0.1" value="1.0">
          <span id="blue_gain_val">1.0</span>
        </div>
        <div class="slider-group">
          <label>Contrast:</label>
          <input type="range" id="contrast" min="0.0" max="32.0" step="0.1" value="1.0">
          <span id="contrast_val">1.0</span>
        </div>
        <div class="slider-group">
          <label>Sharpness:</label>
          <input type="range" id="sharpness" min="0.0" max="16.0" step="0.1" value="1.0">
          <span id="sharpness_val">1.0</span>
        </div>
        <button style="width:100%;height:50px;font-size:16px;margin-top:20px;background:#4caf50;" onclick="resetAdjustments()">🔄 Reset Adjustments</button>
    </div>
  </div>
   

  <script>
    function sendCommand(direction) {
      fetch('/control', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'direction=' + direction
      });
    }

    function sendPWM(value) {
      document.getElementById('pwmValue').innerText = value;
      fetch('/pwm', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'value=' + value
      });
    }

    function updateCameraControls() {
      const red_gain = parseFloat(document.getElementById('red_gain').value);
      const blue_gain = parseFloat(document.getElementById('blue_gain').value);
      const contrast = parseFloat(document.getElementById('contrast').value);
      const sharpness = parseFloat(document.getElementById('sharpness').value);

      document.getElementById('red_gain_val').innerText = red_gain.toFixed(1);
      document.getElementById('blue_gain_val').innerText = blue_gain.toFixed(1);
      document.getElementById('contrast_val').innerText = contrast.toFixed(1);
      document.getElementById('sharpness_val').innerText = sharpness.toFixed(1);

      fetch('/camera_control', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          red_gain: red_gain,
          blue_gain: blue_gain,
          contrast: contrast,
          sharpness: sharpness
        })
      });
    }

   function capturePhoto() {
	  fetch('/capture', {method:'POST'})
	    .then(r => r.json())
	    .then(data => {
	      if (data.success) {
	        // Ask user if they want to download
	        if (confirm('✅ Photo saved as ' + data.file + '.\nDo you want to download it now?')) {
	          // Create a temporary download link
	          const a = document.createElement('a');
	          a.href = '/' + data.file;   // make sure Flask serves static files in that folder
	          a.download = data.file;
	          document.body.appendChild(a);
	          a.click();
	          document.body.removeChild(a);
	        }
	      }
	    });
	}


    function resetAdjustments() {
      fetch('/camera_reset', {method:'POST'})
        .then(r => r.json())
        .then(data => {
          if(data.success){
            // Reset slider UI values
            document.getElementById('red_gain').value = 1.0;
            document.getElementById('blue_gain').value = 1.0;
            document.getElementById('contrast').value = 1.0;
            document.getElementById('sharpness').value = 1.0;
            document.getElementById('red_gain_val').innerText = '1.0';
            document.getElementById('blue_gain_val').innerText = '1.0';
            document.getElementById('contrast_val').innerText = '1.0';
            document.getElementById('sharpness_val').innerText = '1.0';
            alert('✅ Adjustments reset and Auto WB enabled.');
          }
        });
    }


    document.querySelectorAll('#red_gain,#blue_gain,#contrast,#sharpness').forEach(slider => {
      slider.addEventListener('input', updateCameraControls);
    });


    function checkSerialStatus() {
      fetch('/serial_status')
        .then(r => r.json())
        .then(data => {
          if (data.serial_enabled) {
            document.getElementById('controls-enabled').style.display = '';
            document.getElementById('controls-disabled').style.display = 'none';
          } else {
            document.getElementById('controls-enabled').style.display = 'none';
            document.getElementById('controls-disabled').style.display = '';
          }
        });
    }
    setInterval(checkSerialStatus, 2000);
    checkSerialStatus();



    // KEY PRESS continuous
    let activeKey = null;
    document.addEventListener('keydown', e => {
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' '].includes(e.key)) {
        e.preventDefault();  // ✅ prevent scroll
      }
      if (activeKey) return;  // already pressed
      switch(e.key) {
        case 'ArrowUp': sendCommand('forward'); activeKey = e.key; break;
        case 'ArrowDown': sendCommand('backward'); activeKey = e.key; break;
        case 'ArrowLeft': sendCommand('left'); activeKey = e.key; break;
        case 'ArrowRight': sendCommand('right'); activeKey = e.key; break;
      }
    });

    document.addEventListener('keyup', e => {
      if (e.key === activeKey) {
        sendCommand('stop');
        activeKey = null;
      }
    });
  </script>
</body>
</html>


EOF

# Install deps only if internet
if check_internet; then
  echo "🔧 Installing dependencies..."
  sudo apt update
  sudo apt install -y python3-picamera2 python3-flask python3-serial python3-opencv
else
  echo "⏭️  Skipping dependency installation."
fi

echo "⚙️ Creating systemd service file..."
cat << 'EOF' | sudo tee /etc/systemd/system/motorweb.service > /dev/null
[Unit]
Description=Flask App for Robot Motor Control and Camera
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/raspi/motor_cam_web/app.py
WorkingDirectory=/home/raspi/motor_cam_web
StandardOutput=inherit
StandardError=inherit
Restart=always
User=raspi

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Reloading systemd daemon and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable motorweb.service
sudo systemctl restart motorweb.service

echo "✅ Setup complete!"
echo "👉 Open http://$(hostname -I | awk '{print $1}'):5000 in your browser"
