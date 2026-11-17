# Architecture Complète Novastream Media Server

## Vue d'ensemble du Système

Novastream utilise un système de stockage hybride qui combine le stockage local SSD pour le cache et le cloud S3 Scaleway pour l'archivage long-terme, avec accès transparent via Jellyfin.

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Jellyfin      │    │    MergerFS     │    │  Stockage S3    │
│   (Docker)      │───▶│   Union FS      │───▶│   Scaleway      │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
   Port 8096              /novastream/data        Bucket infini
  Interface Web         Cache + Cloud             75GB+ films
```

## Architecture en Détail

### 1. Stockage Local (`/novastream/local/`)
```
/novastream/local/
├── cache/
│   ├── media/           # Cache des métadonnées (posters, .nfo, etc.)
│   ├── jellyfin/        # Cache Jellyfin (transcoding, métadonnées DB)
│   ├── rclone_vfs/      # Cache VFS rclone (chunks de fichiers lus)
│   ├── usenet/          # Téléchargements en cours
│   ├── radarr_temp/     # Temp Radarr
│   └── sonarr_temp/     # Temp Sonarr
└── usenet/              # Téléchargements finalisés
```

**Rôle** : Cache haute performance pour accès rapide et stockage temporaire.

### 2. Stockage Cloud (`/novastream/cloud/`)
```
/novastream/cloud/       # Montage rclone de $S3_REMOTE
└── media/
    ├── movies/          # Films archivés (.mkv, .mp4)
    │   ├── Film1/
    │   │   ├── film.mkv
    │   │   ├── poster.jpg
    │   │   └── *.trickplay/
    │   └── Film2/
    └── tv/              # Séries TV archivées
        └── Serie1/
```

**Rôle** : Stockage infini et permanent, accès à la demande via internet.

### 3. Vue Unifiée (`/novastream/data/`)
```
/novastream/data/        # MergerFS: local/cache + cloud
├── media/               # Vue combinée des médias
│   ├── movies/          # Films (local + cloud)
│   └── tv/              # TV (local + cloud)
├── jellyfin/           # Config Jellyfin
└── usenet/             # Téléchargements
```

**Rôle** : Point d'accès unique pour Jellyfin, combine automatiquement local + cloud.

## Configuration des Services

### A. Rclone Mount (Service Principal)

**Fichier** : `/etc/systemd/system/rclone-s3.service`
```ini
[Unit]
Description=rclone mount for Scaleway S3
After=network-online.target

[Service]
Type=notify
User=1000
ExecStart=/usr/bin/rclone mount $S3_REMOTE/ /novastream/cloud \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --vfs-cache-max-age 24h \
    --cache-dir /novastream/local/cache/rclone_vfs \
    --vfs-read-chunk-size 32M \
    --vfs-read-ahead 128M \
    --dir-cache-time 72h \
    --allow-other \
    --allow-non-empty \
    --log-level INFO
ExecStop=/bin/fusermount3 -u /novastream/cloud
Restart=on-abort
RestartSec=5

[Install]
WantedBy=default.target
```

**Paramètres Critiques** :
- `--vfs-cache-mode full` : Cache complet pour performances
- `--vfs-cache-max-size 10G` : Limite de cache local
- `--dir-cache-time 72h` : Cache de répertoires (IMPORTANT: ne pas mettre trop bas)

### B. MergerFS (Union Filesystem)

**Fichier** : `/etc/fstab`
```
/novastream/local/cache:/novastream/cloud /novastream/data fuse.mergerfs defaults,allow_other,category.create=ff,minfreespace=25G,func.getattr=newest 0 0
```

**Paramètres Critiques** :
- `category.create=ff` : Nouveaux fichiers vont sur le premier FS (local)
- `minfreespace=25G` : Garde 25G d'espace libre sur local
- `func.getattr=newest` : Utilise la version la plus récente du fichier

### C. Jellyfin Docker

**Fichier** : `/opt/stacks/jelly/compose.yaml`
```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin
    container_name: jellyfin
    volumes:
      - ./jellyfin/config:/config
      - /downloads:/downloads
      - /novastream/data/media:/media          # POINT CLÉ
      - /novastream/local/cache/jellyfin:/cache
    environment:
      - JELLYFIN_METADATA_DIR=/cache/metadata
      - JELLYFIN_CACHE_DIR=/cache/transcodes
