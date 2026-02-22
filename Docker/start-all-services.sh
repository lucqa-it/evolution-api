#!/bin/bash

# =============================================================================
# Evolution API - Script para levantar todos los servicios Docker
# Excluye: swarm
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_FILE="$SCRIPT_DIR/credentials-$(date +%Y%m%d_%H%M%S).txt"
TEMP_DIR="$SCRIPT_DIR/.temp_compose"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "============================================================================="
echo "   Evolution API - Configuración de Servicios Docker"
echo "============================================================================="
echo -e "${NC}"

# Función para leer input con valor por defecto
read_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_password="$4"
    
    if [ "$is_password" = "true" ]; then
        echo -ne "${YELLOW}$prompt [$default]: ${NC}"
        read -s input
        echo ""
    else
        echo -ne "${YELLOW}$prompt [$default]: ${NC}"
        read input
    fi
    
    if [ -z "$input" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

# Función para generar password aleatorio
generate_password() {
    openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16
}

# Crear directorio temporal
mkdir -p "$TEMP_DIR"

echo -e "${GREEN}Vamos a configurar las credenciales para cada servicio.${NC}"
echo -e "${GREEN}Presiona ENTER para usar el valor por defecto mostrado entre corchetes.${NC}"
echo ""

# =============================================================================
# MINIO
# =============================================================================
echo -e "${BLUE}--- MinIO (Almacenamiento S3) ---${NC}"
DEFAULT_MINIO_USER="admin"
DEFAULT_MINIO_PASS=$(generate_password)
read_with_default "Usuario MinIO" "$DEFAULT_MINIO_USER" "MINIO_USER" "false"
read_with_default "Password MinIO" "$DEFAULT_MINIO_PASS" "MINIO_PASS" "true"
read_with_default "URL del navegador MinIO" "http://localhost:9001" "MINIO_BROWSER_URL" "false"
read_with_default "URL del servidor MinIO" "http://localhost:9000" "MINIO_SERVER_URL" "false"
echo ""

# =============================================================================
# MYSQL
# =============================================================================
echo -e "${BLUE}--- MySQL ---${NC}"
DEFAULT_MYSQL_ROOT_PASS=$(generate_password)
read_with_default "Password root MySQL" "$DEFAULT_MYSQL_ROOT_PASS" "MYSQL_ROOT_PASS" "true"
read_with_default "Zona horaria" "America/Sao_Paulo" "MYSQL_TZ" "false"
echo ""

# =============================================================================
# POSTGRESQL
# =============================================================================
echo -e "${BLUE}--- PostgreSQL ---${NC}"
DEFAULT_POSTGRES_PASS=$(generate_password)
read_with_default "Password PostgreSQL" "$DEFAULT_POSTGRES_PASS" "POSTGRES_PASS" "true"
echo ""

echo -e "${BLUE}--- PgAdmin (Panel PostgreSQL) ---${NC}"
DEFAULT_PGADMIN_EMAIL="admin@evolution.local"
DEFAULT_PGADMIN_PASS=$(generate_password)
read_with_default "Email PgAdmin" "$DEFAULT_PGADMIN_EMAIL" "PGADMIN_EMAIL" "false"
read_with_default "Password PgAdmin" "$DEFAULT_PGADMIN_PASS" "PGADMIN_PASS" "true"
echo ""

# =============================================================================
# RABBITMQ
# =============================================================================
echo -e "${BLUE}--- RabbitMQ ---${NC}"
DEFAULT_RABBITMQ_USER="admin"
DEFAULT_RABBITMQ_PASS=$(generate_password)
DEFAULT_RABBITMQ_COOKIE=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 40)
read_with_default "Usuario RabbitMQ" "$DEFAULT_RABBITMQ_USER" "RABBITMQ_USER" "false"
read_with_default "Password RabbitMQ" "$DEFAULT_RABBITMQ_PASS" "RABBITMQ_PASS" "true"
read_with_default "Erlang Cookie" "$DEFAULT_RABBITMQ_COOKIE" "RABBITMQ_COOKIE" "false"
echo ""

