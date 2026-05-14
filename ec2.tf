# =====================================================================
# DRP GRUPO 5: SERVIDOR DE RESCATE AUTOMÁTICO (GITEA + DB + REDIS + LDAP)
# =====================================================================

# 'resource' le dice a Terraform que queremos crear una máquina virtual en AWS (EC2)
resource "aws_instance" "drp_server" {
  
  # 1. CONFIGURACIÓN FÍSICA DE LA MÁQUINA
  ami           = "ami-0cd59ecaf368e5ccf" # Imagen del Sistema Operativo: Ubuntu 24.04 LTS
  instance_type = "t3.medium"             # Tamaño: 2 vCPUs y 4GB RAM. Necesario para soportar los 4 contenedores sin que se cuelgue.
  
  # 2. REDES Y PERMISOS
  vpc_security_group_ids = [aws_security_group.drp_sg.id] # Le aplicamos el firewall (puertos 80, 22, etc.) creado en este mismo Terraform
  iam_instance_profile   = "LabInstanceProfile"           # FUNDAMENTAL: Le da permiso a la máquina para entrar a S3 sin pedir contraseñas.

  # 3. ETIQUETAS
  tags = {
    Name = "DRP-Grupo5-Rescate-Final" # El nombre que aparecerá en el panel de control de AWS
  }

  # =====================================================================
  # 4. SCRIPT DE ARRANQUE AUTOMÁTICO (USER DATA)
  # Este código se ejecuta SOLO en la máquina Ubuntu nada más encenderse
  # =====================================================================
  user_data = <<-EOF
#!/bin/bash

# --- CONFIGURACIÓN DE LOGS ---
# Guarda todo lo que hace este script en un archivo para poder buscar errores si algo falla
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Iniciando Recuperación Total - Grupo 5..."

# --- FASE 1: INSTALACIÓN DE PAQUETES ---
apt-get update -y
apt-get install -y docker.io docker-compose awscli tar # Instalamos Docker y el cliente de AWS
systemctl start docker  # Encendemos el motor de Docker
systemctl enable docker # Hacemos que Docker arranque siempre al reiniciar la máquina

# --- FASE 2: PREPARACIÓN DE CARPETAS ---
# Definimos dónde vamos a guardar las cosas. 
DIR_BASE="/opt/drp"
DIR_GITEA_DATA="$DIR_BASE/nfs_data/gitea" # IMPORTANTE: /gitea al final para que el contenedor detecte su app.ini
DIR_LDAP_DATA="$DIR_BASE/ldap_data"
BUCKET_NAME="drp-gitea-backups-grup5-2026"

mkdir -p $DIR_GITEA_DATA
mkdir -p $DIR_LDAP_DATA

# --- FASE 3: DESCARGA DEL CÓDIGO (BACKUP) DESDE LA NUBE S3 ---
echo "Descargando backups..."
# aws s3 sync baja todos los archivos de esa carpeta del S3 a una carpeta temporal
aws s3 sync s3://$BUCKET_NAME/gitea/ /tmp/gitea_backup/
aws s3 sync s3://$BUCKET_NAME/ldap/ /tmp/ldap_backup/

# Busca el archivo de Gitea más reciente y lo descomprime
LATEST_GITEA=$(ls -t /tmp/gitea_backup/*.tar.gz | head -1)
if [ -n "$LATEST_GITEA" ]; then
    echo "Restaurando Gitea desde $LATEST_GITEA..."
    tar -xzf "$LATEST_GITEA" -C $DIR_GITEA_DATA/ # Extrae el código y el app.ini
fi

# Busca el archivo de LDAP más reciente y lo copia
LATEST_LDAP=$(ls -t /tmp/ldap_backup/*.ldif | head -1)
if [ -n "$LATEST_LDAP" ]; then
    cp "$LATEST_LDAP" $DIR_LDAP_DATA/backup.ldif # Extrae a los usuarios de Torrelles
fi

# --- FASE 4: CREACIÓN DEL DOCKER COMPOSE ---
# Escribimos el archivo docker-compose.yml directamente desde este script
cat << 'COMPOSE' > $DIR_BASE/docker-compose.yml
version: '3.3'
services:
  
  # SERVICIO 1: CACHÉ 
  redis:
    image: redis:alpine
    container_name: drp_redis
    restart: always

  # SERVICIO 2: BASE DE DATOS (El "Catálogo" de repositorios)
  db:
    image: mariadb:10
    container_name: drp_db
    restart: always
    environment:
      - MYSQL_ROOT_PASSWORD=gitea
      - MYSQL_DATABASE=gitea
      - MYSQL_USER=gitea
      - MYSQL_PASSWORD=gitea
    volumes:
      - ./db_data:/var/lib/mysql
      # LÍNEA MÁGICA: Si Lluc metió el gitea_db.sql en el backup, MariaDB lo importa solo al arrancar
      - ./nfs_data/gitea/gitea_db.sql:/docker-entrypoint-initdb.d/gitea_db.sql

  # SERVICIO 3: DIRECTORIO DE USUARIOS (Para mantener los logins de Torrelles)
  ldap:
    image: osixia/openldap:latest
    container_name: drp_ldap
    ports:
      - "389:389"
    environment:
      LDAP_ORGANISATION: "Torrelles"
      LDAP_DOMAIN: "torrelles.cat"
    volumes:
      - ./ldap_data/backup.ldif:/container/run/custom/backup.ldif # Inyecta a los usuarios rescatados
      - ldap_data:/var/lib/ldap
      - ldap_config:/etc/ldap/slapd.d

  # SERVICIO 4: EL CÓDIGO FUENTE WEB
  gitea:
    image: gitea/gitea:latest
    container_name: drp_gitea
    restart: always
    environment:
      - USER_UID=1000 # Gitea usa el usuario 1000 por seguridad
      - USER_GID=1000
      - GITEA__database__DB_TYPE=mysql
      - GITEA__database__HOST=db:3306  # Le decimos que se conecte al contenedor de arriba llamado 'db'
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=gitea
    ports:
      - "80:3000"  # Exponemos el puerto 80 para entrar desde el navegador
      - "222:22"   # Exponemos el puerto SSH para clonar repositorios
    volumes:
      - ./nfs_data:/data  # Conectamos la carpeta rescatada de S3 con el cerebro de Gitea
    depends_on:
      - redis # Gitea esperará pacientemente a que los otros 3 arranquen primero
      - db
      - ldap

volumes:
  ldap_data:
  ldap_config:
COMPOSE

# --- FASE 5: PERMISOS DE SEGURIDAD ---
echo "Ajustando permisos..."
# Gitea exige que los archivos le pertenezcan al usuario 1000, si no, se bloquea.
chown -R 1000:1000 $DIR_BASE/nfs_data
chmod -R 755 $DIR_BASE/nfs_data

# --- FASE 6: EL ARRANQUE FINAL ---
echo "Levantando servicios..."
cd $DIR_BASE
# Arranca los 4 servidores a la vez y los deja corriendo en segundo plano (-d)
sudo docker-compose up -d

echo "¡DRP FINALIZADO CON ÉXITO!"
EOF
}