```

**Point Critique** : Jellyfin lit depuis `/novastream/data/media` (vue unifiée)

## Flux de Données

### 1. Ajout d'un Nouveau Film
```
1. Radarr/Sonarr télécharge → /novastream/local/cache/media/movies/
2. MergerFS expose → /novastream/data/media/movies/ 
3. Jellyfin scanne et indexe
4. Scripts de nettoyage déplacent → S3 après 1h-7 jours
5. Fichier reste accessible via MergerFS (local OU cloud)
```

### 2. Lecture d'un Film Archivé
```
1. Utilisateur clique sur film dans Jellyfin
2. Jellyfin demande fichier → /novastream/data/media/movies/film.mkv
3. MergerFS redirige → /novastream/cloud/media/movies/film.mkv
4. Rclone VFS télécharge chunks → cache local
5. Streaming transparent vers utilisateur
```

## Scripts de Gestion Automatique

### 1. Script de Nettoyage Principal
**Fichier** : `/usr/local/bin/check_space.sh`
**Fréquence** : Toutes les 15 minutes
**Déclencheur** : Espace disque > 70%

```bash
# Actions effectuées :
1. Trouve fichiers > 1h dans /novastream/local/cache/media/
2. Upload vers S3 avec: rclone move source $S3_REMOTE/media/
3. Supprime copie locale après upload réussi
4. Nettoie répertoires vides
5. Actualise cache rclone
```

### 2. Script de Migration Inactive
**Fichier** : `/usr/local/bin/move_inactive.sh`
**Fréquence** : Toutes les 3h
**Critère** : Fichiers non accédés depuis 7 jours

```bash
# Actions :
1. Identifie fichiers atime > 7 jours
2. Upload vers S3 
3. Supprime local
4. Notification Discord
```

### 3. Configuration Cron
```bash
*/15 * * * * /usr/local/bin/check_space.sh              # Nettoyage urgence
0 */3 * * * /usr/local/bin/move_inactive.sh             # Migration inactive
0 0 * * * /usr/bin/docker system prune -f               # Nettoyage Docker
```

## Structure S3 Correcte (CRITIQUE)

### ✅ Structure Attendue
```
$S3_REMOTE/
└── media/
    ├── movies/
    │   ├── Film (2025) [tmdbid-123456]/
    │   │   ├── film.mkv                    # Fichier principal
    │   │   ├── poster.jpg                  # Métadonnées
    │   │   └── *.trickplay/               # Previews Jellyfin
    │   └── ...
    └── tv/
        ├── Serie (2023) [tvdbid-789]/
        │   └── Season 01/
        │       ├── episode.mkv
        │       └── ...
        └── ...
```

### ❌ Structures Problématiques à Éviter
```
# MAUVAIS - Films à la racine
$S3_REMOTE/
├── movies/           # ❌ Pas dans media/
└── tv/              # ❌ Pas dans media/

# MAUVAIS - Fichiers isolés
$S3_REMOTE/media/movies/
├── film1.mkv        # ❌ Pas dans son dossier
└── Film1/           # ✅ Dossier vide
```

## Commandes de Maintenance

### Diagnostic Système
```bash
# Vérifier l'état général
./scripts/check_jellyfin_ready.sh

# Voir la structure S3
rclone tree $S3_REMOTE --human-readable --max-depth 3

# Compter les films accessibles
find /novastream/data/media/movies/ -name "*.mkv" | wc -l

# Vérifier les montages
mount | grep -E "(rclone|mergerfs)"
```

### Redémarrage Complet du Système
```bash
# 1. Arrêter les services
cd /opt/stacks/jelly && docker compose down
fusermount3 -u /novastream/cloud
umount /novastream/data

