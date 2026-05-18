# =====================================================================
# DRP GRUPO 5: SERVIDOR DE RESCATE (VERSIÓN FINAL + LDAP FIX)
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
# Log de todo lo que pase para auditoría
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "🚀 Iniciando Recuperación Total Blindada - Grupo 5..."

apt-get update -y
apt-get install -y docker.io docker-compose awscli tar
systemctl start docker
systemctl enable docker

DIR_BASE="/opt/drp"
DIR_NFS="$DIR_BASE/nfs_data"
DIR_DB_INIT="$DIR_BASE/db_init"
BUCKET_NAME="drp-gitea-backups-grup5-2026"

mkdir -p $DIR_NFS
mkdir -p $DIR_DB_INIT
mkdir -p $DIR_BASE/ldap_data

echo "⬇️ Descargando el backup 'pesado' de S3..."
aws s3 sync s3://$BUCKET_NAME/gitea/ /tmp/gitea_backup/
aws s3 sync s3://$BUCKET_NAME/ldap/ /tmp/ldap_backup/

LATEST_GITEA=$(ls -t /tmp/gitea_backup/*.tar.gz | head -1)
if [ -n "$LATEST_GITEA" ]; then
    echo "📦 Descomprimiendo estructura completa (git, gitea, ssh)..."
    tar -xzf "$LATEST_GITEA" -C $DIR_NFS/
fi

LATEST_LDAP=$(ls -t /tmp/ldap_backup/*.ldif | head -1)
if [ -n "$LATEST_LDAP" ]; then
    cp "$LATEST_LDAP" $DIR_BASE/ldap_data/backup.ldif
    
    echo "🧹 Limpiando el LDIF de atributos operacionales (slapcat)..."
    sed -i '/^structuralObjectClass:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^entryUUID:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^creatorsName:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^createTimestamp:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^entryCSN:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^modifiersName:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^modifyTimestamp:/d' $DIR_BASE/ldap_data/backup.ldif
    sed -i '/^contextCSN:/d' $DIR_BASE/ldap_data/backup.ldif
fi

echo "🔍 Moviendo el SQL a la carpeta de inyección de MariaDB..."
find $DIR_NFS -name "gitea_db.sql" -exec mv {} $DIR_DB_INIT/init.sql \;

# 🛠️ AJUSTE DE PERMISOS: Gitea usa el UID 1000
chown -R 1000:1000 $DIR_NFS
chmod -R 755 $DIR_NFS

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
      - MYSQL_ROOT_PASSWORD=Admin10.
      - MYSQL_DATABASE=gitea
      - MYSQL_USER=gitea
      - MYSQL_PASSWORD=Admin10.
    volumes:
      - db_data:/var/lib/mysql
      - ./db_init:/docker-entrypoint-initdb.d

  ldap:
    image: osixia/openldap:latest
    container_name: drp_ldap
    ports:
      - "389:389"
    networks:
      default:
        aliases:
          - ldap.torrelles.cat
    environment:
      LDAP_ORGANISATION: "Torrelles"
      LDAP_DOMAIN: "torrelles.cat"
      LDAP_ADMIN_PASSWORD: "Admin10."
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
      - GITEA__database__PASSWD=Admin10.
      - GITEA__security__INSTALL_LOCK=true
      - USER_UID=1000
      - USER_GID=1000
    ports:
      - "80:3000"
      - "222:22"
    volumes:
      - ./nfs_data:/data
    depends_on:
      - db
      - ldap

volumes:
  db_data:
COMPOSE

echo "⚙️ Arrancando servicios por fases..."
cd $DIR_BASE
sudo docker-compose up -d db redis ldap

echo "Esperando 20 segundos a que LDAP se asiente..."
sleep 20

echo "👥 Inyectando usuarios en LDAP a la fuerza..."
sudo docker exec drp_ldap ldapadd -x -D "cn=admin,dc=torrelles,dc=cat" -w Admin10. -c -f /container/run/service/slapd/assets/config/bootstrap/ldif/custom/backup.ldif || true
echo "Esperando 25 segundos más para la inyección de la DB MariaDB..."
sleep 25
sudo docker-compose up -d gitea

echo "DRP FINALIZADO CON ÉXITO"
EOF
}