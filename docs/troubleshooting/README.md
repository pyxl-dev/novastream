# 🔧 Guide de Dépannage NovaStream

Index des solutions pour les problèmes courants du système NovaStream.

## 🚨 **Problèmes Urgents**

### Films Manquants
**Symptômes** : Bibliothèque Jellyfin vide ou incomplète
**Solutions** :
1. **Redémarrer Jellyfin** : `cd /opt/stacks/jelly && docker compose restart jellyfin`
2. **Redémarrer rclone** : `../scripts/fix_jellyfin_access.sh`
3. **Vérifier montages** : `mount | grep -E "(rclone|mergerfs)"`

### Espace Disque Critique
**Symptômes** : Disque >95% plein, téléchargements échouent
**Solutions** :
1. **Upload d'urgence** : `../scripts/emergency_s3_upload.sh`
2. **Nettoyer cache** : `rm -rf /novastream/local/cache/rclone_vfs/*`
3. **Arrêt services** : `cd /opt/stacks/jelly && docker compose stop jellyseerr`

### Erreurs Permissions
**Symptômes** : "permission denied" dans les logs
**Solutions** :
1. **Fix rapide** : `sudo chown -R $USER:$USER /novastream/local/cache/media/`
2. **Script dédié** : `../scripts/fix_permissions.sh`

## 📋 **Guides Détaillés**

- **[Dépannage Général](GENERAL.md)** - Solutions complètes pour tous problèmes
- **[Applications Starr](STARR_APPS.md)** - Radarr, Sonarr, Prowlarr, SABnzbd

## 🔍 **Diagnostic Rapide**

```bash
# État global du système
../scripts/check_jellyfin_ready.sh

# Espace disque
df -h / | grep vda1

# Processus actifs
ps aux | grep -E "(rclone|jellyfin)"

# Montages
mount | grep -E "(rclone|mergerfs)"
```

## 📞 **Escalation**

Si les solutions ci-dessus ne résolvent pas le problème :
1. Consulter les [logs détaillés](../logs/README.md)
2. Examiner [l'architecture système](../architecture/ARCHITECTURE.md)
3. Vérifier la [configuration des intégrations](../guides/INTEGRATIONS.md)