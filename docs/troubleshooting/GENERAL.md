# Guide de Dépannage Novastream

## Problèmes les Plus Fréquents

### 🚨 1. Jellyfin Vide ou Films Manquants

#### Symptômes
- Bibliothèque Jellyfin vide
- Certains films manquants
- Films visibles hier mais plus aujourd'hui

#### Diagnostic
```bash
# Vérifier nombre de films accessibles
find /novastream/data/media/movies/ -name "*.mkv" | wc -l

# Vérifier les montages
mount | grep -E "(rclone|mergerfs)"

# Vérifier structure S3
rclone lsd $S3_REMOTE/media/movies | head -10
```

#### Solutions par Ordre de Priorité

**Solution 1 - Redémarrage Simple**
```bash
cd /opt/stacks/jelly && docker compose restart jellyfin
```
Puis scanner la bibliothèque dans l'interface Jellyfin.

**Solution 2 - Problème de Cache rclone**
```bash
# Redémarrer rclone avec cache court
fusermount3 -u /novastream/cloud
rclone mount $S3_REMOTE/ /novastream/cloud \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --vfs-cache-max-age 24h \
    --cache-dir /novastream/local/cache/rclone_vfs \
    --vfs-read-chunk-size 32M \
    --vfs-read-ahead 128M \
    --dir-cache-time 30s \
    --allow-other \
    --allow-non-empty \
    --log-level INFO \
    --daemon
```

**Solution 3 - Structure S3 Corrompue**
```bash
# Diagnostic complet
rclone tree $S3_REMOTE --max-depth 3

# Si films dans mauvais endroit (movies/ au lieu de media/movies/)
rclone move $S3_REMOTE/movies/ $S3_REMOTE/media/movies/
```

### 🚨 2. Espace Disque Plein (>90%)

#### Symptômes
- Erreur "No space left on device"
- Services qui s'arrêtent
- Téléchargements qui échouent

#### Diagnostic
```bash
df -h /
du -sh /novastream/local/cache/* | sort -rh
```

#### Solutions Immédiates

**Solution d'Urgence - Upload Automatique**
```bash
./scripts/emergency_s3_upload.sh
```

**Nettoyage Manuel**
```bash
# Identifier les gros fichiers
find /novastream/local/cache/media -name "*.mkv" -exec du -sh {} \; | sort -rh | head -10

# Upload manuel des plus gros
rclone move "/chemin/vers/gros/film/" "${S3_REMOTE:-s3remote:media-bucket}/media/movies/" --log-level INFO
```

**Vérifier Scripts de Nettoyage**
```bash
# Logs des scripts automatiques
tail -50 /var/log/novastream/space_cleanup.log

# Forcer nettoyage si bloqué
pkill -f "rclone move"  # Tuer processus bloqués
/usr/local/bin/check_space.sh  # Relancer manuellement
```

### 🚨 3. Films Non Lisibles (Erreur de Lecture)

#### Symptômes
- Erreur "Playback Error" dans Jellyfin
- Film s'arrête ou ne démarre pas
- Buffering infini

#### Diagnostic
```bash
# Tester accès au fichier
ls -la "/novastream/data/media/movies/[NOM_FILM]/"

# Vérifier si le fichier est dans S3
rclone ls "${S3_REMOTE:-s3remote:media-bucket}/media/movies/[NOM_FILM]/" --include "*.mkv"

# Tester téléchargement d'un petit chunk
rclone copy "${S3_REMOTE:-s3remote:media-bucket}/media/movies/[NOM_FILM]/film.mkv" /tmp/ --max-size 100M
```

#### Solutions
```bash
# Redémarrer rclone pour reconnecter S3
fusermount3 -u /novastream/cloud
# Puis remonter avec configuration standard
$HOME/fix_jellyfin_access.sh

# Si problème persiste, vérifier intégrité du fichier
rclone check "${S3_REMOTE:-s3remote:media-bucket}/media/movies/[NOM_FILM]/film.mkv" /dev/null
```

### 🚨 4. Processus rclone Bloqués

#### Symptômes
- Upload qui n'avance pas
- Commandes rclone qui ne répondent pas
- Espace disque qui ne se libère pas

#### Diagnostic
```bash
ps aux | grep rclone
```

#### Solution
```bash
# Tuer tous les processus rclone move
pkill -f "rclone move"

# Attendre 30 secondes puis vérifier
sleep 30
ps aux | grep rclone | grep -v mount

# Si nécessaire, kill brutal
pkill -9 -f rclone
```

