# IIS Discovery – All Sites

A **read-only**, production-safe PowerShell toolkit for discovering IIS configuration across a Windows server.
It produces a **clean, boss-friendly report** covering sites, applications, virtual directories, endpoints,
config files, and **masked** connection strings.

---

## Repository structure

```text
iis-discovery/
├─ README.md
├─ Scripts/
│  └─ AllSites/
│     ├─ Get-IIS-Inventory-Compat.ps1
│     ├─ Discover-IIS-Dependencies-CLEAN.ps1
│     └─ Clean-IIS-Discovery-DedupAndCompactRoot.ps1
```

---

## Folder structure on target IIS server

```text
C:\IISDiscovery\
├─ Scripts\
│  └─ AllSites\
│     ├─ Get-IIS-Inventory-Compat.ps1
│     ├─ Discover-IIS-Dependencies-CLEAN.ps1
│     └─ Clean-IIS-Discovery-DedupAndCompactRoot.ps1
└─ Reports\
   ├─ IIS_Sites_Apps_VDirs.csv
   ├─ IIS_Discovery_AllSites_CLEAN.csv
   └─ IIS_Discovery_AllSites_DEDUP_COMPACTROOT.csv
```

---

## What this tool does

- Discovers **IIS Sites, Applications, and Virtual Directories**
- Collects **bindings and endpoints** (protocol, host header, port)
- Scans application folders for **config files**
  - `web.config`, `*.config`, `*.settings`
  - `appsettings*.json`, `*config*.json`
- Extracts **connection strings** (passwords masked)
- Produces a **final compact report** with one root row per site

> Safe by design: scripts are **read-only** and do **not** modify IIS or files.

---

## Output location

All output is written to:

```
C:\IISDiscovery\Reports\
```

**File to share:**
```
IIS_Discovery_AllSites_DEDUP_COMPACTROOT.csv
```

---

## Prerequisites

- Windows Server with IIS
- PowerShell 5.1
- Read access to IIS application folders

---

## Folder setup on target server

```powershell
New-Item -ItemType Directory -Force -Path "C:\IISDiscovery\Scripts\AllSites"
New-Item -ItemType Directory -Force -Path "C:\IISDiscovery\Reports"
```

Copy scripts from the repository:

```
iis-discovery\Scripts\AllSites\*.ps1
```
to:
```
C:\IISDiscovery\Scripts\AllSites\
```

---

## How to run (in order)

### 1) Inventory

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IISDiscovery\Scripts\AllSites\Get-IIS-Inventory-Compat.ps1"
```

### 2) Dependency discovery

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IISDiscovery\Scripts\AllSites\Discover-IIS-Dependencies-CLEAN.ps1"
```

### 3) Deduplicate and compact root rows

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IISDiscovery\Scripts\AllSites\Clean-IIS-Discovery-DedupAndCompactRoot.ps1" `
-InputCsv  "C:\IISDiscovery\Reports\IIS_Discovery_AllSites_CLEAN.csv" `
-OutputCsv "C:\IISDiscovery\Reports\IIS_Discovery_AllSites_DEDUP_COMPACTROOT.csv"
```

---

## Notes

- Close Excel before rerunning scripts (CSV files are locked)
- Connection string passwords are masked
- Large applications may take longer to scan

---

## Ownership

Maintainer: **Mehrshad Arshi (DevOps)**
