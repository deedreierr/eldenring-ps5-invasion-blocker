#!/bin/sh
# invasion-control.sh - Verbessertes Kontrollskript für PS5 Invasionsschutz

# Konfiguration laden
. ./invasion-config.sh

# Funktionen
# --------------------------------------

# Whitelist bereinigen
clean_whitelist() {
    echo "Whitelist wird bereinigt..."
    
    if [ ! -f "$WHITELIST_FILE" ]; then
        touch "$WHITELIST_FILE"
        return
    fi
    
    # Temporäre Datei
    TEMP_FILE="$TMP_DIR/whitelist_temp.$$"
    > "$TEMP_FILE"
    
    # Nur gültige IP:Port Einträge behalten
    while read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        if validate_ip_port "$line"; then
            echo "$line" >> "$TEMP_FILE"
        else
            echo "Entferne ungültigen Eintrag: $line"
        fi
    done < "$WHITELIST_FILE"
    
    # Entferne Duplikate und aktualisiere Whitelist
    sort "$TEMP_FILE" | uniq > "$WHITELIST_FILE"
    rm -f "$TEMP_FILE"
    
    echo "Whitelist bereinigt: $(grep -c "." "$WHITELIST_FILE") gültige Einträge."
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Whitelist von inaktiven Verbindungen bereinigen
clean_inactive_connections() {
    echo "Suche aktive Verbindungen..."
    
    # Temporäre Datei erstellen
    TEMP_FILE="$TMP_DIR/active_connections.$$"
    > "$TEMP_FILE"
    
    # Aktive Verbindungen zur PS5 erfassen
    conns=$(conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "$LOCAL_RANGE")
    echo "$conns" | while read -r conn; do
        remote_ip=$(echo "$conn" | grep -oE "src=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "$PS5_IP" | head -1 | cut -d= -f2)
        remote_port=$(echo "$conn" | grep -oE "sport=[0-9]+" | head -1 | cut -d= -f2)
        
        if [ -n "$remote_ip" ] && [ -n "$remote_port" ]; then
            echo "$remote_ip:$remote_port" >> "$TEMP_FILE"
        fi
    done
    
    # Whitelist bereinigen
    if [ -f "$WHITELIST_FILE" ]; then
        echo "Prüfe Whitelist-Einträge..."
        
        # Zähler für entfernte Einträge
        removed=0
        CLEAN_FILE="$TMP_DIR/clean_whitelist.$$"
        > "$CLEAN_FILE"
        
        # Jeden Whitelist-Eintrag prüfen
        while read -r entry; do
            if [ -z "$entry" ]; then
                continue
            fi
            
            # Prüfen, ob der Eintrag in den aktiven Verbindungen ist
            if grep -q "^$entry$" "$TEMP_FILE"; then
                # Aktive Verbindung beibehalten
                echo "$entry" >> "$CLEAN_FILE"
            else
                # Keine aktive Verbindung mehr, entfernen
                echo "Entferne inaktive Verbindung: $entry"
                removed=$((removed + 1))
            fi
        done < "$WHITELIST_FILE"
        
        # Whitelist aktualisieren
        mv "$CLEAN_FILE" "$WHITELIST_FILE"
        
        echo "$removed inaktive Verbindungen wurden aus der Whitelist entfernt."
        echo "Whitelist enthält jetzt $(grep -c "." "$WHITELIST_FILE") Einträge."
    else
        echo "Keine Whitelist-Datei gefunden."
    fi
    
    # Aufräumen
    rm -f "$TEMP_FILE"
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Blockiere alle Verbindungen in Beobachtung
block_observed() {
    echo "Blockiere alle Verbindungen unter Beobachtung..."
    
    if [ ! -f "$WATCH_FILE" ] || [ ! -s "$WATCH_FILE" ]; then
        echo "Keine Verbindungen unter Beobachtung gefunden."
        echo "Drücke ENTER um fortzufahren..."
        read dummy
        return
    fi
    
    count=0
    
    while read -r line; do
        conn_id=$(echo "$line" | cut -d'|' -f1)
        ip=$(echo "$conn_id" | cut -d: -f1)
        port=$(echo "$conn_id" | cut -d: -f2)
        
        if [ -n "$ip" ] && [ -n "$port" ] && validate_ip_port "$conn_id"; then
            echo "Blockiere Verbindung: $conn_id"
            
            # Blockieren
            iptables -I "$IPTABLES_CHAIN" -s "$ip" -d "$PS5_IP" -j DROP
            iptables -I "$IPTABLES_CHAIN" -d "$ip" -s "$PS5_IP" -j DROP
            
            count=$((count + 1))
        else
            echo "Überspringe ungültige Verbindung: $conn_id"
        fi
    done < "$WATCH_FILE"
    
    # Überwachungsdatei leeren
    > "$WATCH_FILE"
    
    echo "$count Verbindungen wurden blockiert."
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Blockiere alle nicht-whitelist Verbindungen für 20 Sekunden
block_all_nonwhitelist() {
    echo "Blockiere alle Verbindungen außerhalb der Whitelist für 20 Sekunden..."
    
    # Aktuelle Verbindungen ermitteln
    conns=$(conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "$LOCAL_RANGE")
    
    count=0
    TEMP_BLOCK_LIST="$TMP_DIR/temp_blocks.$$"
    > "$TEMP_BLOCK_LIST"
    
    echo "$conns" | while read -r conn; do
        remote_ip=$(echo "$conn" | grep -oE "src=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | grep -v "$PS5_IP" | head -1 | cut -d= -f2)
        remote_port=$(echo "$conn" | grep -oE "sport=[0-9]+" | head -1 | cut -d= -f2)
        
        if [ -n "$remote_ip" ] && [ -n "$remote_port" ]; then
            conn_id="$remote_ip:$remote_port"
            
            # Prüfen, ob in Whitelist
            if ! grep -q "^$conn_id$" "$WHITELIST_FILE" 2>/dev/null && validate_ip_port "$conn_id"; then
                echo "Blockiere nicht gewhitelistete Verbindung: $conn_id"
                
                # Blockieren
                iptables -I "$IPTABLES_CHAIN" -s "$remote_ip" -d "$PS5_IP" -j DROP
                iptables -I "$IPTABLES_CHAIN" -d "$remote_ip" -s "$PS5_IP" -j DROP
                
                # Für späteres Aufheben der Blockierung speichern
                echo "$remote_ip:$remote_port" >> "$TEMP_BLOCK_LIST"
                
                count=$((count + 1))
            fi
        fi
    done
    
    echo "$count Verbindungen wurden für 20 Sekunden blockiert."
    echo "Warte 20 Sekunden..."
    
    # Nach 20 Sekunden Blockierungen aufheben
    sleep 20
    
    # Blockierungen aufheben
    if [ -f "$TEMP_BLOCK_LIST" ]; then
        while read -r entry; do
            ip=$(echo "$entry" | cut -d: -f1)
            
            if [ -n "$ip" ]; then
                iptables -D "$IPTABLES_CHAIN" -s "$ip" -d "$PS5_IP" -j DROP 2>/dev/null
                iptables -D "$IPTABLES_CHAIN" -d "$ip" -s "$PS5_IP" -j DROP 2>/dev/null
                echo "Blockierung aufgehoben: $entry"
            fi
        done < "$TEMP_BLOCK_LIST"
    fi
    
    rm -f "$TEMP_BLOCK_LIST"
    echo "Alle temporären Blockierungen wurden aufgehoben."
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Herunterfahren von laufenden Schutzprozessen
shutdown_shields() {
    echo "Beende laufende Invasionsschutz-Prozesse..."
    
    # Alle möglichen Prozesse finden und beenden
    ps | grep -E "invasion-(shield|learn)" | grep -v "$$" | while read -r line; do
        pid=$(echo "$line" | awk '{print $1}')
        kill -9 "$pid" 2>/dev/null
        echo "Prozess $pid beendet."
    done
    
    # PID-Datei entfernen
    rm -f "$PID_FILE"
    
    # iptables-Regeln entfernen
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null
    iptables -D FORWARD -j "$IPTABLES_CHAIN" 2>/dev/null
    iptables -X "$IPTABLES_CHAIN" 2>/dev/null
    
    echo "Alle Schutzprozesse wurden beendet."
    echo "Iptables-Regeln wurden entfernt."
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Zeige Verbindungsmuster und Statistiken
show_stats() {
    echo "Verbindungsmuster und Statistiken:"
    echo "----------------------------------"
    
    if [ ! -f "$WHITELIST_FILE" ] || [ ! -s "$WHITELIST_FILE" ]; then
        echo "Keine Whitelist-Daten vorhanden."
        echo "Drücke ENTER um fortzufahren..."
        read dummy
        return
    fi
    
    # IPs zählen
    echo "Häufigste IPs in der Whitelist:"
    cut -d: -f1 "$WHITELIST_FILE" | sort | uniq -c | sort -nr | head -5
    
    # Ports zählen
    echo ""
    echo "Häufigste Ports in der Whitelist:"
    cut -d: -f2 "$WHITELIST_FILE" | sort | uniq -c | sort -nr | head -5
    
    # Aktuelle Verbindungen
    echo ""
    echo "Aktuelle Verbindungen zur PS5:"
    conntrack -L 2>/dev/null | grep "$PS5_IP" | grep -v "$LOCAL_RANGE" | wc -l
    
    echo "Drücke ENTER um fortzufahren..."
    read dummy
}

# Hauptmenü anzeigen
show_menu() {
    clear
    echo "=== PS5 INVASIONSSCHUTZ - KONTROLLMENÜ ==="
    echo ""
    echo "1. Whitelist bereinigen (ungültige Einträge entfernen)"
    echo "2. Inaktive Verbindungen aus der Whitelist entfernen"
    echo "3. Beobachtete Verbindungen sofort blockieren"
    echo "4. Alle nicht-whitelist Verbindungen für 20s blockieren"
    echo "5. Alle laufenden Schutzprozesse beenden"
    echo "6. Verbindungsstatistiken anzeigen"
    echo "0. Beenden"
    echo ""
    echo -n "Bitte wähle eine Option (0-6) und drücke ENTER: "
    read choice
    
    case "$choice" in
        1) clean_whitelist ;;
        2) clean_inactive_connections ;;
        3) block_observed ;;
        4) block_all_nonwhitelist ;;
        5) shutdown_shields ;;
        6) show_stats ;;
        0) echo "Beende Kontrollskript." ; exit 0 ;;
        *) echo "Ungültige Option: $choice" ; sleep 2 ;;
    esac
}

# Hauptprogramm
while true; do
    show_menu
done

