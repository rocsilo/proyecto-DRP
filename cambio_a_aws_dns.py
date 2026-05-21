import requests

print("🔄 [FAILBACK] Iniciando retorno de DNS a la infraestructura local...")

url_api = "https://api-domains.cdmon.services/api-domains/dnsrecords/edit"

headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "apikey": "3WdR0Fjs7v92FSQErCaiQboagf40S07h"  # Tu API Key fija
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
            "destination": "35.172.67.186"  # Tu IP local de Torrelles
        }
    }
}

try:
    respuesta = requests.post(url_api, headers=headers, json=body_dns, timeout=10)
    if respuesta.status_code in [200, 201]:
        print("✅ [FAILBACK] ¡DNS restaurado! git.mandretin.xyz apuntr aAWS (35.172.67.186)")
    else:
        print(f"⚠️ [FAILBACK] cdmon denegó el cambio. Código: {respuesta.status_code} - Detalle: {respuesta.text}")
except Exception as e:
    print(f"❌ [FAILBACK] Error de conexión con la API de cdmon: {e}")
