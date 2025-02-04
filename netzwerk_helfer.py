# netzwerk_helfer.py
"""
Hilfsfunktionen für die Netzwerkanalyse.
Stellt gemeinsam genutzte Funktionen für beide Hauptskripte bereit.
"""

import json
import subprocess
import logging
from typing import List, Set, Optional
from datetime import datetime

def logging_einrichten(log_datei: str) -> None:
    """Richtet das Logging-System ein."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_datei),
            logging.StreamHandler()
        ]
    )

def hole_verbindungen(ps5_ip: str) -> List[str]:
    """
    Ruft aktuelle UDP-Verbindungen zur PS5 ab.
    
    Args:
        ps5_ip: IP-Adresse der PlayStation 5

    Returns:
        Liste der aktiven Verbindungen
    """
    befehl = f"conntrack -L --proto udp | grep {ps5_ip}"
    try:
        ergebnis = subprocess.run(befehl, shell=True, capture_output=True, text=True)
        if ergebnis.returncode == 0:
            return [zeile for zeile in ergebnis.stdout.strip().split('\n') if zeile]
        return []
    except subprocess.SubprocessError as e:
        logging.error(f"Fehler beim Abrufen der Verbindungen: {e}")
        return []

def extrahiere_ip(verbindung: str) -> Optional[str]:
    """
    Extrahiert die Quell-IP aus einer Verbindungszeile.
    
    Args:
        verbindung: Eine Zeile aus der conntrack-Ausgabe

    Returns:
        IP-Adresse oder None bei Fehler
    """
    try:
        teile = verbindung.split()
        for teil in teile:
            if teil.startswith('src='):
                return teil.split('=')[1]
        return None
    except Exception as e:
        logging.error(f"Fehler beim Extrahieren der IP: {e}")
        return None

