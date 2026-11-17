# 🛠️ Guide de Troubleshooting Starr Apps - Novastream

## Vue d'Ensemble

Ce guide couvre les problèmes courants et leurs solutions pour les Starr Apps de votre écosystème Novastream :
- **Radarr** (Films) - Port 7878
- **Sonarr** (Séries TV) - Port 8989
- **Prowlarr** (Indexeurs) - Port 9696
- **SABnzbd** (Téléchargement Usenet) - Port 8080

## 🚨 Diagnostic Rapide

### Vérification de l'État des Services
```bash
# Statut des conteneurs
docker ps | grep -E "(radarr|sonarr|prowlarr|sabnzbd)"

# Logs en temps réel
docker logs -f radarr
docker logs -f sonarr
docker logs -f prowlarr
docker logs -f sabnzbd
```

### URLs d'Accès
- Radarr: http://server:7878
- Sonarr: http://server:8989  
- Prowlarr: http://server:9696
- SABnzbd: http://server:8080

## 🎬 Radarr - Troubleshooting Films

### Problème : Films Non Trouvés
**Symptômes** :
- Recherche ne retourne aucun résultat
- Status "Missing" persiste après recherche

**Solutions** :
1. **Vérifier Prowlarr** :
   ```bash
   # Tester la connexion Radarr → Prowlarr
   curl -H "X-Api-Key: YOUR_RADARR_API_KEY" \
        http://localhost:7878/api/v3/indexer/test/all
   ```

2. **Vérifier les Indexeurs** :
   - Aller dans Settings > Indexers
   - Tester chaque indexeur : bouton "Test"
   - Supprimer les indexeurs en erreur

3. **Ajuster les Critères de Recherche** :
   - Movies > Film > Search Options
   - Réduire les filtres de qualité temporairement
   - Vérifier le titre original vs titre français

### Problème : Téléchargements Bloqués
**Symptômes** :
- Status "Queued" qui ne change pas
- Downloads clients en erreur

**Solutions** :
1. **Vérifier SABnzbd** :
   ```bash
   # Status SABnzbd
   curl http://localhost:8080/api?mode=queue\&apikey=YOUR_SABNZBD_API_KEY
   ```

2. **Reconfigurer Download Client** :
   - Settings > Download Clients > SABnzbd
   - Test Connection
   - Vérifier API Key et catégorie "movies"

3. **Nettoyer la Queue** :
   ```bash
   # Supprimer downloads bloqués
   # Dans SABnzbd Web UI > Queue > Delete
   ```

### Problème : Post-Processing Échoue
**Symptômes** :
- Films téléchargés mais pas importés
- Erreurs "Unable to move file"

**Solutions** :
1. **Vérifier Permissions** :
   ```bash
   # Fix permissions critiques
   sudo chown -R $USER:$USER /novastream/local/cache/
   sudo chown -R $USER:$USER /novastream/data/media/movies/
   ```

2. **Vérifier Paths** :
   - Settings > Media Management > Root Folders
   - Doit pointer vers `/data/media/movies` (dans container)
   - Équivaut à `/novastream/data/media/movies` sur host

3. **Logs Détaillés** :
   ```bash
   # Logs Radarr spécifiques au post-processing
   docker exec radarr tail -f /config/logs/radarr.txt | grep -i "import"
   ```

## 📺 Sonarr - Troubleshooting Séries

### Problème : Épisodes Manqués
**Symptômes** :
- Nouveaux épisodes non détectés
- Series monitoring actif mais pas de téléchargement

**Solutions** :
1. **Vérifier RSS Sync** :
   - Settings > General > Updates
   - RSS Sync Interval : 15 minutes maximum
   - Forcer refresh : Series > Update Series

2. **Vérifier Season Monitoring** :
   - Series > Season > Monitor bouton
   - Vérifier que saisons actuelles sont monitored

3. **Recherche Manuelle** :
   - Series > Season > Search bouton
   - Wanted > Missing > Search Selected

