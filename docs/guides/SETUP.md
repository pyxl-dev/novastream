# 🚀 Guide de Setup Complet Novastream

Ce guide détaille l'installation et la configuration complète du système Novastream depuis zéro.

## 📋 Prérequis Système

### Infrastructure de Base
- **OS** : Ubuntu Server 22.04+ (ou Debian 12+)
- **RAM** : 8GB minimum, 16GB recommandé
- **Storage** : 250GB SSD local + Stockage S3 illimité
- **Network** : 1Gbps recommandé pour streaming multiple
- **Docker** : Version 24.0+, Docker Compose 2.0+

### Comptes Externes Requis
- **Scaleway** : Bucket S3 pour stockage cloud
- **Discord** : Webhook pour notifications (optionnel)
- **Providers Usenet** : Minimum 1 provider + indexeurs
- **Domaine** : DNS pour accès externe (optionnel)

## 🏗️ Architecture Cible

```
Internet ─── Traefik Proxy ─── Docker Network
                │
                ├── Jellyfin (Stream) : 8096
                ├── Jellyseerr (Requests) : 5055  
                ├── Radarr (Movies) : 7878
                ├── Sonarr (TV) : 8989
                ├── Prowlarr (Indexers) : 9696
                ├── SABnzbd (Downloader) : 8080
                └── Notifiarr (Alerts) : 5454

/novastream/
├── local/cache/        # Cache SSD local
├── cloud/             # Montage S3 rclone
└── data/              # MergerFS (cache + cloud)
```

## 📂 Phase 1 : Préparation Système

### 1.1 Installation Docker
```bash
# Désinstaller anciennes versions
sudo apt remove docker docker-engine docker.io containerd runc

# Installer dépendances
sudo apt update
sudo apt install apt-transport-https ca-certificates curl gnupg lsb-release

# Ajouter clé GPG Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Ajouter repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installer Docker
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Ajouter utilisateur au groupe docker
sudo usermod -aG docker $USER
newgrp docker

# Vérifier installation
docker --version
docker compose version
```

### 1.2 Installation rclone
```bash
# Télécharger et installer rclone
curl https://rclone.org/install.sh | sudo bash

# Vérifier version
rclone version

# Configuration S3 Scaleway
rclone config
# Suivre assistant pour créer remote "scaleway" avec credentials S3
```

### 1.3 Création Structure Répertoires
```bash
# Créer l'arborescence Novastream
sudo mkdir -p /novastream/{local/{cache/{media/{movies,tv},jellyfin,rclone_vfs,usenet,radarr_temp,sonarr_temp},usenet/{incomplete,complete}},cloud,data}

# Créer structure /opt/stacks
sudo mkdir -p /opt/stacks/{jelly,starr,traefik}

# Permissions appropriées
sudo chown -R $USER:$USER /novastream/local/
sudo chown -R $USER:$USER /opt/stacks/
```

### 1.4 Configuration MergerFS
```bash
# Installer mergerfs
sudo apt update
sudo apt install mergerfs

# Configuration dans /etc/fstab
echo "/novastream/local/cache:/novastream/cloud /novastream/data fuse.mergerfs defaults,allow_other,category.create=ff,minfreespace=25G,func.getattr=newest 0 0" | sudo tee -a /etc/fstab

# Test montage (après configuration rclone)
sudo mount -a
```

## ⚙️ Phase 2 : Configuration Stockage Cloud

### 2.1 Service rclone Systemd
```bash
# Créer service systemd
sudo tee /etc/systemd/system/rclone-s3.service > /dev/null << EOF
[Unit]
Description=rclone mount for Scaleway S3
After=network-online.target

[Service]
Type=notify
User=1000
ExecStart=/usr/bin/rclone mount $S3_REMOTE/ /novastream/cloud \\
    --vfs-cache-mode full \\
    --vfs-cache-max-size 10G \\
    --vfs-cache-max-age 24h \\
    --cache-dir /novastream/local/cache/rclone_vfs \\
    --vfs-read-chunk-size 32M \\
    --vfs-read-ahead 128M \\
    --dir-cache-time 72h \\
    --allow-other \\
    --allow-non-empty \\
    --log-level INFO
ExecStop=/bin/fusermount3 -u /novastream/cloud
Restart=on-abort
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Activer et démarrer service
sudo systemctl enable rclone-s3.service
sudo systemctl start rclone-s3.service

# Vérifier status
sudo systemctl status rclone-s3.service
```

