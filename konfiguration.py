# konfiguration.py
"""
Zentrale Konfigurationsdatei für das Elden Ring Netzwerk-Schutz System.
Enthält alle wichtigen Einstellungen für die Analyse und den Schutz.
"""

EINSTELLUNGEN = {
    "ps5_ip": "192.168.22.143",    # IP-Adresse der PlayStation 5
    "analyse_zeit": 30,           # Sekunden bis zur Sperrung einer verdächtigen Verbindung
    "whitelist_datei": "/mnt/sda1/eldenring/koop_ips.json",
    "log_datei": "/mnt/sda1/eldenring/verbindungen.log",
    "netzwerk": "br-lan"          # Standard OpenWRT Interface
}