### Problème : Mauvaise Qualité Téléchargée
**Symptômes** :
- Episodes en 720p au lieu de 1080p
- Formats non désirés (HDTV vs WEB-DL)

**Solutions** :
1. **Ajuster Profiles de Qualité** :
   - Settings > Profiles > Quality Profiles
   - HD-1080p : Réordonner préférences
   - WEB-DL 1080p en premier, HDTV 1080p en dernier

2. **Custom Formats** (Avancé) :
   ```json
   // Settings > Custom Formats
   {
     "name": "Preferred WEB-DL",
     "conditions": [{
       "implementation": "ReleaseTitleSpecification",
       "value": "WEB-DL|WEBDL"
     }],
     "score": 10
   }
   ```

### Problème : Import Échoue pour Séries
**Symptômes** :
- "No files found are eligible for import"
- Episodes téléchargés mais pas dans Sonarr

**Solutions** :
1. **Vérifier Naming** :
   - Fichier doit être : `Series.S01E01.Episode.Title.1080p.WEB-DL.mkv`
   - Settings > Media Management > Episode Naming

2. **Manual Import** :
   - Activity > Manual Import
   - Browse `/data/usenet/complete/tv/`
   - Import fichiers manuellement

## 🔍 Prowlarr - Troubleshooting Indexeurs

### Problème : Indexeurs Fréquemment en Erreur
**Symptômes** :
- Indexeurs status "Red" 
- Rate limiting messages

**Solutions** :
1. **Optimiser Requêtes** :
   - Settings > General > Query Limit: 200/jour pour indexeurs gratuits
   - Stagger requests : 2-5 secondes entre requêtes

2. **Rotation des Indexeurs** :
   ```bash
   # Désactiver temporairement indexeurs problématiques
   # Prowlarr > Indexers > Toggle Enable
   ```

3. **Indexeurs de Backup** :
   - Configurer 15-20 indexeurs variés
   - Mix public/privé pour redondance

### Problème : Sync Apps Échoue
**Symptômes** :
- Radarr/Sonarr ne reçoivent pas indexeurs de Prowlarr
- Apps show "No indexers available"

**Solutions** :
1. **Reconfigurer Apps** :
   - Settings > Apps > Radarr/Sonarr
   - Test Connection : vérifier API keys
   - Full Sync : forcer resync complet

2. **Vérifier Catégories** :
   - Apps > Categories : Movies, TV appropriées
   - Tags matching si utilisés

## 📥 SABnzbd - Troubleshooting Downloads

### Problème : Downloads Très Lents
**Symptômes** :
- Vitesse < 1MB/s alors que connexion permet plus
- Downloads qui trainent en heures

**Solutions** :
1. **Optimiser Connexions** :
   - Config > Servers > Connections: 20-30 par serveur
   - Multiple servers si disponibles

2. **Vérifier Serveurs Usenet** :
   ```bash
   # Test vitesse serveur
   # Config > Servers > Test Server
   ```

3. **Ajuster Cache** :
   - Config > General > Article Cache: 1024MB
   - RAM disponible permettant

### Problème : Extractions Échouent
**Symptômes** :
- Downloads completed mais pas extraits
- RAR files restent en queue

**Solutions** :
1. **Vérifier Outils** :
   ```bash
   # Dans container SABnzbd
   docker exec sabnzbd which unrar
   docker exec sabnzbd which par2
   ```

2. **Configuration Post-Processing** :
   - Config > Switches
   - Enable Direct Unpack: ON
   - Enable Par Cleanup: ON

### Problème : Disk Space Errors
**Symptômes** :
- "Not enough disk space" même avec espace libre
- Downloads pausés automatiquement

**Solutions** :
1. **Nettoyer Download History** :
   - History > Clear History (older than 1 month)

2. **Vérifier Quotas Docker** :
   ```bash
   # Espace containers
   docker system df
   
   # Espace volumes
   df -h /novastream/local/usenet/
   ```

