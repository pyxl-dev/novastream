#!/bin/bash

# Script pour corriger les permissions des fichiers Jellyfin
# À exécuter si les scripts rclone échouent avec des erreurs de permissions

echo "Correction des permissions des fichiers média..."

# Corriger ownership des fichiers média
sudo chown -R "$(id -un):$(id -gn)" /novastream/local/cache/media/ 2>/dev/null

# Corriger permissions
chmod -R 755 /novastream/local/cache/media/ 2>/dev/null

echo "Permissions corrigées !"

# Vérifier qu'il n'y a plus de fichiers root
ROOT_FILES=$(find /novastream/local/cache/media -user root 2>/dev/null | wc -l)
if [ $ROOT_FILES -gt 0 ]; then
    echo "⚠️  Il reste $ROOT_FILES fichiers appartenant à root"
    echo "Exécuter: sudo chown -R "$(id -un):$(id -gn)" /novastream/local/cache/media/"
else
    echo "✅ Toutes les permissions sont correctes"
fi