### 2.2 Configuration Notifications
```bash
# Créer configuration Discord (optionnel)
sudo tee /etc/s3-notify.conf > /dev/null << EOF
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK_HERE"
LOG_DIR="/var/log/novastream"
EOF

# Créer dossier logs
sudo mkdir -p /var/log/novastream
sudo chown $USER:$USER /var/log/novastream
```

## 🐳 Phase 3 : Déploiement Docker Stack

### 3.1 Configuration Traefik (Reverse Proxy)
```bash
# Créer network Docker
docker network create reverse-proxy

# Configuration Traefik
mkdir -p /opt/stacks/traefik
cat > /opt/stacks/traefik/compose.yaml << EOF
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.network=reverse-proxy
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - reverse-proxy
    restart: unless-stopped

networks:
  reverse-proxy:
    external: true
EOF

cd /opt/stacks/traefik
docker compose up -d
```

### 3.2 Stack Jellyfin + Jellyseerr
```bash
# Copier configuration existante ou créer nouvelle
mkdir -p /opt/stacks/jelly/{jellyfin,jellyseerr}
cat > /opt/stacks/jelly/compose.yaml << 'EOF'
services:
  jellyfin:
    image: jellyfin/jellyfin
    container_name: jellyfin
    group_add:
      - "107" #render
      - "44" #video
    networks:
      - reverse-proxy
    volumes:
      - ./jellyfin/config:/config
      - /downloads:/downloads
      - /novastream/data/media:/media
      - /novastream/local/cache/jellyfin:/cache
    environment:
      - JELLYFIN_METADATA_DIR=/cache/metadata
      - JELLYFIN_CACHE_DIR=/cache/transcodes
    restart: always
    labels:
      - traefik.enable=true
      - traefik.http.routers.jellyfin.rule=Host(`stream.example.com`)
      - traefik.http.services.jellyfin.loadbalancer.server.port=8096

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - LOG_LEVEL=debug
      - TZ=Europe/Paris
      - PORT=5055
    volumes:
      - ./jellyseerr/config:/app/config
    restart: unless-stopped
    networks:
      - reverse-proxy
    labels:
      - traefik.enable=true
      - traefik.http.routers.jellyseerr.rule=Host(`requests.example.com`)
      - traefik.http.services.jellyseerr.loadbalancer.server.port=5055

networks:
  reverse-proxy:
    external: true
EOF

cd /opt/stacks/jelly
docker compose up -d
```

### 3.3 Stack Starr Apps
```bash
mkdir -p /opt/stacks/starr/{config/{radarr,sonarr,prowlarr,sabnzbd}}
cat > /opt/stacks/starr/compose.yaml << 'EOF'
services:
  radarr:
    container_name: radarr
    image: ghcr.io/hotio/radarr:latest
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
      - RADARR__UMASK=002
    labels:
      - traefik.enable=true
      - traefik.http.services.radarr.loadbalancer.server.port=7878
      - traefik.http.routers.radarr.rule=Host(`radarr.example.com`)
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config/radarr:/config
      - /novastream/data:/data
      - /novastream/local/cache/radarr_temp:/tmp
    networks:
      - reverse-proxy

  sonarr:
    container_name: sonarr
    image: ghcr.io/hotio/sonarr:latest
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
      - SONARR__UMASK=002
    labels:
      - traefik.enable=true
      - traefik.http.services.sonarr.loadbalancer.server.port=8989
      - traefik.http.routers.sonarr.rule=Host(`sonarr.example.com`)
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config/sonarr:/config
      - /novastream/data:/data
      - /novastream/local/cache/sonarr_temp:/tmp
    networks:
      - reverse-proxy

  prowlarr:
    container_name: prowlarr
    image: ghcr.io/hotio/prowlarr:latest
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    labels:
      - traefik.enable=true
      - traefik.http.services.prowlarr.loadbalancer.server.port=9696
      - traefik.http.routers.prowlarr.rule=Host(`prowlarr.example.com`)
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config/prowlarr:/config
      - /novastream/data:/data
    networks:
      - reverse-proxy

  sabnzbd:
    container_name: sabnzbd
    image: ghcr.io/hotio/sabnzbd:latest
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    labels:
      - traefik.enable=true
      - traefik.http.services.sabnzbd.loadbalancer.server.port=8080
      - traefik.http.routers.sabnzbd.rule=Host(`sabnzbd.example.com`)
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config/sabnzbd:/config
      - /novastream/local/usenet/incomplete:/data/usenet/incomplete
      - /novastream/data/usenet/complete:/data/usenet/complete
    networks:
      - reverse-proxy

networks:
  reverse-proxy:
    external: true
EOF

cd /opt/stacks/starr
docker compose up -d
```

