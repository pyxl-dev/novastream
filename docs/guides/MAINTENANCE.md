# Checklist de Maintenance Novastream

## 📅 Maintenance Quotidienne (Automatique)

### Scripts Automatiques Configurés
- ✅ `check_space.sh` - Toutes les 15 minutes
- ✅ `move_inactive.sh` - Toutes les 3 heures  
- ✅ Docker prune - Chaque nuit à 00h00

### Vérification Manuelle Rapide (2 minutes)
```bash
# Script de check global
./scripts/check_jellyfin_ready.sh
```

**Indicateurs à surveiller :**
- 🟢 Espace disque < 80%
- 🟢 Films accessibles > 5
- 🟢 Montages rclone + mergerfs actifs
- 🟢 Jellyfin running
- 🟢 Aucun processus rclone move bloqué

## 📅 Maintenance Hebdomadaire (10 minutes)

### Dimanche Soir - Nettoyage Approfondi

**1. Vérification de l'Intégrité S3**
```bash
# Structure S3 complète
rclone tree $S3_REMOTE --human-readable --max-depth 3

# Compter films dans S3 vs local
echo "Films en S3: $(rclone ls $S3_REMOTE/media/movies --include "*.mkv" | wc -l)"
echo "Films accessibles: $(find /novastream/data/media/movies/ -name "*.mkv" | wc -l)"
```

**2. Nettoyage des Logs**
```bash
# Nettoyer logs > 30 jours
find /var/log/novastream/ -name "*.log" -mtime +30 -delete

# Garder seulement 1000 dernières lignes des logs actifs
tail -1000 /var/log/novastream/space_cleanup.log > /tmp/cleanup.log
mv /tmp/cleanup.log /var/log/novastream/space_cleanup.log
```

**3. Optimisation Cache**
```bash
# Nettoyer cache rclone si > 8GB
CACHE_SIZE=$(du -s /novastream/local/cache/rclone_vfs/ | cut -f1)
if [ $CACHE_SIZE -gt 8388608 ]; then  # 8GB en KB
    echo "Cache rclone volumineux ($(($CACHE_SIZE/1024/1024))GB), nettoyage..."
    rm -rf /novastream/local/cache/rclone_vfs/*
fi

# Redémarrer rclone si nécessaire
if [ $CACHE_SIZE -gt 8388608 ]; then
    fusermount3 -u /novastream/cloud
    $HOME/fix_jellyfin_access.sh
fi
```

**4. Correction Permissions Jellyfin**
```bash
# Vérifier s'il y a des fichiers root (créés par Jellyfin Docker)
ROOT_FILES=$(find /novastream/local/cache/media -user root 2>/dev/null | wc -l)
if [ $ROOT_FILES -gt 0 ]; then
    echo "Correction de $ROOT_FILES fichiers avec permissions root..."
    sudo chown -R $USER:$USER /novastream/local/cache/media/
    echo "Permissions corrigées"
else
    echo "Permissions OK (pas de fichiers root)"
fi
```

**5. Vérification Docker**
```bash
cd /opt/stacks/jelly
docker compose ps
docker compose logs --tail=50 jellyfin
```

## 📅 Maintenance Mensuelle (30 minutes)

### Premier Dimanche du Mois

**1. Sauvegarde Configuration**
```bash
# Créer dossier backup mensuel
mkdir -p $HOME/backups/$(date +%Y-%m)

# Sauvegarder configurations critiques
cp /etc/fstab $HOME/backups/$(date +%Y-%m)/
cp /etc/systemd/system/rclone-s3.service $HOME/backups/$(date +%Y-%m)/
cp -r /opt/stacks/jelly/ $HOME/backups/$(date +%Y-%m)/
cp /etc/s3-notify.conf $HOME/backups/$(date +%Y-%m)/

# Sauvegarder structure S3
rclone tree $S3_REMOTE > $HOME/backups/$(date +%Y-%m)/s3_structure.txt
rclone ls $S3_REMOTE --include "*.mkv" > $HOME/backups/$(date +%Y-%m)/s3_movies.txt
```

**2. Audit de Sécurité**
```bash
# Vérifier permissions critiques
ls -la /novastream/
ls -la /opt/stacks/jelly/

# Vérifier utilisateurs avec accès rclone
ls -la ~/.config/rclone/

# Vérifier cron jobs actifs
crontab -l
```

**3. Test de Recovery**
```bash
# Test de restauration depuis S3 (sur un fichier test)
# Créer un petit fichier test
echo "test" > /tmp/recovery_test.txt
rclone copy /tmp/recovery_test.txt $S3_REMOTE/test/

# Vérifier qu'on peut le récupérer
rclone copy $S3_REMOTE/test/recovery_test.txt /tmp/recovered_test.txt
diff /tmp/recovery_test.txt /tmp/recovered_test.txt

# Nettoyer
rclone purge $S3_REMOTE/test/
rm /tmp/*test.txt
```

**4. Analyse Performance**
```bash
# Statistiques d'utilisation
echo "=== STATS MENSUELLES ==="
echo "Espace total utilisé en S3:"
rclone size $S3_REMOTE --human-readable

echo "Cache local moyen:"
du -sh /novastream/local/cache/

echo "Nombre total de films:"
rclone ls $S3_REMOTE --include "*.mkv" | wc -l

echo "Films ajoutés ce mois:"
find /novastream/data/media/movies/ -name "*.mkv" -mtime -30 | wc -l
```

## 📅 Maintenance Trimestrielle (1 heure)

### Chaque 3 Mois - Révision Complète

