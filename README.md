# HMD — Helium Miner Dashboards

Lightweight, self-hosted dashboards for Helium miners on different vendors.
This repository will grow with dashboards for other devices (e.g. SenseCap).

[English](#english) | [Polski](#polski)

## Contents
- `heltec/helium-dashboard.sh` — Heltec Indoor Hotspot dashboard (HT-M2808 + HT-M01S Rev.2.0 radio, or without external radio)
- `img/` — screenshots used in README

---

<a id="english"></a>
# English

## Heltec Indoor Hotspot Dashboard
Target device:
- **HT-M2808 Indoor Hotspot for Helium**
- **HT-M01S Indoor LoRa Gateway (Rev.2.0)** or without external radio

This dashboard is the **Heltec-specific** implementation inside the multi-vendor HMD repository.

### Prerequisites
- **Root access** is required to install and manage the dashboard on Heltec.
- How to obtain root on Heltec:
  - https://github.com/hattimon/miner_watchdog/blob/main/linki.md
- Related Heltec helper script (watchdog):
  - https://github.com/hattimon/miner_watchdog

### Install on Heltec (from this repo)
```bash
sudo -i
curl -fsSL https://raw.githubusercontent.com/hattimon/HMD/main/heltec/helium-dashboard.sh -o /opt/helium-dashboard.sh
chmod +x /opt/helium-dashboard.sh
/opt/helium-dashboard.sh
```

### Screenshots
![Install (EN)](img/install.png)
![Panel (EN)](img/panel.png)

---

<a id="polski"></a>
# Polski

## Dashboard dla Heltec Indoor Hotspot
Urz¹dzenie docelowe:
- **HT-M2808 Indoor Hotspot for Helium**
- **HT-M01S Indoor LoRa Gateway (Rev.2.0)** lub bez zewnêtrznego radia

To jest **wersja Heltec** w repozytorium HMD (docelowo dla wielu producentów).

### Wymagania
- **Wymagane jest konto root** do instalacji i zarz¹dzania dashboardem.
- Jak uzyskaæ root na Heltecu:
  - https://github.com/hattimon/miner_watchdog/blob/main/linki.md
- Powi¹zany skrypt (watchdog) dla Helteca:
  - https://github.com/hattimon/miner_watchdog

### Instalacja na Heltecu (z tego repozytorium)
```bash
sudo -i
curl -fsSL https://raw.githubusercontent.com/hattimon/HMD/main/heltec/helium-dashboard.sh -o /opt/helium-dashboard.sh
chmod +x /opt/helium-dashboard.sh
/opt/helium-dashboard.sh
```

### Zrzuty ekranu
![Instalacja (PL)](img/install_pl.png)
![Panel (PL)](img/panel_pl.png)
