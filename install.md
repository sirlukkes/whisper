# 📋 Guía de Instalación: Dictado Whisper en otra Mac

Esta guía contiene las instrucciones paso a paso para configurar el entorno y hacer funcionar la aplicación **Dictado Whisper.app** en cualquier otra computadora Mac (soporta tanto procesadores Intel como Apple Silicon M1/M2/M3/M4).

---

## ⚡ Instalación Automática (Recomendada)

Si deseas instalar y configurar todo con un solo comando, hemos preparado un script autoejecutable que se encarga de todo.

1. Abre la Terminal de macOS.
2. Navega al directorio donde descargaste el proyecto:
   ```bash
   cd /ruta/a/la/carpeta/whisper
   ```
3. Ejecuta el script de instalación:
   ```bash
   ./setup.sh
   ```
   *El script comprobará Xcode, instalará Homebrew (si no lo tienes), descargará Python 3.12 y las dependencias de audio del sistema, instalará las librerías de Python e intentará remover automáticamente la bandera de cuarentena de la aplicación.*

---

## 🛠️ Instalación Manual (Paso a Paso)

Si prefieres realizar el proceso manualmente o el script automático encuentra algún conflicto de red en tu sistema, sigue estos pasos:

### Requisitos Previos

Si la nueva Mac nunca ha sido configurada para desarrollo, abre la Terminal y ejecuta el siguiente comando para instalar las herramientas de línea de comandos de Apple:

```bash
xcode-select --install
```

### Paso 2: Instalar Homebrew
Homebrew es el gestor de paquetes de macOS necesario para instalar Python 3.12 y los componentes de audio. Si no lo tienes instalado, cópialo y ejecútalo en tu terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

> [!NOTE]
> Sigue las instrucciones al final de la instalación de Homebrew en la consola para añadir `brew` al `$PATH` de tu terminal si es necesario.

### Paso 3: Instalar Dependencias del Sistema
Necesitamos instalar **Python 3.12**, **ffmpeg** (para procesar y transcribir el audio) y **portaudio** (para grabar el micrófono). Ejecuta:

```bash
brew install python@3.12 ffmpeg portaudio
```

### Paso 4: Instalar las Librerías de Python (pip)
Una vez instalado Python 3.12, debemos instalar las librerías requeridas. Es **muy importante** usar `pip3.12` específicamente para que se instalen en el entorno de la versión 3.12:

```bash
pip3.12 install openai-whisper torch sounddevice soundfile numpy pyautogui pynput
```

---

## 📦 Copiar y Desbloquear la Aplicación

1. Copia el archivo **`Dictado Whisper.app`** a la nueva Mac y colócalo en la carpeta **`/Applications`** (Aplicaciones).

2. **Quitar Cuarentena de macOS (¡Crucial!)**:
   Debido a que creamos la aplicación manualmente y contiene scripts de ejecución internos, Gatekeeper de macOS la bloqueará y dirá que está "dañada" o que proviene de un desarrollador no identificado. 
   
   Para solucionar esto de manera segura, abre la Terminal y ejecuta el siguiente comando:

   ```bash
   xattr -rc "/Applications/Dictado Whisper.app"
   ```

   *Este comando limpia los atributos de cuarentena para que la aplicación pueda iniciar normalmente sin advertencias de seguridad.*

---

## 🔒 Otorgar Permisos de Sistema

La primera vez que abras y utilices la aplicación, macOS te solicitará permisos por razones de seguridad. Sigue estos pasos para habilitarlos:

1. **Permiso de Micrófono**: 
   - Al iniciar la grabación de voz por primera vez, el sistema te preguntará si permites que la app acceda al micrófono. Haz clic en **Aceptar**.
   
2. **Permiso de Accesibilidad (Control de Teclado)**:
   - Para que la aplicación pueda pegar el texto transcrito de manera automática usando la combinación `Command + V`, requiere permisos de accesibilidad.
   - Ve a **Configuración del Sistema** ➔ **Privacidad y seguridad** ➔ **Accesibilidad**.
   - Haz clic en el botón `+`, ingresa tu contraseña y busca **Dictado Whisper.app** en la carpeta `/Applications` para agregarla y activarla.
   - Si no aparece en la lista automáticamente, arrastra y suelta **Dictado Whisper.app** directamente dentro de la lista de aplicaciones en el panel de Accesibilidad.

---

## 📂 Ubicación de Modelos y Caché

* **Descarga Automática**: La primera vez que uses la app, Whisper descargará automáticamente el modelo configurado (por defecto `base`, aprox. 140MB) desde los servidores de OpenAI.
* **Carpeta de Caché**: El modelo se guardará en la carpeta oculta de tu usuario: `~/.cache/whisper`.
* **Uso sin Internet**: Una vez descargado el modelo por primera vez, la aplicación funcionará **100% de manera local y offline**, sin necesidad de conexión a internet.

---

## 🛠️ Resolución de Problemas (Troubleshooting)

Si la aplicación no se abre o no transcribe, puedes investigar lo que está ocurriendo detrás de escena:

1. **Ver Logs en Tiempo Real**:
   La app redirige toda la salida interna a un archivo de registro en `/tmp`. Abre la Terminal y ejecuta para ver errores detallados de ejecución:
   ```bash
   cat /tmp/whisper_app.log
   ```

2. **Comprobar Rutas**:
   El launcher está programado para detectar dinámicamente si Python 3.12 está en `/usr/local/bin` (Intel) o `/opt/homebrew/bin` (Apple Silicon). Asegúrate de haber completado exitosamente el **Paso 3** para que el script pueda encontrar el intérprete correcto.