**1. Audit de Capacité**
```bash
# Projection croissance
echo "Croissance stockage S3 (3 derniers mois):"
# Analyser les logs d'upload pour calculer la tendance

# Vérifier limites Scaleway
rclone about $S3_REMOTE
```

**2. Optimisation Scripts**
```bash
# Réviser seuils des scripts de nettoyage
echo "Seuils actuels dans check_space.sh:"
grep -E "(THRESHOLD|MIN_AGE)" /usr/local/bin/check_space.sh

# Analyser efficacité
echo "Nettoyages d'urgence déclenchés (3 derniers mois):"
grep -c "Espace disque local critique" /var/log/novastream/space_cleanup.log
```

**3. Mise à Jour Système**
```bash
# Vérifier versions
echo "Version rclone: $(rclone version | head -1)"
echo "Version Docker: $(docker --version)"

# Sauvegarder avant mise à jour
$HOME/backups/backup_before_update.sh

# Mettre à jour si nécessaire (avec prudence)
# sudo apt update && sudo apt upgrade
# docker compose pull  # Depuis /opt/stacks/jelly/
```

## 🚨 Maintenance d'Urgence

### Procédures d'Urgence

**Espace Disque Critique (>95%)**
```bash
# 1. Upload immédiat
./scripts/emergency_s3_upload.sh

# 2. Nettoyage brutal si nécessaire
rm -rf /novastream/local/cache/rclone_vfs/*
docker system prune -af

# 3. Arrêt services non critiques
cd /opt/stacks/jelly && docker compose stop jellyseerr jellystat

# 4. Alerte
curl -d "{\"content\":\"🚨 URGENCE: Espace disque critique, intervention manuelle requise\"}" \
     -H "Content-Type: application/json" \
     "$DISCORD_WEBHOOK"
```

**Panne S3 / Connectivité**
```bash
# 1. Basculer en mode local uniquement
fusermount3 -u /novastream/cloud
umount /novastream/data

# 2. Monter uniquement le cache local
mount --bind /novastream/local/cache /novastream/data

# 3. Notifier que seuls les films en cache sont disponibles
```

**Corruption Structure S3**
```bash
# 1. Sauvegarde état corrompu
rclone tree $S3_REMOTE > /tmp/corrupted_structure.txt

# 2. Script de nettoyage
rclone dedupe --dry-run "$S3_REMOTE/media"  # verifier les doublons avant tout deplacement

# 3. Si trop corrompu, reconstruction manuelle
# Identifier films valides et les regrouper dans media/movies/
```

## 📊 Métriques de Santé

### KPIs à Surveiller

**Quotidien**
- ✅ Espace disque < 80%
- ✅ Films accessibles = Films en S3 (±2)
- ✅ Temps réponse Jellyfin < 3s
- ✅ 0 processus rclone bloqués

**Hebdomadaire**  
- ✅ Cache rclone < 8GB
- ✅ Logs sans erreurs critiques
- ✅ Upload automatique fonctionne

**Mensuel**
- ✅ Croissance S3 prévisible
- ✅ Aucune perte de fichiers
- ✅ Performance stable

## 🛠️ Scripts de Maintenance

### Script Maintenance Hebdomadaire
```bash
#!/bin/bash
# $HOME/weekly_maintenance.sh

echo "=== MAINTENANCE HEBDOMADAIRE $(date) ==="

# 1. Vérifications santé
./scripts/check_jellyfin_ready.sh

# 2. Nettoyage logs
find /var/log/novastream/ -name "*.log" -mtime +7 -delete

# 3. Optimisation cache
CACHE_SIZE=$(du -s /novastream/local/cache/rclone_vfs/ | cut -f1)
echo "Cache rclone: $(($CACHE_SIZE/1024/1024))GB"

if [ $CACHE_SIZE -gt 8388608 ]; then
    echo "Nettoyage cache rclone..."
    fusermount3 -u /novastream/cloud
    rm -rf /novastream/local/cache/rclone_vfs/*
    $HOME/fix_jellyfin_access.sh
fi

# 4. Statistiques
echo "Films en S3: $(rclone ls $S3_REMOTE/media/movies --include "*.mkv" | wc -l)"
echo "Films accessibles: $(find /novastream/data/media/movies/ -name "*.mkv" | wc -l)"

# 5. Test accès S3
rclone ls $S3_REMOTE --max-items 1 > /dev/null
echo "Test S3: $([[ $? -eq 0 ]] && echo "OK" || echo "ERREUR")"

echo "Maintenance hebdomadaire terminée"
```

### Automatisation
Ajouter à crontab :
```bash
# Maintenance hebdomadaire - Dimanche 02h00
0 2 * * 0 $HOME/weekly_maintenance.sh >> /var/log/novastream/weekly_maintenance.log
```

## ✅ Checklist Post-Maintenance

Après chaque maintenance, vérifier :

- [ ] Jellyfin accessible sur http://localhost:8096
- [ ] Au moins 5 films visibles dans la bibliothèque
- [ ] Lecture d'un film fonctionne (test 30 secondes)
- [ ] Espace disque < 80%
- [ ] Pas d'erreurs dans les logs récents
- [ ] Notifications Discord reçues si configurées
- [ ] Processus rclone mount actif
- [ ] MergerFS monté correctement

**En cas de problème détecté**, utiliser :
```bash
./scripts/check_jellyfin_ready.sh
```

Et si nécessaire :
```bash
$HOME/auto_fix.sh  # (à créer depuis le guide troubleshooting)
```

Cette maintenance préventive garantit un système Novastream stable et performant ! 🔧✨