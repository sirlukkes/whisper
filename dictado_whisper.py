import os
import queue
import sys
import threading
import subprocess
import json
import platform
import tkinter as tk
from tkinter import ttk, messagebox
from pynput import keyboard

# Añadir rutas comunes de macOS al PATH para que .app encuentre ffmpeg
os.environ["PATH"] += os.pathsep + "/usr/local/bin" + os.pathsep + "/opt/homebrew/bin"

# Declarar variables globales para módulos pesados que se importarán en segundo plano
np = None
sd = None
sf = None
whisper = None
pyautogui = None
torch = None

def get_device():
    # En macOS con procesador Intel, torch.backends.mps.is_available() puede devolver True,
    # pero falla al cargar el modelo por falta de operadores en GPUs Intel/AMD.
    # Por tanto, solo activamos MPS en Apple Silicon (ARM).
    is_arm = platform.machine().lower() in ("arm64", "arm")
    if torch.cuda.is_available():
        return "cuda"
    elif torch.backends.mps.is_available() and is_arm:
        return "mps"
    else:
        return "cpu"

# Configuración por defecto (guardado en tu carpeta de usuario para que sea compatible al compilar a app)
CONFIG_FILE = os.path.expanduser("~/.dictado_whisper_config.json")
SAMPLE_RATE = 16000
FILENAME = "/tmp/dictado_whisper_temp.wav"

# Variables globales de control
recording = False
audio_data = []
model = None
model_loaded_size = None
listener = None
shortcut = None
status_var = None
root = None

def load_config():
    default_config = {
        "model_size": "tiny",
        "language": "es",
        "hotkey": "<ctrl>+<alt>+r",
        "device_name": "Predeterminado",
        "play_sounds": True
    }
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                config = json.load(f)
                for k, v in default_config.items():
                    if k not in config:
                        config[k] = v
                return config
        except Exception as e:
            print(f"Error cargando config: {e}")
    return default_config

def save_config(config_dict):
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(config_dict, f, indent=4)
    except Exception as e:
        print(f"Error guardando config: {e}")

# Cargar configuración inicial
config = load_config()

def play_sound(sound_name):
    if not config.get("play_sounds", True):
        return
    # Sonidos típicos de macOS: Tink, Glass, Pop, Hero, Ping, Basso, Blow
    sound_path = f"/System/Library/Sounds/{sound_name}.aiff"
    if os.path.exists(sound_path):
        try:
            subprocess.Popen(["afplay", sound_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

def get_input_devices():
    if sd is None:
        return ["Predeterminado"]
    try:
        devices = sd.query_devices()
        input_devices = ["Predeterminado"]
        for idx, dev in enumerate(devices):
            if dev['max_input_channels'] > 0:
                input_devices.append(f"{dev['name']} (ID: {idx})")
        return input_devices
    except Exception as e:
        print(f"Error al listar micrófonos: {e}")
        return ["Predeterminado"]

def get_device_index_from_name(name):
    if not name or name == "Predeterminado":
        return None
    try:
        if "(ID: " in name:
            parts = name.split("(ID: ")
            idx_str = parts[-1].replace(")", "").strip()
            return int(idx_str)
    except Exception:
        pass
    return None

def copy_to_clipboard(text):
    try:
        # En macOS usamos pbcopy para soporte perfecto de caracteres en español
        process = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE, close_fds=True)
        process.communicate(input=text.encode('utf-8'))
        return True
    except Exception as e:
        print(f"Error al copiar al portapapeles: {e}")
        return False

def update_status(text):
    print(f"[LOG] {text}")
    if status_var and root:
        root.after(0, lambda: status_var.set(text))

def load_whisper_model(model_size):
    global model, model_loaded_size
    if model is not None and model_loaded_size == model_size:
        update_status("Listo")
        return True
        
    # Verificar si el archivo ya existe en la caché local para no volverlo a descargar
    default_root = os.path.join(os.path.expanduser("~"), ".cache", "whisper")
    url = None
    if hasattr(whisper, "_MODELS") and model_size in whisper._MODELS:
        url = whisper._MODELS[model_size]
    
    if url:
        filename = os.path.basename(url)
        dest_path = os.path.join(default_root, filename)
        
        # Si no existe localmente, descargarlo de manera manual con indicador de progreso
        if not os.path.exists(dest_path):
            import urllib.request
            os.makedirs(default_root, exist_ok=True)
            try:
                update_status(f"Descargando {model_size} (0 MB)...")
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req) as response:
                    total_size = int(response.info().get('Content-Length', 0))
                    bytes_downloaded = 0
                    block_size = 1024 * 64  # 64 KB
                    
                    with open(dest_path, "wb") as f:
                        while True:
                            buffer = response.read(block_size)
                            if not buffer:
                                break
                            f.write(buffer)
                            bytes_downloaded += len(buffer)
                            if total_size > 0:
                                percent = int((bytes_downloaded / total_size) * 100)
                                downloaded_mb = bytes_downloaded / (1024 * 1024)
                                total_mb = total_size / (1024 * 1024)
                                update_status(f"Descargando '{model_size}': {percent}% ({downloaded_mb:.1f}/{total_mb:.1f} MB)")
            except Exception as e:
                print(f"Error descargando modelo manualmente: {e}")
                if os.path.exists(dest_path):
                    try:
                        os.remove(dest_path)
                    except:
                        pass
        
    update_status(f"Cargando modelo '{model_size}'...")
    try:
        device = get_device()
        # Cargar el modelo en el dispositivo apropiado
        model = whisper.load_model(model_size, device=device)
        model_loaded_size = model_size
        update_status("Listo")
        return True
    except Exception as e:
        err_msg = str(e)
        print(f"Error al cargar modelo: {err_msg}")
        update_status(f"❌ Error al cargar modelo: {err_msg[:60]}...")
        return False

