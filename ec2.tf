# =====================================================================
# DRP GRUPO 5: SERVIDOR DE RESCATE (VERSIÓN FINAL + NATIVE LDAP FIX)
# =====================================================================

resource "aws_instance" "drp_server" {
  ami           = "ami-0cd59ecaf368e5ccf"
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.drp_subnet.id
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

# 1. ACTUALIZACIÓN E INSTALACIÓN DE DEPENDENCIAS (AÑADIMOS SLAPD)
apt-get update -y

# Automatizamos las respuestas de apt para instalar slapd en silencio
sudo debconf-set-selections <<'DEBCONF'
slapd slapd/internal/adminpw password Admin10.
slapd slapd/internal/adminpw_again password Admin10.
slapd slapd/domain string torrelles.cat
DEBCONF

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose awscli tar slapd ldap-utils

systemctl start docker
systemctl enable docker
systemctl start slapd
systemctl enable slapd

DIR_BASE="/opt/drp"
DIR_NFS="$DIR_BASE/nfs_data"
DIR_DB_INIT="$DIR_BASE/db_init"
BUCKET_NAME="drp-gitea-backups-grup5-2026"

mkdir -p $DIR_NFS
mkdir -p $DIR_DB_INIT

echo "⬇️ Descargando backups desde Amazon S3..."
aws s3 sync s3://$BUCKET_NAME/gitea/ /tmp/gitea_backup/
aws s3 sync s3://$BUCKET_NAME/ldap/ /tmp/ldap_backup/

# 2. RESTAURACIÓN DE GITEA (TU INFRAESTRUCTURA ORIGINAL)
LATEST_GITEA=$(ls -t /tmp/gitea_backup/*.tar.gz | head -1)
if [ -n "$LATEST_GITEA" ]; then
    echo "📦 Descomprimiendo estructura completa (git, gitea, ssh)..."
    tar -xzf "$LATEST_GITEA" -C $DIR_NFS/
fi

echo "🔍 Moviendo el SQL a la carpeta de inyección de MariaDB..."
find $DIR_NFS -name "gitea_db.sql" -exec mv {} $DIR_DB_INIT/init.sql \;
chown -R 1000:1000 $DIR_NFS
chmod -R 755 $DIR_NFS

# 3. RESTAURACIÓN E INYECCIÓN EN EL LDAP NATIVO
LATEST_LDAP=$(ls -t /tmp/ldap_backup/*.ldif | head -1)
if [ -n "$LATEST_LDAP" ]; then
    echo "🧹 Preparando e importando base de datos LDAP nativa..."
    cp "$LATEST_LDAP" /tmp/backup_limpio.ldif
    
    # 1. Limpieza de atributos operacionales (vuestra lógica original)
    sed -i '/^structuralObjectClass:/d' /tmp/backup_limpio.ldif
    sed -i '/^entryUUID:/d' /tmp/backup_limpio.ldif
    sed -i '/^creatorsName:/d' /tmp/backup_limpio.ldif
    sed -i '/^createTimestamp:/d' /tmp/backup_limpio.ldif
    sed -i '/^entryCSN:/d' /tmp/backup_limpio.ldif
    sed -i '/^modifiersName:/d' /tmp/backup_limpio.ldif
    sed -i '/^modifyTimestamp:/d' /tmp/backup_limpio.ldif
    sed -i '/^contextCSN:/d' /tmp/backup_limpio.ldif

    # 2. Paramos el servicio de fábrica obligatoriamente
    sudo systemctl stop slapd

    # 3. Forzamos a que slapd escuche en todas las IPs (0.0.0.0) para que Gitea llegue desde Docker
    sudo sed -i 's/SLAPD_SERVICES=.*/SLAPD_SERVICES="ldap:\/\/0.0.0.0:389\/"/g' /etc/default/slapd

    # 4. Cargamos los esquemas Cosine y NIS (Posix) en el motor de configuración slapd.d
    sudo slapauth -g -F /etc/ldap/slapd.d/ -d 0 >/dev/null 2>&1 || true
    
    # 5. Vaciamos la base de datos vacía de fábrica
    rm -rf /var/lib/ldap/*

    # 6. Inyectamos vuestro backup de Torrelles en frío respetando vuestros esquemas locales
    sudo slapadd -F /etc/ldap/slapd.d/ -l /tmp/backup_limpio.ldif

    # 7. TRUCO INMORTAL: Modificamos la contraseña de administración directamente en el archivo config de slapd
    # Generamos el hash SSHA de 'Admin10.' de forma segura
    HASH_PW=$(slappasswd -s Admin10.)
    
    # Buscamos el archivo de configuración mdb e inyectamos la línea de la contraseña RootPW directamente
    CONF_FILE=$(find /etc/ldap/slapd.d/ -name "olcDatabase={1}mdb.ldif" | head -1)
    if [ -n "$CONF_FILE" ]; then
        # Si ya existe una línea olcRootPW la borramos para evitar duplicados
        sed -i '/^olcRootPW:/d' "$CONF_FILE"
        # Añadimos la contraseña debajo del dn de la base de datos
        sed -i "/^olcDatabase:/a olcRootPW: $HASH_PW" "$CONF_FILE"
    fi

    # 8. Corregimos permisos finales de carpetas con los archivos modificados
    chown -R openldap:openldap /var/lib/ldap/
    chown -R openldap:openldap /etc/ldap/slapd.d/
    
    # 9. Arrancamos el servicio limpio y definitivo
    sudo systemctl start slapd
    
    echo "🌳 LDAP Nativo desplegado con éxito, abierto en red y con credenciales fijadas en frío."
fi
# 4. CREACIÓN DEL DOCKER COMPOSE (ELIMINADO EL CONTENEDOR LDAP)
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
    extra_hosts:
      - "ldap.torrelles.cat:172.17.0.1" # Mapeo clave para que Docker vea el host local
    volumes:
      - ./nfs_data:/data
    depends_on:
      - db

volumes:
  db_data:
COMPOSE

echo "⚙️ Arrancando servicios Docker restantes por fases..."
cd $DIR_BASE
sudo docker-compose up -d db redis

echo "Esperando 25 segundos para la inicialización completa de MariaDB..."
sleep 25
sudo docker-compose up -d gitea
echo "DRP FINALIZADO CON ÉXITO"
EOF
}
