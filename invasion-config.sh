#!/bin/sh
# invasion-config.sh - Konfiguration für PS5 Invasionsschutz mit statischer Whitelist (nur IPs)

# Script-Verzeichnis ermitteln und eigenes tmp-Verzeichnis erstellen
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
TMP_DIR="$SCRIPT_DIR/tmp"
mkdir -p "$TMP_DIR"

# Netzwerkeinstellungen
PS5_IP="192.168.24.143"         # IP der PlayStation 5
LOCAL_RANGE="192.168.24.0/24"   # Lokales Netzwerk (ausgenommen)

# Zeiteinstellungen
OBSERVATION_TIME=30             # Beobachtungszeit für neue Verbindungen (Sekunden)
BLOCK_DURATION=180              # Blockierungsdauer (3 Minuten)
REFRESH_INTERVAL=4              # Aktualisierungsintervall für alle Skripte (4 Sekunden)

# Dateipfade
LOG_FILE="$TMP_DIR/invasion-shield.log"
WHITELIST_FILE="$TMP_DIR/coop_whitelist.txt"
STATIC_WHITELIST_FILE="$SCRIPT_DIR/static_whitelist.txt" # Statische Whitelist (nur IPs)
PID_FILE="$TMP_DIR/invasion.pid"
WATCH_FILE="$TMP_DIR/invasion_watch.txt"

# Iptables-Einstellungen
IPTABLES_CHAIN="PS5_SHIELD"     # Name der Iptables-Kette

# Farben für Terminal (busybox-kompatibel)
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'                    # Keine Farbe

# Grundlegende Hilfsfunktionen
# --------------------------

# Protokollierung
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Zeige Whitelist mit Nummern
show_whitelist() {
    if [ ! -f "$WHITELIST_FILE" ] || [ ! -s "$WHITELIST_FILE" ]; then
        echo "Whitelist ist leer"
        return
    fi
    
    echo "Nr. | IP:Port"
    echo "----+-------------------"
    line_num=1
    
    while read -r line; do
        if [ -n "$line" ]; then
            printf "%3d | %s\n" "$line_num" "$line"
            line_num=$((line_num + 1))
        fi
    done < "$WHITELIST_FILE"
}

# Überprüfen, ob Skripte laufen
is_shield_running() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0  # Läuft
        else
            rm -f "$PID_FILE"
        fi
    fi
    return 1  # Läuft nicht
}

# Überprüfen, ob andere Invasionsschutz-Skripte laufen
is_other_script_running() {
    ps | grep -E "invasion-(shield|learn)" | grep -v "$$" | grep -v grep > /dev/null
    return $?
}

# Prozess-ID speichern
save_pid() {
    echo $$ > "$PID_FILE"
    log "PID gespeichert: $$"
}

# Validiere IP:Port Format
validate_ip_port() {
    local entry="$1"
    local ip port
    
    # IP und Port extrahieren
    ip=$(echo "$entry" | cut -d: -f1)
    port=$(echo "$entry" | cut -d: -f2)
    
    # Validierung
    if [ -z "$ip" ] || [ -z "$port" ]; then
        return 1
    fi
    
    if ! echo "$ip" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; then
        return 1
    fi
    
    if ! echo "$port" | grep -Eq "^[0-9]+$"; then
        return 1
    fi
    
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    return 0
}

# Validiere nur IP-Format (ohne Port)
validate_ip() {
    local ip="$1"
    
    # Validierung
    if [ -z "$ip" ]; then
        return 1
    fi
    
    if ! echo "$ip" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; then
        return 1
    fi
    
    return 0
}

# Prüfen, ob eine Verbindung in der Whitelist ist (dynamisch oder statisch)
is_in_whitelist() {
    local conn_id="$1"
    local ip port
    
    # IP und Port extrahieren
    ip=$(echo "$conn_id" | cut -d: -f1)
    port=$(echo "$conn_id" | cut -d: -f2)
    
    # Prüfe dynamische Whitelist (IP:Port)
    if [ -f "$WHITELIST_FILE" ] && grep -q "^$conn_id$" "$WHITELIST_FILE" 2>/dev/null; then
        return 0  # Gefunden in dynamischer Whitelist
    fi
    
    # Prüfe statische Whitelist (nur IP, ohne Port)
    if [ -f "$STATIC_WHITELIST_FILE" ] && grep -q "^$ip$" "$STATIC_WHITELIST_FILE" 2>/dev/null; then
        return 0  # IP gefunden in statischer Whitelist
    fi
    
    return 1  # Nicht gefunden
}

# Initialisiere die statische Whitelist-Datei, falls sie nicht existiert
init_static_whitelist() {
    if [ ! -f "$STATIC_WHITELIST_FILE" ]; then
        touch "$STATIC_WHITELIST_FILE"
        log "Statische Whitelist-Datei erstellt: $STATIC_WHITELIST_FILE"
        
        # Füge Kommentar als Erklärung hinzu
        cat > "$STATIC_WHITELIST_FILE" << EOL
# Statische Whitelist für PS5 Invasionsschutz
# Format: Nur IP-Adressen (OHNE Port), eine IP pro Zeile
# Diese IPs werden niemals blockiert, unabhängig vom Port
# Kommentare beginnen mit einer Raute (#)
# Beispiel:
# 44.226.16.109
EOL
    fi
}

# Lade die statische Whitelist und zeige sie an
load_static_whitelist() {
    # Initialisiere die Datei, falls sie nicht existiert
    init_static_whitelist
    
    # Zähle Einträge
    if [ -f "$STATIC_WHITELIST_FILE" ]; then
        count=$(grep -v "^#" "$STATIC_WHITELIST_FILE" | grep -c "." || echo "0")
        log "Statische Whitelist geladen mit $count IPs"
        
        # Gib Einträge für Debug-Zwecke aus
        if [ "$count" -gt 0 ]; then
            log "Statische Whitelist-Einträge (IPs):"
            grep -v "^#" "$STATIC_WHITELIST_FILE" | while read -r line; do
                if [ -n "$line" ] && validate_ip "$line"; then
                    log "STATISCHE IP: $line"
                else
                    log "WARNUNG: Ungültige IP in statischer Whitelist: $line"
                fi
            done
        fi
    else
        log "Keine statische Whitelist gefunden"
    fi
}

