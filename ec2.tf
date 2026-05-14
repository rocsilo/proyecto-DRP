# =====================================================================
# DRP GRUPO 5: SERVIDOR DE RESCATE AUTOMÁTICO (CORREGIDO - INYECCIÓN SQL)
# =====================================================================

resource "aws_instance" "drp_server" {
  ami           = "ami-0cd59ecaf368e5ccf"
  instance_type = "t3.medium"
  vpc_security_group_ids = [aws_security_group.drp_sg.id]
  iam_instance_profile   = "LabInstanceProfile"

  tags = {
    Name = "DRP-Grupo5-Rescate-Final"
  }

  user_data = <<-EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "🚀 Iniciando Recuperación Total - Grupo 5..."

# --- FASE 1: INSTALACIÓN ---
apt-get update -y
apt-get install -y docker.io docker-compose awscli tar
systemctl start docker
systemctl enable docker

# --- FASE 2: CARPETAS ---
DIR_BASE="/opt/drp"
DIR_GITEA_DATA="$DIR_BASE/nfs_data/gitea"
DIR_LDAP_DATA="$DIR_BASE/ldap_data"
BUCKET_NAME="drp-gitea-backups-grup5-2026"

mkdir -p $DIR_GITEA_DATA
mkdir -p $DIR_LDAP_DATA

# --- FASE 3: DESCARGA DE S3 ---
aws s3 sync s3://$BUCKET_NAME/gitea/ /tmp/gitea_backup/
aws s3 sync s3://$BUCKET_NAME/ldap/ /tmp/ldap_backup/

LATEST_GITEA=$(ls -t /tmp/gitea_backup/*.tar.gz | head -1)
if [ -n "$LATEST_GITEA" ]; then
    tar -xzf "$LATEST_GITEA" -C $DIR_GITEA_DATA/
fi

LATEST_LDAP=$(ls -t /tmp/ldap_backup/*.ldif | head -1)
if [ -n "$LATEST_LDAP" ]; then
    cp "$LATEST_LDAP" $DIR_LDAP_DATA/backup.ldif
fi

# --- FASE 4: DOCKER COMPOSE ---
cat << 'COMPOSE' > $DIR_BASE/docker-compose.yml
version: '3.3'
services:
  redis:
    image: redis:alpine
    container_name: drp_redis
    restart: always

  db:
    image: mariadb:10.6
    container_name: drp_db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=gitea
      - MYSQL_DATABASE=gitea
      - MYSQL_USER=gitea
      - MYSQL_PASSWORD=gitea
    volumes:
      - db_data:/var/lib/mysql

  ldap:
    image: osixia/openldap:latest
    container_name: drp_ldap
    ports:
      - "389:389"
    environment:
      LDAP_ORGANISATION: "Torrelles"
      LDAP_DOMAIN: "torrelles.cat"
    volumes:
      - ./ldap_data/backup.ldif:/container/run/service/slapd/assets/config/bootstrap/ldif/custom/backup.ldif

  gitea:
    image: gitea/gitea:latest
    container_name: drp_gitea
    restart: always
    environment:
      - GITEA__database__DB_TYPE=mysql
      - GITEA__database__HOST=db:3306
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=gitea
    ports:
      - "80:3000"
      - "222:22"
    volumes:
      - ./nfs_data/gitea:/data
    depends_on:
      - db
      - ldap

volumes:
  db_data:
COMPOSE

# --- FASE 5: PERMISOS ---
chown -R 1000:1000 $DIR_BASE/nfs_data
chmod -R 755 $DIR_BASE/nfs_data

# --- FASE 6: EL ARRANQUE E INYECCIÓN (EL "SQLDAM") ---
echo "Levantando contenedores..."
cd $DIR_BASE
sudo docker-compose up -d

echo "Esperando a que MariaDB esté lista para el SQLDAM..."
# Esperamos 45 segundos para asegurar que el motor de la BD ha arrancado
sleep 45

echo "Inyectando el SQL Dump en la base de datos..."
# Este es el comando que mete vuestro backup directamente al motor de la BD
docker exec -i drp_db mysql -u gitea -pgitea gitea < $DIR_GITEA_DATA/gitea_db.sql

echo "Reiniciando Gitea para que reconozca los nuevos datos..."
docker restart drp_gitea

echo "¡DRP FINALIZADO CON ETSITO!"
EOF
}