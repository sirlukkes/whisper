import os
import stat

APP_NAME = "Dictado Whisper"
APP_DIR = f"{APP_NAME}.app"
CONTENTS_DIR = os.path.join(APP_DIR, "Contents")
MACOS_DIR = os.path.join(CONTENTS_DIR, "MacOS")
RESOURCES_DIR = os.path.join(CONTENTS_DIR, "Resources")

# Crear directorios
os.makedirs(MACOS_DIR, exist_ok=True)
os.makedirs(RESOURCES_DIR, exist_ok=True)

# Obtener la ruta absoluta del script actual y de python
script_path = os.path.abspath("dictado_whisper.py")
python_path = "/usr/local/bin/python3.12" # Podemos usar sys.executable pero hardcodear python3.12 puede ser más seguro basado en el entorno del usuario.

import sys
python_path = sys.executable

# Crear el script de lanzamiento en bash
launcher_script = f"""#!/bin/bash
# Script de lanzamiento para la app
cd "{os.path.dirname(script_path)}"
"{python_path}" "{script_path}"
"""

launcher_path = os.path.join(MACOS_DIR, APP_NAME)
with open(launcher_path, "w") as f:
    f.write(launcher_script)

# Dar permisos de ejecución al script
st = os.stat(launcher_path)
os.chmod(launcher_path, st.st_mode | stat.S_IEXEC)

# Crear el Info.plist (crítico para permisos de micrófono en macOS)
info_plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.lukkes.dictadowhisper</string>
    <key>CFBundleName</key>
    <string>{APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Esta aplicación necesita acceso al micrófono para grabar tu voz y transcribirla a texto usando Whisper.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Esta aplicación necesita controlar el teclado para pegar el texto transcrito.</string>
</dict>
</plist>
"""

with open(os.path.join(CONTENTS_DIR, "Info.plist"), "w") as f:
    f.write(info_plist)

print(f"✅ ¡App '{APP_NAME}.app' creada con éxito!")
print("Puedes moverla a tu carpeta de Aplicaciones e iniciarla con doble clic.")
