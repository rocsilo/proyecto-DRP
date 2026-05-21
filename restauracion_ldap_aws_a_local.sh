#!/bin/bash

# ==============================================================================
# SCRIPT 3: S3 -> LOCAL LDAP (RESTAURAR Y ACTUALIZAR USUARIOS)
# ==============================================================================

# 👇 CAMBIO AQUÍ: Ahora apunta a la carpeta de AWS
BUCKET_LDAP="s3://drp-gitea-backups-grup5-2026/ldap_aws/"
TMP_DIR="/tmp/restore_ldap"

mkdir -p $TMP_DIR

echo "🔍 Buscando el último backup de LDAP de AWS en S3..."
ULTIMO_BACKUP=$(aws s3 ls $BUCKET_LDAP | sort | tail -n 1 | awk '{print $4}')

if [ -z "$ULTIMO_BACKUP" ]; then
    echo "❌ No se encontraron backups de LDAP en S3."
    exit 1
fi

echo "⬇️ Descargando: $ULTIMO_BACKUP..."
aws s3 cp "${BUCKET_LDAP}${ULTIMO_BACKUP}" "$TMP_DIR/backup.ldif"

echo "💉 Inyectando nuevos usuarios en el servidor LDAP local..."
sudo ldapadd -x -D "cn=admin,dc=torrelles,dc=cat" -w 'Admin10.' -c -f $TMP_DIR/b              ackup.ldif || true

rm -rf $TMP_DIR

echo "🎉 Sincronización de usuarios LDAP finalizada."
