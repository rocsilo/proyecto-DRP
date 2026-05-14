resource "aws_security_group" "drp_sg" {
  name        = "drp_security_group"
  description = "Reglas de firewall para el servidor de rescate DRP (Grupo 5)"

  # 1. Regla para conectarse por SSH a la máquina de AWS (Terminal negra)
  ingress {
    description = "SSH para administracion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 2. Regla para ver la web de Gitea en el navegador
  ingress {
    description = "Acceso web HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 3. Regla para clonar repositorios de Gitea por SSH
  ingress {
    description = "Puerto SSH de Gitea"
    from_port   = 222
    to_port     = 222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 4. Regla para el servidor LDAP (opcional pero recomendado)
  ingress {
    description = "Puerto LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 5. Regla de salida: Permite a la máquina descargar cosas de internet (S3, Docker, etc.)
  egress {
    description = "Trafico de salida libre"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # El -1 significa "todos los protocolos"
    cidr_blocks = ["0.0.0.0/0"]
  }
}