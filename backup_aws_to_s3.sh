#!/bin/bash
# ==============================================================================
# SCRIPT DE RESPALDO AUTOMÁTICO: ENTORNO CLOUD (AWS EC2) -> AMAZON S3 (FIXED)
# ==============================================================================

FECHA=$(date +"%Y-%m-%d_%H-%M-%S")
DIR_BASE="/opt/drp"
DIR_NFS="$DIR_BASE/nfs_data"
TMP_DIR="/tmp/backup_drp"
BUCKET_NAME="drp-gitea-backups-grup5-2026"

mkdir -p $TMP_DIR

echo "🚀 [DRP LOG] Iniciando proceso de Backup Estructurado..."

# FASE 1: EXTRACCIÓN DE LA BASE DE DATOS (MARIADB)
echo "💾 [Fase 1/5] Realizando volcado de la base de datos de Gitea..."
sudo docker exec drp_db sh -c 'exec mysqldump -u gitea -p"Admin10." gitea' > $DIR_NFS/gitea_db.sql 

if [ $? -eq 0 ]; then
    echo "✅ Volcado de MariaDB generado correctamente."
else
    echo "❌ ERROR Crítico: Falló el volcado de la base de datos."
    exit 1 
fi

# FASE 2: EMPAQUETADO Y COMPRESIÓN DE REPOSITORIOS (GITEA)
echo "📦 [Fase 2/5] Comprimiendo el volumen persistente y código fuente..."
NOMBRE_BACKUP_GITEA="gitea_mariadb_${FECHA}_aws.tar.gz"
sudo tar -czf $TMP_DIR/$NOMBRE_BACKUP_GITEA -C $DIR_BASE nfs_data/

# FASE 3: VOLCADO DE DIRECTORIO DE USUARIOS (LDAP NATIVO FIX)
echo "👥 [Fase 3/5] Extrayendo base de datos de usuarios (OpenLDAP Nativo)..."
NOMBRE_BACKUP_LDAP="ldap_${FECHA}_aws.ldif"

# CORRECCIÓN: Llamamos a slapcat directamente en el host nativo
sudo slapcat > $TMP_DIR/$NOMBRE_BACKUP_LDAP

# FASE 4: TRANSFERENCIA SEGURA A AMAZON S3
echo "☁️ [Fase 4/5] Transfiriendo archivos de respaldo al almacenamiento S3..."
aws s3 cp $TMP_DIR/$NOMBRE_BACKUP_GITEA s3://$BUCKET_NAME/gitea_aws/ 
aws s3 cp $TMP_DIR/$NOMBRE_BACKUP_LDAP s3://$BUCKET_NAME/ldap_aws/

# FASE 5: SANEAMIENTO Y LIMPIEZA
echo "🧹 [Fase 5/5] Iniciando tareas de limpieza post-backup..."
rm -rf $TMP_DIR
rm -f $DIR_NFS/gitea_db.sql

echo "🎉 [DRP LOG] ¡Proceso finalizado! Respaldo consolidado en S3."
