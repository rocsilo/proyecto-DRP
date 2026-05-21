#!/bin/bash

# --- CONFIGURACIÓN DEL NUEVO USUARIO (CALCO DE PROFE / LLUC) ---
NUEVO_USER="alumno_drp2"
NOMBRE_COMPLETO="Alumno Creado en AWS"
PASSWORD_USER="Admin10."
EMAIL_USER="alumnodrp2@mandretin.xyz"

# Generamos el hash SSHA oficial que vuestro OpenLDAP entiende perfectamente
HASH_PASSWORD=$(slappasswd -s "$PASSWORD_USER")

echo "📝 Generando archivos de datos estructurados (Modelo: inetOrgPerson puro)..."

# PARTE 1: Alta limpia con cn como identificador principal (Igual que cn=profe)
cat << EOF > /tmp/alta_usuario.ldif
dn: cn=$NUEVO_USER,ou=usuaris,dc=torrelles,dc=cat
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
cn: $NUEVO_USER
sn: DRP
mail: $EMAIL_USER
userPassword: $HASH_PASSWORD
EOF

# PARTE 2: Asociación al grupo posixGroup (Usando el cn como memberUid)
cat << EOF > /tmp/modificar_grupo.ldif
dn: cn=tecnics,ou=grups,dc=torrelles,dc=cat
changetype: modify
add: memberUid
memberUid: $NUEVO_USER
EOF

echo "📥 1/2. Inyectando usuario inetOrgPerson en AWS..."
ldapadd -x -D "cn=admin,dc=torrelles,dc=cat" -w "Admin10." -f /tmp/alta_usuario.ldif

if [ $? -eq 0 ]; then
    echo "📥 2/2. Asociando al grupo 'tecnics' en AWS..."
    ldapmodify -x -D "cn=admin,dc=torrelles,dc=cat" -w "Admin10." -f /tmp/modificar_grupo.ldif
    
    if [ $? -eq 0 ]; then
        echo "✅ [ÉXITO] Usuario completamente integrado con el estándar real de Torrelles."
        # Forzamos que OpenLDAP asiente los cambios en los ficheros mdb de AWS
        sudo slapindex -F /etc/ldap/slapd.d/ >/dev/null 2>&1 || true
    else
        echo "⚠️ Usuario creado pero falló la asignación al grupo."
    fi
else
    echo "❌ ERROR: No se pudo registrar el usuario en AWS."
fi
# Limpieza de archivos temporales
rm -f /tmp/alta_usuario.ldif
rm -f /tmp/modificar_grupo.ldif
