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

- **Leader**: Startet und steuert die Show.
- **Follower**: Zeigt dieselbe Setlist und folgt den Befehlen des Leaders.
- Kommunikation über TCP/IP (lokales Netzwerk).

---

## Troubleshooting

- **Schrift zu klein im Show-Modus**  
  → Überprüfen, ob REAPER in den Anzeigeeinstellungen auf 100% skaliert ist.
- **Follower reagiert nicht**  
  → Firewall-Einstellungen prüfen, ob der Port für die Verbindung freigegeben ist.
- **Setlist leer**  
  → Sicherstellen, dass im Edit-Modus Songs hinzugefügt und gespeichert wurden.

---

## Lizenz

Dieses Projekt ist unter der **MIT-Lizenz** veröffentlicht – freie Nutzung, Veränderung und Weitergabe erlaubt.
