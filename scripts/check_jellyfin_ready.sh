#!/bin/bash

# Script pour vérifier quand Jellyfin sera prêt à voir tous les films

echo "=== Vérification Status Novastream ==="
echo "Date: $(date)"
echo ""

# Vérifier les processus rclone en cours
RCLONE_MOVES=$(ps aux | grep "rclone move" | grep -v grep | wc -l)
echo "Processus rclone move en cours: $RCLONE_MOVES"

if [ $RCLONE_MOVES -gt 0 ]; then
    echo "⏳ Déplacements S3 en cours..."
    echo "   Attendre que les processus se terminent avant de tester Jellyfin"
    echo ""
else
    echo "✅ Tous les déplacements terminés"
    echo ""
    
    # Vérifier la structure S3
    echo "Films dans S3 (media/movies):"
    rclone lsd ${S3_REMOTE:-s3remote:media-bucket}/media/movies | wc -l
    
    echo "Films dans S3 (ancien movies):"  
    rclone lsd ${S3_REMOTE:-s3remote:media-bucket}/movies 2>/dev/null | wc -l
    
    # Vérifier le montage local
    echo ""
    echo "Fichiers .mkv visibles via mergerfs:"
    find "/novastream/data/media/movies/" -name "*.mkv" 2>/dev/null | wc -l
    
    echo ""
    echo "État du montage rclone:"
    if mount | grep -q "${S3_REMOTE:-s3remote:media-bucket}"; then
        echo "✅ Montage rclone actif"
    else
        echo "❌ Montage rclone non trouvé"
    fi
    
    echo ""
    echo "État du montage mergerfs:"
    if mount | grep -q "fuse.mergerfs"; then
        echo "✅ Montage mergerfs actif"
    else  
        echo "❌ Montage mergerfs non trouvé"
    fi
    
    # Vérifier permissions Jellyfin
    ROOT_FILES=$(find /novastream/local/cache/media -user root 2>/dev/null | wc -l)
    if [ $ROOT_FILES -gt 0 ]; then
        echo ""
        echo "⚠️  Problème permissions détecté:"
        echo "   $ROOT_FILES fichiers appartiennent à root (créés par Jellyfin)"
        echo "   Exécute: ./scripts/fix_permissions.sh"
    fi
    
    echo ""
    echo "Actions recommandées:"
    if [ $(find "/novastream/data/media/movies/" -name "*.mkv" 2>/dev/null | wc -l) -gt 1 ]; then
        echo "🎉 Les fichiers sont accessibles ! Redémarre Jellyfin et fais un scan:"
        echo "   cd /opt/stacks/jelly && docker compose restart jellyfin"
    else
        echo "⚠️  Redémarrage du montage rclone nécessaire"
        echo "   Exécute: $HOME/fix_jellyfin_access.sh"
    fi
fi

echo ""
echo "==============================================="