# =============================================================================
# REDIS
# =============================================================================
echo -e "${BLUE}--- Redis ---${NC}"
DEFAULT_REDIS_PASS=$(generate_password)
read_with_default "Password Redis (vacío para sin password)" "$DEFAULT_REDIS_PASS" "REDIS_PASS" "true"
echo ""

# =============================================================================
# KAFKA
# =============================================================================
echo -e "${BLUE}--- Kafka ---${NC}"
echo -e "${GREEN}Kafka no requiere credenciales adicionales en esta configuración.${NC}"
echo ""

# =============================================================================
# Crear archivos docker-compose temporales con las credenciales
# =============================================================================
echo -e "${BLUE}Creando archivos de configuración...${NC}"

# MinIO
cat > "$TEMP_DIR/minio-docker-compose.yaml" << EOF
version: '3.3'

services:
  minio:
    container_name: minio
    image: quay.io/minio/minio
    networks:
      - evolution-net
    command: server /data --console-address ":9001"
    restart: always
    ports:
      - 9000:9000
      - 9001:9001
    environment:
      - MINIO_ROOT_USER=$MINIO_USER
      - MINIO_ROOT_PASSWORD=$MINIO_PASS
      - MINIO_BROWSER_REDIRECT_URL=$MINIO_BROWSER_URL
      - MINIO_SERVER_URL=$MINIO_SERVER_URL
    volumes:
      - minio_data:/data
    expose:
      - 9000
      - 9001

volumes:
  minio_data:

networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF

# MySQL
cat > "$TEMP_DIR/mysql-docker-compose.yaml" << EOF
version: '3.3'

services:
  mysql:
    container_name: mysql
    image: percona/percona-server:8.0
    networks:
      - evolution-net
    restart: always
    ports:
      - 3306:3306
    environment:
      - MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
      - TZ=$MYSQL_TZ
    volumes:
      - mysql_data:/var/lib/mysql
    expose:
      - 3306

volumes:
  mysql_data:

networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF

# PostgreSQL
cat > "$TEMP_DIR/postgres-docker-compose.yaml" << EOF
version: '3.3'

services:
  postgres:
    container_name: postgres
    image: postgres:15
    networks:
      - evolution-net
    command: ["postgres", "-c", "max_connections=1000"]
    restart: always
    ports:
      - 5432:5432
    environment:
      - POSTGRES_PASSWORD=$POSTGRES_PASS
    volumes:
      - postgres_data:/var/lib/postgresql/data
    expose:
      - 5432

  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: pgadmin
    networks:
      - evolution-net
    environment:
      - PGADMIN_DEFAULT_EMAIL=$PGADMIN_EMAIL
      - PGADMIN_DEFAULT_PASSWORD=$PGADMIN_PASS
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    ports:
      - 4000:80
    links:
      - postgres

volumes:
  postgres_data:
  pgadmin_data:

networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF

# RabbitMQ
cat > "$TEMP_DIR/rabbitmq-docker-compose.yaml" << EOF
version: '3.3'

services:
  rabbitmq:
    container_name: rabbitmq
    image: rabbitmq:management
    networks:
      - evolution-net
    environment:
      - RABBITMQ_ERLANG_COOKIE=$RABBITMQ_COOKIE
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=$RABBITMQ_USER
      - RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASS
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq/
    ports:
      - 5672:5672
      - 15672:15672

volumes:
  rabbitmq_data:

networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF

# Redis
if [ -z "$REDIS_PASS" ]; then
    REDIS_COMMAND="redis-server --port 6379 --appendonly yes"
else
    REDIS_COMMAND="redis-server --port 6379 --appendonly yes --requirepass $REDIS_PASS"
fi

