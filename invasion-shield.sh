#!/bin/sh
# invasion-shield.sh - Vereinfachte und robuste Version des Schutzmodus

# Konfiguration laden
. ./invasion-config.sh

# Variablen
RUNNING=1
BLOCKED_COUNT=0

# Aufräumen beim Beenden
cleanup() {
    log "Beende Schutzmodus und entferne Blockierungsregeln..."
    RUNNING=0
    
    # Versuche, alle Kindprozesse zu beenden
    pkill -P $$ 2>/dev/null
    
    # Entferne iptables-Regeln
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null
    iptables -D FORWARD -j "$IPTABLES_CHAIN" 2>/dev/null
    iptables -X "$IPTABLES_CHAIN" 2>/dev/null
    
    # Dateien entfernen
    rm -f "$PID_FILE" 2>/dev/null
    rm -f "$WATCH_FILE" 2>/dev/null
    
    log "Invasionsschutz deaktiviert."
    exit 0
}
trap cleanup INT TERM EXIT

# Initialisierung
setup() {
    log "Starte Schutzmodus für PS5 Invasionsschutz"
    
    # Prüfe, ob ein anderes Skript läuft
    if is_shield_running || is_other_script_running; then
        echo "FEHLER: Ein anderes Invasionsschutz-Skript läuft bereits."
        echo "Bitte beenden Sie es zuerst mit: killall -9 invasion-*.sh"
        exit 1
    fi
    
    # PID speichern
    save_pid
    
    # Prüfe, ob Whitelist existiert
    if [ ! -f "$WHITELIST_FILE" ]; then
        echo "FEHLER: Dynamische Whitelist existiert nicht."
        echo "Bitte führen Sie zuerst invasion-learn.sh aus."
        exit 1
    fi
    
    # Initialisiere statische Whitelist
    if [ ! -f "$STATIC_WHITELIST_FILE" ]; then
        cat > "$STATIC_WHITELIST_FILE" << EOL
# Statische Whitelist für PS5 Invasionsschutz
# Format: Nur IP-Adressen (OHNE Port), eine IP pro Zeile
# Diese IPs werden niemals blockiert, unabhängig vom Port
# Kommentare beginnen mit einer Raute (#)
# Beispiel:
# 44.226.16.109
EOL
        log "Statische Whitelist erstellt: $STATIC_WHITELIST_FILE"
    fi
    
    # iptables-Kette erstellen/leeren
    if ! iptables -N "$IPTABLES_CHAIN" 2>/dev/null; then
        iptables -F "$IPTABLES_CHAIN" 2>/dev/null
    fi
    
    # Regel einfügen
    iptables -D FORWARD -j "$IPTABLES_CHAIN" 2>/dev/null
    iptables -I FORWARD -j "$IPTABLES_CHAIN"
    
    # Überwachungsdatei initialisieren
    > "$WATCH_FILE"
    
    log "SCHUTZMODUS: Initialisiert"
}

# Prüfen, ob eine Verbindung in der Whitelist ist (dynamisch oder statisch)
is_whitelisted() {
    local conn_id="$1"
    local ip
    
    # Prüfe dynamische Whitelist (exakte IP:Port Übereinstimmung)
    if grep -q "^$conn_id$" "$WHITELIST_FILE" 2>/dev/null; then
        return 0
    fi
    
    # IP extrahieren für statische Whitelist-Prüfung
    ip=$(echo "$conn_id" | cut -d: -f1)
    
    # Prüfe statische Whitelist (nur IP ohne Port)
    if grep -v "^#" "$STATIC_WHITELIST_FILE" 2>/dev/null | grep -q "^$ip$"; then
        return 0
    fi
    
    return 1
}

