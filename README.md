***For English version scroll down***

# REAPER Live Show Setlist Controller

Ein Lua-Script für **REAPER**, das Setlists für Live-Shows verwaltet und die Steuerung von Songs (Play, Pause, Next, Prev) direkt im REAPER-Interface ermöglicht.  
Es gibt zwei Hauptmodi:

- **Edit-Modus** – Erstellen, Bearbeiten und Anordnen der Setlist.
- **Show-Modus** – Anzeige der Setlist in Großschrift für Live-Performance mit direkter Steuerung.

⚠️ **Wichtiger Hinweis**: Die Benutzung dieses Scripts für Live-Shows erfolgt **auf eigene Gefahr**!  
Bitte immer vorher ausgiebig testen, um Ausfälle oder unerwartetes Verhalten während der Performance zu vermeiden.

---

## Features

- **Setlist-Verwaltung**
  - Songs hinzufügen, umsortieren, entfernen.
  - Mehrere Setlists speichern und laden.
- **Show-Modus**
  - Große, gut lesbare Anzeige aller Songs.
  - Steuerbuttons für *Prev*, *Play/Pause*, *Next* direkt verfügbar.
  - Identisches Layout wie im Edit-Modus (nur optimiert für Live).
- **Leader/Follower-Modus**
  - Synchronisation zwischen mehreren Rechnern über Netzwerk.
- **Dark Mode** & Fensteroptionen (*Windowed*, Vollbild).
- Speichert automatisch die zuletzt geladene Setlist.

---

## Voraussetzungen

Damit das Script reibungslos funktioniert, müssen folgende Punkte beachtet werden:

### Erforderlich
- **REAPER 6.x oder neuer** (wegen GUI- und TCP-Funktionen im Script).  
- **SWS Extension** installiert → [Download hier](https://www.sws-extension.org/)  
  - Die SWS-Extension wird für erweiterte Funktionen in REAPER benötigt.
- **Script-API in REAPER aktivieren**  
  - Menü **Options → Preferences → Plug-ins → ReaScript**
  - **"Enable Lua"** muss aktiviert sein.

### Optional (empfohlen für Live)
- **Smooth Seeking aktivieren**  
  - Menü **Options → Smooth seek (smooth seek on bar/beat change)**
  - Sorgt dafür, dass Songs beim Wechsel an Takt- oder Beat-Grenzen starten → keine abrupten Sprünge.
- **Auto-Scroll in Arrange View deaktivieren**  
  - Damit die Ansicht während der Show nicht springt.
- **Zweiten Bildschirm im Show-Modus** nutzen  
  - Ideal, um die Setlist groß für Musiker anzuzeigen.

---

## Installation

1. **Script herunterladen**  
   Lade die `.lua`-Datei dieses Projekts von GitHub herunter.

2. **In REAPER importieren**  
   - Öffne in REAPER das Menü: `Actions` → `Show Action List`.
   - Klicke auf **Load...** und wähle die heruntergeladene `.lua`-Datei.
   - Script erscheint nun in der Liste und kann wie jede andere Action gestartet werden.

3. **Optional: Toolbar-Button erstellen**  
   - In REAPER `View` → `Toolbars` öffnen.
   - Rechtsklick → `Add action` → dein Script auswählen.
   - Icon zuweisen (optional).

---

## Verwendung

1. **Edit-Modus starten**  
   - Songs hinzufügen, Reihenfolge ändern, speichern.

2. **Show-Modus starten**  
   - Große Anzeige aller Songs, Steuerung per Mausklick oder Tastenkürzel.
   - Perfekt für Live-Shows auf einem zweiten Bildschirm.

3. **Tastatursteuerung**  
   - `← / →` für Prev/Next Song.
   - `Space` für Play/Pause.

---

## Leader/Follower Setup (optional)

Der Leader/Follower-Modus erlaubt es, dass **mehrere Rechner synchronisiert** dieselbe Show steuern oder anzeigen.  
Das ist nützlich, wenn z. B. du auf der Bühne den Leader bedienst, während am FOH (Front of House) ein Techniker die Show in Echtzeit mitverfolgt.

### Funktionsweise
- **Leader**
  - Startet, pausiert und wechselt Songs.
  - Sendet Steuerbefehle per **TCP-Netzwerk** an alle verbundenen Follower.
  - Führt auch die Setlist und sendet Änderungen live an die Follower.

- **Follower**
  - Empfängt Befehle vom Leader.
  - Spielt Songs synchron mit ab oder zeigt nur die Songliste im Show-Modus.
  - Kann nicht selbst steuern (reiner Zuhörer).

### Einrichtung
1. **Leader-PC**
   - Im Script **"Leader Mode"** aktivieren.
   - **Port** festlegen (z. B. `5000`).

2. **Follower-PC**
   - Im Script **"Follower Mode"** aktivieren.
   - **IP-Adresse des Leaders** und denselben Port eintragen.

3. **Firewall**
   - Port freigeben, damit PCs kommunizieren können.

4. **Setlist abgleichen**
   - Beide REAPER-Instanzen sollten dieselbe Setlist geladen haben  
     *(oder der Leader sendet sie automatisch beim Start)*.

💡 **Hinweis:** Der Modus ist nur für Mehrrechner-Setups relevant – wenn du nur einen Rechner nutzt, kannst du ihn deaktivieren.

---

## Troubleshooting

- **Schrift zu klein im Show-Modus**  
  → Überprüfen, ob REAPER in den Anzeigeeinstellungen auf 100% skaliert ist.

- **Follower reagiert nicht**  
  → Firewall-Einstellungen prüfen und sicherstellen, dass der Port offen ist.

- **Setlist leer**  
  → Im Edit-Modus Songs hinzufügen und speichern.

---

## Lizenz

Dieses Projekt ist unter der **MIT-Lizenz** veröffentlicht – freie Nutzung, Veränderung und Weitergabe erlaubt.

---
# English Version

# REAPER Live Show Setlist Controller

A Lua script for **REAPER** that manages setlists for live shows and allows song control (Play, Pause, Next, Prev) directly in the REAPER interface.  
It has two main modes:

- **Edit Mode** – Create, edit, and arrange the setlist.
- **Show Mode** – Large-font display of the setlist for live performance with direct control.

⚠️ **Important Note**: Using this script for live shows is **at your own risk**!  
Always test extensively before using it in a live performance to avoid unexpected behavior.

---

## Features

- **Setlist management**
  - Add, reorder, remove songs.
  - Save and load multiple setlists.
- **Show Mode**
  - Large, easy-to-read display of all songs.
  - Control buttons for *Prev*, *Play/Pause*, *Next* directly available.
  - Identical layout to Edit Mode (optimized for live use).
- **Leader/Follower mode**
  - Synchronization between multiple computers over the network.
- **Dark Mode** & window options (*Windowed*, Fullscreen).
- Automatically saves the last loaded setlist.

---

## Requirements

To ensure smooth operation, the following points must be considered:

### Required
- **REAPER 6.x or later** (due to GUI and TCP features in the script).  
- **SWS Extension** installed → [Download here](https://www.sws-extension.org/)  
  - Required for extended REAPER features.
- **Enable Script API in REAPER**  
  - Menu **Options → Preferences → Plug-ins → ReaScript**
  - Enable **"Lua"**.

### Optional (recommended for live use)
- **Enable Smooth Seeking**  
  - Menu **Options → Smooth seek (smooth seek on bar/beat change)**
  - Ensures songs start on beat/bar boundaries → no abrupt jumps.
- **Disable Auto-Scroll in Arrange View**  
  - Prevents the view from jumping during the show.
- **Use a second screen in Show Mode**  
  - Ideal for displaying the setlist in large font to musicians.

---

## Installation

1. **Download the script**  
   Download the `.lua` file from this project's GitHub.

2. **Import into REAPER**  
   - In REAPER, open: `Actions` → `Show Action List`.
   - Click **Load...** and select the downloaded `.lua` file.
   - The script will now appear in the list and can be started like any other action.

3. **Optional: Create a toolbar button**  
   - In REAPER, open `View` → `Toolbars`.
   - Right-click → `Add action` → select your script.
   - Assign an icon (optional).

---

## Usage

1. **Start Edit Mode**  
   - Add songs, change order, save.

2. **Start Show Mode**  
   - Large display of all songs, control via mouse click or hotkeys.
   - Perfect for live shows on a second screen.

3. **Keyboard controls**  
   - `← / →` for Prev/Next song.
   - `Space` for Play/Pause.

---

## Leader/Follower Setup (optional)

The Leader/Follower mode allows **multiple computers to be synchronized**, controlling or displaying the same show.  
This is useful when you operate the Leader on stage, while a sound engineer at FOH follows the show in real time.

### How it works
- **Leader**
  - Starts, pauses, and switches songs.
  - Sends commands via **TCP network** to all connected followers.
  - Manages the setlist and sends live changes to followers.

- **Follower**
  - Receives commands from the Leader.
  - Plays songs in sync or only displays the song list in Show Mode.
  - Cannot control (read-only).

### Setup
1. **Leader PC**
   - Enable **"Leader Mode"** in the script.
   - Set a **port** (e.g., `5000`).

2. **Follower PC**
   - Enable **"Follower Mode"** in the script.
   - Enter the **Leader's IP address** and the same port.

3. **Firewall**
   - Open the port to allow communication.

4. **Sync setlists**
   - Both REAPER instances should load the same setlist  
     *(or the Leader sends it automatically at start)*.

💡 **Note:** Only relevant for multi-PC setups – disable if using a single PC.

---

## Troubleshooting

- **Font too small in Show Mode**  
  → Check if REAPER is set to 100% display scaling.

- **Follower not responding**  
  → Check firewall settings and ensure the port is open.

- **Empty setlist**  
  → Add and save songs in Edit Mode.

---

## License

This project is released under the **MIT License** – free to use, modify, and distribute.
