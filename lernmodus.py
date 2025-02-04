# lernmodus.py
"""
Lernmodus für Koop-Verbindungen.
Beobachtet und speichert vertrauenswürdige Verbindungen während einer Koop-Session.
"""

import time
import json
from typing import Set
from datetime import datetime
from konfiguration import EINSTELLUNGEN
from netzwerk_helfer import logging_einrichten, hole_verbindungen, extrahiere_ip
import logging

def speichere_whitelist(ips: Set[str]) -> None:
    """Speichert die erkannten Koop-IPs in der Whitelist."""
    try:
        with open(EINSTELLUNGEN['whitelist_datei'], 'w') as f:
            json.dump(list(ips), f, indent=2)
        logging.info(f"Whitelist mit {len(ips)} IPs erfolgreich gespeichert")
    except IOError as e:
        logging.error(f"Fehler beim Speichern der Whitelist: {e}")

def lerne_koop_verbindungen() -> None:
    """Hauptfunktion des Lernmodus."""
    logging.info("Lernmodus gestartet. Bitte Koop-Sitzung starten...")
    
    koop_ips = set()
    start_zeit = datetime.now()
    
    try:
        while True:
            aktuelle_verbindungen = hole_verbindungen(EINSTELLUNGEN['ps5_ip'])
            
            for verbindung in aktuelle_verbindungen:
                quell_ip = extrahiere_ip(verbindung)
                if quell_ip and quell_ip != EINSTELLUNGEN['ps5_ip']:
                    if quell_ip not in koop_ips:
                        koop_ips.add(quell_ip)
                        logging.info(f"Neue Koop-IP erkannt: {quell_ip}")
            
            # Status-Update alle 30 Sekunden
            vergangene_zeit = (datetime.now() - start_zeit).seconds
            if vergangene_zeit % 30 == 0:
                logging.info(f"Bekannte Koop-IPs: {sorted(list(koop_ips))}")
            
            time.sleep(1)
            
    except KeyboardInterrupt:
        logging.info("\nSpeichere erkannte Verbindungen...")
        speichere_whitelist(koop_ips)
        logging.info("Lernvorgang abgeschlossen")

if __name__ == "__main__":
    logging_einrichten(EINSTELLUNGEN['log_datei'])
    lerne_koop_verbindungen()
