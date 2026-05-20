import os
import time
import subprocess
import requests
import json
# ==========================================
# ⚙️ CONFIGURACIÓN DE LA FLOTA TAILSCALE
# ==========================================
MAQUINAS = {
    "Nginx Proxy":   {"ip": "100.84.255.113", "critica": True},
    "Nodo 1 Manager":{"ip": "100.118.24.124", "critica": True},
    "Nodo 2 Worker": {"ip": "100.83.140.53",  "critica": False},
    "Nodo 3 Worker": {"ip": "100.77.186.72",  "critica": False},
    "NFS Server":    {"ip": "100.113.86.1",   "critica": True},
    "LDAP Server":   {"ip": "100.84.89.43",   "critica": True}
}

INTENTOS_MAXIMOS = 3         # Fallos seguidos antes de darla por muerta
TIEMPO_ENTRE_RONDAS = 15     # Segundos que espera antes de volver a revisar todas
WEBHOOK_DISCORD = "https://discord.com/api/webhooks/1494364227287384246/YpVgL1pgJ46MLCGWGcFXMqiUmPCrRRUhEJGxGPBRRPK9jFLGtaXKi_MzxAron2eI92rN" # Pon tu Webhook real
PATH_TERRAFORM = "/home/ubuntu/proyecto-DRP"

# Diccionarios internos para llevar la cuenta de cada máquina
fallos_consecutivos = {nombre: 0 for nombre in MAQUINAS}
alerta_enviada = {nombre: False for nombre in MAQUINAS}

# ==========================================
# 🛠️ FUNCIONES DEL SISTEMA
# ==========================================
def enviar_discord(mensaje, titulo="🚨 ALERTA DEL SISTEMA DRP 🚨", color="16711680"): 
    payload = {
        "embeds": [{
            "title": titulo,
            "description": mensaje,
            "color": int(color)
        }]
    }
    try:
        requests.post(WEBHOOK_DISCORD, json=payload, timeout=5)
    except:
        pass

def comprobar_ping(ip):
    # Ping silencioso (funciona en Linux y Windows)
    comando = ["ping", "-c", "1", "-W", "2", ip] if os.name != "nt" else ["ping", "-n", "1", "-w", "2000", ip]
    resultado = subprocess.run(comando, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return resultado.returncode == 0

def activar_rescate_aws(nombre_caida):
    print("\n" + "="*50)
    print("🚀 INICIANDO PROTOCOLO DE EMERGENCIA TERRAFORM...")
    print("="*50)
    
    enviar_discord(
        mensaje=f"🔥 **CAÍDA CRÍTICA DETECTADA.**\nLa máquina principal **{nombre_caida}** ha dejado de responder.\nIniciando despliegue de emergencia en AWS via Terraform (IaC)...",
        titulo="💥 PROTOCOLO DRP ACTIVADO 💥",
        color="16711680" # Rojo
    )
    
    try:
        if PATH_TERRAFORM != "":
            subprocess.run(["terraform", "apply", "-auto-approve"], cwd=PATH_TERRAFORM, capture_output=True, text=True, check=True)
            enviar_discord("✅ **RESCATE COMPLETADO.**\nLa infraestructura espejo está operativa en el Cloud.", color="65280")
            print("Terraform finalizado correctamente.")
            print("🌐 [DNS] Conectando con la API de cdmon para redirigir el tráfico...")
            
            url_api = "https://api-domains.cdmon.services/api-domains/dnsrecords/edit"
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json",
                "apikey": "3WdR0Fjs7v92FSQErCaiQboagf40S07h"  
            }
            body_dns = {
                "data": {
                    "domain": "mandretin.xyz",
                    "current": {
                        "host": "git",
                        "type": "A"
                    },
                    "new": {
                        "ttl": 300,                  
                        "destination": "35.172.67.186"
                    }
                }
            }
            try:
                respuesta = requests.post(url_api, headers=headers, json=body_dns, timeout=10)
                if respuesta.status_code in [200, 201]:
                    print("✅ [DNS] ¡Actualización exitosa! git.mandretin.xyz ahora apunta a AWS (35.172.67.186)")
                else:
                    print(f"⚠️ [DNS] Error en la API de cdmon. Código: {respuesta.status_code} - Respuesta: {respuesta.text}")
            except Exception as e:
                print(f"❌ [DNS] Error crítico de conexión con cdmon: {e}")
        else:
            print("⚠️ Modo simulación: Terraform no configurado aún.")
            enviar_discord("⚠️ **SIMULACIÓN:** Terraform no está configurado, pero el Watchdog ha hecho su trabajo.", color="16705372")
            
    except subprocess.CalledProcessError as e:
        enviar_discord(f"❌ **ERROR CRÍTICO EN TERRAFORM:**\nNo se ha podido levantar el entorno AWS.\n\n`{e.stderr[-200:]}`")
        print("Fallo en Terraform.")

# ==========================================
# 🚀 BUCLE PRINCIPAL DEL WATCHDOG
# ==========================================
print("="*60)
print(f"🕵️  WATCHDOG SOC MULTISERVER INICIADO")
print(f"📡 Vigilando {len(MAQUINAS)} servidores a través de Tailscale...")
print("="*60)

drp_activado = False

while not drp_activado:
    print(f"\n--- ⏱️ Ronda de comprobación: {time.strftime('%H:%M:%S')} ---")
    
    for nombre, config in MAQUINAS.items():
        ip = config["ip"]
        es_critica = config["critica"]
        
        # Comprobamos la máquina
        if comprobar_ping(ip):
            fallos_consecutivos[nombre] = 0
            if alerta_enviada[nombre]:
                # Si estaba caída y vuelve a la vida, avisamos en verde
                enviar_discord(f"💚 La máquina **{nombre}** ({ip}) ha vuelto a responder y está operativa.", titulo="✅ SERVIDOR RECUPERADO", color="65280")
                alerta_enviada[nombre] = False
                
            print(f"✅ {nombre.ljust(15)} ({ip}) -> OK")
            
        else:
            fallos_consecutivos[nombre] += 1
            intentos = fallos_consecutivos[nombre]
            print(f"⚠️ {nombre.ljust(15)} ({ip}) -> FALLO {intentos}/{INTENTOS_MAXIMOS}")
            
            # Si alcanza el máximo de fallos permitidos
            if intentos >= INTENTOS_MAXIMOS and not alerta_enviada[nombre]:
                alerta_enviada[nombre] = True
                
                if es_critica:
                    activar_rescate_aws(nombre)
                    drp_activado = True # Rompe el bucle para no lanzar Terraform múltiples veces
                    break # Salimos del bucle FOR
                else:
                    # Si no es crítica, solo mandamos un aviso naranja a Discord
                    enviar_discord(
                        mensaje=f"⚠️ La máquina secundaria **{nombre}** ({ip}) no responde. La infraestructura principal sigue activa, pero requiere revisión.",
                        titulo="⚠️ ALERTA DE NODO CAÍDO",
                        color="16744192" # Naranja
                    )
                    print(f"🔔 Aviso enviado a Discord por pérdida de nodo no crítico: {nombre}")

    if not drp_activado:
        time.sleep(TIEMPO_ENTRE_RONDAS)

print("🔒 Watchdog detenido tras ejecutar el DRP.")
