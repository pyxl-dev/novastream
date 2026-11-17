# 🎬 Workflow Complet Novastream - De la Demande à la Diffusion

## Vue d'Ensemble du Système

Novastream est un écosystème média automatisé qui transforme une simple demande utilisateur en film disponible pour streaming, en passant par 8 services interconnectés.

```
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│ Jellyseerr  │──▶│    Radarr   │──▶│   Prowlarr  │──▶│   SABnzbd   │
│  (Demandes) │   │  (Films)    │   │ (Indexeurs) │   │(Télécharge.)│
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
      │                                                       │
      │                                                       ▼
      ▼                                               ┌─────────────┐
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │   Stockage  │
│   Sonarr    │   │   Jellyfin  │◀──│  MergerFS   │◀──│   Hybride   │
│   (TV)      │   │ (Streaming) │   │(Union FS)   │   │ Local + S3  │
└─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘
```

## 📋 Services et Leurs Rôles

### 🎯 **Interface Utilisateur**
- **Jellyseerr** : Interface de demandes (Port 5055)
- **Jellyfin** : Interface de streaming (Port 8096)
- **Wizarr** : Gestion des invitations utilisateurs

### 🔍 **Orchestrateurs**
- **Radarr** : Gestion automatisée des films (Port 7878)
- **Sonarr** : Gestion automatisée des séries TV (Port 8989)
- **Prowlarr** : Gestionnaire d'indexeurs Usenet/Torrent (Port 9696)

### 📥 **Téléchargement**
- **SABnzbd** : Client Usenet pour téléchargements (Port 8080)

### 📊 **Monitoring et Notifications**
- **Notifiarr** : Notifications Discord/Pushover (Port 5454)
- **JellyStat** : Statistiques d'utilisation Jellyfin
- **SuggestArr** : Suggestions de contenu automatiques

## 🔄 Workflow Détaillé : Demande → Diffusion

### Phase 1 : Demande Utilisateur
```
[Utilisateur] → [Jellyseerr] → [Base de données des demandes]
```

**Actions** :
1. Utilisateur se connecte sur `catalogue.example.com`
2. Recherche film via interface Jellyseerr
3. Clique "Demander" 
4. Jellyseerr enregistre la demande avec statut "Pending"

### Phase 2 : Traitement par Radarr/Sonarr
```
[Jellyseerr] → [API Call] → [Radarr/Sonarr] → [Recherche automatique]
```

**Actions Films (Radarr)** :
1. Jellyseerr envoie requête API vers Radarr
2. Radarr ajoute le film à sa liste "Wanted"
3. Radarr lance recherche automatique toutes les 15min
4. Radarr interroge Prowlarr pour les sources

**Actions Séries (Sonarr)** :
1. Même processus mais gestion par épisodes/saisons
2. Sonarr suit la diffusion et télécharge automatiquement nouveaux épisodes

### Phase 3 : Recherche et Indexation
```
[Radarr/Sonarr] → [Prowlarr API] → [Indexeurs Usenet] → [Résultats]
```

**Configuration Prowlarr** :
- **Indexeurs configurés** : ~15-20 indexeurs Usenet privés/publics
- **Filtres qualité** : 1080p minimum, taille max 20GB
- **Langues** : Français + VOSTFR prioritaires
- **Formats** : x264/x265, AAC/AC3/DTS

**Actions** :
1. Radarr demande à Prowlarr : "Film X en 1080p VOSTFR"
2. Prowlarr interroge tous les indexeurs configurés
3. Retourne les résultats triés par qualité/seeders
4. Radarr sélectionne le meilleur selon profils qualité

### Phase 4 : Téléchargement
```
[Radarr/Sonarr] → [SABnzbd API] → [Serveurs Usenet] → [Téléchargement]
```

**Configuration SABnzbd** :
- **Dossiers de sortie** :
  - Movies : `/novastream/local/usenet/complete/movies/`
  - TV : `/novastream/local/usenet/complete/tv/`
- **Post-traitement** : Extraction automatique, vérification PAR
- **Serveurs Usenet** : Plusieurs providers pour redondance

**Actions** :
1. Radarr envoie .nzb vers SABnzbd via API
2. SABnzbd télécharge depuis serveurs Usenet
3. Extraction et vérification automatiques
4. Placement dans dossier de sortie approprié
5. Notification vers Radarr : "Téléchargement terminé"

### Phase 5 : Post-Traitement et Organisation
```
[SABnzbd] → [Notification] → [Radarr/Sonarr] → [Renommage] → [Déplacement]
```

