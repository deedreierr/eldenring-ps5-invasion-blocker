#!/bin/sh
# invasion-learn.sh - Vollständig überarbeiteter Lernmodus

# Konfiguration laden
. ./invasion-config.sh

# Variablen
RUNNING=1
LEARN_DURATION=20  # Automatisch nach 20 Sekunden beenden

# Aufräumen beim Beenden
cleanup() {
    log "Beende Lernmodus..."
    RUNNING=0
    rm -f "$PID_FILE"
    wl_count=$(wc -l < "$WHITELIST_FILE" 2>/dev/null || echo "0")
    log "Whitelist enthält nun $wl_count Einträge."
    exit 0
}
trap cleanup INT TERM EXIT

# Initialisierung
setup() {
    log "Starte Lernmodus für PS5 Invasionsschutz"
    
    # Prüfe, ob ein anderes Skript läuft
    if is_shield_running || is_other_script_running; then
        echo "FEHLER: Ein anderes Invasionsschutz-Skript läuft bereits."
        echo "Bitte beenden Sie es zuerst mit: killall -9 invasion-*.sh"
        exit 1
    fi
    
    # PID speichern
    save_pid
    
    # Whitelist vorbereiten
    touch "$WHITELIST_FILE"
    > "$WHITELIST_FILE"  # Whitelist leeren zu Beginn
    log "Lernmodus bereit - Erfasse Verbindungen zur PS5 ($PS5_IP)"
    
    # Timer für automatisches Beenden starten
    (
        sleep "$LEARN_DURATION"
        if [ $RUNNING -eq 1 ]; then
            log "Automatisches Beenden nach $LEARN_DURATION Sekunden"
            kill -INT $$
        fi
    ) &
}

# Extrahiere externe IPs direkt aus netstat/ss
extract_connections_simple() {
    log "LERNMODUS: Verwende einfache Methode zur Verbindungserfassung"
    
    # Temporäre Datei für externe IPs
    TEMP_IPS="$TMP_DIR/external_ips.$$"
    > "$TEMP_IPS"
    
    # Verwende ss für TCP-Verbindungen
    if command -v ss >/dev/null 2>&1; then
        log "LERNMODUS: Nutze ss für Verbindungserfassung"
        ss -tn | grep ESTAB | while read -r line; do
            if echo "$line" | grep -q "$PS5_IP"; then
                # Extrahiere externe IP und Port
                if echo "$line" | grep -q "$PS5_IP:"; then
                    # PS5 ist links (lokal)
                    remote=$(echo "$line" | awk '{print $4}')
                else
                    # PS5 ist rechts (remote)
                    remote=$(echo "$line" | awk '{print $3}')
                fi
                
                # Wenn wir eine externe IP haben
                if [ -n "$remote" ] && ! echo "$remote" | grep -q "^192\.168\."; then
                    log "LERNMODUS: Gefunden (ss): $remote"
                    echo "$remote" >> "$TEMP_IPS"
                fi
            fi
        done
    fi
    
    # Verwende netstat als Fallback
    if command -v netstat >/dev/null 2>&1; then
        log "LERNMODUS: Nutze netstat für Verbindungserfassung"
        netstat -tn | grep ESTABLISHED | while read -r line; do
            if echo "$line" | grep -q "$PS5_IP"; then
                # Extrahiere externe IP und Port
                local_addr=$(echo "$line" | awk '{print $4}')
                remote_addr=$(echo "$line" | awk '{print $5}')
                
                if echo "$local_addr" | grep -q "$PS5_IP"; then
                    # PS5 ist lokal
                    if ! echo "$remote_addr" | grep -q "^192\.168\."; then
                        log "LERNMODUS: Gefunden (netstat local): $remote_addr"
                        echo "$remote_addr" >> "$TEMP_IPS"
                    fi
                elif echo "$remote_addr" | grep -q "$PS5_IP"; then
                    # PS5 ist remote
                    if ! echo "$local_addr" | grep -q "^192\.168\."; then
                        log "LERNMODUS: Gefunden (netstat remote): $local_addr"
                        echo "$local_addr" >> "$TEMP_IPS"
                    fi
                fi
            fi
        done
    fi
    
    # Verwende manuelle Analyse von conntrack-Ausgabe
    log "LERNMODUS: Nutze conntrack für Verbindungserfassung"
    conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "127.0.0.1" | while read -r line; do
        # Suche nach allen externen IPs in der Zeile
        for ip in $(echo "$line" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "192\.168\."); do
            # Finde alle Ports in der Zeile
            for port in $(echo "$line" | grep -oE "=[0-9]{2,5}" | cut -d= -f2 | grep -v "^[0-9]\$" | grep -v "^[0-9][0-9]\$"); do
                # Prüfe, ob Port größer als 1000 ist (wahrscheinlich externes Ende)
                if [ "$port" -gt 1000 ] 2>/dev/null; then
                    conn_id="$ip:$port"
                    log "LERNMODUS: Gefunden (conntrack): $conn_id"
                    echo "$conn_id" >> "$TEMP_IPS"
                fi
            done
        done
    done
    
    # Füge alle gefundenen IPs zur Whitelist hinzu
    if [ -f "$TEMP_IPS" ] && [ -s "$TEMP_IPS" ]; then
        sort "$TEMP_IPS" | uniq > "$WHITELIST_FILE"
        wl_count=$(wc -l < "$WHITELIST_FILE")
        log "LERNMODUS: $wl_count externe Verbindungen in Whitelist aufgenommen"
    else
        log "LERNMODUS: WARNUNG - Keine externen Verbindungen gefunden!"
    fi
    
    # Aufräumen
    rm -f "$TEMP_IPS"
}

# Status anzeigen und Verbindungen erfassen
show_status() {
    # Initial alle Verbindungen erfassen
    extract_connections_simple
    
    # Zeige Status
    while [ $RUNNING -eq 1 ]; do
        clear
        echo "=== PS5 INVASIONSSCHUTZ - LERNMODUS ==="
        echo "Überwache Verbindungen zur PS5: $PS5_IP"
        echo "Automatisches Beenden in $LEARN_DURATION Sekunden"
        echo ""
        
        # Aktuelle Verbindungen zählen - mit Fehlerbehandlung
        conn_count=$(conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "127.0.0.1" | wc -l)
        echo "Aktive Verbindungen: $conn_count"
        
        # Whitelist-Einträge zählen - mit Fehlerbehandlung
        wl_count=0
        if [ -f "$WHITELIST_FILE" ]; then
            wl_count=$(wc -l < "$WHITELIST_FILE")
        fi
        echo "Whitelist-Einträge: $wl_count"
        echo ""
        
        if [ "$wl_count" -gt 0 ]; then
            echo "Aktuelle Verbindungen in Whitelist:"
            echo "--------------------------------"
            cat "$WHITELIST_FILE" | head -10
            
            if [ "$wl_count" -gt 10 ]; then
                echo "... und $((wl_count - 10)) weitere"
            fi
            echo ""
        fi
        
        echo "Der Lernmodus erfasst aktive Verbindungen..."
        echo "Drücken Sie STRG+C, um den Lernmodus sofort zu beenden"
        
        # Wiederhole die Verbindungserfassung
        extract_connections_simple
        sleep 2
    done
}

# Hauptprogramm
setup
show_status

