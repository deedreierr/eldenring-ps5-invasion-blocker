#!/bin/sh
# invasion-monitor.sh - Reiner Monitor für PS5 Invasionsschutz

# Konfiguration laden
. ./invasion-config.sh

# Variablen
RUNNING=1
REFRESH_INTERVAL=3

# Aufräumen beim Beenden
cleanup() {
    echo ""
    echo "Monitor wird beendet..."
    RUNNING=0
    exit 0
}
trap cleanup INT TERM EXIT

# Status der Schutzskripte anzeigen
show_shield_status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            if ps | grep "$pid" | grep -q "learn"; then 
                echo -e "${YELLOW}Status: LERNMODUS AKTIV (PID: $pid)${NC}"
                return 0
            elif ps | grep "$pid" | grep -q "shield"; then
                echo -e "${GREEN}Status: SCHUTZMODUS AKTIV (PID: $pid)${NC}"
                return 0
            fi
        fi
    fi
    
    echo -e "${RED}Status: INAKTIV - Kein Schutz läuft${NC}"
    return 1
}

# Blockierungen zählen
count_blocks() {
    block_count=$(iptables -L "$IPTABLES_CHAIN" 2>/dev/null | grep -c DROP || echo "0")
    echo "$block_count"
}

# Verbindungen anzeigen
show_connections() {
    conn_output=$(conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "$LOCAL_RANGE")
    if [ -n "$conn_output" ]; then
        echo "IP:Port                | Status       | Whitelist | Beobachtung"
        echo "------------------------|--------------|-----------|------------"
        
        now=$(date +%s)
        
        echo "$conn_output" | while read -r conn; do
            # Remote-IP und Port extrahieren
            remote_ip=$(echo "$conn" | grep -oE "src=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "$PS5_IP" | head -1 | cut -d= -f2)
            remote_port=$(echo "$conn" | grep -oE "sport=[0-9]+" | head -1 | cut -d= -f2)
            
            # Status extrahieren
            status=$(echo "$conn" | grep -oE "ESTABLISHED|NEW|RELATED|TIME_WAIT")
            
            if [ -n "$remote_ip" ] && [ -n "$remote_port" ]; then
                conn_id="$remote_ip:$remote_port"
                
                # Prüfen, ob auf Whitelist
                whitelist="Nein"
                whitelist_color="$RED"
                if grep -q "^$conn_id$" "$WHITELIST_FILE" 2>/dev/null; then
                    whitelist="Ja"
                    whitelist_color="$GREEN"
                fi
                
                # Prüfen, ob unter Beobachtung
                watch_info="-"
                watch_color="$NC"
                if [ -f "$WATCH_FILE" ] && grep -q "^$conn_id|" "$WATCH_FILE"; then
                    # Startzeit aus Überwachungsdatei lesen
                    start_time=$(grep "^$conn_id|" "$WATCH_FILE" | cut -d'|' -f2)
                    if [ -n "$start_time" ]; then
                        elapsed=$((now - start_time))
                        remaining=$((OBSERVATION_TIME - elapsed))
                        
                        if [ $remaining -gt 0 ]; then
                            watch_info="Noch ${remaining}s"
                            watch_color="$YELLOW"
                        else
                            watch_info="Entscheidung..."
                            watch_color="$RED"
                        fi
                    fi
                fi
                
                printf "%-22s | %-12s | ${whitelist_color}%-9s${NC} | ${watch_color}%s${NC}\n" \
                       "$conn_id" "$status" "$whitelist" "$watch_info"
            fi
        done
    else
        echo "Keine aktiven Verbindungen gefunden."
    fi
}

# Hauptfunktion
show_monitor() {
    clear
    
    echo "=================================================="
    echo "       PS5 INVASIONSSCHUTZ MONITOR               "
    echo "=================================================="
    echo ""
    
    # Status der Schutzskripte
    show_shield_status
    echo ""
    
    # Whitelist anzeigen
    wl_count=$(grep -c "." "$WHITELIST_FILE" 2>/dev/null || echo "0")
    echo -e "Whitelist-Einträge: ${GREEN}$wl_count${NC}"
    
    if [ "$wl_count" -gt 0 ]; then
        echo ""
        echo "Geschützte Verbindungen (Whitelist):"
        echo "--------------------------------"
        cat "$WHITELIST_FILE" | head -n 10
        if [ "$wl_count" -gt 10 ]; then
            echo "... und $((wl_count - 10)) weitere"
        fi
    fi
    
    echo ""
    
    # Verbindungen unter Beobachtung
    watch_count=0
    if [ -f "$WATCH_FILE" ]; then
        watch_count=$(grep -c "." "$WATCH_FILE")
    fi
    
    echo -e "Verbindungen unter Beobachtung: ${YELLOW}$watch_count${NC}"
    
    if [ "$watch_count" -gt 0 ]; then
        echo ""
        echo "Beobachtete Verbindungen:"
        echo "--------------------------------"
        
        now=$(date +%s)
        if [ -f "$WATCH_FILE" ]; then
            sort -t'|' -k2 -n "$WATCH_FILE" | while read -r line; do
                conn_id=$(echo "$line" | cut -d'|' -f1)
                start_time=$(echo "$line" | cut -d'|' -f2)
                
                if [ -n "$start_time" ]; then
                    elapsed=$((now - start_time))
                    remaining=$((OBSERVATION_TIME - elapsed))
                    
                    if [ $remaining -gt 0 ]; then
                        printf "${YELLOW}%-22s${NC} | Seit %3ds | Noch %3ds bis zur Entscheidung\n" \
                               "$conn_id" "$elapsed" "$remaining"
                    else
                        printf "${RED}%-22s${NC} | Seit %3ds | Entscheidung steht bevor\n" \
                               "$conn_id" "$elapsed"
                    fi
                fi
            done
        fi
    fi
    
    echo ""
    echo "Aktuelle Verbindungen:"
    echo "--------------------------------"
    show_connections
    
    echo ""
    echo "Drücken Sie STRG+C zum Beenden des Monitors"
    
    sleep "$REFRESH_INTERVAL"
}

# Hauptprogramm
echo "Starte PS5 Invasionsschutz-Monitor..."
echo "Drücken Sie STRG+C zum Beenden."
sleep 1

while [ $RUNNING -eq 1 ]; do
    show_monitor
done

