# 🔗 Intégrations et APIs Novastream

Ce document détaille toutes les connexions et intégrations entre les services du système Novastream.

## 🌐 Vue d'Ensemble des Connexions

```
┌─────────────┐    API     ┌─────────────┐    API     ┌─────────────┐
│ Jellyseerr  │◄──────────▶│   Radarr    │◄──────────▶│  Prowlarr   │
│             │            │   Sonarr    │            │             │
└─────────────┘            └─────────────┘            └─────────────┘
      │                           │                           │
      │ API                       │ API                       │ 
      ▼                           ▼                           ▼
┌─────────────┐            ┌─────────────┐            ┌─────────────┐
│   Jellyfin  │            │   SABnzbd   │            │ Indexeurs   │
│             │            │             │            │   Usenet    │
└─────────────┘            └─────────────┘            └─────────────┘
      │                           │
      │ Webhook                   │ Webhook
      ▼                           ▼
┌─────────────┐            ┌─────────────┐
│  Notifiarr  │            │   Discord   │
│             │            │   Webhooks  │
└─────────────┘            └─────────────┘
```

## 🔧 Configuration APIs par Service

### Jellyseerr - Hub Central des Demandes

**Endpoints Intégrés** :
```
Jellyfin API:
- URL: http://jellyfin:8096
- Auth: API Key + Username/Password  
- Functions: Library sync, user auth, metadata

Radarr API:
- URL: http://radarr:7878
- Auth: API Key (X-Api-Key header)
- Functions: Movie requests, status, quality profiles

Sonarr API: 
- URL: http://sonarr:8989
- Auth: API Key (X-Api-Key header)
- Functions: TV requests, season tracking, episodes
```

**Configuration Jellyseerr** :
```json
{
  "jellyfin": {
    "name": "Jellyfin",
    "hostname": "jellyfin",
    "port": 8096,
    "ssl": false,
    "apiKey": "JELLYFIN_API_KEY",
    "libraryUpdateInterval": 12
  },
  "radarr": [
    {
      "name": "Radarr",
      "hostname": "radarr", 
      "port": 7878,
      "ssl": false,
      "apiKey": "RADARR_API_KEY",
      "rootFolder": "/data/media/movies",
      "qualityProfileId": 4,
      "minimumAvailability": "released",
      "tags": []
    }
  ],
  "sonarr": [
    {
      "name": "Sonarr",
      "hostname": "sonarr",
      "port": 8989, 
      "ssl": false,
      "apiKey": "SONARR_API_KEY",
      "rootFolder": "/data/media/tv",
      "qualityProfileId": 1,
      "languageProfileId": 1,
      "tags": []
    }
  ]
}
```

### Radarr - Orchestrateur Films

**APIs Consommées** :
```
Prowlarr Indexer Sync:
- URL: http://prowlarr:9696/api/v1/indexer
- Auth: API Key
- Function: Sync automatic des indexeurs configurés

SABnzbd Download Client:
- URL: http://sabnzbd:8080/api
- Auth: API Key  
- Function: Envoi .nzb, monitoring téléchargements

TheMovieDB Metadata:
- URL: https://api.themoviedb.org/3/
- Auth: API Key public
- Function: Métadonnées films, posters, casting

Jellyfin Connect (Webhook):
- URL: http://jellyfin:8096/api_key/[KEY]/Library/Refresh
- Function: Trigger scan après import
```

**Webhooks Émis** :
```
On Import - Notifiarr:
POST http://notifiarr:5454/api/v1/notification/radarr
{
  "eventType": "Download", 
  "movie": {
    "title": "Film Title (2023)",
    "quality": "WebDL-1080p",
    "size": "8.5 GB",
    "path": "/data/media/movies/Film (2023) [tmdbid-123456]"
  }
}

On Import - Custom Discord:
POST https://discord.com/api/webhooks/[WEBHOOK-ID]
{
  "content": "🎬 **Nouveau Film Disponible**\\n**Film**: Film Title (2023)\\n**Qualité**: 1080p WebDL",
  "embeds": [{
    "title": "Film Title (2023)",
    "color": 3447003,
    "image": {"url": "poster_url"},
    "fields": [
      {"name": "Qualité", "value": "1080p", "inline": true},
      {"name": "Taille", "value": "8.5 GB", "inline": true}
    ]
  }]
}
```