**Actions Radarr** :
1. Reçoit notification de téléchargement terminé
2. Vérifie qualité et intégrité du fichier
3. Renomme selon pattern : `Film (Année) [tmdbid-123456] - [Quality][Audio][Codec]-Group.mkv`
4. Déplace vers : `/novastream/local/cache/media/movies/Film (Année) [tmdbid-123456]/`
5. Télécharge métadonnées (poster, backdrop, .nfo)
6. Marque comme "Downloaded" dans Jellyseerr

**Actions Sonarr** :
1. Même processus mais structure : `/novastream/local/cache/media/tv/Serie/Season XX/`
2. Gestion des épisodes individuels et saisons complètes

### Phase 6 : Indexation Jellyfin
```
[Déplacement fichier] → [Jellyfin Scanner] → [Base de données] → [Métadonnées]
```

**Configuration Jellyfin** :
- **Scan automatique** : Surveillé `/novastream/data/media/` via inotify
- **Métadonnées** : TheMovieDB pour films, TheTVDB pour séries
- **Transcoding** : Hardware (Intel QuickSync) + Software fallback

**Actions** :
1. Jellyfin détecte nouveau fichier dans `/novastream/data/media/movies/`
2. Lance scan de la bibliothèque automatiquement
3. Extrait métadonnées (titre, synopsis, casting)
4. Télécharge artwork supplémentaire si nécessaire  
5. Génère previews .trickplay pour navigation rapide
6. Film devient disponible dans interface

### Phase 7 : Archivage Automatique (Arrière-plan)
```
[Scripts cron] → [Vérification âge] → [Upload S3] → [Suppression locale]
```

**Timing** :
- **Fichiers récents** (< 1h) : Restent en local pour accès rapide
- **Fichiers inactifs** (> 7 jours) : Archivés automatiquement en S3
- **Urgence** (espace > 70%) : Upload immédiat de tous fichiers > 1h

**Actions** :
1. Script `check_space.sh` tourne toutes les 15min
2. Identifie fichiers candidats à l'archivage
3. Upload vers S3 avec `rclone move`
4. Supprime copie locale après upload réussi
5. Fichier reste accessible via MergerFS

### Phase 8 : Streaming Utilisateur
```
[Utilisateur] → [Jellyfin] → [MergerFS] → [Local OU S3] → [Stream]
```

**Scénarios** :

**Film en Local** :
1. Utilisateur clique sur film dans Jellyfin
2. Jellyfin lit depuis `/novastream/data/media/movies/`
3. MergerFS redirige vers cache local 
4. Streaming direct haute performance

**Film Archivé en S3** :
1. Utilisateur clique sur film archivé
2. Jellyfin demande fichier via MergerFS
3. MergerFS redirige vers montage rclone
4. Rclone télécharge chunks à la demande
5. Cache local temporal pour smooth playback
6. Streaming transparent (utilisateur ne voit pas la différence)

## 🔧 Configuration Critique des Starr Apps

### Radarr - Configuration Films

**Profils Qualité** :
```
- Any (Web-DL/BluRay)
  ├── WebDL-1080p (Preferred)
  ├── BluRay-1080p  
  ├── WebDL-720p
  └── BluRay-720p (Minimum)
```

**Root Folders** :
```
/data/media/movies (via Docker)
= /novastream/data/media/movies (sur host)
= MergerFS(local/cache/media/movies + cloud/media/movies)
```

**Download Clients** :
- **SABnzbd** : Priorité 1 (Usenet)
- **Catégorie** : `movies` → `/complete/movies/`

### Sonarr - Configuration Séries

**Profils Qualité** :
```
- HD-1080p
  ├── WebDL-1080p (Preferred)
  ├── HDTV-1080p
  └── WebDL-720p (Minimum)
```

**Gestion Saisonnière** :
- **Suivi automatique** : Nouvelles saisons détectées
- **Recherche rétroactive** : Episodes manquants recherchés
- **Upgrade automatique** : Meilleure qualité remplace ancienne

### Prowlarr - Configuration Indexeurs

**Indexeurs configurés** :
- **Usenet publics** : NZBgeek, NZBindex, Binsearch
- **Usenet privés** : NZBgeek VIP, DogNZB (selon abonnements)
- **Filtres globaux** :
  - Taille min : 50MB
  - Taille max : 25GB  
  - Langues : FR, EN, Multi
  - Formats exclus : CAM, TS, R5