def record_audio():
    global recording, audio_data
    audio_data = []
    
    def callback(indata, frames, time, status):
        if recording:
            audio_data.append(indata.copy())

    try:
        dev_idx = get_device_index_from_name(config.get("device_name"))
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=1, callback=callback, device=dev_idx):
            while recording:
                sd.sleep(100)
    except Exception as e:
        print(f"Error mic: {e}")
        update_status("❌ Error de micrófono")
        recording = False

def run_transcription():
    global recording, model
    update_status("Procesando audio...")
    
    if not audio_data:
        update_status("⚠️ No se grabó audio.")
        return
        
    try:
        # Concatenar y guardar el audio grabado
        audio = np.concatenate(audio_data, axis=0)
        sf.write(FILENAME, audio, SAMPLE_RATE)
        
        if model is None:
            success = load_whisper_model(config["model_size"])
            if not success:
                return
                
        device = get_device()
        use_fp16 = (device != "cpu")
        
        lang = config.get("language", "es")
        lang_code = None if lang == "auto" else lang
        
        update_status("⌛ Transcribiendo...")
        result = model.transcribe(FILENAME, language=lang_code, fp16=use_fp16)
        text = result["text"].strip()
        
        if text:
            update_status(f"✍️ Transcrito: \"{text[:30]}...\"" if len(text) > 30 else f"✍️ Transcrito: \"{text}\"")
            def paste_text():
                if copy_to_clipboard(text):
                    pyautogui.hotkey('command', 'v')
                else:
                    pyautogui.write(text)
            
            # IMPORTANTE: En macOS, pyautogui (o cualquier API de accesibilidad de teclado) 
            # crashea la app (SIGILL) si no corre en el hilo principal.
            if root:
                root.after(0, paste_text)
            else:
                paste_text()
            play_sound("Glass")
        else:
            update_status("⚠️ No se detectó voz.")
            play_sound("Pop")
            
    except Exception as e:
        err_msg = str(e)
        print(f"Error en transcripción: {err_msg}")
        update_status(f"❌ Error: {err_msg[:60]}...")
        play_sound("Basso")
    finally:
        if os.path.exists(FILENAME):
            try:
                os.remove(FILENAME)
            except Exception:
                pass
        # Esperar 3 segundos y volver al estado Listo
        if root:
            root.after(3000, lambda: update_status("Listo"))