## ⚙️ Phase 4 : Configuration Services

### 4.1 Configuration Jellyfin
```bash
# Accès initial : http://server-ip:8096
# Ou https://stream.example.com si Traefik configuré

# Configuration initiale via interface web :
# 1. Language: Français
# 2. User: Créer admin user
# 3. Media Libraries:
#    - Movies: /media/movies
#    - TV Shows: /media/tv
# 4. Remote Access: Configurer si nécessaire
# 5. Hardware Transcoding: Activer si disponible
```

### 4.2 Configuration SABnzbd
```bash
# Accès : http://server-ip:8080

# Configuration requise :
# 1. Servers: Ajouter providers Usenet
# 2. Categories:
#    - movies: /data/usenet/complete/movies
#    - tv: /data/usenet/complete/tv  
# 3. Folders:
#    - Temporary Download: /data/usenet/incomplete
#    - Complete Download: /data/usenet/complete
# 4. Switches:
#    - Direct Unpack: On
#    - Cleanup List: On
#    - Par Cleanup: On
```

### 4.3 Configuration Prowlarr
```bash
# Accès : http://server-ip:9696

# Configuration :
# 1. Indexers: Ajouter indexeurs Usenet/Torrent
# 2. Apps: Sync vers Radarr/Sonarr
#    - Radarr: http://radarr:7878, API key
#    - Sonarr: http://sonarr:8989, API key
# 3. Download Clients: Ajouter SABnzbd
#    - Host: sabnzbd:8080
#    - API Key: [from SABnzbd]
```

### 4.4 Configuration Radarr
```bash
# Accès : http://server-ip:7878

# Configuration essentielle :
# 1. Media Management:
#    - Root Folder: /data/media/movies
#    - File Naming: Movie (Year) [tmdbid-12345]
#    - Permissions: 755 folders, 644 files
# 2. Profiles:
#    - Quality: HD-1080p preferred
#    - Language: French preferred
# 3. Download Clients: SABnzbd
#    - Category: movies
#    - Priority: Normal
# 4. Connect: Jellyfin notification
#    - Host: jellyfin:8096
#    - API Key: [from Jellyfin]
```

### 4.5 Configuration Sonarr
```bash
# Accès : http://server-ip:8989

# Configuration similaire à Radarr :
# 1. Root Folder: /data/media/tv  
# 2. Quality Profile: HD-1080p
# 3. Language Profile: French/English
# 4. Series Type: Standard/Anime selon besoin
# 5. Download Client: SABnzbd category "tv"
```

### 4.6 Configuration Jellyseerr
```bash
# Accès : http://server-ip:5055

# Configuration intégration :
# 1. Jellyfin Settings:
#    - Server URL: http://jellyfin:8096
#    - API Key: [from Jellyfin]
#    - Sync Libraries: Movies + TV
# 2. Radarr Settings:
#    - Server URL: http://radarr:7878  
#    - API Key: [from Radarr]
#    - Root Folder: /data/media/movies
#    - Quality Profile: HD-1080p
# 3. Sonarr Settings:
#    - Server URL: http://sonarr:8989
#    - API Key: [from Sonarr] 
#    - Root Folder: /data/media/tv
#    - Quality Profile: HD-1080p
```

## 🔧 Phase 5 : Scripts Automation

