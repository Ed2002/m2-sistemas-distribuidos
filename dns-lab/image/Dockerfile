# Imagem única usada por todos os nós (servidores BIND e cliente de teste)
FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bind9 bind9-utils bind9-dnsutils iproute2 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/entrypoint.sh"]