**Sync Apps** :
- Radarr : Categories Movies, Movies/Foreign, Movies/Other
- Sonarr : Categories TV, TV/Foreign, TV/Anime

## 🔗 Intégrations API et Webhooks

### Jellyseerr ↔ Radarr/Sonarr
```yaml
# Dans Jellyseerr Settings > Services
Radarr:
  - URL: http://radarr:7878
  - API Key: [RADARR_API_KEY]
  - Root Folder: /data/media/movies
  - Quality Profile: Any
  - Minimum Availability: Released

Sonarr:
  - URL: http://sonarr:8989  
  - API Key: [SONARR_API_KEY]
  - Root Folder: /data/media/tv
  - Quality Profile: HD-1080p
  - Language Profile: French/English
```

### Radarr/Sonarr ↔ Prowlarr
```yaml
# Sync automatique des indexeurs
Prowlarr Push:
  - Apps: Radarr, Sonarr
  - Categories: Auto-sync
  - Tags: Quality tags
```

### Radarr/Sonarr ↔ SABnzbd
```yaml
# Download Client Settings
SABnzbd:
  - Host: sabnzbd
  - Port: 8080
  - API Key: [SABNZBD_API_KEY]
  - Category: movies/tv
  - Priority: Normal
  - Recent Priority: High
```

### Notifications Notifiarr
```yaml
# Webhook endpoints pour Discord
Services:
  - Radarr: Movie Downloaded
  - Sonarr: Episode Downloaded  
  - SABnzbd: Download Complete/Failed
  - Jellyfin: New Media Added

Discord Channels:
  - #media-requests (Jellyseerr)
  - #downloads (Radarr/Sonarr)
  - #system-alerts (Errors)
```

## 📊 Monitoring et Métriques

### Métriques Clés à Surveiller

**Performance Téléchargement** :
- Temps moyen film : ~15-45min (selon taille/serveur)
- Temps moyen série : ~5-15min par épisode
- Taux succès : >95% pour indexeurs privés, >80% publics

**Stockage** :
- Cache local : 20-30 films récents (~150GB)
- Archive S3 : Collection complète (300+ films)
- Rotation automatique : 7 jours moyenne avant archivage

**Disponibilité** :
- Délai demande→disponible : 15min-2h selon source
- Uptime services : >99.5% (Docker + healthchecks)
- Streaming performance : <3s démarrage, 0 buffering local

### Logs Importants

**Radarr** : `/opt/stacks/starr/config/radarr/logs/`
**Sonarr** : `/opt/stacks/starr/config/sonarr/logs/`
**SABnzbd** : `/opt/stacks/starr/config/sabnzbd/logs/`
**Prowlarr** : `/opt/stacks/starr/config/prowlarr/logs/`

## 🚨 Points de Défaillance et Solutions

### 1. Indexeurs Hors Service
**Symptôme** : Aucun résultat pour nouvelles demandes
**Solution** : Prowlarr gère automatiquement fallback vers autres indexeurs

### 2. SABnzbd Saturé
**Symptôme** : Queue bloquée, téléchargements lents  
**Solution** : Priorités configurées, pause automatique si espace bas

### 3. Espace Disque Local Plein
**Symptôme** : Téléchargements échouent
**Solution** : Scripts automatiques forcent archivage S3

### 4. Métadonnées Manquantes
**Symptôme** : Films sans poster/synopsis
**Solution** : Jellyfin refresh metadata, sources multiples (TMDB/TVDB)

### 5. Qualité Non Souhaitée
**Symptôme** : Films en 720p au lieu de 1080p
**Solution** : Ajustement profils qualité, recherche manuelle si besoin

## ⚡ Optimisations Performance

### Starr Apps
- **Refresh Interval** : 15min (assez fréquent sans spam)
- **RSS Sync** : 5min pour indexeurs rapides
- **History Cleanup** : 30 jours (économie espace DB)
- **Parallel Tasks** : 2-3 max (évite surcharge)

### SABnzbd
- **Connections** : 20-30 par serveur Usenet
- **Cache** : 1GB RAM pour extraction rapide
- **Post-processing** : Scripts custom pour notifications

### Jellyfin
- **Hardware Transcoding** : Intel QuickSync activé
- **Metadata Refresh** : Automatique sur nouveaux fichiers
- **Library Scan** : Real-time via inotify (Linux)

Cette architecture garantit un flux automatisé complet de la demande utilisateur au streaming, avec gestion intelligente du stockage et performance optimale ! 🎬✨