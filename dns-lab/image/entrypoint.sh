#!/bin/sh
# Prepara o contêiner e inicia o BIND em primeiro plano (logs vão para `docker compose logs`).
set -e

# As zonas chegam somente leitura em /zones; copiamos para um diretório gravável
# para os scripts poderem alterar a zona (serial, glue) sem mexer nos arquivos do repositório.
mkdir -p /var/lib/bind /var/cache/bind /run/named
if [ -d /zones ]; then
  cp /zones/* /var/lib/bind/ 2>/dev/null || true
fi

# Chave do rndc (o pacote já gera; isto é só uma garantia)
[ -s /etc/bind/rndc.key ] || rndc-confgen -a >/dev/null 2>&1

chown -R bind:bind /var/lib/bind /var/cache/bind /run/named
chown root:bind /etc/bind/rndc.key && chmod 640 /etc/bind/rndc.key

named-checkconf -z /etc/bind/named.conf

# -g: primeiro plano, log no stderr | -u bind: sem root | -n 2: duas threads (economiza memória)
exec /usr/sbin/named -g -u bind -n 2 -c /etc/bind/named.conf