### Sonarr - Orchestrateur Séries

**APIs Similaires à Radarr** avec spécificités TV :
```
TheTVDB Metadata:
- URL: https://api.thetvdb.com/
- Auth: JWT Token
- Function: Métadonnées séries, épisodes, calendrier

Calendar Tracking:
- Function: Suivi automatique nouvelles saisons
- Trigger: Recherche automatique nouveaux épisodes
- Webhook: Notification épisode disponible
```

### Prowlarr - Gestionnaire Indexeurs

**Indexeurs Configurés** :
```yaml
Public Indexeurs:
  - NZBgeek Public
  - NZBindex  
  - Binsearch
  - NewzNab generic sites

Private Indexeurs (si configurés):
  - DogNZB
  - NZBgeek VIP
  - NZBPlanet
  - 6box

Configuration par Indexeur:
  - URL: https://indexer.domain.com/
  - API Key: Individual keys
  - Categories: Movies (2000), TV (5000), etc.
  - Search Capabilities: Search, TV Search, Movie Search
  - Rate Limits: Per indexer settings
```

**Sync Apps Configuration** :
```json
{
  "applications": [
    {
      "name": "Radarr",
      "syncLevel": "fullSync", 
      "baseUrl": "http://radarr:7878",
      "apiKey": "RADARR_API_KEY",
      "syncCategories": ["Movies", "Movies/Foreign", "Movies/Other"],
      "syncTags": ["1080p", "webdl", "bluray"]
    },
    {
      "name": "Sonarr",
      "syncLevel": "fullSync",
      "baseUrl": "http://sonarr:8989", 
      "apiKey": "SONARR_API_KEY",
      "syncCategories": ["TV", "TV/Foreign", "TV/Anime"],
      "syncTags": ["1080p", "hdtv", "webdl"]
    }
  ]
}
```

### SABnzbd - Client Téléchargement

**APIs Exposées** :
```
Status API:
GET http://sabnzbd:8080/api?mode=queue&apikey=API_KEY
Response: Current download queue, speeds, ETA

History API:  
GET http://sabnzbd:8080/api?mode=history&apikey=API_KEY
Response: Completed downloads, post-processing status

Add NZB API:
POST http://sabnzbd:8080/api
Form Data:
  - mode: addurl
  - apikey: API_KEY
  - nzburl: http://indexer.com/download.nzb
  - cat: movies/tv
  - priority: 0 (Normal) | 1 (High) | -1 (Low)
```

**Configuration Catégories** :
```
Categories:
  movies:
    - dir: /data/usenet/complete/movies
    - script: None
    - priority: 0
    - pp: 3 (Repair + Unpack + Delete)
    
  tv:
    - dir: /data/usenet/complete/tv
    - script: None 
    - priority: 0
    - pp: 3 (Repair + Unpack + Delete)
    
  anime:
    - dir: /data/usenet/complete/anime
    - script: None
    - priority: 1
    - pp: 3
```

**Post-Processing Scripts** :
```bash
#!/bin/bash
# Custom post-processing script
# Variables disponibles : $1 (directory), $2 (nzb name), $3 (clean name), etc.

SAB_FINAL_DIR="$1"
SAB_FILENAME="$2" 
SAB_CAT="$5"
SAB_PP_STATUS="$7"

# Log du traitement
echo "[$(date)] Post-processing: $SAB_FILENAME in $SAB_FINAL_DIR" >> /config/logs/custom_pp.log

# Notifications custom si requis
if [ "$SAB_PP_STATUS" = "0" ]; then
    # Success - notify Radarr/Sonarr via webhook
    curl -X POST "http://radarr:7878/api/v3/command" \
         -H "X-Api-Key: $RADARR_API_KEY" \
         -d '{"name": "DownloadedMoviesScan", "path": "'$SAB_FINAL_DIR'"}'
fi
```

### Jellyfin - Media Server

**APIs Exposées** :
```
Library API:
GET /api_key/[KEY]/Library/VirtualFolders
Response: Configured libraries (Movies, TV, etc.)

Items API:  
GET /api_key/[KEY]/Users/{userId}/Items
Response: Media items with metadata

Sessions API:
GET /api_key/[KEY]/Sessions  
Response: Active streaming sessions, transcoding status

System API:
POST /api_key/[KEY]/Library/Refresh
Function: Force library rescan
```

