#!/usr/bin/env bash
# Helium Miner Dashboard installer/uninstaller (no docker compose)
# Creates dashboard in /opt/helium-dashboard, auto-detects miner log source

set -euo pipefail

BASE_DIR="/opt/helium-dashboard"
LOG_PATH="/var/log/gateway_config/console.log"

IMG_PARSER="helium-dashboard-parser"
IMG_API="helium-dashboard-api"
IMG_UI="helium-dashboard-ui"
NET_NAME="heliumdash-net"
AUTH_USER="${AUTH_USER:-}"
AUTH_PASS="${AUTH_PASS:-}"

CTR_PARSER="miner-log-parser"
CTR_API="miner-dashboard-api"
CTR_UI="miner-dashboard-ui"

VOL_DB="helium-dashboard_parser_db"

RESET="\e[0m"; BOLD="\e[1m"; DIM="\e[2m"
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"
BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"

banner() {
  echo -e "${CYAN}+---------------------------------------------------------------+${RESET}"
  printf "${CYAN}|${RESET} ${BOLD}%-59s${RESET} ${CYAN}|${RESET}\n" "$1"
  echo -e "${CYAN}+---------------------------------------------------------------+${RESET}"
}
section() { echo -e "\n${MAGENTA}-- ${BOLD}${1}${RESET}${MAGENTA} ---------------------------------------------${RESET}"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*"; }

LANG_CHOICE="en"

t() {
  local key="$1"
  case "$LANG_CHOICE" in
    pl) case "$key" in
        welcome)           echo "Helium Miner Dashboard - instalator";;
        choose_lang)       echo "Wybierz jezyk / Choose language [en/pl]:";;
        invalid_lang)      echo "Nieprawidlowy wybor, domyslnie en.";;
        menu)              echo "Co chcesz zrobic? [1] Zainstaluj  [2] Odinstaluj  [3] Wyjdz:";;
        invalid_choice)    echo "Nieprawidlowy wybor.";;
        installing)        echo "Rozpoczynam instalacje dashboardu w $BASE_DIR ...";;
        uninstalling)      echo "Rozpoczynam odinstalowywanie z $BASE_DIR ...";;
        done_install)      echo "Instalacja zakonczona. Dashboard dostepny pod:";;
        done_uninstall)    echo "Odinstalowywanie zakonczone. Kontenery usuniete.";;
        log_missing)       echo "Brak pliku logu: $LOG_PATH";;
        require_root)      echo "Uruchom skrypt jako root.";;
        docker_missing)    echo "Brak polecenia docker. Zainstaluj Docker i sprobuj ponownie.";;
        confirm_uninstall) echo "Na pewno odinstalowac dashboard i usunac $BASE_DIR? [y/N]:";;
        cancelled)         echo "Anulowano.";;
        creating_files)    echo "Tworzenie struktury katalogow i plikow...";;
        building_images)   echo "Budowanie obrazow Docker...";;
        starting_stack)    echo "Uruchamianie kontenerow Docker...";;
        stopping_stack)    echo "Zatrzymywanie kontenerow Docker...";;
        removing_dir)      echo "Usuwanie katalogu $BASE_DIR ...";;
        ip_header)         echo "Wykryte adresy IP:";;
        ip_line)           echo "  - http://%s:1111";;
        note_firewall)     echo "Upewnij sie, ze port 1111 jest dostepny w sieci lokalnej.";;
        curl_check)        echo "Sprawdzam dostep lokalnie (curl 127.0.0.1:1111) ...";;
        curl_ok)           echo "Panel odpowiada poprawnie.";;
        curl_fail)         echo "Panel nie odpowiada - sprawdz logi: docker logs miner-dashboard-ui";;
        auth_user)         echo "Login do panelu (puste = brak hasla):";;
        auth_pass)         echo "Haslo do panelu:";;
        auth_empty)        echo "Haslo nie moze byc puste, gdy ustawiasz login.";;
        auth_missing_ssl)  echo "Brak openssl - nie moge utworzyc hasla. Zainstaluj openssl i sprobuj ponownie.";;
      esac ;;
    *) case "$key" in
        welcome)           echo "Helium Miner Dashboard - installer";;
        choose_lang)       echo "Choose language / Wybierz jezyk [en/pl]:";;
        invalid_lang)      echo "Invalid choice, defaulting to en.";;
        menu)              echo "What do you want to do? [1] Install  [2] Uninstall  [3] Exit:";;
        invalid_choice)    echo "Invalid choice.";;
        installing)        echo "Starting installation into $BASE_DIR ...";;
        uninstalling)      echo "Starting uninstall from $BASE_DIR ...";;
        done_install)      echo "Installation finished. Dashboard available at:";;
        done_uninstall)    echo "Uninstall finished. Containers removed.";;
        log_missing)       echo "Log file not found: $LOG_PATH";;
        require_root)      echo "Run this script as root.";;
        docker_missing)    echo "Docker not found. Install Docker and try again.";;
        confirm_uninstall) echo "Really uninstall dashboard and remove $BASE_DIR? [y/N]:";;
        cancelled)         echo "Cancelled.";;
        creating_files)    echo "Creating directory structure and files...";;
        building_images)   echo "Building Docker images...";;
        starting_stack)    echo "Starting Docker containers...";;
        stopping_stack)    echo "Stopping Docker containers...";;
        removing_dir)      echo "Removing directory $BASE_DIR ...";;
        ip_header)         echo "Detected IP addresses:";;
        ip_line)           echo "  - http://%s:1111";;
        note_firewall)     echo "Make sure port 1111 is reachable on your local network.";;
        curl_check)        echo "Checking panel locally (curl 127.0.0.1:1111) ...";;
        curl_ok)           echo "Panel responds correctly.";;
        curl_fail)         echo "Panel not responding - check: docker logs miner-dashboard-ui";;
        auth_user)         echo "Panel username (empty = no password):";;
        auth_pass)         echo "Panel password:";;
        auth_empty)        echo "Password cannot be empty when username is set.";;
        auth_missing_ssl)  echo "openssl not found - cannot generate password. Install openssl and retry.";;
      esac ;;
  esac
}

detect_ips() {
  local IPS=""
  if command -v hostname >/dev/null 2>&1; then
    IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' || true)
  fi
  if [[ -z "$IPS" ]] && command -v ip >/dev/null 2>&1; then
    IPS=$(ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v '^127\.')
  fi
  if [[ -z "$IPS" ]] && command -v ifconfig >/dev/null 2>&1; then
    IPS=$(ifconfig | awk '/inet / && $2 !~ /127.0.0.1/ {print $2}')
  fi
  echo "$IPS"
}

detect_log_source() {
  # Prefer gateway_rs logs; fallback to existing LOG_PATH.
  if [[ -f "$LOG_PATH" ]]; then
    if grep -m1 -q "gateway_rs::" "$LOG_PATH" 2>/dev/null; then
      echo "$LOG_PATH"
      return
    fi
  fi

  # Try docker json log for the miner container
  local cid=""
  cid=$(docker inspect -f '{{.Id}}' miner 2>/dev/null || true)
  if [[ -z "$cid" ]]; then
    cid=$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | awk '/team-helium\\/miner|helium/ {print $1; exit}')
  fi
  if [[ -n "$cid" && -f "/var/lib/docker/containers/${cid}/${cid}-json.log" ]]; then
    echo "/var/lib/docker/containers/${cid}/${cid}-json.log"
    return
  fi

  # Fallback
  echo "$LOG_PATH"
}

