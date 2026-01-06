# Amazon Echo Dot 2 (Biscuit) - Sterowanie LED przez MQTT i Root

[🇺🇸 English Version](README.md)

To repozytorium zawiera skrypty i instrukcje pokazane w moim filmie na YouTube, dotyczącym modowania **Amazon Echo Dot 2. generacji (2016)**, o nazwie kodowej **"biscuit"**.

Dzięki zrootowaniu tego urządzenia i użyciu poniższych skryptów, możesz przejąć pełną kontrolę nad pierścieniem LED za pomocą MQTT (idealne dla Home Assistant) oraz włączyć ADB przez Wi-Fi.

<div align="center">
  <a href="https://www.youtube.com/watch?v=PwSRFhiGyJs">
    <img src="https://img.youtube.com/vi/PwSRFhiGyJs/0.jpg" alt="YouTube Video">
  </a>
  <br>
  <em>(Kliknij obrazek, aby obejrzeć poradnik)</em>
</div>

## ⚠️ Uwaga (Disclaimer)
**Nie ponoszę odpowiedzialności za uszkodzone urządzenia (tzw. cegły/bricked devices).** Proces ten wymaga fizycznej ingerencji w urządzenie (zwarcie pinów) i modyfikacji partycji systemowych. Robisz to na własną odpowiedzialność.

## Wymagania

1.  **Amazon Echo Dot 2. generacji** (Model RS03QR).
2.  **Dostęp do Roota:** Musisz najpierw odblokować bootloader i zrootować urządzenie, korzystając z poradnika użytkownika `rortiz2` na XDA.
    *   🔗 [Wątek XDA: Unlock/Root/TWRP/Unbrick Amazon Echo Dot 2nd Gen](https://xdaforums.com/t/unlock-root-twrp-unbrick-amazon-echo-dot-2nd-gen-2016-biscuit.4761416/)
3.  **Najnowszy Magisk:** Poradnik na XDA instaluje Magiska w wersji 17.1. **Musisz zaktualizować Magiska do nowszej wersji** (v24+), aby skrypty `service.d` działały poprawnie (jak wspomniałem w filmie).
4.  **Binarki Mosquitto:** Dołączone do tego repozytorium (skompilowane pod ARM64 `mosquitto_sub` oraz `mosquitto_pub`).

## Zawartość Repozytorium

*   `led_mqtt.sh`: Główny skrypt usługi. Łączy się z brokerem MQTT, nasłuchuje komend JSON i steruje diodami LED (obsługuje statyczne kolory bez migotania oraz animacje).
*   `adb_tcp.sh`: Prosty skrypt włączający ADB przez Wi-Fi przy starcie systemu (Port 5555).
*   `mosquitto_sub` / `mosquitto_pub`: Wymagane pliki binarne do komunikacji MQTT.

## Instrukcja Instalacji

### Krok 1: Konfiguracja Skryptów
Otwórz plik `led_mqtt.sh` w edytorze tekstu na komputerze i **edytuj sekcję konfiguracyjną**, wpisując dane swojej sieci:

```bash
# MQTT Settings
MQTT_HOST="192.168.1.XX"      # IP twojego Brokera/Home Assistant
MQTT_USER="TwojUzytkownik"    # Nazwa użytkownika MQTT
MQTT_PASS="TwojeHaslo"        # Hasło MQTT
```

### Krok 2: Przesyłanie plików na Echo Dot
Nie możemy wysłać plików bezpośrednio do folderów systemowych. Najpierw musimy wysłać je na `/sdcard/`, a potem przenieść jako Root.

1.  Podłącz Echo Dot kablem USB.
2.  Wyślij pliki przez ADB:
    ```bash
    adb push led_mqtt.sh /sdcard/
    adb push adb_tcp.sh /sdcard/
    adb push mosquitto_pub /sdcard/
    adb push mosquitto_sub /sdcard/
    ```

### Krok 3: Instalacja w `service.d`
Wejdź do konsoli urządzenia i przenieś pliki do folderu usług Magiska, aby uruchamiały się przy starcie.

```bash
adb shell
su
```

*Przyznaj uprawnienia roota na urządzeniu, jeśli zostaniesz o to poproszony.*

Teraz przenieś pliki i nadaj im uprawnienia:

```bash
# 1. Instalacja binarek Mosquitto
mv /sdcard/mosquitto_pub /data/adb/
mv /sdcard/mosquitto_sub /data/adb/
chmod 755 /data/adb/mosquitto_pub
chmod 755 /data/adb/mosquitto_sub

# 2. Instalacja skryptów usług
mv /sdcard/led_mqtt.sh /data/adb/service.d/
mv /sdcard/adb_tcp.sh /data/adb/service.d/
chmod 755 /data/adb/service.d/led_mqtt.sh
chmod 755 /data/adb/service.d/adb_tcp.sh
```

### Krok 4: Restart
Zrestartuj urządzenie. Diody LED powinny się zaświecić (jeśli są skonfigurowane) lub połączyć z brokerem. ADB przez Wi-Fi będzie aktywne na porcie 5555.

```bash
reboot
```

## Konfiguracja Home Assistant

Dodaj poniższy kod do swojego pliku `configuration.yaml`. Ta konfiguracja używa schematu JSON i obsługuje jasność, kolory RGB oraz efekty.

```yaml
mqtt:
  light:
    - name: "Echo Dot LED"
      unique_id: "echo_dot_mqtt_led"
      schema: json
      command_topic: "echodot/light/set"
      state_topic: "echodot/light/state"
      brightness: true
      supported_color_modes: ["rgb"]
      effect: true
      effect_list:
        - "Stop Effect"
        - "rainbow"
        - "notification"
        - "pulse_blue"
      optimistic: false
      qos: 0
```

## Rozwiązywanie Problemów

Jeśli diody nie działają:

1.  **Sprawdź logi:**
    ```bash
    adb shell cat /data/adb/led_mqtt.log
    ```
2.  **Sprawdź uprawnienia:** Upewnij się, że wszystkie pliki w `/data/adb/service.d/` oraz `/data/adb/` mają uprawnienia wykonywalne (`chmod 755`).
3.  **Test ręczny:** Spróbuj uruchomić skrypt ręcznie, aby zobaczyć ewentualne błędy:
    ```bash
    adb shell
    su
    /data/adb/service.d/led_mqtt.sh
    ```