# 2. Nettoyer les caches
rm -rf /novastream/local/cache/rclone_vfs/*

# 3. Remonter dans l'ordre
rclone mount $S3_REMOTE/ /novastream/cloud --daemon [options]
mount -a  # Pour mergerfs via fstab
cd /opt/stacks/jelly && docker compose up -d
```

### Upload Manuel vers S3
```bash
# Upload d'un film spécifique
rclone move "/novastream/local/cache/media/movies/Film (2025)/" \
           "${S3_REMOTE:-s3remote:media-bucket}/media/movies/" --log-level INFO

# Upload de tous les films locaux
rclone move "/novastream/local/cache/media/movies/" \
           "${S3_REMOTE:-s3remote:media-bucket}/media/movies/" --log-level INFO
```

## Problèmes Fréquents et Solutions

### 1. Films Invisibles dans Jellyfin
**Symptômes** : Bibliothèque vide ou incomplète
**Causes Possibles** :
- Structure S3 incorrecte (films dans `movies/` au lieu de `media/movies/`)
- Montage rclone déconnecté
- Cache de répertoires rclone obsolète

**Solutions** :
```bash
# Vérifier les montages
mount | grep -E "(rclone|mergerfs)"

# Redémarrer rclone avec cache court
fusermount3 -u /novastream/cloud
rclone mount $S3_REMOTE/ /novastream/cloud \
    --dir-cache-time 10s --daemon [autres options]

# Forcer scan Jellyfin
cd /opt/stacks/jelly && docker compose restart jellyfin
```

### 2. Espace Disque Plein Malgré les Scripts
**Symptômes** : Disque à >90% d'utilisation
**Causes** : Scripts de nettoyage défaillants ou upload S3 bloqué

**Solutions** :
```bash
# Upload d'urgence manuel
./scripts/emergency_s3_upload.sh

# Vérifier les logs de nettoyage
tail -f /var/log/novastream/space_cleanup.log

# Tuer processus rclone bloqués
pkill -f "rclone move"
```

### 3. Films Dupliqués ou Structure Corrompue
**Symptômes** : Doublons, fichiers .mkv isolés, dossiers .trickplay orphelins

**Solutions** :
```bash
# Script de nettoyage S3
rclone dedupe --dry-run "$S3_REMOTE/media"  # verifier les doublons avant tout deplacement

# Diagnostic complet
rclone tree $S3_REMOTE --max-depth 3
rclone ls $S3_REMOTE --include "*.mkv"
```

## Notifications et Monitoring

### Webhook Discord
**Configuration** : `/etc/s3-notify.conf`
```bash
DISCORD_WEBHOOK="https://discord.com/api/webhooks/[ton-webhook]"
```

**Notifications Automatiques** :
- Upload d'urgence déclenché
- Fichiers archivés automatiquement
- Erreurs de script de nettoyage

### Logs Importants
```bash
# Logs rclone
journalctl -u rclone-s3.service -f

# Logs nettoyage
tail -f /var/log/novastream/space_cleanup.log

# Logs Docker Jellyfin  
cd /opt/stacks/jelly && docker compose logs -f jellyfin
```

## Points Critiques à Retenir

### ⚠️ JAMAIS FAIRE
1. **Écrire directement dans `/novastream/cloud/`** - C'est un montage en lecture
2. **Lancer plusieurs `rclone move` simultanés** - Crée des conflits
3. **Modifier `/etc/fstab` sans backup** - Peut casser le système au démarrage
4. **Vider `/novastream/local/cache/media/`** - Perte des métadonnées locales

### ✅ BONNES PRATIQUES
1. **Toujours utiliser `rclone move`** pour uploader vers S3 (pas copy)
2. **Tester avec `--dry-run`** avant les opérations importantes
3. **Vérifier la structure S3** après chaque modification
4. **Redémarrer Jellyfin** après changements majeurs dans les médias
5. **Surveiller l'espace disque** régulièrement

## Script de Sanity Check Quotidien

Créer un check quotidien automatique :
```bash
# /usr/local/bin/daily_health_check.sh
#!/bin/bash
{
    echo "=== HEALTH CHECK $(date) ==="
    echo "Espace disque: $(df -h / | tail -1 | awk '{print $5}')"
    echo "Films accessibles: $(find /novastream/data/media/movies/ -name "*.mkv" | wc -l)"
    echo "Films dans S3: $(rclone ls $S3_REMOTE/media/movies --include "*.mkv" | wc -l)"
    echo "Montages actifs:"
    mount | grep -E "(rclone|mergerfs)"
} >> /var/log/novastream/daily_health.log
```

Cette architecture garantit un système robuste avec stockage hybride performant ! 🎬