**Webhooks Émis (Plugin requis)** :
```json
{
  "NotificationType": "ItemAdded",
  "Description": "New movie added to library",
  "Name": "Film Title (2023)",
  "Year": 2023,
  "Type": "Movie",
  "ItemId": "jellyfin-item-id-12345",
  "ServerId": "jellyfin-server-id",
  "Provider_tmdb": "123456"
}
```

## 🔄 Flux de Données Détaillés

### Workflow Demande Film

**1. Jellyseerr → Radarr**
```http
POST http://radarr:7878/api/v3/movie
Headers:
  X-Api-Key: RADARR_API_KEY
  Content-Type: application/json

Body:
{
  "title": "Film Title",
  "year": 2023,
  "tmdbId": 123456,
  "qualityProfileId": 4,
  "rootFolderPath": "/data/media/movies",
  "monitored": true,
  "addOptions": {
    "monitor": "movieOnly",
    "searchForMovie": true
  }
}

Response:
{
  "id": 15,
  "title": "Film Title",  
  "status": "wanted",
  "monitored": true,
  "downloaded": false
}
```

**2. Radarr → Prowlarr Search**
```http
GET http://prowlarr:9696/api/v1/search?apikey=PROWLARR_API_KEY&cat=2000&q=Film%20Title%202023

Response:
{
  "results": [
    {
      "guid": "unique-result-id",
      "title": "Film.Title.2023.1080p.WEB-DL.x264-GROUP",
      "size": 9123456789,
      "link": "http://indexer.com/download/abc123.nzb",
      "category": [2000],
      "seeders": 150,
      "peers": 5,
      "publishDate": "2023-12-01T15:30:00Z"
    }
  ]
}
```

**3. Radarr → SABnzbd Download**  
```http
POST http://sabnzbd:8080/api
Form Data:
  mode=addurl
  apikey=SABNZBD_API_KEY
  nzburl=http://indexer.com/download/abc123.nzb
  cat=movies
  priority=0
  nzbname=Film.Title.2023.1080p.WEB-DL

Response:
{
  "status": true,
  "nzo_id": "SABnzbd_nzo_abc123"
}
```

### Workflow Post-Processing

**1. SABnzbd → Radarr Completion**
```http
POST http://radarr:7878/api/v3/command
Headers:
  X-Api-Key: RADARR_API_KEY

Body:
{
  "name": "DownloadedMoviesScan",
  "path": "/data/usenet/complete/movies/Film.Title.2023.1080p.WEB-DL-GROUP"
}
```

**2. Radarr Post-Processing**
```bash
# Actions automatiques Radarr:
# 1. Vérification qualité téléchargée
# 2. Renommage selon template
# 3. Déplacement vers library path
# 4. Download metadata (poster, fanart, nfo)
# 5. Notification apps connectées

Source: /data/usenet/complete/movies/Film.Title.2023.1080p.WEB-DL-GROUP/
Target: /data/media/movies/Film Title (2023) [tmdbid-123456]/
  ├── Film Title (2023) [tmdbid-123456] - [WEBDL-1080p][AC3 5.1][x264]-GROUP.mkv
  ├── poster.jpg
  ├── fanart.jpg  
  ├── logo.png
  └── movie.nfo
```

**3. Radarr → Jellyfin Notification**
```http
POST http://jellyfin:8096/api_key/JELLYFIN_API_KEY/Library/Refresh
Headers:
  Content-Type: application/json

Body: {} (Empty - triggers full library scan)
```

### Workflow Streaming

**1. Utilisateur → Jellyfin Request**
```http
GET http://jellyfin:8096/Videos/item-id-12345/stream.mkv
Headers:
  Authorization: MediaBrowser Token="jellyfin-access-token"
  
# Jellyfin résout le chemin physique:
# /media/movies/Film (2023) [tmdbid-123456]/film.mkv
# Via Docker mount = /novastream/data/media/movies/...
# Via MergerFS = Check local puis S3 si nécessaire
```

**2. MergerFS → Local ou S3**
```bash
# Si fichier en local:
/novastream/local/cache/media/movies/Film (2023)/film.mkv
→ Direct streaming, performance maximale

# Si fichier archivé S3:
/novastream/cloud/media/movies/Film (2023)/film.mkv  
→ rclone VFS streaming avec cache chunks local
→ Performance adaptative selon bande passante
```

