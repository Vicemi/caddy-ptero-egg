#!/bin/ash

# Obtener el puerto de la variable de entorno global del servidor
PORT="${SERVER_PORT:-8080}"

echo "Configurando Caddy para usar el puerto $PORT..."

# 1. Primero, verificar y reemplazar los puertos en la configuración global
echo "Actualizando puertos en configuración global..."
sed -i "s/http_port [0-9]\+/http_port $PORT/g" ./caddy/Caddyfile
sed -i "s/https_port [0-9]\+/https_port $PORT/g" ./caddy/Caddyfile

# 2. Buscar y reemplazar el puerto en la definición del sitio (:3095)
echo "Actualizando puerto del sitio..."
# Buscar línea que comience con :3095 y reemplazar
sed -i "s/^:3095/:$PORT/g" ./caddy/Caddyfile
# También buscar con espacios/tabs antes
sed -i "s/[[:space:]]*:3095/:$PORT/g" ./caddy/Caddyfile

# 3. Asegurar que PHP-FPM está configurado (añadirlo si no existe)
echo "Verificando configuración de PHP-FPM..."
if ! grep -q "php_fastcgi" ./caddy/Caddyfile; then
    echo "Añadiendo configuración PHP-FPM..."
    # Añadir después de 'file_server' o al final del bloque del sitio
    sed -i "/:${PORT} {/,/}/ {
        /file_server/a\
        php_fastcgi unix//var/run/php/php-fpm.sock
    }" ./caddy/Caddyfile
fi

# 4. Asegurar que el root path es correcto para tu contenedor
echo "Verificando ruta root..."
sed -i "s|root \* .*$|root * /home/container/public|g" ./caddy/Caddyfile

# 5. Formatear el Caddyfile
echo "Formateando Caddyfile..."
./caddy-server fmt --overwrite ./caddy/Caddyfile

# 6. Mostrar la configuración final para depuración
echo "=== Configuración final del Caddyfile ==="
cat ./caddy/Caddyfile
echo "=========================================="

# 7. Iniciar PHP-FPM
echo "Iniciando PHP-FPM..."
PHP_FPM=$(find /usr/sbin -name "php-fpm*" -type f | tail -n 1)
$PHP_FPM --fpm-config /home/container/php-fpm/php-fpm.conf -c /home/container/php-fpm/ --daemonize

# 8. Verificar que PHP-FPM está corriendo
sleep 2
if pgrep -x "php-fpm" > /dev/null; then
    echo "PHP-FPM iniciado correctamente"
else
    echo "ERROR: PHP-FPM no se inició. Intentando alternativa..."
    # Intentar con un método alternativo
    php-fpm82 --fpm-config /home/container/php-fpm/php-fpm.conf -y /home/container/php-fpm/php-fpm.conf --daemonize || true
fi

# 9. Verificar que el socket de PHP-FPM existe
echo "Verificando socket PHP-FPM..."
if [ -S "/var/run/php/php-fpm.sock" ]; then
    echo "Socket PHP-FPM encontrado"
else
    echo "Buscando socket PHP-FPM alternativo..."
    # Intentar encontrar el socket
    find /var/run -name "*.sock" -type s 2>/dev/null || echo "No se encontraron sockets"
fi

# 10. Iniciar Caddy
echo "Iniciando Caddy en el puerto $PORT..."
./caddy-server run --watch --config ./caddy/Caddyfile
