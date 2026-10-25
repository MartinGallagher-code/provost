"""`arduino-cli board list | core list | lib list | board listall`: tables
with single-space gutters, multi-word headers and values, empty trailing
cells for unknown boards, and `-` placeholders."""
from lib import Doc, fake

TOOL = "arduino-cli"

BOARDS = [("Arduino Uno", "arduino:avr:uno", "arduino:avr"), ("Arduino Mega or Mega 2560", "arduino:avr:mega", "arduino:avr"),
          ("Arduino Nano 33 IoT", "arduino:samd:nano_33_iot", "arduino:samd"),
          ("Arduino Leonardo", "arduino:avr:leonardo", "arduino:avr"),
          ("ESP32 Dev Module", "esp32:esp32:esp32", "esp32:esp32"),
          ("Raspberry Pi Pico", "rp2040:rp2040:rpipico", "rp2040:rp2040"),
          ("Arduino UNO R4 WiFi", "arduino:renesas_uno:unor4wifi", "arduino:renesas_uno"),
          ("Arduino Nano ESP32", "arduino:esp32:nano_nora", "arduino:esp32")]
CORES = [("arduino:avr", "Arduino AVR Boards", ["1.8.5", "1.8.6"]), ("arduino:samd", "Arduino SAMD Boards (32-bits ARM Cortex-M0+)", ["1.8.13", "1.8.14"]),
         ("esp32:esp32", "esp32", ["2.0.11", "2.0.14", "3.0.4"]), ("rp2040:rp2040", "Raspberry Pi Pico/RP2040", ["3.6.0", "3.9.5"]),
         ("arduino:renesas_uno", "Arduino UNO R4 Boards", ["1.0.5", "1.2.0"]), ("arduino:mbed_nano", "Arduino Mbed OS Nano Boards", ["4.0.10", "4.1.5"]),
         ("esp8266:esp8266", "esp8266", ["3.1.2"])]
LIBS = [("ArduinoJson", ["6.21.3", "7.0.4", "7.2.0"], "A simple and efficient JSON library for embedded C++."),
        ("PubSubClient", ["2.8"], "A client library for MQTT messaging."),
        ("Adafruit NeoPixel", ["1.11.0", "1.12.3"], "Arduino library for controlling single-wire-based LED pixels and strip."),
        ("DHT sensor library", ["1.4.4", "1.4.6"], "Arduino library for DHT11, DHT22, etc Temp & Humidity Sensors"),
        ("LoRa", ["0.8.0"], "An Arduino library for sending and receiving data using LoRa radios."),
        ("RadioHead", ["1.122.1"], "-"), ("WiFiNINA", ["1.8.14"], "Enables network connection (local and Internet) with the Arduino boards."),
        ("Servo", ["1.2.1", "1.2.2"], "Allows Arduino boards to control a variety of servo motors."),
        ("MySensors", ["2.3.2"], "Home Automation Framework")]


def board_list(d, rng):
    rows = []
    for _ in range(rng.randint(1, 6)):
        c = rng.random()
        if c < .4:
            port = rng.choice(["/dev/ttyS0", "/dev/ttyS1", "/dev/cu.Bluetooth-Incoming-Port", "COM1", "/dev/ttyAMA0"])
            rows.append([port, "serial", "Serial Port", "Unknown", None, None])
        elif c < .85:
            name, fqbn, core = rng.choice(BOARDS)
            port = rng.choice([f"/dev/ttyACM{rng.randint(0, 3)}", f"/dev/ttyUSB{rng.randint(0, 3)}",
                               f"/dev/cu.usbmodem{rng.randint(1000, 149999)}", f"COM{rng.randint(3, 12)}"])
            if rng.random() < .15:
                rows.append([port, "serial", "Serial Port (USB)", "Unknown", None, None])
            else:
                rows.append([port, "serial", "Serial Port (USB)", name, fqbn, core])
        else:
            name, fqbn, core = rng.choice(BOARDS)
            rows.append([fake.ip(rng), "network", "Network Port", name, fqbn, core])
    d.table(["Port", "Protocol", "Type", "Board Name", "FQBN", "Core"], rows, gap=1)


def core_list(d, rng):
    rows = []
    for cid, name, vers in sorted(rng.sample(CORES, rng.randint(1, len(CORES)))):
        inst = rng.choice(vers)
        rows.append([cid, inst, vers[-1], name])
    d.table(["ID", "Installed", "Latest", "Name"], rows, gap=1)


def lib_list(d, rng):
    rows = []
    for name, vers, desc in sorted(rng.sample(LIBS, rng.randint(1, len(LIBS)))):
        inst = rng.choice(vers)
        avail = vers[-1] if inst != vers[-1] else "-"
        loc = rng.choice(["LIBRARY_LOCATION_USER", "LIBRARY_LOCATION_USER", "LIBRARY_LOCATION_PLATFORM_BUILTIN",
                          "user", "platform"])
        rows.append([name, inst, avail, loc, desc])
    d.table(["Name", "Installed", "Available", "Location", "Description"], rows, gap=1)


def listall(d, rng):
    rows = [[n, f] for n, f, _ in rng.sample(BOARDS, rng.randint(2, len(BOARDS)))]
    rows.sort()
    d.table(["Board Name", "FQBN"], rows, gap=1)


def generate(rng):
    d = Doc()
    rng.choice([board_list, board_list, core_list, lib_list, listall])(d, rng)
    if rng.random() < .2:
        d.blank()
    return d