def toggle_recording():
    global recording
    if model is None:
        update_status("Cargando modelo...")
        return
        
    if not recording:
        recording = True
        update_status("🎤 Grabando...")
        play_sound("Tink")
        threading.Thread(target=record_audio, daemon=True).start()
    else:
        recording = False
        play_sound("Ping")
        threading.Thread(target=run_transcription, daemon=True).start()

def start_keyboard_listener(shortcut_str):
    global listener, shortcut
    try:
        parsed_shortcut = keyboard.HotKey.parse(shortcut_str)
        shortcut = keyboard.HotKey(
            parsed_shortcut,
            toggle_recording
        )
        
        # Iniciar el hilo del Listener solo una vez para evitar crasheos (SIGILL) en macOS
        if listener is None:
            def on_press(key):
                if shortcut:
                    shortcut.press(key)
                
            def on_release(key):
                if shortcut:
                    shortcut.release(key)
                
            listener = keyboard.Listener(on_press=on_press, on_release=on_release)
            listener.start()
            
        return True
    except Exception as e:
        print(f"Error configurando atajo: {e}")
        if "--headless" not in sys.argv:
            messagebox.showerror("Atajo Inválido", f"No se pudo registrar el atajo '{shortcut_str}'.\nEjemplo de formato: <ctrl>+<alt>+r")
        return False