### 🚨 5. Erreurs de Permissions (Fichiers .trickplay)

#### Symptômes
- Erreurs "permission denied" dans les logs rclone
- Messages "Couldn't delete" sur fichiers .trickplay
- Processus rclone move qui se bloquent
- Logs montrent "not deleting directories as there were IO errors"

#### Cause
Jellyfin (Docker) crée des fichiers .trickplay en tant que root, mais rclone tourne sous ton utilisateur.

#### Diagnostic
```bash
# Vérifier les permissions problématiques
find /novastream/local/cache/media -name "*.trickplay" -type d -exec ls -la {} \;

# Chercher fichiers appartenant à root
find /novastream/local/cache/media -user root | head -10

# Vérifier logs rclone pour "permission denied"
tail -50 ./logs/emergency_upload.log | grep "permission denied"
```

#### Solutions

**Solution Rapide**
```bash
# Corriger toutes les permissions
sudo chown -R $USER:$USER /novastream/local/cache/media/

# Ou utiliser le script dédié
./scripts/fix_permissions.sh
```

**Vérification**
```bash
# Vérifier qu'il ne reste plus de fichiers root
find /novastream/local/cache/media -user root | wc -l
# Doit retourner 0

# Vérifier que les processus bloqués sont terminés
ps aux | grep "rclone move" | grep -v grep
```

**Prévention**
```bash
# Ajouter à la maintenance hebdomadaire
sudo chown -R $USER:$USER /novastream/local/cache/media/

# Ou configurer Jellyfin pour utiliser le bon utilisateur (avancé)
```

### 🚨 6. Structure S3 Désorganisée

#### Symptômes
- Films dans `movies/` au lieu de `media/movies/`
- Fichiers .mkv isolés sans leur dossier
- Dossiers .trickplay orphelins

#### Diagnostic
```bash
rclone tree $S3_REMOTE --max-depth 3
```

#### Solution - Nettoyage Automatique
```bash
rclone dedupe --dry-run "$S3_REMOTE/media"  # verifier les doublons avant tout deplacement
```

#### Solution - Nettoyage Manuel
```bash
# Déplacer films mal placés
rclone move $S3_REMOTE/movies/ $S3_REMOTE/media/movies/

# Regrouper fichiers .mkv isolés
rclone move "${S3_REMOTE:-s3remote:media-bucket}/media/movies/film.mkv" "${S3_REMOTE:-s3remote:media-bucket}/media/movies/Film (2025)/"

# Nettoyer orphelins
rclone purge "${S3_REMOTE:-s3remote:media-bucket}/media/movies/Film.trickplay"
```

## Commandes de Diagnostic Rapide

### Script de Santé Globale
```bash
./scripts/check_jellyfin_ready.sh
```

### Vérifications Manuelles
```bash
# 1. État des montages
mount | grep -E "(rclone|mergerfs)"

# 2. Espace disque
df -h / | grep vda1

# 3. Nombre de films accessibles
find /novastream/data/media/movies/ -name "*.mkv" | wc -l

# 4. Processus suspects
ps aux | grep -E "(rclone|jellyfin)" | grep -v grep

# 5. Logs récents
tail -20 /var/log/novastream/space_cleanup.log
```

## Procédures de Recovery

### Recovery Complète (En Cas de Gros Problème)

**1. Sauvegarde État Actuel**
```bash
rclone tree $S3_REMOTE > /tmp/s3_structure_backup.txt
mount > /tmp/mount_backup.txt
```

**2. Arrêt Propre des Services**
```bash
cd /opt/stacks/jelly && docker compose down
pkill -f rclone
fusermount3 -u /novastream/cloud
umount /novastream/data
```

**3. Nettoyage Complet**
```bash
rm -rf /novastream/local/cache/rclone_vfs/*
```

**4. Redémarrage Étape par Étape**
```bash
# Remonter rclone
rclone mount $S3_REMOTE/ /novastream/cloud \
    --vfs-cache-mode full \
    --vfs-cache-max-size 10G \
    --vfs-cache-max-age 24h \
    --cache-dir /novastream/local/cache/rclone_vfs \
    --vfs-read-chunk-size 32M \
    --vfs-read-ahead 128M \
    --dir-cache-time 30s \
    --allow-other \
    --allow-non-empty \
    --log-level INFO \
    --daemon

# Remonter mergerfs
mount -a

# Vérifier que tout est OK
sleep 10
find /novastream/data/media/movies/ -name "*.mkv" | wc -l

# Redémarrer Jellyfin
cd /opt/stacks/jelly && docker compose up -d
```