create_files() {
  section "$(t creating_files)"
  mkdir -p "$BASE_DIR/parser" "$BASE_DIR/api" "$BASE_DIR/ui/www"

  # ---- AUTH ----
  local AUTH_ENABLED="0"
  if [[ -n "$AUTH_USER" ]]; then
    if ! command -v openssl >/dev/null 2>&1; then
      err "$(t auth_missing_ssl)"
      exit 1
    fi
    local HASH
    HASH=$(openssl passwd -apr1 "$AUTH_PASS")
    echo "${AUTH_USER}:${HASH}" > "$BASE_DIR/ui/.htpasswd"
    AUTH_ENABLED="1"
  else
    : > "$BASE_DIR/ui/.htpasswd"
  fi

  # ---- PARSER ----
  cat > "$BASE_DIR/parser/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app.py .
CMD ["python", "app.py"]
EOF

  cat > "$BASE_DIR/parser/app.py" <<'EOF'
import json
import os
import re
import sqlite3
import time

LOG_PATH   = "/logs/console.log"
DB_PATH    = os.getenv("DB_PATH", "/data/events.db")
STATE_PATH = os.getenv("STATE_PATH", "/data/offset.txt")

os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

conn = sqlite3.connect(DB_PATH, check_same_thread=False)
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("PRAGMA synchronous=NORMAL")
conn.execute("PRAGMA busy_timeout=2000")
cur  = conn.cursor()

cur.execute("""
CREATE TABLE IF NOT EXISTS events (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        TEXT,
    level     TEXT,
    module    TEXT,
    type      TEXT,
    beacon_id TEXT,
    mac       TEXT,
    freq      INTEGER,
    snr       REAL,
    rssi      INTEGER,
    len       INTEGER,
    region    TEXT,
    raw       TEXT
)""")
conn.commit()

cur.execute("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)")
cur.execute("CREATE INDEX IF NOT EXISTS idx_events_type ON events(type)")
cur.execute("CREATE INDEX IF NOT EXISTS idx_events_mac ON events(mac)")
cur.execute("CREATE INDEX IF NOT EXISTS idx_events_beacon ON events(beacon_id)")
conn.commit()

GW_RS_RE  = re.compile(r'^(?P<ts>\d{4}-\d{2}-\d{2}T[^ ]+)\s+(?P<level>INFO|WARN|ERROR)\s+(?P<rest>.*)$')
GW_CFG_RE = re.compile(r'^(?P<date>\d{4}-\d{2}-\d{2})\s+(?P<time>\d{2}:\d{2}:\d{2}\.\d+)\s+\[(?P<level>[A-Za-z]+)\]\s+(?P<rest>.*)$')

def clean_beacon_id(bid):
    if not bid:
        return None
    bid = str(bid).strip().strip('"')
    # filter obvious junk like "t"
    if len(bid) < 16:
        return None
    return bid


def classify(msg, raw=""):
    t=bid=mac=freq=snr=rssi=length=region=None
    def grab(pattern):
        for s in (msg, raw):
            if not s:
                continue
            m = re.search(pattern, s)
            if m:
                return m.group(1)
        return None
    if "beaconer: transmitting beacon" in msg:
        t="beacon_tx"
        m=re.search(r'beacon_id=\"?([^\"\\s]+)\"?',msg); bid=m.group(1) if m else None
    elif "poc beacon report submitted" in msg:
        t="beacon_tx_report"
        m=re.search(r'beacon_id=\"?([^\"\\s]+)\"?',msg); bid=m.group(1) if m else None
    elif "poc witness report submitted" in msg:
        t="witness_report"
        m=re.search(r'beacon_id=\"?([^\"\\s]+)\"?',msg); bid=m.group(1) if m else None
    elif "ignoring duplicate or self beacon witness" in msg:
        t="witness_ignored"
        m=re.search(r'beacon_id=?(\"?[^\"\\s]+\"?)',msg)
        bid=m.group(1).strip('\"') if m and m.group(1) else None
    elif "received potential beacon" in msg:
        t="beacon_rx"
        m=re.search(r'downlink_mac=([0-9A-Fa-f:]+)',msg); mac=m.group(1) if m else None
        if not mac:
            m=re.search(r'downlink_mac=([0-9A-Fa-f:]+)',raw); mac=m.group(1) if m else None
        v = grab(r'(\\d+)\\s*MHz'); freq=int(v) if v else None
        v = grab(r'snr:\\s*([-0-9.]+)'); snr=float(v) if v else None
        v = grab(r'rssi:\\s*([-0-9.]+)'); rssi=int(float(v)) if v else None
        v = grab(r'len:\\s*(\\d+)'); length=int(v) if v else None
    elif "beacon transmitted" in msg:
        t="beacon_tx_gateway"
        m=re.search(r'beacon_id=\"?([^\"\\s]+)\"?',msg); bid=m.group(1) if m else None
    elif "next beacon time" in msg:
        t="beacon_next_time"
    elif "region updated region=" in msg or "fetched config region_params" in msg:
        t="region_update"
        m=re.search(r'region=\"?([A-Z0-9]+)\"?',msg); region=m.group(1) if m else None
    elif "starting server version" in msg:
        t="server_start"
    elif "starting listen" in msg or "starting default_region" in msg or "starting beacon_interval" in msg:
        t="start"
    elif "initialized session module" in msg:
        t="session_init"
    elif "failed to reconnect" in msg or "router error" in msg or "ingest error" in msg:
        t="error"
    elif "new packet forwarder client" in msg:
        t="client_connect"
        m=re.search(r'mac=([0-9A-Fa-f:]+)',msg); mac=m.group(1) if m else None
    if t is None:
        t="info"
    if bid:
        bid = clean_beacon_id(bid)
    return t,bid,mac,freq,snr,rssi,length,region


def insert(ts,level,module,msg,raw):
    t,bid,mac,freq,snr,rssi,length,region=classify(msg, raw)
    cur.execute("""INSERT INTO events
        (ts,level,module,type,beacon_id,mac,freq,snr,rssi,len,region,raw)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
        (ts,level,module,t,bid,mac,freq,snr,rssi,length,region,raw))
    conn.commit()


def load_offset():
    try:
        with open(STATE_PATH,"r") as f:
            return int(f.read().strip() or 0)
    except:
        return 0


def save_offset(v):
    try:
        with open(STATE_PATH,"w") as f:
            f.write(str(v))
    except:
        pass


def event_count():
    try:
        return cur.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    except:
        return 0


def parse_line(raw_line):
    line = raw_line.strip()
    json_ts = None
    if line.startswith("{") and "\"log\"" in line:
        try:
            obj = json.loads(line)
            json_ts = obj.get("time")
            line = str(obj.get("log", "")).strip()
        except:
            pass
    if not line:
        return None

    m = GW_RS_RE.match(line)
    if m:
        ts = m.group("ts")
        level = m.group("level").upper()
        rest = m.group("rest").strip()
        rest = re.sub(r'^(?:run:)+\\s*', '', rest)
        mm = re.match(r'(?P<module>gateway_rs::[A-Za-z0-9_:]+):?\\s*(?P<msg>.*)$', rest)
        module = mm.group("module") if mm else ""
        msg = mm.group("msg") if mm else rest
        return ts, level, module, msg, line

    m = GW_CFG_RE.match(line)
    if m:
        ts = f"{m.group('date')}T{m.group('time')}Z"
        level = m.group("level").upper()
        rest = m.group("rest")
        mm = re.search(r'@([A-Za-z0-9_]+):', rest)
        module = mm.group(1) if mm else "gateway_config"
        msg = rest
        return ts, level, module, msg, line

    if json_ts:
        ts = json_ts.replace(" ", "T")
        level = "INFO"
        module = ""
        msg = line
        return ts, level, module, msg, line

    return None


def follow(path):
    offset = load_offset()
    if offset > 0 and event_count() == 0:
        offset = 0
        save_offset(0)
    with open(path,"r",encoding="utf-8",errors="ignore") as f:
        if offset > 0:
            f.seek(offset)
        else:
            f.seek(0)
        while True:
            line = f.readline()
            if line:
                offset = f.tell()
                save_offset(offset)
                parsed = parse_line(line)
                if not parsed:
                    continue
                ts, level, module, msg, raw = parsed
                insert(ts, level, module, msg, raw)
            else:
                time.sleep(0.5)
                try:
                    size = os.path.getsize(path)
                    if size < offset:
                        offset = 0
                        save_offset(offset)
                        f.seek(0)
                except:
                    pass


if __name__=="__main__":
    while not os.path.exists(LOG_PATH):
        print(f"Waiting for {LOG_PATH}...")
        time.sleep(5)
    follow(LOG_PATH)
EOF

  # ---- API ----
  cat > "$BASE_DIR/api/Dockerfile" <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY main.py .
CMD ["python", "main.py"]
EOF

  cat > "$BASE_DIR/api/main.py" <<'EOF'
import os, json, sqlite3, re
import urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

DB_PATH      = os.getenv("DB_PATH", "/data/events.db")
DEVICES_PATH = os.getenv("DEVICES_PATH", "/data/devices.json")
BASE58_RE    = re.compile(r'^[1-9A-HJ-NP-Za-km-z]{20,}$')


def db():
    c = sqlite3.connect(DB_PATH, timeout=1, check_same_thread=False)
    c.row_factory = sqlite3.Row
    try:
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("PRAGMA busy_timeout=1000")
    except:
        pass
    return c


def load_devices():
    try:
        with open(DEVICES_PATH,"r",encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except:
        return {}


def save_devices(d):
    with open(DEVICES_PATH,"w",encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=True, indent=2)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _json(self, data, st=200):
        b = json.dumps(data, default=str).encode()
        self.send_response(st)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(b)))
        self.send_header("Access-Control-Allow-Origin","*")
        self.end_headers()
        self.wfile.write(b)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Access-Control-Allow-Methods","GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers","Content-Type")
        self.end_headers()

    def do_POST(self):
        p = urlparse(self.path)
        if p.path != "/devices":
            return self._json({"error":"not found"},404)
        length = int(self.headers.get("Content-Length","0") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
            if not isinstance(data, dict):
                return self._json({"error":"invalid payload"},400)
            save_devices(data)
            return self._json({"ok": True})
        except Exception as e:
            return self._json({"error": str(e)},400)

    def do_GET(self):
        p   = urlparse(self.path)
        qs  = parse_qs(p.query)
        path= p.path
        if   path == "/metrics/summary": self.summary(qs)
        elif path == "/events":          self.events(qs)
        elif path == "/beacons":         self.beacons(qs)
        elif path.startswith("/beacon/"):  self.beacon_detail(path.split("/",2)[2])
        elif path == "/chart/daily":     self.chart_daily(qs)
        elif path == "/devices":         self.devices()
        elif path == "/macs":            self.macs()
        elif path == "/local/info":      self.local_info(qs)
        elif path == "/hotspot":         self.hotspot(qs)
        elif path == "/health":          self._json({"ok": True})
        else: self._json({"error":"not found"},404)

    def _where(self, qs):
        frm = qs.get("from",[""])[0]
        to  = qs.get("to",  [""])[0]
        cond=[]; params=[]
        if frm: cond.append("ts >= ?"); params.append(frm)
        if to:  cond.append("ts <= ?"); params.append(to)
        where = ("WHERE " + " AND ".join(cond)) if cond else ""
        andwhere = ("AND " + " AND ".join(cond)) if cond else ""
        return where, andwhere, params

    def summary(self, qs):
        where, andwhere, params = self._where(qs)
        conn = db(); cur = conn.cursor()
        cur.execute(f"""
            SELECT
              SUM(type='beacon_tx')        as beacons_tx,
              SUM(type='beacon_rx')        as beacons_rx,
              SUM(type='witness_report')   as witnesses,
              SUM(type='witness_ignored')  as witnesses_ignored,
              SUM(type='error')            as errors,
              SUM(type='server_start')     as restarts,
              AVG(CASE WHEN type='beacon_rx' THEN rssi END) as avg_rssi,
              AVG(CASE WHEN type='beacon_rx' THEN snr  END) as avg_snr,
              MIN(CASE WHEN type='beacon_rx' THEN rssi END) as min_rssi,
              MAX(CASE WHEN type='beacon_rx' THEN rssi END) as max_rssi,
              MIN(CASE WHEN type='beacon_rx' THEN snr  END) as min_snr,
              MAX(CASE WHEN type='beacon_rx' THEN snr  END) as max_snr
            FROM events {where}
        """, params)
        row = cur.fetchone()
        cur.execute(f"""
            SELECT raw FROM events
            WHERE type='beacon_next_time' {andwhere}
            ORDER BY id DESC LIMIT 1
        """, params)
        nbt = cur.fetchone()
        next_beacon = None
        if nbt:
            m = re.search(r'beacon_time=([^,]+)', nbt["raw"])
            if m: next_beacon = m.group(1).strip()
        if not next_beacon:
            cur.execute(f"""
                SELECT raw FROM events
                WHERE raw LIKE '%beacon_time=%' {andwhere}
                ORDER BY id DESC LIMIT 1
            """, params)
            row2 = cur.fetchone()
            if row2:
                m = re.search(r'beacon_time=([^,]+)', row2["raw"])
                if m: next_beacon = m.group(1).strip()
        cur.execute(f"""
            SELECT region FROM events
            WHERE type='region_update' AND region IS NOT NULL {andwhere}
            ORDER BY id DESC LIMIT 1
        """, params)
        rrow = cur.fetchone()
        # If RF stats missing (older DB), derive from raw beacon_rx lines
        rf = None
        if (row["avg_rssi"] is None) and (row["avg_snr"] is None):
            rf = self._rf_from_raw(andwhere, params)
        conn.close()
        self._json({
            "beacons_tx":        row["beacons_tx"] or 0,
            "beacons_rx":        row["beacons_rx"] or 0,
            "witnesses":         row["witnesses"]  or 0,
            "witnesses_ignored": row["witnesses_ignored"] or 0,
            "errors":            row["errors"]     or 0,
            "restarts":          row["restarts"]   or 0,
            "avg_rssi":          rf["avg_rssi"] if rf else row["avg_rssi"],
            "avg_snr":           rf["avg_snr"] if rf else row["avg_snr"],
            "min_rssi":          rf["min_rssi"] if rf else row["min_rssi"],
            "max_rssi":          rf["max_rssi"] if rf else row["max_rssi"],
            "min_snr":           rf["min_snr"] if rf else row["min_snr"],
            "max_snr":           rf["max_snr"] if rf else row["max_snr"],
            "next_beacon":       next_beacon,
            "region":            rrow["region"] if rrow else None,
        })

    def events(self, qs):
        where, _, params = self._where(qs)
        typ  = qs.get("type",[""])[0]
        mac  = qs.get("mac", [""])[0]
        page = max(0, int(qs.get("page",["0"])[0]))
        limit= min(200, max(10, int(qs.get("limit",["100"])[0])))
        offset = page * limit
        extra=[]; ep=[]
        if typ: extra.append("type = ?"); ep.append(typ)
        if mac: extra.append("mac = ?");  ep.append(mac)
        if extra:
            sep = "AND " if where else "WHERE "
            where += " " + sep + " AND ".join(extra)
        params += ep
        conn = db(); cur = conn.cursor()
        cur.execute(f"SELECT COUNT(*) as n FROM events {where}", params)
        total = cur.fetchone()["n"]
        cur.execute(f"""
            SELECT ts,level,module,type,beacon_id,mac,freq,snr,rssi,len,region,raw
            FROM events {where}
            ORDER BY id DESC LIMIT ? OFFSET ?
        """, params + [limit, offset])
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        # Fill missing RF from raw if not parsed earlier
        for r in rows:
            if r.get("raw") and (r.get("rssi") is None or r.get("snr") is None or r.get("freq") is None or r.get("len") is None):
                rf = self._parse_rf(r["raw"])
                if rf:
                    r["rssi"] = r["rssi"] if r["rssi"] is not None else rf.get("rssi")
                    r["snr"]  = r["snr"]  if r["snr"]  is not None else rf.get("snr")
                    r["freq"] = r["freq"] if r["freq"] is not None else rf.get("freq")
                    r["len"]  = r["len"]  if r["len"]  is not None else rf.get("len")
        self._json({"total":total,"page":page,"limit":limit,"rows":rows})

    def beacons(self, qs):
        _, andwhere, params = self._where(qs)
        conn = db(); cur = conn.cursor()
        cur.execute(f"""
            SELECT beacon_id,
                   MIN(ts) as first_seen,
                   SUM(type='beacon_tx')        as tx,
                   SUM(type='beacon_rx')        as rx,
                   SUM(type='beacon_tx_report') as tx_reported,
                   SUM(type='witness_report')   as witnesses,
                   SUM(type='witness_ignored')  as ignored,
                   AVG(CASE WHEN type='beacon_rx' THEN rssi END) as avg_rssi,
                   AVG(CASE WHEN type='beacon_rx' THEN snr  END) as avg_snr
            FROM events
            WHERE beacon_id IS NOT NULL AND LENGTH(beacon_id) >= 16 {andwhere}
            GROUP BY beacon_id
            ORDER BY first_seen DESC
            LIMIT 100
        """, params)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self._json(rows)

    def beacon_detail(self, bid):
        conn = db(); cur = conn.cursor()
        cur.execute("SELECT * FROM events WHERE beacon_id=? ORDER BY id ASC",(bid,))
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self._json(rows)

    def chart_daily(self, qs):
        _, andwhere, params = self._where(qs)
        conn = db(); cur = conn.cursor()
        cur.execute(f"""
            SELECT substr(ts,1,10) as day,
                   SUM(type='beacon_tx')       as tx,
                   SUM(type='beacon_rx')       as rx,
                   SUM(type='witness_report')  as wit,
                   SUM(type='error')           as err,
                   AVG(CASE WHEN type='beacon_rx' THEN rssi END) as avg_rssi,
                   AVG(CASE WHEN type='beacon_rx' THEN snr  END) as avg_snr
            FROM events
            WHERE 1=1 {andwhere}
            GROUP BY day ORDER BY day ASC
        """, params)
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        self._json(rows)

    def devices(self):
        self._json(load_devices())

    def macs(self):
        conn = db(); cur = conn.cursor()
        cur.execute("SELECT DISTINCT mac FROM events WHERE mac IS NOT NULL ORDER BY mac ASC")
        rows = [r["mac"] for r in cur.fetchall()]
        conn.close()
        self._json(rows)

    def local_info(self, qs):
        host = (qs.get("host", [""])[0] or "").strip()
        if not re.match(r'^[0-9.]+$', host):
            host = "127.0.0.1"
        gw = self._last_gateway_key()
        panel = self._heltec_panel_info(host)
        info = {"gateway_key": gw}
        info.update(panel)
        addr = gw if self._is_addr(gw) else panel.get("address")
        if self._is_addr(addr):
            info["address"] = addr
        elif "address" in info:
            del info["address"]
        self._json(info)

    def _is_addr(self, s):
        if not s:
            return False
        return bool(BASE58_RE.match(s))

    def _last_gateway_key(self):
        try:
            conn = db(); cur = conn.cursor()
            # Prefer the server start line (contains the real gateway key)
            cur.execute("SELECT raw FROM events WHERE raw LIKE '%server:%key=%' ORDER BY id DESC LIMIT 1")
            row = cur.fetchone()
            if not row:
                cur.execute("SELECT raw FROM events WHERE raw LIKE '%key=%' AND raw NOT LIKE '%pubkey=%' ORDER BY id DESC LIMIT 1")
                row = cur.fetchone()
            conn.close()
            if not row:
                return None
            m = re.search(r'key=([1-9A-HJ-NP-Za-km-z]{20,})', row["raw"])
            return m.group(1) if m else None
        except Exception:
            return None

    def _heltec_panel_info(self, host="127.0.0.1"):
        info = {}
        url = f"http://{host}/apply.php"
        payloads = [b"{}", b'{"apply":"getinfo"}']
        for body in payloads:
            try:
                req = urllib.request.Request(url, data=body, headers={"Content-Type":"application/json"})
                with urllib.request.urlopen(req, timeout=3) as resp:
                    raw = resp.read().decode("utf-8", "ignore")
                data = json.loads(raw)
                if isinstance(data, dict):
                    if data.get("addr"):
                        info["address"] = data.get("addr")
                    if data.get("name"):
                        info["name"] = data.get("name")
                    if data.get("wallet"):
                        info["wallet"] = data.get("wallet")
                    if info:
                        return info
            except Exception:
                pass
        # fallback: scrape HTML if apply.php not reachable
        try:
            with urllib.request.urlopen(f"http://{host}/", timeout=3) as resp:
                html = resp.read().decode("utf-8", "ignore")
        except Exception:
            return info

        m = re.search(r'\\baddress\\s*[:=]\\s*([1-9A-HJ-NP-Za-km-z]{20,})', html, re.IGNORECASE)
        if m:
            info["address"] = m.group(1)
        m = re.search(r'Helium wallet[^\\n\\r]*value=\"([^\"]+)\"', html, re.IGNORECASE)
        if m and m.group(1).strip():
            info["wallet"] = m.group(1).strip()
        return info

    def _parse_rf(self, raw):
        try:
            s = raw or ""
            m = re.search(r'snr:\s*([-0-9.]+)', s, re.IGNORECASE)
            snr = float(m.group(1)) if m else None
            m = re.search(r'rssi:\s*([-0-9.]+)', s, re.IGNORECASE)
            rssi = int(float(m.group(1))) if m else None
            m = re.search(r'(\\d+)\\s*MHz', s, re.IGNORECASE)
            freq = int(m.group(1)) if m else None
            m = re.search(r'len:\s*(\\d+)', s, re.IGNORECASE)
            ln = int(m.group(1)) if m else None
            if snr is None and rssi is None and freq is None and ln is None:
                return None
            return {"snr": snr, "rssi": rssi, "freq": freq, "len": ln}
        except Exception:
            return None

    def _rf_from_raw(self, andwhere, params):
        try:
            conn = db(); cur = conn.cursor()
            cur.execute(f"""
                SELECT raw FROM events
                WHERE type='beacon_rx' {andwhere}
                ORDER BY id DESC LIMIT 2000
            """, params)
            vals_rssi = []
            vals_snr  = []
            for row in cur.fetchall():
                rf = self._parse_rf(row["raw"])
                if not rf:
                    continue
                if rf.get("rssi") is not None:
                    vals_rssi.append(rf["rssi"])
                if rf.get("snr") is not None:
                    vals_snr.append(rf["snr"])
            conn.close()
            if not vals_rssi and not vals_snr:
                return None
            def avg(v): return sum(v)/len(v) if v else None
            return {
                "avg_rssi": avg(vals_rssi),
                "min_rssi": min(vals_rssi) if vals_rssi else None,
                "max_rssi": max(vals_rssi) if vals_rssi else None,
                "avg_snr":  avg(vals_snr),
                "min_snr":  min(vals_snr) if vals_snr else None,
                "max_snr":  max(vals_snr) if vals_snr else None,
            }
        except Exception:
            return None

    def hotspot(self, qs):
        addr = (qs.get("addr", [""])[0] or "").strip()
        if not addr:
            return self._json({"error": "addr required"}, 400)
        url = "https://entities.nft.helium.io/" + addr
        try:
            with urllib.request.urlopen(url, timeout=6) as resp:
                raw = resp.read().decode("utf-8")
            data = json.loads(raw)
            return self._json(data)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return self._json({"error":"not_found","message":"Adres nie istnieje w Entity API (brak hotspotu NFT)."})
            return self._json({"error":"upstream","message":f"Entity API HTTP {e.code}"}, 502)
        except Exception as e:
            return self._json({"error": str(e)}, 502)


if __name__ == "__main__":
    s = HTTPServer(("0.0.0.0", 8000), H)
    print("API on :8000")
    s.serve_forever()
EOF

  # ---- UI ----
  cat > "$BASE_DIR/ui/Dockerfile" <<'EOF'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY www /usr/share/nginx/html
COPY .htpasswd /etc/nginx/.htpasswd
EOF

  if [[ "$AUTH_ENABLED" == "1" ]]; then
    cat > "$BASE_DIR/ui/nginx.conf" <<'EOF'
events {}
http {
    resolver 127.0.0.11 ipv6=off;
    server {
        listen 1111;
        server_name _;
        auth_basic "Helium Dashboard";
        auth_basic_user_file /etc/nginx/.htpasswd;
        root /usr/share/nginx/html;
        index index.html;
        location /logout {
            return 401;
        }
        location /api/ {
            proxy_pass http://miner-dashboard-api:8000/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header Connection "";
        }
        location / { try_files $uri /index.html; }
    }
}
EOF
  else
    cat > "$BASE_DIR/ui/nginx.conf" <<'EOF'
events {}
http {
    resolver 127.0.0.11 ipv6=off;
    server {
        listen 1111;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;
        location /api/ {
            proxy_pass http://miner-dashboard-api:8000/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header Connection "";
        }
        location / { try_files $uri /index.html; }
    }
}
EOF
  fi

  cat > "$BASE_DIR/ui/www/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="pl" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <title>Helium Miner Dashboard</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    :root{
      --bg:#0b1020;--fg:#e5e7eb;--muted:#9aa4b2;
      --card:#10172a;--border:#1f2a44;
      --accent:#5eead4;--accent-2:#60a5fa;--accent-3:#f59e0b;
      --danger:#f87171;--good:#34d399;
      --chip:#0f172a;--shadow:0 10px 30px rgba(2,8,23,.35);
      --note-bg:rgba(56,189,248,.08);--note-border:rgba(56,189,248,.25);--note-text:#bae6fd;
      --grid:linear-gradient(180deg, rgba(255,255,255,.04), rgba(255,255,255,0));
      --bg-grad:radial-gradient(800px 500px at 10% -10%, rgba(94,234,212,.25), transparent 60%),
                radial-gradient(800px 500px at 90% -10%, rgba(96,165,250,.25), transparent 60%),
                linear-gradient(180deg, #070b16 0%, #0b1020 40%, #0b1020 100%);
    }
    [data-theme="light"]{
      --bg:#f1f3f6;--fg:#0f172a;--muted:#5b6473;
      --card:#ffffff;--border:#d8dee8;
      --accent:#0ea5e9;--accent-2:#2563eb;--accent-3:#f59e0b;
      --danger:#ef4444;--good:#16a34a;
      --chip:#eef2f7;--shadow:0 10px 24px rgba(15,23,42,.08);
      --note-bg:#e6f4ff;--note-border:#93c5fd;--note-text:#0f172a;
      --grid:linear-gradient(180deg, rgba(15,23,42,.03), rgba(255,255,255,0));
      --bg-grad:linear-gradient(180deg, #eef1f5 0%, #f3f5f8 55%, #f7f9fb 100%);
    }
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      font-family:"Space Grotesk","Segoe UI",sans-serif;
      background:var(--bg-grad);
      color:var(--fg);
      min-height:100vh;
    }
    .container{max-width:1180px;margin:0 auto;padding:28px 18px 60px}
    header{display:flex;flex-wrap:wrap;gap:14px;align-items:center;justify-content:space-between;margin-bottom:18px}
    .title{font-size:24px;font-weight:700;letter-spacing:.2px}
    .subtitle{color:var(--muted);font-size:13px;margin-top:4px}
    .status-line{display:flex;align-items:center;gap:8px}
    .section-title{font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);margin:18px 0 8px}
    .controls{display:flex;flex-wrap:wrap;gap:8px;align-items:center;min-width:0}
    button,select,input{border:1px solid var(--border);background:var(--card);color:var(--fg);padding:8px 10px;border-radius:10px;font-size:13px;box-shadow:var(--shadow)}
    .controls input{min-width:0}
    button{cursor:pointer}
    .chip{display:inline-flex;gap:8px;align-items:center;background:var(--chip);border:1px solid var(--border);padding:6px 10px;border-radius:999px;font-size:12px;color:var(--muted)}
    label.chip{cursor:pointer}
    label.chip input{accent-color:var(--accent)}
    .grid{display:grid;gap:14px}
    .grid.metrics{grid-template-columns:repeat(auto-fit,minmax(170px,1fr));margin:12px 0 18px}
    .grid.two{grid-template-columns:repeat(auto-fit,minmax(320px,1fr));margin:10px 0 18px}
    .card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:16px;box-shadow:var(--shadow)}
    .card-wide{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:16px;box-shadow:var(--shadow)}
    .lbl{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.05em}
    .val{font-size:18px;font-weight:700;margin-top:6px}
    .val.yellow{color:var(--accent-3)} .val.blue{color:var(--accent)} .val.green{color:#4ade80} .val.white{color:var(--text)}
    .meta{font-size:11px;color:var(--muted);margin-top:4px}
    .badge{display:inline-block;padding:3px 10px;border-radius:999px;font-size:11px;font-weight:700}
    .b-on{background:#14532d;color:#4ade80}
    .b-off{background:#450a0a;color:#f87171}
    .b-unk{background:#1e1b4b;color:#a5b4fc}
    .status-dot{width:8px;height:8px;border-radius:50%;display:inline-block;background:var(--muted)}
    .status-dot.ok{background:var(--good);box-shadow:0 0 8px rgba(16,185,129,.6)}
    .status-dot.bad{background:var(--danger);box-shadow:0 0 8px rgba(239,68,68,.6)}
    .spin{display:inline-block;width:13px;height:13px;border:2px solid #374151;border-top-color:#22c55e;border-radius:50%;animation:sp .7s linear infinite;vertical-align:middle;margin-right:6px}
    @keyframes sp{to{transform:rotate(360deg)}}
    .metric-title{font-size:12px;color:var(--muted);margin-bottom:8px;display:flex;align-items:center;gap:6px}
    .metric-value{font-size:26px;font-weight:700}
    .metric-value.long{font-size:12px;word-break:break-all;line-height:1.2}
    .metric-sub{font-size:12px;color:var(--muted);margin-top:6px}
    .card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}
    .legend{display:flex;gap:10px;flex-wrap:wrap}
    .dot{width:10px;height:10px;border-radius:50%}
    .table-wrap{overflow-x:hidden;overflow-y:auto;border-radius:12px;border:1px solid var(--border)}
    .table-wrap.scroll-x{overflow-x:hidden}
    .table-wrap.beacons-wrap{overflow-x:hidden}
    table{width:100%;border-collapse:collapse;font-size:12px;table-layout:fixed}
    th,td{padding:10px;border-bottom:1px solid var(--border);text-align:left;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    td.trunc{max-width:240px}
    th.col-time, td.col-time{width:150px}
    th.col-type, td.col-type{width:150px}
    th.col-dev, td.col-dev{width:170px}
    td.col-dev{white-space:normal;line-height:1.2}
    .dev-alias{font-size:11px;color:var(--muted);margin-top:2px;word-break:break-word}
    th.col-id, td.col-id{width:220px}
    th.col-rf, td.col-rf{width:150px}
    th.col-mini, td.col-mini{width:56px;text-align:center}
    .rf{display:flex;flex-direction:column;gap:2px;font-size:11px;color:var(--muted);white-space:normal}
    .rf b{color:var(--fg);font-weight:600}
    th{position:sticky;top:0;background:var(--card);z-index:1}
    tr:hover td{background:rgba(100,116,139,.12)}
    .pill{display:inline-flex;align-items:center;gap:6px;padding:4px 8px;border-radius:999px;font-size:11px;background:rgba(94,234,212,.12);border:1px solid rgba(94,234,212,.25)}
    .pill.warn{background:rgba(245,158,11,.15);border-color:rgba(245,158,11,.3)}
    .pill.err{background:rgba(248,113,113,.15);border-color:rgba(248,113,113,.3)}
    .pill.info{background:rgba(96,165,250,.15);border-color:rgba(96,165,250,.3)}
    .mark{display:inline-flex;align-items:center;justify-content:center;padding:2px 6px;border-radius:6px;font-size:10px;font-weight:700;margin-left:6px;border:1px solid transparent}
    .mark.ok{color:#34d399;background:rgba(16,185,129,.15);border-color:rgba(16,185,129,.35)}
    .mark.money{color:#fbbf24;background:rgba(245,158,11,.15);border-color:rgba(245,158,11,.45)}
    .mark.bad{color:#f87171;background:rgba(248,113,113,.15);border-color:rgba(248,113,113,.35)}
    .ico{width:12px;height:12px;display:inline-block;background-size:contain;background-repeat:no-repeat}
    .ico.tx{background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2360a5fa' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M12 19V5'/><path d='M7 10l5-5 5 5'/></svg>")}
    .ico.rx{background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%235eead4' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M12 5v14'/><path d='M7 14l5 5 5-5'/></svg>")}
    .ico.wit{background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23f59e0b' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7Z'/><circle cx='12' cy='12' r='3'/></svg>")}
    .ico.err{background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23f87171' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M12 9v4'/><path d='M12 17h.01'/><path d='M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z'/></svg>")}
    .muted{color:var(--muted)}
    .split{display:flex;gap:10px;flex-wrap:wrap}
    .chart{width:100%;height:220px;border-radius:12px;background:var(--grid);border:1px solid var(--border)}
    .rf-charts{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-top:12px}
    .mini-chart{width:100%;height:70px;border-radius:10px;background:var(--grid);border:1px solid var(--border)}
    .device-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:6px 0}
    .dev-mac{min-width:160px;font-size:12px;color:var(--fg)}
    #apiBaseInput{flex:1;min-width:160px;max-width:240px}
    #devicesList input{flex:1;min-width:160px;max-width:240px}
    .devices-head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
    .devices-note{margin-top:6px}
    @media (max-width: 780px){
      .table-wrap{overflow-x:hidden}
      .table-wrap.scroll-x{overflow-x:auto;-webkit-overflow-scrolling:touch}
      .table-wrap.scroll-x table{min-width:860px}
      .table-wrap.beacons-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}
      .table-wrap.beacons-wrap table{min-width:620px}
      .table-wrap.scroll-x th.col-type,
      .table-wrap.scroll-x td.col-type{width:230px}
      .table-wrap.scroll-x td.col-type{overflow:visible}
      .controls{flex-direction:column;align-items:stretch}
      .controls .chip{justify-content:center}
      .controls button,.controls select{width:100%;text-align:center}
      #apiBaseInput{max-width:none;width:100%}
      #devicesList input{max-width:none;width:100%}
      .device-row{flex-direction:column;align-items:stretch}
      .dev-mac{min-width:0;word-break:break-all}
      .devices-head{align-items:stretch}
      .devices-note{font-size:12px;line-height:1.4}
      .note{font-size:13px}
    }
    .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
    .btn{background:var(--accent-2);border:none;color:#0b1020;padding:6px 12px;border-radius:10px;font-weight:700;cursor:pointer}
    .btn:disabled{opacity:.6;cursor:default}
    .err{color:var(--danger);font-size:12px;margin-top:8px}
    .note{background:var(--note-bg);border:1px solid var(--note-border);padding:10px 12px;border-radius:10px;color:var(--note-text);font-size:12px;line-height:1.5;margin-bottom:10px}
    .info-row{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}
    .info-chip{background:rgba(148,163,184,.12);border-radius:8px;padding:4px 8px;font-size:11px;color:var(--text)}
    .info-chip span{color:var(--accent);font-weight:600}
    .ext{color:var(--accent);font-size:12px;text-decoration:none}
    .ext:hover{text-decoration:underline}
    .updated{font-size:11px;color:var(--muted);margin-top:8px}
    .hotspot-grid{grid-template-columns:repeat(auto-fit,minmax(180px,1fr));margin-top:10px}
    .mini{padding:10px;border-radius:12px;box-shadow:none}
    footer{color:var(--muted);font-size:12px;margin-top:10px}
    .pre{white-space:pre-wrap;font-size:12px;color:var(--muted);background:rgba(15,23,42,.2);border:1px dashed var(--border);padding:10px;border-radius:12px;margin-top:10px;max-width:100%;overflow-wrap:anywhere;word-break:break-word;max-height:140px;overflow:auto}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div>
        <div class="title">Helium Miner Dashboard</div>
        <div class="subtitle status-line" id="statusLine">-</div>
      </div>
      <div class="controls">
        <span class="chip" id="regionChip">Region: -</span>
        <span class="chip" id="nextBeaconChip">Next beacon: -</span>
        <select id="rangeSelect">
          <option value="1h">1h</option>
          <option value="24h" selected>24h</option>
          <option value="7d">7d</option>
          <option value="30d">30d</option>
          <option value="all">all</option>
        </select>
        <select id="langSelect">
          <option value="pl">PL</option>
          <option value="en">EN</option>
        </select>
        <button id="themeToggle" data-i18n="theme">Motyw</button>
        <button id="refreshBtn">Refresh</button>
        <button id="logoutBtn" data-i18n="logout">Wyloguj</button>
      </div>
    </header>

    <div class="note" data-i18n="dataNote">
      Dane lokalne: logi gateway-rs + panel Heltec. Dane sieciowe: Entity API (bez klucza).
    </div>

    <div class="section-title" data-i18n="summary">Podsumowanie</div>
    <div class="grid metrics">
      <div class="card">
        <div class="metric-title"><span class="ico tx"></span><span data-i18n="beaconsSent">Beacony wyslane</span></div>
        <div class="metric-value" id="mTx">0</div>
        <div class="metric-sub" id="mTxSub">-</div>
      </div>
      <div class="card">
        <div class="metric-title"><span class="ico rx"></span><span data-i18n="beaconsReceived">Beacony odebrane</span></div>
        <div class="metric-value" id="mRx">0</div>
        <div class="metric-sub" id="mRxSub">-</div>
      </div>
      <div class="card">
        <div class="metric-title"><span class="ico wit"></span><span data-i18n="witnesses">Witnessy</span></div>
        <div class="metric-value" id="mWit">0</div>
        <div class="metric-sub" id="mWitSub">-</div>
      </div>
      <div class="card">
        <div class="metric-title"><span class="ico err"></span><span data-i18n="errors">Bledy</span></div>
        <div class="metric-value" id="mErr">0</div>
        <div class="metric-sub" id="mErrSub">-</div>
      </div>
    </div>

    <div class="grid metrics">
      <div class="card">
        <div class="metric-title" data-i18n="regionLabel">Region</div>
        <div class="metric-value" id="sRegion">-</div>
      </div>
      <div class="card">
        <div class="metric-title" data-i18n="nextBeaconLabel">Next beacon</div>
        <div class="metric-value" id="sNextBeacon">-</div>
      </div>
      <div class="card">
        <div class="metric-title" data-i18n="restartsLabel">Restarty</div>
        <div class="metric-value" id="sRestarts">-</div>
      </div>
      <div class="card">
        <div class="metric-title" data-i18n="witnessIgnored">Witness ignored</div>
        <div class="metric-value" id="mWitIgnored">-</div>
      </div>
    </div>

    <div class="grid two">
      <div class="card">
        <div class="card-header">
          <div data-i18n="activityChart">Aktywnosc (TX/RX/Witness)</div>
          <div class="legend">
            <span class="pill info"><span class="ico tx"></span>TX</span>
            <span class="pill"><span class="ico rx"></span>RX</span>
            <span class="pill warn"><span class="ico wit"></span>WIT</span>
            <span class="pill err"><span class="ico err"></span>ERR</span>
          </div>
        </div>
        <div class="chart" id="chart"></div>
      </div>
      <div class="card">
        <div class="card-header">
          <div data-i18n="rfStats">RF Statystyki</div>
        </div>
        <div class="split">
          <div>
            <div class="metric-title">RSSI avg</div>
            <div class="metric-value" id="rssiAvg">-</div>
          </div>
          <div>
            <div class="metric-title">RSSI min/max</div>
            <div class="metric-value" id="rssiMinMax">-</div>
          </div>
        </div>
        <div class="split" style="margin-top:12px">
          <div>
            <div class="metric-title">SNR avg</div>
            <div class="metric-value" id="snrAvg">-</div>
          </div>
          <div>
            <div class="metric-title">SNR min/max</div>
            <div class="metric-value" id="snrMinMax">-</div>
          </div>
        </div>
        <div class="rf-charts">
          <div>
            <div class="metric-title" data-i18n="rssiTrend">RSSI trend</div>
            <div class="mini-chart" id="rssiChart"></div>
          </div>
          <div>
            <div class="metric-title" data-i18n="snrTrend">SNR trend</div>
            <div class="mini-chart" id="snrChart"></div>
          </div>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <div data-i18n="events">Zdarzenia</div>
        <div class="controls">
          <select id="macSelect">
            <option value="" data-i18n="allDevices">Wszystkie urzadzenia</option>
          </select>
          <label class="chip">
            <input id="showTech" type="checkbox">
            <span data-i18n="showTech">Techniczne</span>
          </label>
          <label class="chip">
            <input id="showErrors" type="checkbox">
            <span data-i18n="showErrors">Bledy</span>
          </label>
          <select id="typeSelect">
            <option value="" data-i18n="all">Wszystkie</option>
            <option value="beacon_tx">Beacon TX</option>
            <option value="beacon_rx">Beacon RX</option>
            <option value="witness_report">Witness</option>
            <option value="error">Error</option>
            <option value="region_update">Region</option>
            <option value="session_init">Session</option>
          </select>
        </div>
      </div>
      <div class="table-wrap scroll-x">
        <table>
          <thead>
            <tr>
              <th class="col-time" data-i18n="time">Czas</th>
              <th class="col-type" data-i18n="type">Typ</th>
              <th class="col-dev" data-i18n="device">Urzadzenie</th>
              <th class="col-id" data-i18n="beaconId">Beacon ID</th>
              <th class="col-rf">RF</th>
            </tr>
          </thead>
          <tbody id="eventsBody"></tbody>
        </table>
      </div>
      <div class="pre" id="eventDetail">-</div>
    </div>

    <div class="grid two">
      <div class="card">
        <div class="card-header">
          <div data-i18n="beacons">Beacony</div>
          <div class="muted" id="beaconHint">-</div>
        </div>
        <div class="table-wrap beacons-wrap">
          <table>
            <thead>
              <tr>
                <th class="col-id" data-i18n="beaconId">Beacon ID</th>
                <th class="col-time" data-i18n="firstSeen">Pierwszy</th>
                <th class="col-mini">TX</th>
                <th class="col-mini">RX</th>
                <th class="col-mini">WIT</th>
              </tr>
            </thead>
            <tbody id="beaconsBody"></tbody>
          </table>
        </div>
        <div class="pre" id="beaconDetail">-</div>
      </div>
      <div class="card">
        <div class="card-header devices-head">
          <div data-i18n="devices">Urzadzenia</div>
          <div class="controls devices-controls">
            <input id="apiBaseInput" placeholder="API base (np. http://192.168.0.119:8000)">
            <button id="apiBaseSave" data-i18n="save">Zapisz</button>
          </div>
        </div>
        <div class="muted devices-note" data-i18n="devicesNote">Alias = Twoja nazwa dla MAC (pokazuje sie w Zdarzeniach).</div>
        <div id="devicesList"></div>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <div data-i18n="hotspotTitle">Hotspot Info</div>
        <div class="muted" id="hotspotStatus">-</div>
      </div>
      <div class="note" id="hotspotNote" data-i18n="hotspotNote">
        Entity API (oficjalne, bez klucza). Jesli adres nie ma przypisanego hotspotu NFT, pojawi sie blad.
      </div>
      <div class="row">
        <input id="hotspotAddr" placeholder="Hotspot address" value="">
        <button class="btn" id="hotspotBtn" data-i18n="hotspotRefresh">Odswiez</button>
      </div>
      <div id="hotspotErr" class="err"></div>
      <div class="grid hotspot-grid">
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotName">Nazwa</div>
          <div class="metric-value" id="hotspotName">-</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotAddress">Adres</div>
          <div class="metric-value long" id="hotspotAddress">-</div>
        </div>
        <div class="card mini" id="hotspotWalletCard">
          <div class="metric-title" data-i18n="hotspotWallet">Portfel</div>
          <div class="metric-value long" id="hotspotWallet">-</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotLocation">Lokalizacja</div>
          <div class="metric-value" id="hotspotCity">-</div>
          <div class="metric-sub" id="hotspotCountry">-</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotGain">Gain</div>
          <div class="metric-value" id="hotspotGain">-</div>
          <div class="metric-sub">dBi</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotElevation">Wysokość</div>
          <div class="metric-value" id="hotspotElev">-</div>
          <div class="metric-sub" data-i18n="meters">metry n.p.m.</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotRewardable">Rewardable</div>
          <div class="metric-value" id="hotspotRewardable">-</div>
        </div>
        <div class="card mini">
          <div class="metric-title" data-i18n="hotspotNetworks">Sieci</div>
          <div class="metric-value" id="hotspotNetworks">-</div>
        </div>
      </div>
      <div id="hotspotChips" class="info-row">-</div>
      <div class="row" style="margin-top:8px">
        <a id="hotspotExplorer" class="ext" href="#" target="_blank">Helium Explorer</a>
        <a id="hotspotTracker" class="ext" href="#" target="_blank">HeliumTracker</a>
      </div>
      <div id="hotspotUpdated" class="updated">-</div>
    </div>

    <footer id="lastUpdate">-</footer>
  </div>

<script>
const i18n = {
  pl: {
    summary: "Podsumowanie",
    beaconsSent: "Beacony wyslane",
    beaconsReceived: "Beacony odebrane",
    witnesses: "Swiadkowie",
    errors: "Bledy",
    regionLabel: "Region",
    nextBeaconLabel: "Nastepny beacon",
    restartsLabel: "Restarty",
    witnessIgnored: "Swiadkowie (ignor.)",
    allDevices: "Wszystkie urzadzenia",
    showTech: "Techniczne",
    showErrors: "Bledy",
    activityChart: "Aktywnosc (TX/RX/Swiadek)",
    rfStats: "RF Statystyki",
    rssiTrend: "Trend RSSI",
    snrTrend: "Trend SNR",
    events: "Zdarzenia",
    beacons: "Beacony",
    beaconDetail: "Zdarzenia beacona",
    devices: "Urzadzenia",
    devicesNote: "Alias = Twoja nazwa dla MAC (pokazuje sie w Zdarzeniach).",
    hotspotTitle: "Hotspot Info",
    hotspotNote: "Entity API (oficjalne, bez klucza). Stare api.helium.io/v1 jest wylaczone. 404 oznacza brak hotspotu NFT.",
    dataNote: "Dane lokalne: logi gateway-rs + panel Heltec. Dane sieciowe: Entity API (bez klucza).",
    hotspotRefresh: "Odswiez",
    hotspotName: "Nazwa",
    hotspotAddress: "Adres",
    hotspotWallet: "Portfel",
    hotspotLocation: "Lokalizacja",
    hotspotGain: "Gain",
    hotspotElevation: "Wysokość",
    hotspotRewardable: "Zarabia",
    hotspotNetworks: "Sieci",
    meters: "metry n.p.m.",
    statusActive: "AKTYWNY",
    statusInactive: "NIEAKTYWNY",
    statusUnknown: "BRAK DANYCH",
    yes: "TAK",
    no: "NIE",
    time: "Czas",
    type: "Typ",
    module: "Modul",
    device: "Urzadzenie",
    beaconId: "Beacon ID",
    firstSeen: "Pierwszy",
    all: "Wszystkie",
    save: "Zapisz",
    logout: "Wyloguj",
    theme: "Motyw",
    lastUpdate: "Ostatnia aktualizacja",
    noData: "Brak danych",
    updated: "Zaktualizowano",
    apiOffline: "API niedostepne",
    allTime: "caly okres",
  },
  en: {
    summary: "Summary",
    beaconsSent: "Beacons sent",
    beaconsReceived: "Beacons received",
    witnesses: "Witnesses",
    errors: "Errors",
    regionLabel: "Region",
    nextBeaconLabel: "Next beacon",
    restartsLabel: "Restarts",
    witnessIgnored: "Witness (ignored)",
    allDevices: "All devices",
    showTech: "Technical",
    showErrors: "Errors",
    activityChart: "Activity (TX/RX/Witness)",
    rfStats: "RF Stats",
    rssiTrend: "RSSI trend",
    snrTrend: "SNR trend",
    events: "Events",
    beacons: "Beacons",
    beaconDetail: "Beacon events",
    devices: "Devices",
    devicesNote: "Alias = your label for MAC (shown in Events).",
    hotspotTitle: "Hotspot Info",
    hotspotNote: "Entity API (official, no key). Legacy api.helium.io/v1 is disabled. 404 means no hotspot NFT.",
    dataNote: "Local data: gateway-rs logs + Heltec panel. Network data: Entity API (no key).",
    hotspotRefresh: "Refresh",
    hotspotName: "Name",
    hotspotAddress: "Address",
    hotspotWallet: "Wallet",
    hotspotLocation: "Location",
    hotspotGain: "Gain",
    hotspotElevation: "Elevation",
    hotspotRewardable: "Rewardable",
    hotspotNetworks: "Networks",
    meters: "meters a.s.l.",
    statusActive: "ACTIVE",
    statusInactive: "INACTIVE",
    statusUnknown: "NO DATA",
    yes: "YES",
    no: "NO",
    time: "Time",
    type: "Type",
    module: "Module",
    device: "Device",
    beaconId: "Beacon ID",
    firstSeen: "First seen",
    all: "All",
    save: "Save",
    logout: "Logout",
    theme: "Theme",
    lastUpdate: "Last update",
    noData: "No data",
    updated: "Updated",
    apiOffline: "API offline",
    allTime: "all time",
  }
};

const DEFAULT_ADDR = "11LNfAVzNginVeqo9TqniUfoqs4wVGMriHyn7Wmm1SRpiGoGTWw";

let state = {
  lang: localStorage.getItem("lang") || "pl",
  theme: localStorage.getItem("theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"),
  range: localStorage.getItem("range") || "24h",
  type: "",
  mac: "",
  showTech: localStorage.getItem("showTech") === "1",
  showErrors: localStorage.getItem("showErrors") === "1",
  hotspotAddr: localStorage.getItem("hotspotAddr") || "",
  hotspotManual: localStorage.getItem("hotspotAddrManual") === "1",
  localWallet: "",
  devices: {},
  macs: [],
  rfFallback: null,
  rfFromSummary: null,
  lastEvents: []
};

const defaultApi = `${location.origin}/api`;
let apiBase = localStorage.getItem("apiBase") || defaultApi;

function isPrivateHost(h){
  return /^127\\./.test(h) || /^10\\./.test(h) || /^192\\.168\\./.test(h) || /^172\\.(1[6-9]|2\\d|3[0-1])\\./.test(h) || h === "localhost";
}

try{
  const u = new URL(apiBase);
  if (isPrivateHost(u.hostname) && !isPrivateHost(location.hostname)){
    apiBase = defaultApi;
    localStorage.removeItem("apiBase");
  }
}catch(e){}

const $ = (id) => document.getElementById(id);

function t(key){ return (i18n[state.lang] && i18n[state.lang][key]) || key; }

function applyI18n(){
  document.querySelectorAll("[data-i18n]").forEach(el=>{
    const key = el.getAttribute("data-i18n");
    el.textContent = t(key);
  });
}

function setTheme(){
  document.documentElement.setAttribute("data-theme", state.theme);
  localStorage.setItem("theme", state.theme);
}

function setLang(){
  localStorage.setItem("lang", state.lang);
  $("langSelect").value = state.lang;
  applyI18n();
}

function setRange(){
  localStorage.setItem("range", state.range);
  $("rangeSelect").value = state.range;
}

function setFilters(){
  $("showTech").checked = state.showTech;
  $("showErrors").checked = state.showErrors;
  localStorage.setItem("showTech", state.showTech ? "1" : "0");
  localStorage.setItem("showErrors", state.showErrors ? "1" : "0");
}

function rangeFrom(){
  if(state.range === "all") return null;
  const now = new Date();
  if(state.range === "1h") return new Date(now.getTime() - 1*3600*1000);
  if(state.range === "24h") return new Date(now.getTime() - 24*3600*1000);
  if(state.range === "7d") return new Date(now.getTime() - 7*24*3600*1000);
  if(state.range === "30d") return new Date(now.getTime() - 30*24*3600*1000);
  return null;
}

function withRangeParams(params){
  const from = rangeFrom();
  if (from) params.set("from", from.toISOString());
  return params;
}

async function api(path, timeoutMs = 6000){
  const ctrl = new AbortController();
  const to = setTimeout(()=>ctrl.abort(), timeoutMs);
  let res;
  try {
    res = await fetch(apiBase + path, { cache: "no-store", signal: ctrl.signal });
  } finally {
    clearTimeout(to);
  }
  let data = null;
  try { data = await res.json(); } catch(e){ data = null; }
  if(!res.ok){
    const msg = data && data.error ? data.error : `HTTP ${res.status}`;
    throw new Error(msg);
  }
  return data;
}

function fmt(n){
  if(n === null || n === undefined) return "-";
  return Number(n).toFixed(1);
}

function fmtTs(ts){
  if(!ts) return "-";
  return ts.replace("T"," ").replace("Z","").replace(/\.\d+$/,"");
}

function fmtFreq(f){
  if(f === null || f === undefined) return "-";
  const n = Number(f);
  if (!isFinite(n)) return "-";
  if (n >= 1000000) return (n/1000000).toFixed(3) + " MHz";
  if (n >= 1000) return (n/1000).toFixed(3) + " MHz";
  return n + " MHz";
}

function rfFromRaw(raw){
  if(!raw) return {};
  const snrM = /snr:\\s*([-0-9.]+)/i.exec(raw);
  const rssiM = /rssi:\\s*([-0-9.]+)/i.exec(raw);
  const freqM = /(\\d+)\\s*MHz/i.exec(raw);
  const lenM = /len:\\s*(\\d+)/i.exec(raw);
  const snr = snrM ? Number(snrM[1]) : null;
  const rssi = rssiM ? Number(rssiM[1]) : null;
  const freq = freqM ? Number(freqM[1]) : null;
  const len = lenM ? Number(lenM[1]) : null;
  return {snr, rssi, freq, len};
}

function isAddr(s){
  if (!s) return false;
  return /^[1-9A-HJ-NP-Za-km-z]{40,80}$/.test(s);
}

const typeLabels = {
  pl: {
    beacon_tx: "Beacon TX",
    beacon_rx: "Beacon RX",
    beacon_tx_report: "Raport beaconu",
    beacon_tx_gateway: "Beacon TX (gateway)",
    beacon_next_time: "Nastepny beacon",
    witness_report: "Swiadek",
    witness_ignored: "Swiadek (ignor.)",
    error: "Blad",
    region_update: "Region",
    session_init: "Sesja",
    client_connect: "Klient",
    server_start: "Restart",
    start: "Start",
    info: "Info",
    other: "Info",
  },
  en: {
    beacon_tx: "Beacon TX",
    beacon_rx: "Beacon RX",
    beacon_tx_report: "Beacon Report",
    beacon_tx_gateway: "Beacon TX (gateway)",
    beacon_next_time: "Next beacon",
    witness_report: "Witness",
    witness_ignored: "Witness (ignored)",
    error: "Error",
    region_update: "Region",
    session_init: "Session",
    client_connect: "Client",
    server_start: "Restart",
    start: "Start",
    info: "Info",
    other: "Info",
  }
};

function typeLabel(type){
  const map = typeLabels[state.lang] || typeLabels.en;
  return map[type] || type || "-";
}

function typeIcon(type){
  if (type === "error") return "err";
  if (type === "witness_report" || type === "witness_ignored") return "wit";
  if (type === "beacon_rx") return "rx";
  if (type === "beacon_tx" || type === "beacon_tx_report" || type === "beacon_tx_gateway") return "tx";
  return "rx";
}

function typePill(type){
  if(type === "error") return "pill err";
  if(type === "witness_report") return "pill warn";
  if(type === "beacon_rx") return "pill";
  return "pill info";
}

function typeMark(type){
  if (type === "beacon_tx_report" || type === "witness_report") {
    return '<span class="mark ok">&#10003;</span><span class="mark money">$</span>';
  }
  if (type === "witness_ignored") return '<span class="mark bad">&times;</span>';
  return "";
}

function cacheKey(prefix, extra=""){
  return `cache:${prefix}:${extra}`;
}

function cacheGet(key, maxAgeMs){
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const obj = JSON.parse(raw);
    if (!obj || typeof obj.ts !== "number") return null;
    if (maxAgeMs && (Date.now() - obj.ts > maxAgeMs)) return null;
    return obj.data;
  } catch(e){
    return null;
  }
}

function cacheSet(key, data){
  try {
    localStorage.setItem(key, JSON.stringify({ ts: Date.now(), data }));
  } catch(e){}
}

function applySummary(s){
  $("mTx").textContent = s.beacons_tx || 0;
  $("mRx").textContent = s.beacons_rx || 0;
  $("mWit").textContent = s.witnesses || 0;
  $("mErr").textContent = s.errors || 0;
  $("mWitIgnored").textContent = s.witnesses_ignored || 0;
  $("sRestarts").textContent = s.restarts || 0;
  $("sRegion").textContent = s.region || "-";
  $("sNextBeacon").textContent = s.next_beacon || "-";
  $("regionChip").textContent = `Region: ${s.region || "-"}`;
  $("nextBeaconChip").textContent = `Next beacon: ${s.next_beacon || "-"}`;
  const rl = state.range === "all" ? t("allTime") : state.range;
  $("mTxSub").textContent = rl;
  $("mRxSub").textContent = rl;
  $("mWitSub").textContent = rl;
  $("mErrSub").textContent = rl;

  const rf = {
    avg_rssi: s.avg_rssi, min_rssi: s.min_rssi, max_rssi: s.max_rssi,
    avg_snr: s.avg_snr, min_snr: s.min_snr, max_snr: s.max_snr
  };
  const hasRf = rf.avg_rssi !== null || rf.avg_snr !== null || rf.min_rssi !== null || rf.max_rssi !== null;
  state.rfFromSummary = hasRf ? rf : null;
  if (hasRf) {
    applyRfStats(rf);
  } else if (state.rfFallback) {
    applyRfStats(state.rfFallback);
  } else {
    applyRfStats(rf);
  }
}
function applyRfStats(rf){
  const r = rf || {};
  $("rssiAvg").textContent = fmt(r.avg_rssi);
  $("rssiMinMax").textContent = `${fmt(r.min_rssi)} / ${fmt(r.max_rssi)}`;
  $("snrAvg").textContent = fmt(r.avg_snr);
  $("snrMinMax").textContent = `${fmt(r.min_snr)} / ${fmt(r.max_snr)}`;
}

function renderMiniChart(el, vals, color){
  const w = el.clientWidth || 200;
  const h = el.clientHeight || 70;
  el.innerHTML = "";
  const data = vals.filter(v => v !== null && v !== undefined);
  if (!data.length){
    el.innerHTML = `<div class="muted" style="padding:10px">${t("noData")}</div>`;
    return;
  }
  const minV = Math.min(...data);
  const maxV = Math.max(...data);
  const pad = 6;
  const step = (w - pad*2) / Math.max(1, vals.length-1);
  const range = (maxV - minV) || 1;
  const svg = document.createElementNS("http://www.w3.org/2000/svg","svg");
  svg.setAttribute("width", w);
  svg.setAttribute("height", h);
  let d = "";
  let started = false;
  vals.forEach((v,i)=>{
    if (v === null || v === undefined || isNaN(v)) { started = false; return; }
    const x = pad + i*step;
    const y = h - pad - ((v - minV)/range) * (h - pad*2);
    if (!started){
      d += `M ${x} ${y}`;
      started = true;
    } else {
      d += ` L ${x} ${y}`;
    }
  });
  const path = document.createElementNS(svg.namespaceURI,"path");
  path.setAttribute("d", d);
  path.setAttribute("fill","none");
  path.setAttribute("stroke", color);
  path.setAttribute("stroke-width","2");
  svg.appendChild(path);
  el.appendChild(svg);
}

function renderRfCharts(){
  const rows = (state.lastEvents || []).filter(r => r.type === "beacon_rx");
  const tail = rows.slice(0, 40).reverse();
  const rssi = tail.map(r => (r.rssi !== undefined && r.rssi !== null) ? Number(r.rssi) : null);
  const snr = tail.map(r => (r.snr !== undefined && r.snr !== null) ? Number(r.snr) : null);
  renderMiniChart($("rssiChart"), rssi, "var(--accent-2)");
  renderMiniChart($("snrChart"), snr, "var(--accent-3)");
}

async function loadSummary(){
  const params = withRangeParams(new URLSearchParams());
  const q = params.toString() ? `?${params.toString()}` : "";
  const key = cacheKey("summary", params.toString() || "all");
  const cached = cacheGet(key, 5*60*1000);
  if (cached) applySummary(cached);
  const s = await api(`/metrics/summary${q}`, 6000);
  cacheSet(key, s);
  applySummary(s);
}

function renderChart(rows){
  const el = $("chart");
  const w = el.clientWidth, h = el.clientHeight;
  el.innerHTML = "";
  if(!rows || rows.length === 0){
    el.innerHTML = `<div class="muted" style="padding:14px">${t("noData")}</div>`;
    return;
  }
  const series = {
    tx: rows.map(r=>r.tx||0),
    rx: rows.map(r=>r.rx||0),
    wit: rows.map(r=>r.wit||0),
    err: rows.map(r=>r.err||0),
  };
  const maxVal = Math.max(1, ...Object.values(series).flat());
  const pad = 16;
  const step = (w - pad*2) / Math.max(1, rows.length-1);

  function points(vals){
    return vals.map((v,i)=>{
      const x = pad + i*step;
      const y = h - pad - (v/maxVal)*(h - pad*2);
      return `${x},${y}`;
    }).join(" ");
  }

  const svg = document.createElementNS("http://www.w3.org/2000/svg","svg");
  svg.setAttribute("width", w);
  svg.setAttribute("height", h);

  // grid
  for(let i=1;i<=4;i++){
    const y = pad + (i/5) * (h - pad*2);
    const gl = document.createElementNS(svg.namespaceURI,"line");
    gl.setAttribute("x1", pad);
    gl.setAttribute("x2", w - pad);
    gl.setAttribute("y1", y);
    gl.setAttribute("y2", y);
    gl.setAttribute("stroke", "rgba(148,163,184,0.15)");
    gl.setAttribute("stroke-width", "1");
    svg.appendChild(gl);
  }

  const lines = [
    {key:"tx", color:"var(--accent-2)"},
    {key:"rx", color:"var(--accent)"},
    {key:"wit", color:"var(--accent-3)"},
    {key:"err", color:"var(--danger)"},
  ];
  lines.forEach(l=>{
    const pl = document.createElementNS(svg.namespaceURI,"polyline");
    pl.setAttribute("fill","none");
    pl.setAttribute("stroke", l.color);
    pl.setAttribute("stroke-width","2");
    pl.setAttribute("points", points(series[l.key]));
    svg.appendChild(pl);
    // points
    series[l.key].forEach((v,i)=>{
      const x = pad + i*step;
      const y = h - pad - (v/maxVal)*(h - pad*2);
      const c = document.createElementNS(svg.namespaceURI,"circle");
      c.setAttribute("cx", x);
      c.setAttribute("cy", y);
      c.setAttribute("r", "2.5");
      c.setAttribute("fill", l.color);
      svg.appendChild(c);
    });
  });
  el.appendChild(svg);
}

async function loadChart(){
  const params = withRangeParams(new URLSearchParams());
  const q = params.toString() ? `?${params.toString()}` : "";
  const key = cacheKey("chart", params.toString() || "all");
  const cached = cacheGet(key, 10*60*1000);
  if (cached) renderChart(cached);
  let rows = await api(`/chart/daily${q}`, 6000);
  if ((!rows || rows.length === 0) && state.lastEvents && state.lastEvents.length){
    const map = {};
    state.lastEvents.forEach(e=>{
      if (!e.ts) return;
      const day = e.ts.slice(0,10);
      if (!map[day]) map[day] = {day, tx:0, rx:0, wit:0, err:0};
      if (e.type === "beacon_tx" || e.type === "beacon_tx_report" || e.type === "beacon_tx_gateway") map[day].tx++;
      else if (e.type === "beacon_rx") map[day].rx++;
      else if (e.type === "witness_report") map[day].wit++;
      else if (e.type === "error") map[day].err++;
    });
    rows = Object.values(map).sort((a,b)=>a.day.localeCompare(b.day));
  }
  cacheSet(key, rows);
  renderChart(rows);
}

function renderEvents(data){
  const tbody = $("eventsBody");
  tbody.innerHTML = "";
  const techTypes = new Set(["info","start","session_init","client_connect","region_update","beacon_next_time","server_start"]);
  const rows = data.rows.filter(r=>{
    if (!state.showErrors && r.type === "error") return false;
    if (!state.showTech && techTypes.has(r.type)) return false;
    return true;
  });
  rows.forEach(r=>{
    if (r.raw && (r.rssi == null || r.snr == null || r.freq == null || r.len == null)){
      const rf = rfFromRaw(r.raw);
      if (r.rssi == null && rf.rssi != null) r.rssi = rf.rssi;
      if (r.snr == null && rf.snr != null) r.snr = rf.snr;
      if (r.freq == null && rf.freq != null) r.freq = rf.freq;
      if (r.len == null && rf.len != null) r.len = rf.len;
    }
  });
  state.lastEvents = rows;

  const valsRssi = [];
  const valsSnr = [];
  rows.forEach(r=>{
    if (r.rssi != null) valsRssi.push(Number(r.rssi));
    if (r.snr != null) valsSnr.push(Number(r.snr));
  });
  if (valsRssi.length || valsSnr.length){
    const avg = (v) => v.length ? v.reduce((a,b)=>a+b,0)/v.length : null;
    state.rfFallback = {
      avg_rssi: avg(valsRssi),
      min_rssi: valsRssi.length ? Math.min(...valsRssi) : null,
      max_rssi: valsRssi.length ? Math.max(...valsRssi) : null,
      avg_snr:  avg(valsSnr),
      min_snr:  valsSnr.length ? Math.min(...valsSnr) : null,
      max_snr:  valsSnr.length ? Math.max(...valsSnr) : null,
    };
    if (!state.rfFromSummary){
      applyRfStats(state.rfFallback);
    }
  }
  renderRfCharts();

  rows.forEach(r=>{
    const alias = r.mac && state.devices[r.mac] ? state.devices[r.mac] : "";
    const macLine = r.mac || "-";
    const aliasLine = alias ? `<div class="dev-alias">${alias}</div>` : "";
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="col-time">${fmtTs(r.ts)}</td>
      <td class="col-type"><span class="${typePill(r.type)}"><span class="ico ${typeIcon(r.type)}"></span>${typeLabel(r.type)}${typeMark(r.type)}</span></td>
      <td class="col-dev"><div>${macLine}</div>${aliasLine}</td>
      <td class="col-id trunc">${r.beacon_id || "-"}</td>
      <td class="col-rf">
        <div class="rf">
          <span>RSSI: <b>${r.rssi ?? "-"}</b></span>
          <span>SNR: <b>${r.snr ?? "-"}</b></span>
          <span>F: <b>${fmtFreq(r.freq)}</b></span>
          <span>L: <b>${r.len ?? "-"}</b></span>
        </div>
      </td>
    `;
    tr.addEventListener("click", ()=>{
      $("eventDetail").textContent = r.raw || "-";
    });
    tbody.appendChild(tr);
  });
  if (!rows.length){
    tbody.innerHTML = `<tr><td colspan="5" class="muted">${t("noData")}</td></tr>`;
  }
}

async function loadEvents(){
  const params = withRangeParams(new URLSearchParams());
  if (state.type) params.set("type", state.type);
  if (state.mac) params.set("mac", state.mac);
  params.set("limit", "60");
  const key = cacheKey("events", params.toString());
  const cached = cacheGet(key, 5*60*1000);
  if (cached) renderEvents(cached);
  const data = await api(`/events?${params.toString()}`, 8000);
  cacheSet(key, data);
  renderEvents(data);
}

function renderBeacons(rows){
  rows = (rows || []).filter(r => r && r.beacon_id && String(r.beacon_id).length >= 16);
  const tbody = $("beaconsBody");
  tbody.innerHTML = "";
  rows.slice(0,30).forEach(r=>{
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="col-id trunc">${r.beacon_id || "-"}</td>
      <td class="col-time">${fmtTs(r.first_seen)}</td>
      <td class="col-mini">${r.tx || 0}</td>
      <td class="col-mini">${r.rx || 0}</td>
      <td class="col-mini">${r.witnesses || 0}</td>
    `;
    tr.addEventListener("click", async ()=>{
      const detail = await api(`/beacon/${encodeURIComponent(r.beacon_id)}`);
      const techTypes = new Set(["info","start","session_init","client_connect","region_update","beacon_next_time","server_start"]);
      const filtered = detail.filter(d=>!techTypes.has(d.type));
      const use = filtered.length ? filtered : detail;
      const counts = {};
      use.forEach(d=>{ counts[d.type] = (counts[d.type] || 0) + 1; });
      const summary = Object.keys(counts).map(k=>`${typeLabel(k)}:${counts[k]}`).join(", ");
      const lines = use.map(d=>{
        const rf = rfFromRaw(d.raw || "");
        const rfStr = (rf.rssi != null || rf.snr != null || rf.freq != null || rf.len != null)
          ? ` | RSSI:${rf.rssi ?? "-"} SNR:${rf.snr ?? "-"} F:${fmtFreq(rf.freq)} L:${rf.len ?? "-"}`
          : "";
        return `${fmtTs(d.ts)}  ${typeLabel(d.type)}${rfStr}`;
      }).join("\n");
      $("beaconDetail").textContent = `${t("beaconDetail")} (${use.length})\n${summary || t("noData")}\n---\n${lines || "-"}`;
    });
    tbody.appendChild(tr);
  });
  $("beaconHint").textContent = rows.length ? `${rows.length} beacons` : t("noData");
}

async function loadBeacons(){
  const params = withRangeParams(new URLSearchParams());
  const q = params.toString() ? `?${params.toString()}` : "";
  const key = cacheKey("beacons", params.toString() || "all");
  const cached = cacheGet(key, 10*60*1000);
  if (cached) renderBeacons(cached);
  const rows = await api(`/beacons${q}`, 6000);
  cacheSet(key, rows);
  renderBeacons(rows);
}

async function loadHotspot(manual){
  const addr = $("hotspotAddr").value.trim();
  const err = $("hotspotErr");
  const btn = $("hotspotBtn");
  const walletCard = $("hotspotWalletCard");
  if (!addr){
    err.textContent = "";
    $("hotspotStatus").textContent = "-";
    return;
  }
  state.hotspotAddr = addr;
  localStorage.setItem("hotspotAddr", addr);
  if (manual) {
    state.hotspotManual = true;
    localStorage.setItem("hotspotAddrManual", "1");
  }
  $("hotspotAddress").textContent = addr;
  if (state.localWallet){
    $("hotspotWallet").textContent = state.localWallet;
    walletCard.style.display = "block";
  } else {
    walletCard.style.display = "none";
  }
  err.textContent = "";
  btn.disabled = true;
  btn.textContent = t("hotspotRefresh") + "...";
  $("hotspotExplorer").href = "https://explorer.helium.com/hotspots/" + addr;
  $("hotspotTracker").href = "https://heliumtracker.io/hotspots/" + addr;

  try {
    let d = null;
    try {
      d = await api(`/hotspot?addr=${encodeURIComponent(addr)}`);
    } catch(e){
      // fallback: try direct Entity API from the browser (PC may have internet)
      const res = await fetch(`https://entities.nft.helium.io/${encodeURIComponent(addr)}`);
      if (!res.ok) throw e;
      d = await res.json();
    }
    if (d && d.error) {
      throw new Error(d.message || d.error);
    }
    const attrs = d.attributes || [];
    const attr = (k) => {
      const a = attrs.find(x => x.trait_type === k);
      return a ? a.value : null;
    };
    const iot = (d.hotspot_infos && d.hotspot_infos.iot) ? d.hotspot_infos.iot : null;

    const nameStr = d.name || d.entity_key_str || attr("entity_key_string") || addr.slice(0,16) + "...";
    $("hotspotName").textContent = nameStr;

    const city = attr("iot_city") || (iot && iot.city) || "-";
    const regionState = attr("iot_state") || "";
    const country = attr("iot_country") || "";
    $("hotspotCity").textContent = city;
    $("hotspotCountry").textContent = (regionState ? regionState + ", " : "") + (country || "-");

    const gain = iot && iot.gain != null ? (iot.gain / 10).toFixed(1) : "-";
    const elev = iot && iot.elevation != null ? iot.elevation : "-";
    $("hotspotGain").textContent = gain;
    $("hotspotElev").textContent = elev;

    const networks = attr("networks");
    $("hotspotNetworks").textContent = Array.isArray(networks) ? networks.join(", ") : (networks || "IoT");

    const rewardable = attr("rewardable");
    const isRewardable = rewardable === true || rewardable === "true";
    const statusEl = $("hotspotStatus");
    statusEl.innerHTML = "";
    const badge = document.createElement("span");
    if (isRewardable === true){
      badge.className = "pill info";
      badge.innerHTML = `<span class="status-dot ok"></span>${t("statusActive")}`;
      $("hotspotRewardable").textContent = t("yes");
    } else if (isRewardable === false || rewardable === "false"){
      badge.className = "pill err";
      badge.innerHTML = `<span class="status-dot bad"></span>${t("statusInactive")}`;
      $("hotspotRewardable").textContent = t("no");
    } else {
      badge.className = "pill warn";
      badge.innerHTML = `<span class="status-dot"></span>${t("statusUnknown")}`;
      $("hotspotRewardable").textContent = "-";
    }
    statusEl.appendChild(badge);

    const chips = $("hotspotChips");
    chips.innerHTML = "";
    const fields = [
      ["asset_id", d.asset_id],
      ["key_to_asset", d.key_to_asset_key],
      ["wallet", state.localWallet || null],
      ["lat", iot && iot.lat != null ? iot.lat.toFixed(4) : null],
      ["lon", iot && iot.long != null ? iot.long.toFixed(4) : null],
      ["created_at", iot && iot.created_at ? iot.created_at.slice(0,10) : null],
    ];
    fields.forEach(([k,v])=>{
      if (!v) return;
      const c = document.createElement("div");
      c.className = "info-chip";
      c.innerHTML = `<span>${k}:</span> ${v}`;
      chips.appendChild(c);
    });
    if (!chips.children.length){
      chips.textContent = t("noData");
    }

    $("hotspotUpdated").textContent = `${t("lastUpdate")}: ${new Date().toLocaleString()}`;
  } catch (e){
    err.textContent = "Blad: " + e.message;
  } finally {
    btn.disabled = false;
    btn.textContent = t("hotspotRefresh");
  }
}

async function loadDevices(){
  state.devices = await api("/devices");
  state.macs = await api("/macs");
  if (state.localName && state.macs.length > 0) {
    const mac = state.macs[0];
    if (!state.devices[mac]) {
      state.devices[mac] = state.localName;
      await fetch(apiBase + "/devices", {
        method:"POST",
        headers:{ "Content-Type":"application/json" },
        body: JSON.stringify(state.devices)
      });
    }
  }
  const macSel = $("macSelect");
  if (macSel) {
    macSel.innerHTML = `<option value="">${t("allDevices")}</option>`;
    state.macs.forEach(mac=>{
      const opt = document.createElement("option");
      const alias = state.devices[mac] ? ` (${state.devices[mac]})` : "";
      opt.value = mac;
      opt.textContent = `${mac}${alias}`;
      macSel.appendChild(opt);
    });
    macSel.value = state.mac || "";
  }
  const list = $("devicesList");
  list.innerHTML = "";
  state.macs.forEach(mac=>{
    const row = document.createElement("div");
    row.className = "device-row";
    row.innerHTML = `
      <div class="dev-mac">${mac}</div>
      <input data-mac="${mac}" placeholder="Alias" value="${state.devices[mac] || ""}">
    `;
    list.appendChild(row);
  });
  if(state.macs.length === 0){
    list.innerHTML = `<div class="muted">${t("noData")}</div>`;
  }
}

async function saveDevices(){
  const inputs = document.querySelectorAll("#devicesList input[data-mac]");
  const map = {};
  inputs.forEach(i=>{
    const v = i.value.trim();
    if(v) map[i.dataset.mac] = v;
  });
  await fetch(apiBase + "/devices", {
    method:"POST",
    headers:{ "Content-Type":"application/json" },
    body: JSON.stringify(map)
  });
  state.devices = map;
  await loadEvents();
}

async function loadLocalInfo(){
  try {
    const host = isPrivateHost(location.hostname) ? location.hostname : "127.0.0.1";
    const d = await api(`/local/info?host=${encodeURIComponent(host)}`);
    const autoAddr = d.gateway_key || d.address;
    if (isAddr(autoAddr)) {
      state.hotspotAddr = autoAddr;
      state.hotspotManual = false;
      localStorage.setItem("hotspotAddr", autoAddr);
      localStorage.setItem("hotspotAddrManual", "0");
      $("hotspotAddr").value = autoAddr;
      $("hotspotAddress").textContent = autoAddr;
    } else if (isAddr(DEFAULT_ADDR)) {
      state.hotspotAddr = DEFAULT_ADDR;
      state.hotspotManual = false;
      localStorage.setItem("hotspotAddr", DEFAULT_ADDR);
      localStorage.setItem("hotspotAddrManual", "0");
      $("hotspotAddr").value = DEFAULT_ADDR;
      $("hotspotAddress").textContent = DEFAULT_ADDR;
    } else {
      $("hotspotAddr").value = state.hotspotAddr;
      $("hotspotAddress").textContent = state.hotspotAddr;
    }
    if (d.wallet) {
      state.localWallet = d.wallet;
      $("hotspotWallet").textContent = d.wallet;
      $("hotspotWalletCard").style.display = "block";
    } else {
      $("hotspotWalletCard").style.display = "none";
    }
    if (d.name) {
      state.localName = d.name;
      $("hotspotName").textContent = d.name;
    }
  } catch (e) {
    // ignore
  }
}

async function refreshAll(){
  $("eventDetail").textContent = "-";
  $("beaconDetail").textContent = "-";
  const safe = async (fn) => {
    try { await fn(); return true; } catch(e){ return false; }
  };
  await loadLocalInfo();
  const results = await Promise.all([
    safe(loadDevices),
    safe(loadSummary),
    safe(loadChart),
    safe(loadEvents),
    safe(loadBeacons),
  ]);
  const okSummary = results[1];
  const okEvents = results[3];
  const ok = okSummary || okEvents;
  $("lastUpdate").textContent = `${t("lastUpdate")}: ${new Date().toLocaleString()}`;
  $("statusLine").innerHTML = ok
    ? `<span class="status-dot ok"></span>${t("updated")}: ${new Date().toLocaleString()}`
    : `<span class="status-dot bad"></span>${t("apiOffline")}`;
}

window.addEventListener("resize", ()=>{
  try { renderRfCharts(); } catch(e){}
});

document.getElementById("langSelect").addEventListener("change", e=>{
  state.lang = e.target.value;
  setLang();
});

document.getElementById("themeToggle").addEventListener("click", ()=>{
  state.theme = state.theme === "dark" ? "light" : "dark";
  setTheme();
});

document.getElementById("rangeSelect").addEventListener("change", e=>{
  state.range = e.target.value;
  setRange();
  refreshAll();
});

document.getElementById("typeSelect").addEventListener("change", e=>{
  state.type = e.target.value;
  refreshAll();
});

document.getElementById("macSelect").addEventListener("change", e=>{
  state.mac = e.target.value;
  refreshAll();
});

document.getElementById("showTech").addEventListener("change", e=>{
  state.showTech = e.target.checked;
  setFilters();
  refreshAll();
});

document.getElementById("showErrors").addEventListener("change", e=>{
  state.showErrors = e.target.checked;
  setFilters();
  refreshAll();
});

document.getElementById("refreshBtn").addEventListener("click", refreshAll);
document.getElementById("logoutBtn").addEventListener("click", ()=>{
  const url = "/logout?ts=" + Date.now();
  fetch(url, { method:"GET", cache:"no-store" }).finally(()=>{
    window.location.href = url;
  });
});

document.getElementById("apiBaseInput").value = apiBase;
document.getElementById("apiBaseSave").addEventListener("click", async ()=>{
  const v = document.getElementById("apiBaseInput").value.trim();
  if(v){
    apiBase = v;
    localStorage.setItem("apiBase", v);
  }
  await saveDevices();
  await loadDevices();
  refreshAll();
});

setTheme();
setLang();
setRange();
setFilters();
document.getElementById("hotspotBtn").addEventListener("click", () => loadHotspot(true));
loadLocalInfo().then(() => loadHotspot(false));
refreshAll();
setInterval(refreshAll, 60000);
</script>
</body>
</html>
HTMLEOF
}

print_ips() {
  echo
  section "$(t done_install)"
  echo -e "${BLUE}$(t ip_header)${RESET}"
  local IPS
  IPS=$(detect_ips)
  if [[ -z "$IPS" ]]; then
    echo "  - http://<your-device-ip>:1111"
  else
    while read -r ip; do
      [[ -n "$ip" ]] && printf "$(t ip_line)\n" "$ip"
    done <<< "$IPS"
  fi
  echo
  echo -e "${DIM}$(t note_firewall)${RESET}"
}

curl_check() {
  if command -v curl >/dev/null 2>&1; then
    section "$(t curl_check)"
    if [[ -n "${AUTH_USER}" ]]; then
      if curl -sSf -u "${AUTH_USER}:${AUTH_PASS}" http://127.0.0.1:1111 >/dev/null 2>&1; then
        ok "$(t curl_ok)"
      else
        warn "$(t curl_fail)"
      fi
      return
    fi
    if curl -sSf http://127.0.0.1:1111 >/dev/null 2>&1; then
      ok "$(t curl_ok)"
    else
      warn "$(t curl_fail)"
    fi
  fi
}

do_install() {
  local REAL_LOG_PATH
  REAL_LOG_PATH=$(detect_log_source)
  if [[ ! -f "$REAL_LOG_PATH" ]]; then
    err "$(t log_missing)"
    err "Log source not found: $REAL_LOG_PATH"
    exit 1
  fi
  if [[ -z "$AUTH_USER" ]]; then
    read -rp "$(t auth_user) " AUTH_USER
  fi
  if [[ -n "$AUTH_USER" && -z "$AUTH_PASS" ]]; then
    read -rsp "$(t auth_pass) " AUTH_PASS
    echo
  fi
  if [[ -n "$AUTH_USER" && -z "$AUTH_PASS" ]]; then
    err "$(t auth_empty)"
    exit 1
  fi

  section "$(t installing)"
  mkdir -p "$BASE_DIR"
  create_files

  section "$(t building_images)"
  docker build -t "$IMG_PARSER" "$BASE_DIR/parser"
  docker build -t "$IMG_API" "$BASE_DIR/api"
  docker build -t "$IMG_UI" "$BASE_DIR/ui"

  if ! docker volume ls --format '{{.Name}}' | grep -q "^${VOL_DB}$"; then
    docker volume create "$VOL_DB" >/dev/null
  fi

  section "$(t starting_stack)"
  if ! docker network ls --format '{{.Name}}' | grep -q "^${NET_NAME}$"; then
    docker network create "$NET_NAME" >/dev/null
  fi
  docker rm -f "$CTR_PARSER" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CTR_PARSER" \
    --restart unless-stopped \
    -v "$REAL_LOG_PATH":/logs/console.log:ro \
    -v "$VOL_DB":/data \
    "$IMG_PARSER"

  docker rm -f "$CTR_API" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CTR_API" \
    --restart unless-stopped \
    --network "$NET_NAME" \
    -p 8000:8000 \
    -v "$VOL_DB":/data \
    "$IMG_API"

  docker rm -f "$CTR_UI" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CTR_UI" \
    --restart unless-stopped \
    --network "$NET_NAME" \
    -p 1111:1111 \
    "$IMG_UI"

  ok "Dashboard started."
  curl_check
  print_ips
}

do_uninstall() {
  section "$(t uninstalling)"
  read -rp "$(t confirm_uninstall) " ans
  case "$ans" in
    y|Y|yes|YES)
      section "$(t stopping_stack)"
      docker rm -f "$CTR_UI" "$CTR_API" "$CTR_PARSER" >/dev/null 2>&1 || true
      docker volume rm "$VOL_DB" >/dev/null 2>&1 || true
      section "$(t removing_dir)"
      rm -rf "$BASE_DIR"
      ok "$(t done_uninstall)"
      ;;
    *)
      warn "$(t cancelled)"
      ;;
  esac
}

# ---- guards ----
if [[ "$EUID" -ne 0 ]]; then err "$(t require_root)"; exit 1; fi
if ! command -v docker >/dev/null 2>&1; then err "$(t docker_missing)"; exit 1; fi

clear
banner "$(t welcome)"
echo
read -rp "$(t choose_lang) " LANG_IN
case "$LANG_IN" in
  pl|PL) LANG_CHOICE="pl" ;;
  en|EN|"") LANG_CHOICE="en" ;;
  *) warn "$(t invalid_lang)"; LANG_CHOICE="en" ;;
esac

section "$(t menu)"
read -rp ">> " choice
case "$choice" in
  1) do_install ;;
  2) do_uninstall ;;
  3|"") exit 0 ;;
  *) err "$(t invalid_choice)"; exit 1 ;;
esac

