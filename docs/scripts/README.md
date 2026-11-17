# 🛠️ Scripts NovaStream

Collection des scripts d'administration et maintenance automatique.

## 📂 **Scripts Disponibles**

### 🔧 **Maintenance & Diagnostic**
- **`check_jellyfin_ready.sh`** - Diagnostic complet du système
- **`fix_permissions.sh`** - Correction des permissions fichiers
- **`monitor_upload.sh`** - Surveillance des uploads S3

### 🚨 **Urgence & Recovery**
- **`emergency_s3_upload.sh`** - Upload forcé vers S3 (libère l'espace)
- **`upload_completion_notifier.sh`** - Notifications de fin d'upload

### ⚙️ **Automatisation**
- **`check_space_fixed.sh`** - Nettoyage automatique (cron)
- **`move_inactive_fixed.sh`** - Migration fichiers inactifs

## 🚀 **Utilisation**

### Diagnostic Rapide
```bash
# Vérification complète du système (30s)
./check_jellyfin_ready.sh

# État détaillé avec recommandations
./check_jellyfin_ready.sh --verbose
```

### Gestion Espace
```bash
# Upload d'urgence si espace critique
./emergency_s3_upload.sh

# Nettoyage manuel structure S3
```

### Monitoring
```bash
# Surveiller uploads en cours
./monitor_upload.sh

# Logs temps réel
tail -f ../logs/*.log
```

## 🔄 **Automatisation**

Ces scripts sont programmés via cron :
```bash
*/15 * * * * /path/to/check_space_fixed.sh      # Nettoyage auto
0 */3 * * * /path/to/move_inactive_fixed.sh     # Migration inactive  
0 0 * * * /usr/bin/docker system prune -f       # Nettoyage Docker
```

## 📊 **Logs & Monitoring**

Tous les scripts génèrent des logs dans `../logs/` :
- Exécutions réussies et échecs
- Timing et performance
- Notifications Discord intégrées

## ⚠️ **Précautions**

- **Tester avec `--dry-run`** avant modification importante
- **Un seul `rclone move` à la fois** (éviter conflits)
- **Vérifier structure S3** après changements majeurs