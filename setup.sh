#!/bin/bash

# ==============================================================================
# 🚀 Script de Configuración Automatizada para Dictado Whisper
# ==============================================================================
# Este script instalará automáticamente Homebrew, Python 3.12, ffmpeg, portaudio
# y todas las dependencias de Python necesarias para ejecutar Dictado Whisper.
# También eliminará la cuarentena de macOS sobre la aplicación.
# ==============================================================================

# Colores para salida en consola
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0;57m' # No Color
NC='\033[0m'

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}   🎙️  Iniciando Instalador de Dictado Whisper 🎙️   ${NC}"
echo -e "${BLUE}=====================================================${NC}"

# 1. Verificar si estamos en macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌ Este script está diseñado exclusivamente para macOS.${NC}"
    exit 1
fi

# 2. Verificar Xcode Command Line Tools
echo -e "\n${YELLOW}[1/5] Verificando Xcode Command Line Tools...${NC}"
if xcode-select -p &>/dev/null; then
    echo -e "${GREEN}✓ Xcode Command Line Tools ya están instaladas.${NC}"
else
    echo -e "${YELLOW}Instalando Xcode Command Line Tools. Por favor sigue las instrucciones en pantalla...${NC}"
    xcode-select --install
    echo -e "${YELLOW}Presiona ENTER una vez que la instalación de Xcode haya finalizado para continuar...${NC}"
    read -r
fi

# 3. Verificar e instalar Homebrew
echo -e "\n${YELLOW}[2/5] Verificando Homebrew...${NC}"
# Cargar Homebrew en el PATH actual si ya está instalado pero no en la sesión
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if command -v brew &>/dev/null; then
    echo -e "${GREEN}✓ Homebrew ya está instalado (${BLUE}$(brew --version | head -n 1)${GREEN}).${NC}"
else
    echo -e "${YELLOW}Homebrew no fue encontrado. Instalando Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Configurar Homebrew en el entorno actual inmediatamente
    if [ -d "/opt/homebrew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# 4. Instalar dependencias del sistema con Homebrew
echo -e "\n${YELLOW}[3/5] Instalandocomponentes del sistema (Python 3.12, ffmpeg, portaudio)...${NC}"
brew install python@3.12 ffmpeg portaudio

# 5. Instalar librerías de Python usando pip3.12
echo -e "\n${YELLOW}[4/5] Instalando librerías de Python...${NC}"

# Asegurar que estamos usando el pip correcto
PYTHON_BIN=""
if [ -f "/opt/homebrew/bin/python3.12" ]; then
    PYTHON_BIN="/opt/homebrew/bin/python3.12"
elif [ -f "/usr/local/bin/python3.12" ]; then
    PYTHON_BIN="/usr/local/bin/python3.12"
else
    PYTHON_BIN="python3.12"
fi

echo -e "Usando Python en: ${BLUE}$PYTHON_BIN${NC}"

# Intentar instalación estándar de pip
echo -e "Instalando paquetes: openai-whisper, torch, sounddevice, soundfile, numpy, pyautogui, pynput..."
if "$PYTHON_BIN" -m pip install openai-whisper torch sounddevice soundfile numpy pyautogui pynput; then
    echo -e "${GREEN}✓ Paquetes instalados con éxito.${NC}"
else
    echo -e "${YELLOW}La instalación estándar falló o detectó un entorno administrado (PEP 668).${NC}"
    echo -e "${YELLOW}Reintentando con flag --break-system-packages para instalación global...${NC}"
    if "$PYTHON_BIN" -m pip install openai-whisper torch sounddevice soundfile numpy pyautogui pynput --break-system-packages; then
        echo -e "${GREEN}✓ Paquetes instalados con éxito usando --break-system-packages.${NC}"
    else
        echo -e "${RED}❌ Error crítico al instalar los paquetes de Python.${NC}"
        echo -e "${RED}Revisa la salida de error arriba para depurar.${NC}"
        exit 1
    fi
fi

# 6. Desbloquear la aplicación (Quitar Cuarentena de macOS)
echo -e "\n${YELLOW}[5/5] Desbloqueando la aplicación...${NC}"

APP_PATHS=(
    "/Applications/Dictado Whisper.app"
    "./Dictado Whisper.app"
    "../Dictado Whisper.app"
)

APP_UNLOCKED=false

for path in "${APP_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo -e "Quitando bandera de cuarentena para: ${BLUE}$path${NC}"
        xattr -rc "$path"
        APP_UNLOCKED=true
    fi
done

if [ "$APP_UNLOCKED" = true ]; then
    echo -e "${GREEN}✓ Aplicación desbloqueada correctamente.${NC}"
else
    echo -e "${YELLOW}⚠️  No se encontró 'Dictado Whisper.app' en /Applications ni en el directorio actual.${NC}"
    echo -e "${YELLOW}Una vez que muevas la app a /Applications, ejecuta en la Terminal:${NC}"
    echo -e "${BLUE}xattr -rc \"/Applications/Dictado Whisper.app\"${NC}"
fi

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}🎉   ¡Configuración del entorno completada!   🎉${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "\n${YELLOW}📢 NOTAS IMPORTANTES PARA EL PRIMER USO:${NC}"
echo -e "1. ${BLUE}Permiso de Micrófono:${NC} Al iniciar la primera grabación, haz clic en 'Aceptar'."
echo -e "2. ${BLUE}Permiso de Accesibilidad:${NC} Ve a 'Configuración del Sistema' -> 'Privacidad y seguridad'"
echo -e "   -> 'Accesibilidad' y asegúrate de activar/agregar 'Dictado Whisper.app'."
echo -e "3. ${BLUE}Primer Dictado:${NC} Puede tardar un momento la primera vez mientras se descarga el modelo"
echo -e "   de Whisper (140MB) en segundo plano."
echo -e "4. ${BLUE}Logs de Depuración:${NC} Si la app no abre, revisa los logs en: ${BLUE}cat /tmp/whisper_app.log${NC}"
echo -e "=====================================================\n"