### 5.1 Scripts de Nettoyage
```bash
# Créer scripts de gestion automatique
sudo mkdir -p /usr/local/bin/

# Script principal de nettoyage
sudo tee /usr/local/bin/check_space.sh > /dev/null << 'EOF'
#!/bin/bash

source /etc/s3-notify.conf

LOCAL_MEDIA="/novastream/local/cache/media"
S3_BUCKET="${S3_REMOTE:-s3remote:media-bucket}"
THRESHOLD=70
MIN_AGE_MINUTES=60
LOG_DIR="/var/log/novastream"

mkdir -p "$LOG_DIR"

LOCAL_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')

if [[ $LOCAL_USAGE -ge $THRESHOLD ]]; then
    echo "[$(date)] Space critical (${LOCAL_USAGE}%), starting S3 upload" >> "${LOG_DIR}/space_cleanup.log"
    
    find "$LOCAL_MEDIA" -type f -mmin +${MIN_AGE_MINUTES} | while read -r file; do
        relative_path="${file#$LOCAL_MEDIA/}"
        target_dir="${S3_BUCKET}/$(dirname "$relative_path")"
        
        if rclone move "$file" "$target_dir/" --log-level ERROR; then
            echo "[$(date)] Uploaded: $(basename "$file")" >> "${LOG_DIR}/space_cleanup.log"
        fi
    done
    
    rclone rc vfs/refresh recursive=true --fast-list 2>/dev/null || true
    
    find "$LOCAL_MEDIA" -type d -empty -delete 2>/dev/null
fi
EOF

sudo chmod +x /usr/local/bin/check_space.sh

# Script migration fichiers inactifs
sudo tee /usr/local/bin/move_inactive.sh > /dev/null << 'EOF'
#!/bin/bash

source /etc/s3-notify.conf

LOCAL_MEDIA="/novastream/local/cache/media"
S3_BUCKET="${S3_REMOTE:-s3remote:media-bucket}"
DAYS_INACTIVE=7
LOG_DIR="/var/log/novastream"

find "$LOCAL_MEDIA" -type f -atime +${DAYS_INACTIVE} | while read -r file; do
    if [[ -f "$file" ]]; then
        relative_path="${file#$LOCAL_MEDIA/}"
        target_dir="${S3_BUCKET}/$(dirname "$relative_path")"
        
        if rclone move "$file" "$target_dir/" --log-level ERROR; then
            echo "[$(date)] Archived: $(basename "$file")" >> "${LOG_DIR}/move_inactive.log"
        fi
    fi
done

find "$LOCAL_MEDIA" -type d -empty -delete 2>/dev/null
EOF

sudo chmod +x /usr/local/bin/move_inactive.sh
```

### 5.2 Configuration Cron
```bash
# Ajouter tâches cron
(crontab -l 2>/dev/null; echo "*/15 * * * * /usr/local/bin/check_space.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 */3 * * * /usr/local/bin/move_inactive.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/docker system prune -f") | crontab -

# Vérifier cron
crontab -l
```

## 📊 Phase 6 : Tests et Validation

### 6.1 Test Workflow Complet
```bash
# 1. Vérifier tous les services
cd /opt/stacks/jelly && docker compose ps
cd /opt/stacks/starr && docker compose ps

# 2. Test demande film via Jellyseerr
# - Accéder interface Jellyseerr  
# - Rechercher film test
# - Créer demande
# - Vérifier propagation vers Radarr

# 3. Test téléchargement manuel
# - Interface Radarr : Manual Search
# - Vérifier téléchargement SABnzbd
# - Vérifier post-processing vers /novastream/local/cache/media/

# 4. Test scan Jellyfin
# - Dashboard Jellyfin → Libraries → Scan
# - Vérifier film apparaît dans interface

# 5. Test archivage S3
# - Attendre ou forcer avec script check_space.sh
# - Vérifier fichier dans S3: rclone ls $S3_REMOTE/
# - Vérifier streaming encore fonctionnel
```

