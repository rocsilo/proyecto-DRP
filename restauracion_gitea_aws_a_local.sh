#!/bin/bash

# ==============================================================================
# SCRIPT 2: S3 -> LOCAL NODO 1 (RESTAURAR GITEA Y MARIADB DESDE AWS)
# ==============================================================================

# La ruta que me has pedido:
BUCKET_GITEA="s3://drp-gitea-backups-grup5-2026/gitea_aws/"
DIR_LOCAL_GITEA="/mnt/nextcloud_data"
TMP_DIR="/tmp/restore_gitea"

mkdir -p $TMP_DIR

echo "🔍 Buscando el último backup de AWS en la carpeta /gitea_aws/..."

# Buscamos el archivo más reciente (esta es la línea que fallaba si no tenías awscli)
ULTIMO_BACKUP=$(aws s3 ls $BUCKET_GITEA | sort | tail -n 1 | awk '{print $4}')

if [ -z "$ULTIMO_BACKUP" ]; then
    echo "❌ ERROR: No se ha encontrado ningún archivo en $BUCKET_GITEA"
    exit 1
fi

echo "⬇️ Descargando: $ULTIMO_BACKUP..."
aws s3 cp "${BUCKET_GITEA}${ULTIMO_BACKUP}" "$TMP_DIR/backup.tar.gz"

echo "📦 Descomprimiendo archivos en la carpeta de Gitea local..."
sudo tar -xzf "$TMP_DIR/backup.tar.gz" -C $DIR_LOCAL_GITEA/

echo "💉 Inyectando la base de datos en el contenedor MariaDB local..."
# Buscamos el ID del contenedor de MariaDB que esté corriendo
DB_CONTAINER=$(sudo docker ps -q -f ancestor=mariadb:10.6 | head -n 1)

if [ -n "$DB_CONTAINER" ]; then
    # Inyectamos el SQL que venía dentro del tar.gz
    cat $DIR_LOCAL_GITEA/gitea_db.sql | sudo docker exec -i $DB_CONTAINER mysql -u gitea -p'Admin10.' gitea
    echo "✅ Base de datos inyectada con éxito en el contenedor $DB_CONTAINER"
else
    echo "⚠️ ALERTA: No se ha encontrado el contenedor de MariaDB local para inyectar el SQL."
fi

# Limpieza de archivos temporales para no llenar el disco de nuevo
rm -rf $TMP_DIR
rm -f $DIR_LOCAL_GITEA/gitea_db.sql

echo "🎉 ¡Proceso de restauración completado con éxito!"
