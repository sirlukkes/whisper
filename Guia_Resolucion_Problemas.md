# 🐛 Guía de Resolución de Problemas: Dictado Whisper en macOS

Durante el desarrollo y conversión del script `dictado_whisper.py` a una aplicación nativa de macOS, nos encontramos con varios problemas técnicos (específicos del ecosistema de Apple, Python y PyTorch).

Este documento documenta **TODOS** los errores enfrentados y cómo se solucionaron, para servir como referencia futura.

---

## 1. Advertencia `FP16 is not supported on CPU`
* **El Problema**: Whisper por defecto intenta procesar el audio en formato de coma flotante de 16 bits (`fp16`). En procesadores Intel (CPU) o sistemas sin tarjetas gráficas CUDA, esto no está soportado y arrojaba una advertencia molesta en la terminal.
* **La Solución**: Se agregó una verificación dinámica del hardware (`get_device()`). Si el dispositivo es `cpu`, se pasa el parámetro `fp16=False` explícitamente a `model.transcribe()` para evitar la advertencia.

## 2. Fuga de Semáforos (`resource_tracker: leaked semaphore objects`)
* **El Problema**: Al cerrar la aplicación desde la terminal usando `Ctrl + C`, la librería `multiprocessing` de Python (usada internamente por PyTorch) no tenía tiempo de limpiar la memoria, arrojando un error de semáforos huérfanos.
* **La Solución**: 
  1. Implementamos la librería `signal` para atrapar el evento `SIGINT` (`Ctrl + C`) y delegar un cierre limpio usando `root.after(0, on_closing)`.
  2. Se agregó un filtro de advertencias: `warnings.filterwarnings("ignore", module="multiprocessing.resource_tracker")` para silenciar los falsos positivos durante el cierre abrupto.

## 3. Error de `ffmpeg` al ejecutar como `.app` (El error "ff...")
* **El Problema**: El script funcionaba perfecto en la terminal, pero al convertirlo a un `.app` de Mac, Whisper fallaba al transcribir porque no encontraba el programa `ffmpeg`. Esto ocurre porque las aplicaciones gráficas en macOS tienen un entorno `$PATH` muy restrictivo que no incluye `/usr/local/bin` ni `/opt/homebrew/bin`.
* **La Solución**: Al inicio del script `.py`, inyectamos manualmente las rutas comunes de macOS al entorno del sistema:
  ```python
  import os
  os.environ["PATH"] += os.pathsep + "/usr/local/bin" + os.pathsep + "/opt/homebrew/bin"
  ```

## 4. Ocultamiento de Errores Reales en la Interfaz (UI)
* **El Problema**: La interfaz de Tkinter tenía la ventana bloqueada (`resizable(False, False)`) y truncaba los errores reales bajo el mensaje genérico `"❌ Error al cargar modelo"`, lo que hacía imposible depurar fallos en producción.
* **La Solución**: 
  * Se hizo la ventana redimensionable: `root.resizable(True, True)`.
  * Se configuró la etiqueta de estado para soportar múltiples líneas: `wraplength=380, justify=tk.LEFT`.
  * Se capturó la excepción real (`except Exception as e:`) y se inyectó dinámicamente en el texto de estado.

## 5. Crasheo de Seguridad de macOS al Pegar Texto (`SIGILL` / `_dispatch_assert_queue_fail`)
* **El Problema**: La aplicación se cerraba abruptamente ("abortaba") justo después de transcribir. Analizando los Crash Logs nativos de macOS, el error era un `Illegal Instruction (SIGILL)`. Esto ocurría porque la librería `pyautogui` intentaba simular la pulsación de teclado (`Command + V`) desde el **hilo secundario (background thread)** que procesaba el audio. En macOS 14+, invocar APIs de Accesibilidad (InputSource) fuera del hilo principal es una violación de seguridad y causa el cierre inmediato de la app.
* **La Solución**: Se encapsuló toda la lógica de `pyautogui` y del portapapeles en una función, y se obligó a que macOS la ejecutara en el hilo principal usando la cola de eventos de Tkinter:
  ```python
  root.after(0, paste_text)
  ```

## 6. Crasheo `SIGILL` al Cambiar el Atajo de Teclado
* **El Problema**: Al modificar la combinación de teclas y pulsar "Guardar", la app volvía a crashear con un error de hardware ilegal. La librería `pynput` crea un ciclo de vida muy delicado ligado a CoreFoundation en Mac. Al hacer `listener.stop()` y casi inmediatamente crear un `new Listener().start()`, los hilos del sistema colisionaban.
* **La Solución**: En lugar de destruir y recrear el escuchador de teclado, se inicializa **el hilo del Listener una única vez** al abrir la app. Si el usuario cambia el atajo, simplemente reescribimos la variable global `shortcut` que el hilo ya activo está leyendo constantemente.

## 7. App Demasiado Pesada con PyInstaller
* **El Problema**: Usar `PyInstaller` para crear el archivo `.app` empaqueta librerías gigantescas como PyTorch, resultando en un archivo ejecutable de más de 2 Gigabytes.
* **La Solución**: Construimos un **Wrapper App (Aplicación Envoltorio)** nativa. Es decir, creamos la estructura de carpetas estándar de Mac (`Contents/MacOS`, `Contents/Resources`) y un pequeño script bash que utiliza la instalación de Python 3.12 del sistema del usuario, logrando que la App pese apenas unos pocos Kilobytes.

## 8. Permisos de Micrófono y Accesibilidad en el `.app`
* **El Problema**: macOS no permite que las aplicaciones graben audio o escuchen el teclado sin permiso expreso, y un `.app` sin el archivo `Info.plist` no puede ni siquiera solicitar esos permisos, por lo que fallaría silenciosamente.
* **La Solución**: Construimos dinámicamente un `Info.plist` con las llaves `NSMicrophoneUsageDescription` y `NSAppleEventsUsageDescription`. Esto fuerza a macOS a mostrarle el cuadro de diálogo de permisos al usuario la primera vez que abre la App.

## 9. Portabilidad de la Aplicación y Cambio de Ícono
* **El Problema**: Originalmente, el `.app` dependía de que el archivo `.py` estuviera en `/Developer/whisper`. Si el usuario movía la app, se rompería. Además, tenía el ícono por defecto genérico de Mac.
* **La Solución**: 
  1. Se copió `dictado_whisper.py` **dentro** de la carpeta `Contents/MacOS/` de la propia aplicación, haciéndola 100% autocontenida y permitiendo borrar la carpeta original.
  2. Se generó un ícono por Inteligencia Artificial y se utilizaron los comandos nativos `sips` e `iconutil` para convertirlos al formato de Apple (`.icns`), inyectándolo en `Contents/Resources/AppIcon.icns`.