# Prüfe, ob eine Verbindung unter Beobachtung steht
is_watched() {
    local conn_id="$1"
    
    if grep -q "^$conn_id|" "$WATCH_FILE" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Blockiere Verbindung
block_connection() {
    local ip="$1"
    local port="$2"
    
    # Verbindungs-ID erstellen
    local conn_id="$ip:$port"
    
    # Sicherheitsprüfung
    if ! echo "$ip" | grep -q "^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$" || [ -z "$port" ]; then
        log "FEHLER: Ungültige IP oder Port: $ip:$port"
        return 1
    fi
    
    # Aus Überwachungsdatei entfernen
    if is_watched "$conn_id"; then
        sed -i "/^$conn_id|/d" "$WATCH_FILE" 2>/dev/null
    fi
    
    # Blockieren mit iptables
    iptables -I "$IPTABLES_CHAIN" -s "$ip" -d "$PS5_IP" -j DROP 2>/dev/null
    iptables -I "$IPTABLES_CHAIN" -d "$ip" -s "$PS5_IP" -j DROP 2>/dev/null
    
    log "SCHUTZMODUS: Blockiere: $conn_id für $BLOCK_DURATION Sekunden"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    
    # Nach Zeit wieder freigeben
    (
        sleep "$BLOCK_DURATION"
        
        if [ $RUNNING -eq 1 ]; then
            iptables -D "$IPTABLES_CHAIN" -s "$ip" -d "$PS5_IP" -j DROP 2>/dev/null
            iptables -D "$IPTABLES_CHAIN" -d "$ip" -s "$PS5_IP" -j DROP 2>/dev/null
            log "SCHUTZMODUS: Blockierung aufgehoben: $conn_id"
            
            BLOCKED_COUNT=$((BLOCKED_COUNT - 1))
            if [ $BLOCKED_COUNT -lt 0 ]; then
                BLOCKED_COUNT=0
            fi
        fi
    ) &
}

# Hole aktuelle Verbindungen
get_connections() {
    # Sammle Verbindungen mit conntrack
    conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "$LOCAL_RANGE" | while read -r line; do
        # Extrahiere IPs
        for ip in $(echo "$line" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "^192\.168\." | grep -v "^127\."); do
            # Extrahiere Ports
            for port in $(echo "$line" | grep -oE "sport=[0-9]+" | cut -d= -f2); do
                if [ "$port" -gt 1000 ] 2>/dev/null; then
                    echo "$ip:$port"
                fi
            done
            for port in $(echo "$line" | grep -oE "dport=[0-9]+" | cut -d= -f2); do
                if [ "$port" -gt 1000 ] 2>/dev/null; then
                    echo "$ip:$port"
                fi
            done
        done
    done | sort | uniq
}

# Überwachungsroutine
monitor_loop() {
    log "SCHUTZMODUS: Überwachung gestartet"
    
    while [ $RUNNING -eq 1 ]; do
        # Hole aktuelle Verbindungen
        for conn_id in $(get_connections); do
            # Prüfe, ob in Whitelist
            if ! is_whitelisted "$conn_id"; then
                # Prüfe, ob bereits unter Beobachtung
                if ! is_watched "$conn_id"; then
                    # Füge zur Überwachung hinzu
                    timestamp=$(date +%s)
                    echo "$conn_id|$timestamp" >> "$WATCH_FILE"
                    log "SCHUTZMODUS: Neue Verbindung unter Beobachtung: $conn_id"
                    
                    # Starte Beobachtung
                    (
                        sleep "$OBSERVATION_TIME"
                        
                        if [ $RUNNING -eq 1 ]; then
                            # Prüfe erneut, ob in Whitelist
                            if ! is_whitelisted "$conn_id"; then
                                # Prüfe, ob Verbindung noch aktiv
                                if echo "$(get_connections)" | grep -q "^$conn_id$"; then
                                    # Blockiere
                                    ip=$(echo "$conn_id" | cut -d: -f1)
                                    port=$(echo "$conn_id" | cut -d: -f2)
                                    block_connection "$ip" "$port"
                                else
                                    # Entferne aus Überwachung
                                    sed -i "/^$conn_id|/d" "$WATCH_FILE" 2>/dev/null
                                    log "SCHUTZMODUS: Verbindung $conn_id nicht mehr aktiv"
                                fi
                            else
                                # In Whitelist, entferne aus Überwachung
                                sed -i "/^$conn_id|/d" "$WATCH_FILE" 2>/dev/null
                                log "SCHUTZMODUS: Verbindung $conn_id in Whitelist gefunden"
                            fi
                        fi
                    ) &
                fi
            fi
        done
        
        sleep "$REFRESH_INTERVAL"
    done
}

# Status anzeigen
show_status() {
    while [ $RUNNING -eq 1 ]; do
        clear
        echo "=== PS5 INVASIONSSCHUTZ - SCHUTZMODUS ==="
        echo "Schütze PS5: $PS5_IP"
        echo ""
        
        # Zähle aktive Verbindungen
        CONN_COUNT=$(get_connections | wc -l)
        
        # Zähle Whitelist-Einträge
        WHITELIST_COUNT=$(grep -c . "$WHITELIST_FILE" 2>/dev/null || echo "0")
        STATIC_COUNT=$(grep -v "^#" "$STATIC_WHITELIST_FILE" | grep -c . 2>/dev/null || echo "0")
        
        # Zähle überwachte Verbindungen
        WATCH_COUNT=$(grep -c . "$WATCH_FILE" 2>/dev/null || echo "0")
        
        echo "Aktive Verbindungen: $CONN_COUNT"
        echo "Whitelist-Einträge: Dynamisch=$WHITELIST_COUNT, Statisch=$STATIC_COUNT"
        echo "Verbindungen unter Beobachtung: $WATCH_COUNT"
        echo "Aktive Blockierungen: $BLOCKED_COUNT"
        echo ""
        
        # Zeige Whitelist an
        echo "=== Dynamische Whitelist (IP:Port) ==="
        if [ -s "$WHITELIST_FILE" ]; then
            head -10 "$WHITELIST_FILE"
            
            # Berechne restliche Einträge
            REST=$((WHITELIST_COUNT - 10))
            if [ $REST -gt 0 ]; then
                echo "... und $REST weitere"
            fi
        else
            echo "Keine Einträge"
        fi
        
        echo ""
        echo "=== Statische Whitelist (nur IPs) ==="
        if [ $STATIC_COUNT -gt 0 ]; then
            grep -v "^#" "$STATIC_WHITELIST_FILE" | head -10
            
            # Berechne restliche Einträge
            REST=$((STATIC_COUNT - 10))
            if [ $REST -gt 0 ]; then
                echo "... und $REST weitere"
            fi
        else
            echo "Keine Einträge"
        fi
        
        echo ""
        echo "=== Verbindungen unter Beobachtung ==="
        if [ $WATCH_COUNT -gt 0 ]; then
            NOW=$(date +%s)
            while read -r line; do
                CONN=$(echo "$line" | cut -d'|' -f1)
                START=$(echo "$line" | cut -d'|' -f2)
                
                # Berechne verbleibende Zeit
                ELAPSED=$((NOW - START))
                REMAINING=$((OBSERVATION_TIME - ELAPSED))
                
                if [ $REMAINING -gt 0 ]; then
                    echo "$CONN - noch $REMAINING Sekunden"
                else
                    echo "$CONN - Entscheidung steht bevor"
                fi
            done < "$WATCH_FILE" | head -10
            
            # Berechne restliche Einträge
            REST=$((WATCH_COUNT - 10))
            if [ $REST -gt 0 ]; then
                echo "... und $REST weitere"
            fi
        else
            echo "Keine Einträge"
        fi
        
        echo ""
        echo "Letzte Aktivitäten:"
        tail -n 3 "$LOG_FILE" 2>/dev/null || echo "Keine Aktivitäten"
        echo ""
        echo "Drücken Sie STRG+C, um den Schutzmodus zu beenden"
        
        sleep "$REFRESH_INTERVAL"
    done
}

# Hauptprogramm
setup
monitor_loop &
show_status

