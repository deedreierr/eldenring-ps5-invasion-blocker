# schutzmodus.py
"""
Schutzmodus für Elden Ring.
Überwacht Netzwerkverbindungen und blockiert unerwünschte Invasionen.
"""

import time
import json
import subprocess
import logging
from typing import Dict, Set
from konfiguration import EINSTELLUNGEN
from netzwerk_helfer import logging_einrichten, hole_verbindungen, extrahiere_ip

def lade_whitelist() -> Set[str]:
    """Lädt die gespeicherte Whitelist."""
    try:
        with open(EINSTELLUNGEN['whitelist_datei'], 'r') as f:
            return set(json.load(f))
    except IOError as e:
        logging.error(f"Fehler beim Laden der Whitelist: {e}")
        return set()

def sperre_ip(ip: str) -> bool:
    """
    Blockiert eine IP-Adresse.
    
    Args:
        ip: Zu blockierende IP-Adresse

    Returns:
        True wenn erfolgreich, False bei Fehler
    """
    befehl = f"iptables-nft -I FORWARD 1 -s {ip} -j DROP"
    try:
        subprocess.run(befehl, shell=True, check=True)
        logging.info(f"IP blockiert: {ip}")
        return True
    except subprocess.SubprocessError as e:
        logging.error(f"Fehler beim Blockieren von IP {ip}: {e}")
        return False

def entsperre_alle() -> bool:
    """
    Entfernt alle Blocking-Regeln (Notfall-Funktion).
    
    Returns:
        True wenn erfolgreich, False bei Fehler
    """
    befehl = "iptables-nft -F FORWARD"
    try:
        subprocess.run(befehl, shell=True, check=True)
        logging.info("Alle Blocking-Regeln entfernt")
        return True
    except subprocess.SubprocessError as e:
        logging.error(f"Fehler beim Entfernen der Blocking-Regeln: {e}")
        return False

def ueberwache_verbindungen() -> None:
    """Hauptfunktion des Schutzmodus."""
    whitelist = lade_whitelist()
    logging.info(f"Schutz aktiv. Überwache Verbindungen... Whitelist: {sorted(list(whitelist))}")
    
    neue_verbindungen: Dict[str, float] = {}
    
    try:
        while True:
            aktuelle_zeit = time.time()
            
            for verbindung in hole_verbindungen(EINSTELLUNGEN['ps5_ip']):
                quell_ip = extrahiere_ip(verbindung)
                
                if not quell_ip or quell_ip == EINSTELLUNGEN['ps5_ip'] or quell_ip in whitelist:
                    continue
                    
                if quell_ip not in neue_verbindungen:
                    neue_verbindungen[quell_ip] = aktuelle_zeit
                    logging.info(f"Neue Verbindung erkannt: {quell_ip}")
                elif aktuelle_zeit - neue_verbindungen[quell_ip] > EINSTELLUNGEN['analyse_zeit']:
                    if sperre_ip(quell_ip):
                        del neue_verbindungen[quell_ip]
            
            # Bereinige alte ausstehende Verbindungen
            neue_verbindungen = {
                ip: zeit for ip, zeit in neue_verbindungen.items() 
                if aktuelle_zeit - zeit <= EINSTELLUNGEN['analyse_zeit']
            }
            
            time.sleep(1)
            
    except KeyboardInterrupt:
        logging.info("\nBeenden angefordert...")
        wahl = input("Sollen alle Blocking-Regeln entfernt werden? (j/N): ").lower()
        if wahl == 'j':
            entsperre_alle()
        logging.info("Überwachung beendet")

if __name__ == "__main__":
    logging_einrichten(EINSTELLUNGEN['log_datei'])
    ueberwache_verbindungen()