class WhisperDictationApp:
    def __init__(self, root_win):
        # Configuración de ventana
        self.root = root_win
        self.root.title("Dictado Whisper")
        self.root.geometry("450x550")
        self.root.resizable(True, True)
        
        # Colores
        self.bg_color = "#1e1e2e"       # Fondo
        self.card_color = "#181825"     # Tarjetas
        self.fg_color = "#cdd6f4"       # Texto
        self.accent_color = "#cba6f7"   # Púrpura acento
        self.success_color = "#a6e3a1"  # Verde estado
        self.gray_color = "#a6adc8"     # Gris secundario
        self.entry_bg = "#313244"       # Fondo de inputs
        
        self.root.configure(bg=self.bg_color)
        
        # Opciones de la base de datos de Tkinter para ComboBox Dropdowns
        self.root.option_add("*TCombobox*Listbox.background", self.entry_bg)
        self.root.option_add("*TCombobox*Listbox.foreground", self.fg_color)
        self.root.option_add("*TCombobox*Listbox.selectBackground", self.accent_color)
        self.root.option_add("*TCombobox*Listbox.selectForeground", self.bg_color)
        self.root.option_add("*TCombobox*Listbox.font", ("SF Pro Display", 10))
        
        # Estilos TTK
        self.style = ttk.Style()
        self.style.theme_use('clam')
        self.style.configure("TFrame", background=self.bg_color)
        self.style.configure("TLabel", background=self.bg_color, foreground=self.fg_color, font=("SF Pro Display", 11))
        
        self.create_widgets()
        
        # Cargar librerías y modelo de forma asíncrona
        self.async_initialize_app()
        
        # Iniciar escuchador
        start_keyboard_listener(config["hotkey"])
        
    def create_widgets(self):
        # Frame Principal
        main_frame = ttk.Frame(self.root, padding=25)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Cabecera
        header_lbl = tk.Label(main_frame, text="Dictado Whisper 🎙️", bg=self.bg_color, fg=self.accent_color, font=("SF Pro Display", 18, "bold"))
        header_lbl.pack(pady=(0, 2))
        
        subtitle_lbl = tk.Label(main_frame, text="Dictado rápido por voz 100% local e ilimitado", bg=self.bg_color, fg=self.gray_color, font=("SF Pro Display", 10, "italic"))
        subtitle_lbl.pack(pady=(0, 20))
        
        # Tarjeta de Ajustes
        settings_frame = tk.Frame(main_frame, bg=self.card_color, highlightbackground="#313244", highlightthickness=1)
        settings_frame.pack(fill=tk.X, pady=10, ipady=12, ipadx=12)
        
        # Grid layout dentro de la tarjeta
        settings_frame.columnconfigure(0, weight=1)
        settings_frame.columnconfigure(1, weight=1)
        
        # 1. Selector Modelo
        lbl1 = tk.Label(settings_frame, text="Modelo Whisper:", bg=self.card_color, fg=self.fg_color, font=("SF Pro Display", 10, "bold"))
        lbl1.grid(row=0, column=0, sticky=tk.W, padx=10, pady=8)
        
        self.model_var = tk.StringVar(value=config["model_size"])
        self.model_combo = ttk.Combobox(settings_frame, textvariable=self.model_var, values=["tiny", "base", "small", "medium", "large-v2", "large-v3", "turbo"], state="readonly", width=12)
        self.model_combo.grid(row=0, column=1, sticky=tk.E, padx=10, pady=8)
        
        # 2. Selector Idioma
        lbl2 = tk.Label(settings_frame, text="Idioma:", bg=self.card_color, fg=self.fg_color, font=("SF Pro Display", 10, "bold"))
        lbl2.grid(row=1, column=0, sticky=tk.W, padx=10, pady=8)
        
        self.lang_var = tk.StringVar(value=config["language"])
        self.lang_combo = ttk.Combobox(settings_frame, textvariable=self.lang_var, values=["es", "en", "auto"], state="readonly", width=12)
        self.lang_combo.grid(row=1, column=1, sticky=tk.E, padx=10, pady=8)
        
        # 3. Micrófono
        lbl3 = tk.Label(settings_frame, text="Micrófono:", bg=self.card_color, fg=self.fg_color, font=("SF Pro Display", 10, "bold"))
        lbl3.grid(row=2, column=0, sticky=tk.W, padx=10, pady=8)
        
        self.mic_var = tk.StringVar(value=config["device_name"])
        mics = get_input_devices()
        self.mic_combo = ttk.Combobox(settings_frame, textvariable=self.mic_var, values=mics, state="readonly", width=18)
        self.mic_combo.grid(row=2, column=1, sticky=tk.E, padx=10, pady=8)
        
        # 4. Atajo
        lbl4 = tk.Label(settings_frame, text="Atajo Global:", bg=self.card_color, fg=self.fg_color, font=("SF Pro Display", 10, "bold"))
        lbl4.grid(row=3, column=0, sticky=tk.W, padx=10, pady=8)
        
        self.hotkey_var = tk.StringVar(value=config["hotkey"])
        self.hotkey_entry = tk.Entry(settings_frame, textvariable=self.hotkey_var, bg=self.entry_bg, fg=self.fg_color, insertbackground=self.fg_color, bd=0, width=17, highlightthickness=1, highlightbackground=self.entry_bg, highlightcolor=self.accent_color, font=("SF Pro Display", 10))
        self.hotkey_entry.grid(row=3, column=1, sticky=tk.E, padx=10, pady=8)
        
        # 5. Checkbox de Sonidos
        self.sounds_var = tk.BooleanVar(value=config.get("play_sounds", True))
        self.sounds_chk = tk.Checkbutton(settings_frame, text="Reproducir sonidos de guía", variable=self.sounds_var, bg=self.card_color, fg=self.fg_color, selectcolor=self.card_color, activebackground=self.card_color, activeforeground=self.fg_color, highlightthickness=0, font=("SF Pro Display", 10))
        self.sounds_chk.grid(row=4, column=0, columnspan=2, sticky=tk.W, padx=10, pady=8)
        
        # Botón de Guardado Estilizado (Flat Label)
        self.save_btn = tk.Label(
            main_frame, 
            text="Guardar y Aplicar Cambios", 
            bg=self.accent_color, 
            fg=self.bg_color, 
            font=("SF Pro Display", 11, "bold"), 
            pady=10, 
            cursor="hand2", 
            relief=tk.FLAT
        )
        self.save_btn.pack(fill=tk.X, pady=12)
        self.save_btn.bind("<Button-1>", lambda e: self.save_settings())
        self.save_btn.bind("<Enter>", lambda e: self.save_btn.config(bg="#b4befe"))
        self.save_btn.bind("<Leave>", lambda e: self.save_btn.config(bg=self.accent_color))
        
        # Caja de Estado
        status_frame = tk.Frame(main_frame, bg=self.card_color, highlightbackground="#313244", highlightthickness=1)
        status_frame.pack(fill=tk.X, pady=5, ipady=8)
        
        status_title = tk.Label(status_frame, text="Estado:", bg=self.card_color, fg=self.gray_color, font=("SF Pro Display", 10))
        status_title.pack(side=tk.LEFT, padx=15)
        
        global status_var
        status_var = tk.StringVar(value="Cargando...")
        self.status_lbl = tk.Label(status_frame, textvariable=status_var, bg=self.card_color, fg=self.success_color, font=("SF Pro Display", 11, "bold"), wraplength=380, justify=tk.LEFT)
        self.status_lbl.pack(side=tk.LEFT)
        
        # Instrucciones de uso
        instructions = tk.Label(
            main_frame, 
            text="1. Sitúa el cursor donde quieras escribir.\n2. Presiona tu atajo para iniciar/detener la grabación.",
            bg=self.bg_color, 
            fg=self.gray_color, 
            font=("SF Pro Display", 9, "italic"),
            justify=tk.LEFT
        )
        instructions.pack(side=tk.BOTTOM, pady=(10, 0))
        
    def async_load_model(self):
        def run():
            load_whisper_model(config["model_size"])
        threading.Thread(target=run, daemon=True).start()

    def async_initialize_app(self):
        def run():
            global np, sd, sf, pyautogui, torch, whisper
            
            update_status("Cargando pyautogui (teclado)...")
            import pyautogui as temp_pyautogui
            pyautogui = temp_pyautogui
            
            update_status("Cargando numpy...")
            import numpy as temp_np
            np = temp_np
            
            update_status("Cargando sounddevice (audio)...")
            import sounddevice as temp_sd
            import soundfile as temp_sf
            sd = temp_sd
            sf = temp_sf
            
            # Cargar micrófonos detectados ahora que sounddevice está disponible
            mics = get_input_devices()
            self.root.after(0, lambda: self.mic_combo.config(values=mics))
            
            update_status("Cargando PyTorch (IA)...")
            import torch as temp_torch
            torch = temp_torch
            
            update_status("Cargando OpenAI Whisper...")
            import whisper as temp_whisper
            whisper = temp_whisper
            
            # Cargar el modelo Whisper
            load_whisper_model(config["model_size"])
            
        threading.Thread(target=run, daemon=True).start()
        
    def save_settings(self):
        old_model = config["model_size"]
        old_hotkey = config["hotkey"]
        
        # Leer valores de la GUI
        config["model_size"] = self.model_var.get()
        config["language"] = self.lang_var.get()
        config["device_name"] = self.mic_var.get()
        config["hotkey"] = self.hotkey_var.get().strip()
        config["play_sounds"] = self.sounds_var.get()
        
        save_config(config)
        
        # Actualizar atajo si cambió
        if old_hotkey != config["hotkey"]:
            success = start_keyboard_listener(config["hotkey"])
            if not success:
                self.hotkey_var.set(old_hotkey)
                config["hotkey"] = old_hotkey
                save_config(config)
                return
                
        # Recargar modelo si cambió
        if old_model != config["model_size"]:
            self.async_load_model()
        else:
            messagebox.showinfo("Configuración", "¡Configuración aplicada y guardada con éxito!")

import warnings
import signal

def on_closing():
    global listener
    if listener is not None:
        try:
            listener.stop()
        except Exception:
            pass
    root.destroy()
    sys.exit(0)

if __name__ == "__main__":
    # Ignorar la advertencia de fuga de semáforos de multiprocessing en caso de cierre forzado
    warnings.filterwarnings("ignore", category=UserWarning, module="multiprocessing.resource_tracker")

    root = tk.Tk()
    if "--headless" in sys.argv:
        root.withdraw()
        print("[LOG] Iniciando Whisper en segundo plano (modo headless)...")
    
    # Manejar Ctrl+C de forma limpia desde la terminal
    def sigint_handler(sig, frame):
        print("\n[LOG] Interrupción por consola detectada (Ctrl+C). Cerrando aplicación...")
        root.after(0, on_closing)
        
    signal.signal(signal.SIGINT, sigint_handler)
    
    # Prevenir que la GUI bloquee las señales de Python
    def check_signals():
        root.after(200, check_signals)
    root.after(200, check_signals)
    
    root.protocol("WM_DELETE_WINDOW", on_closing)
    app = WhisperDictationApp(root)
    root.mainloop()