3. **Emergency Cleanup** :
   ```bash
   # Lancer script space management
   ./scripts/check_space_fixed.sh
   ```

## 🔄 Problèmes Inter-Services

### Jellyseerr → Radarr/Sonarr Non Fonctionnel
**Symptômes** :
- Requests restent "Pending" dans Jellyseerr
- Pas d'ajout automatique dans Radarr/Sonarr

**Solutions** :
1. **Vérifier Connexions API** :
   ```bash
   # Test Jellyseerr → Radarr
   curl -H "X-Api-Key: RADARR_API_KEY" \
        http://radarr:7878/api/v3/system/status
   ```

2. **Reconfigurer Services Jellyseerr** :
   - Settings > Services > Radarr/Sonarr
   - Test Connection
   - Vérifier URL: `http://radarr:7878` (hostname Docker)

### Radarr/Sonarr → Jellyfin Import Lent
**Symptômes** :
- Films/séries téléchargés mais pas dans Jellyfin
- Délai > 1 heure entre download et disponibilité

**Solutions** :
1. **Forcer Scan Jellyfin** :
   - Dashboard > Libraries > Scan Library
   - Settings > Library > Real-time monitoring

2. **Vérifier MergerFS Mount** :
   ```bash
   # Status mergerfs
   mount | grep mergerfs
   
   # Test écriture
   touch /novastream/data/media/movies/test_file
   ls -la /novastream/local/cache/media/movies/test_file
   ```

## 📊 Monitoring et Alertes

### Métriques à Surveiller
```bash
# Script de monitoring quotidien
#!/bin/bash
echo "=== Status Starr Apps ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(radarr|sonarr|prowlarr|sabnzbd)"

echo "=== Queue Status ==="
# SABnzbd queue non-empty
curl -s "http://localhost:8080/api?mode=qstatus&output=json&apikey=YOUR_API" | jq '.jobs | length'

# Wanted movies/shows
echo "Movies Wanted:" $(curl -s -H "X-Api-Key: YOUR_RADARR_API" http://localhost:7878/api/v3/wanted/missing | jq '.totalRecords')
echo "Episodes Wanted:" $(curl -s -H "X-Api-Key: YOUR_SONARR_API" http://localhost:8989/api/v3/wanted/missing | jq '.totalRecords')
```

### Alertes Critiques Discord (via Notifiarr)
- Downloads failed > 3 en 1h
- Indexeurs down > 50%
- Disk space < 30%
- Services restart > 5 fois/jour

## 🔧 Maintenance Préventive

### Hebdomadaire
```bash
#!/bin/bash
# Nettoyage logs anciens
find /opt/stacks/starr/config/*/logs/ -name "*.txt" -mtime +30 -delete

# Nettoyage history downloads
curl -X DELETE "http://localhost:8080/api?mode=history&name=delete&value=completed&apikey=YOUR_API"

# Test santé indexeurs
curl "http://localhost:9696/api/v1/indexer/test/all" -H "X-Api-Key: YOUR_PROWLARR_API"
```

### Mensuel
- Backup configurations : `/opt/stacks/starr/config/`
- Vérifier versions images Docker : `docker images | grep hotio`
- Review qualité profiles selon nouveaux releases
- Ajuster indexeurs selon performance stats

## 🆘 Recovery Procedures

### Reset Complet d'une Starr App
```bash
# Exemple pour Radarr
docker stop radarr
mv /opt/stacks/starr/config/radarr /opt/stacks/starr/config/radarr_backup_$(date +%Y%m%d)
mkdir /opt/stacks/starr/config/radarr
docker start radarr
# Reconfigurer via Web UI
```

### Import Massif après Reset
1. **Radarr** : Settings > Import Lists > Add Existing Movies
2. **Sonarr** : Settings > Import Lists > Add Existing Series  
3. **Prowlarr** : Apps > Force Full Sync

Cette documentation complète les guides existants avec un focus troubleshooting pour maintenir votre écosystème Novastream opérationnel ! 🎬✨