### 6.2 Validation Monitoring
```bash
# Créer script de santé système
tee /home/$USER/health_check.sh > /dev/null << 'EOF'
#!/bin/bash

echo "=== NOVASTREAM HEALTH CHECK ==="
echo "Date: $(date)"
echo ""

echo "Docker Services:"
cd /opt/stacks/jelly && docker compose ps --format "table {{.Service}}\t{{.Status}}"
cd /opt/stacks/starr && docker compose ps --format "table {{.Service}}\t{{.Status}}"

echo ""
echo "Storage:"
df -h / | grep -E "Filesystem|/dev"
du -sh /novastream/local/cache/media/

echo ""
echo "Mounts:"
mount | grep -E "(rclone|mergerfs)"

echo ""
echo "Recent Activity:"
tail -5 /var/log/novastream/space_cleanup.log 2>/dev/null || echo "No cleanup logs"
EOF

chmod +x /home/$USER/health_check.sh
/home/$USER/health_check.sh
```

## 🔒 Phase 7 : Sécurité et Maintenance

### 7.1 Configuration Firewall
```bash
# Configuration UFW basique
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw --force enable

# Les autres ports sont gérés par Traefik reverse proxy
```

### 7.2 Sauvegarde Configurations
```bash
# Script sauvegarde automatique
tee /home/$USER/backup_configs.sh > /dev/null << 'EOF'
#!/bin/bash

BACKUP_DIR="/home/$USER/novastream-backups/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Sauvegarder configurations Docker
cp -r /opt/stacks/ "$BACKUP_DIR/"

# Sauvegarder configurations système
cp /etc/fstab "$BACKUP_DIR/"
cp /etc/systemd/system/rclone-s3.service "$BACKUP_DIR/"
cp /etc/s3-notify.conf "$BACKUP_DIR/" 2>/dev/null || true

# Sauvegarder structure S3
rclone tree $S3_REMOTE > "$BACKUP_DIR/s3_structure.txt"

echo "Backup completed: $BACKUP_DIR"
EOF

chmod +x /home/$USER/backup_configs.sh

# Programmer sauvegarde hebdomadaire
(crontab -l 2>/dev/null; echo "0 2 * * 0 /home/$USER/backup_configs.sh") | crontab -
```

### 7.3 Monitoring Système
```bash
# Ajouter monitoring basique via cron
(crontab -l 2>/dev/null; echo "0 */6 * * * /home/$USER/health_check.sh >> /var/log/novastream/health.log") | crontab -

# Log rotation pour éviter saturation
sudo tee /etc/logrotate.d/novastream > /dev/null << 'EOF'
/var/log/novastream/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

## ✅ Checklist Validation Finale

### Services Running
- [ ] Traefik proxy accessible
- [ ] Jellyfin accessible et fonctionnel  
- [ ] Jellyseerr accessible et connecté
- [ ] Radarr/Sonarr configurés et indexeurs actifs
- [ ] Prowlarr sync avec Radarr/Sonarr
- [ ] SABnzbd connecté aux providers

### Stockage
- [ ] MergerFS monte local + cloud
- [ ] rclone service systemd actif
- [ ] Scripts de nettoyage programmés
- [ ] Tests upload/download S3 fonctionnels

### Workflow
- [ ] Demande Jellyseerr → Radarr works  
- [ ] Recherche automatique via Prowlarr
- [ ] Téléchargement SABnzbd vers local
- [ ] Post-processing et organisation fichiers
- [ ] Scan Jellyfin automatique
- [ ] Streaming fonctionnel (local + S3)

### Maintenance
- [ ] Backups configurations programmées
- [ ] Monitoring système en place
- [ ] Logs rotation configurée
- [ ] Documentation accessible

## 🎯 Résultats Attendus

Après ce setup complet, ton système Novastream sera :

**Fonctionnel** : Workflow automatisé de bout en bout
**Scalable** : Stockage S3 illimité avec cache local performant  
**Robuste** : Services containerisés avec restart automatique
**Maintenable** : Logs, monitoring et backups automatiques
**Sécurisé** : Reverse proxy, firewall et accès contrôlés

**Temps total d'installation** : 4-6 heures selon expertise
**Délai première demande → streaming** : 15min-2h selon indexeurs

Bienvenue dans ton système média automatisé ! 🎬✨