cat > "$TEMP_DIR/redis-docker-compose.yaml" << EOF
version: '3.3'

services:
  redis:
    image: redis:latest
    networks:
      - evolution-net
    container_name: redis
    command: >
      $REDIS_COMMAND
    volumes:
      - evolution_redis:/data
    ports:
      - 6379:6379

volumes:
  evolution_redis:

networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF

# Kafka (sin cambios)
cp "$SCRIPT_DIR/kafka/docker-compose.yaml" "$TEMP_DIR/kafka-docker-compose.yaml"

# =============================================================================
# Guardar credenciales en archivo
# =============================================================================
echo -e "${BLUE}Guardando credenciales en: $CREDENTIALS_FILE${NC}"

cat > "$CREDENTIALS_FILE" << EOF
================================================================================
  CREDENCIALES DE SERVICIOS DOCKER - Evolution API
  Generado: $(date)
================================================================================

## IMPORTANTE ##
Guarda este archivo en un lugar seguro y elimínalo después de usar las credenciales.

--------------------------------------------------------------------------------
MINIO (Almacenamiento S3)
--------------------------------------------------------------------------------
  URL Consola: $MINIO_BROWSER_URL
  URL API:     $MINIO_SERVER_URL
  Usuario:     $MINIO_USER
  Password:    $MINIO_PASS
  Puertos:     9000 (API), 9001 (Consola)

--------------------------------------------------------------------------------
MYSQL
--------------------------------------------------------------------------------
  Host:        localhost
  Puerto:      3306
  Usuario:     root
  Password:    $MYSQL_ROOT_PASS
  Timezone:    $MYSQL_TZ

  Connection String:
  mysql://root:$MYSQL_ROOT_PASS@localhost:3306/evolution

--------------------------------------------------------------------------------
POSTGRESQL
--------------------------------------------------------------------------------
  Host:        localhost
  Puerto:      5432
  Usuario:     postgres
  Password:    $POSTGRES_PASS
  
  Connection String:
  postgresql://postgres:$POSTGRES_PASS@localhost:5432/evolution

  PgAdmin:
    URL:       http://localhost:4000
    Email:     $PGADMIN_EMAIL
    Password:  $PGADMIN_PASS

--------------------------------------------------------------------------------
RABBITMQ
--------------------------------------------------------------------------------
  Host:            localhost
  Puerto AMQP:     5672
  Puerto Admin:    15672
  URL Admin:       http://localhost:15672
  Usuario:         $RABBITMQ_USER
  Password:        $RABBITMQ_PASS
  VHost:           default
  Erlang Cookie:   $RABBITMQ_COOKIE

  Connection String:
  amqp://$RABBITMQ_USER:$RABBITMQ_PASS@localhost:5672/default

--------------------------------------------------------------------------------
REDIS
--------------------------------------------------------------------------------
  Host:        localhost
  Puerto:      6379
  Password:    ${REDIS_PASS:-"(sin password)"}

  Connection String:
EOF

if [ -z "$REDIS_PASS" ]; then
    echo "  redis://localhost:6379" >> "$CREDENTIALS_FILE"
else
    echo "  redis://:$REDIS_PASS@localhost:6379" >> "$CREDENTIALS_FILE"
fi

cat >> "$CREDENTIALS_FILE" << EOF

--------------------------------------------------------------------------------
KAFKA
--------------------------------------------------------------------------------
  Zookeeper:       localhost:2181
  Broker:          localhost:9092
  Broker Interno:  localhost:29092
  Broker Externo:  localhost:9094
  
  Sin autenticación (modo desarrollo)

================================================================================
  VARIABLES DE ENTORNO PARA .env
================================================================================

# Database (elegir uno)
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://postgres:$POSTGRES_PASS@localhost:5432/evolution

# O para MySQL:
# DATABASE_PROVIDER=mysql
# DATABASE_CONNECTION_URI=mysql://root:$MYSQL_ROOT_PASS@localhost:3306/evolution