## 🔐 Sécurité et Authentification

### API Keys Management
```bash
# Génération et stockage sécurisé des clés API
Radarr API Key: Settings → General → Security → API Key (32 chars)
Sonarr API Key: Settings → General → Security → API Key (32 chars)  
Prowlarr API Key: Settings → General → Security → API Key (32 chars)
SABnzbd API Key: Config → General → API Key (32 chars)
Jellyfin API Key: Dashboard → API Keys → Create New

# Stockage dans variables d'environnement Docker
RADARR_API_KEY=abc123...
SONARR_API_KEY=def456...
PROWLARR_API_KEY=ghi789...
```

### Network Security
```yaml
# Isolation réseau Docker
networks:
  reverse-proxy:
    external: true
    # Accessible via Traefik uniquement
    
  internal:
    internal: true  
    # Communication inter-services uniquement
    
# Exposition ports externe uniquement via Traefik
# APIs internes restent sur réseau Docker privé
```

### Rate Limiting
```yaml
# Configuration Prowlarr per-indexer
indexer_limits:
  nzbgeek: 100 req/day
  binsearch: 20 req/hour  
  dognzb: 1000 req/day

# Backoff automatique si rate limit hit
# Queue requests et retry automatique
```

## 📊 Monitoring APIs

### Health Checks
```bash
#!/bin/bash
# Script monitoring santé APIs

check_api() {
    local service=$1
    local url=$2
    local expected_code=${3:-200}
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    if [ "$response" = "$expected_code" ]; then
        echo "✅ $service API: OK"
    else
        echo "❌ $service API: Failed ($response)"
    fi
}

# Vérifications APIs
check_api "Radarr" "http://radarr:7878/api/v3/system/status?apikey=$RADARR_API_KEY"
check_api "Sonarr" "http://sonarr:8989/api/v3/system/status?apikey=$SONARR_API_KEY"  
check_api "Prowlarr" "http://prowlarr:9696/api/v1/system/status?apikey=$PROWLARR_API_KEY"
check_api "SABnzbd" "http://sabnzbd:8080/api?mode=version&apikey=$SABNZBD_API_KEY"
check_api "Jellyfin" "http://jellyfin:8096/health"
```

### Performance Metrics
```bash
# Métriques importantes à surveiller
- Request latency per API call
- Success/failure rates per integration  
- Queue lengths (SABnzbd, Radarr, Sonarr)
- Library scan durations (Jellyfin)
- Storage usage and transfer rates (S3)
- Indexer response times and availability
```

## 🔧 Configuration Avancée

### Custom API Endpoints
```python
# Extension Jellyseerr custom webhook
# /opt/stacks/jelly/jellyseerr/custom_webhook.py

import requests
import json

def custom_media_notification(media_data):
    """Send custom notification avec données enrichies"""
    
    webhook_url = "https://discord.com/api/webhooks/YOUR_WEBHOOK"
    
    embed = {
        "title": f"🎬 {media_data['title']} disponible",
        "description": media_data.get('overview', 'No description'),
        "color": 3447003,
        "thumbnail": {"url": media_data.get('poster_url')},
        "fields": [
            {"name": "Qualité", "value": media_data['quality'], "inline": True},
            {"name": "Taille", "value": media_data['size'], "inline": True},
            {"name": "Genre", "value": media_data.get('genres', 'Unknown'), "inline": True}
        ],
        "footer": {"text": "Novastream Media Server"}
    }
    
    payload = {"embeds": [embed]}
    requests.post(webhook_url, json=payload)
```

### API Proxy Configuration
```nginx
# Configuration Nginx pour API proxy (si requis)
# /etc/nginx/sites-available/novastream-apis

server {
    listen 80;
    server_name apis.novastream.local;
    
    # Radarr API Proxy
    location /radarr/ {
        proxy_pass http://radarr:7878/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Sonarr API Proxy  
    location /sonarr/ {
        proxy_pass http://sonarr:8989/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
}
```

Cette architecture d'intégrations APIs permet un écosystème média entièrement automatisé avec monitoring et sécurité renforcés ! 🔗🚀