### Recovery Partielle (Films Perdus)

Si certains films ont "disparu" :

**1. Recherche dans S3**
```bash
# Chercher tous les .mkv dans S3
rclone ls $S3_REMOTE --include "*.mkv" | grep -i "[nom_film]"

# Lister tous les répertoires
rclone lsd $S3_REMOTE -R | grep -i "[nom_film]"
```

**2. Relocalisation**
```bash
# Si trouvé dans mauvais endroit
rclone move "scaleway:source/path/" "${S3_REMOTE:-s3remote:media-bucket}/media/movies/"
```

**3. Reconstruction Métadonnées Locales**
```bash
# Si seules les métadonnées locales manquent
mkdir -p "/novastream/local/cache/media/movies/[NOM_FILM]"
# Jellyfin va recréer les métadonnées au prochain scan
```

## Scripts d'Urgence

### Script de Check Rapide
```bash
#!/bin/bash
# $HOME/quick_check.sh

echo "=== QUICK CHECK ==="
echo "Date: $(date)"

# Espace disque
DISK_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
echo "💾 Espace disque: ${DISK_USAGE}%"

# Films accessibles
MOVIE_COUNT=$(find /novastream/data/media/movies/ -name "*.mkv" 2>/dev/null | wc -l)
echo "🎬 Films accessibles: ${MOVIE_COUNT}"

# Montages
if mount | grep -q rclone; then
    echo "✅ rclone monté"
else  
    echo "❌ rclone non monté"
fi

if mount | grep -q mergerfs; then
    echo "✅ mergerfs monté"
else
    echo "❌ mergerfs non monté" 
fi

# Processus suspects
RCLONE_MOVES=$(ps aux | grep "rclone move" | grep -v grep | wc -l)
if [ $RCLONE_MOVES -gt 0 ]; then
    echo "⚠️  ${RCLONE_MOVES} processus rclone move en cours"
fi

# Jellyfin
if docker ps | grep -q jellyfin; then
    echo "✅ Jellyfin running"
else
    echo "❌ Jellyfin arrêté"
fi
```

### Script de Réparation Auto
```bash
#!/bin/bash
# $HOME/auto_fix.sh

echo "=== AUTO REPAIR NOVASTREAM ==="

# Fix 1: Redémarrer Jellyfin
echo "Redémarrage Jellyfin..."
cd /opt/stacks/jelly && docker compose restart jellyfin

# Fix 2: Nettoyer processus bloqués
echo "Nettoyage processus bloqués..."
pkill -f "rclone move" 2>/dev/null || true

# Fix 3: Vérifier montages
if ! mount | grep -q rclone; then
    echo "Remontage rclone..."
    $HOME/fix_jellyfin_access.sh
fi

# Fix 4: Upload d'urgence si espace critique
DISK_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
if [ $DISK_USAGE -gt 85 ]; then
    echo "Espace critique - Upload d'urgence..."
    ./scripts/emergency_s3_upload.sh &
fi

echo "Réparations terminées"
```

## Monitoring et Alertes

### Surveillance Automatique
Ajouter à crontab :
```bash
# Vérification toutes les heures
0 * * * * $HOME/quick_check.sh >> /var/log/novastream/hourly_check.log

# Réparation automatique en cas de problème (optionnel)
# */30 * * * * $HOME/auto_fix.sh >> /var/log/novastream/auto_fix.log
```

### Alertes Discord
Les scripts envoient déjà des notifications Discord configurées dans `/etc/s3-notify.conf`.

Pour ajouter d'autres alertes :
```bash
# Alerte si espace > 90%
DISK_USAGE=$(df --output=pcent / | tail -1 | tr -d '% ')
if [ $DISK_USAGE -gt 90 ]; then
    curl -H "Content-Type: application/json" -X POST \
        -d "{\"content\":\"🚨 **ALERTE ESPACE DISQUE**\\nUtilisation: ${DISK_USAGE}%\\nIntervention requise !\"}" \
        "$DISCORD_WEBHOOK"
fi
```

## Contacts et Support

- **Documentation** : `./scripts/`
- **Logs** : `/var/log/novastream/`  
- **Scripts** : `/usr/local/bin/` et `./scripts/`
- **Configuration** : `/opt/stacks/jelly/compose.yaml`, `/etc/fstab`

En cas de problème complexe, toujours commencer par `./scripts/check_jellyfin_ready.sh` ! 🔧