# Redis
REDIS_ENABLED=true
REDIS_URI=redis://${REDIS_PASS:+":$REDIS_PASS@"}localhost:6379
REDIS_PREFIX_KEY=evolution

# RabbitMQ
RABBITMQ_ENABLED=true
RABBITMQ_URI=amqp://$RABBITMQ_USER:$RABBITMQ_PASS@localhost:5672/default

# S3/MinIO Storage
S3_ENABLED=true
S3_ACCESS_KEY=$MINIO_USER
S3_SECRET_KEY=$MINIO_PASS
S3_BUCKET=evolution
S3_ENDPOINT=localhost
S3_PORT=9000
S3_USE_SSL=false

================================================================================
EOF

echo -e "${GREEN}✓ Credenciales guardadas${NC}"
echo ""

# =============================================================================
# Función para levantar servicios
# =============================================================================
start_service() {
    local service_name="$1"
    local compose_file="$2"
    
    echo -e "${YELLOW}Iniciando $service_name...${NC}"
    
    if docker compose -f "$compose_file" up -d 2>/dev/null || docker-compose -f "$compose_file" up -d 2>/dev/null; then
        echo -e "${GREEN}✓ $service_name iniciado correctamente${NC}"
        return 0
    else
        echo -e "${RED}✗ Error al iniciar $service_name${NC}"
        return 1
    fi
}

# =============================================================================
# Preguntar si desea levantar los servicios
# =============================================================================
echo ""
echo -e "${BLUE}¿Deseas levantar los servicios ahora? (s/n) [s]: ${NC}"
read START_SERVICES

if [ -z "$START_SERVICES" ] || [ "$START_SERVICES" = "s" ] || [ "$START_SERVICES" = "S" ]; then
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}   Iniciando servicios Docker...${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
    
    # Orden de inicio (dependencias primero)
    start_service "Redis" "$TEMP_DIR/redis-docker-compose.yaml"
    echo ""
    
    start_service "PostgreSQL + PgAdmin" "$TEMP_DIR/postgres-docker-compose.yaml"
    echo ""
    
    start_service "MySQL" "$TEMP_DIR/mysql-docker-compose.yaml"
    echo ""
    
    start_service "RabbitMQ" "$TEMP_DIR/rabbitmq-docker-compose.yaml"
    echo ""
    
    start_service "MinIO" "$TEMP_DIR/minio-docker-compose.yaml"
    echo ""
    
    start_service "Kafka + Zookeeper" "$TEMP_DIR/kafka-docker-compose.yaml"
    echo ""
    
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${GREEN}   ¡Todos los servicios han sido iniciados!${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
    
    # Mostrar estado de contenedores
    echo -e "${YELLOW}Estado de los contenedores:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "redis|postgres|pgadmin|mysql|rabbitmq|minio|kafka|zookeeper" || true
    echo ""
fi

echo -e "${GREEN}=============================================================================${NC}"
echo -e "${GREEN}   Archivo de credenciales: $CREDENTIALS_FILE${NC}"
echo -e "${GREEN}=============================================================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANTE:${NC}"
echo -e "  - Guarda las credenciales en un lugar seguro"
echo -e "  - Los archivos temporales están en: $TEMP_DIR"
echo -e "  - Para detener servicios: docker compose -f <archivo> down"
echo ""

# =============================================================================
# Preguntar si desea eliminar archivos temporales
# =============================================================================
echo -e "${BLUE}¿Deseas mantener los archivos docker-compose temporales? (s/n) [s]: ${NC}"
read KEEP_TEMP

if [ "$KEEP_TEMP" = "n" ] || [ "$KEEP_TEMP" = "N" ]; then
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓ Archivos temporales eliminados${NC}"
else
    echo -e "${GREEN}✓ Archivos temporales mantenidos en: $TEMP_DIR${NC}"
fi

echo ""
echo -e "${GREEN}¡Listo!${NC}"
