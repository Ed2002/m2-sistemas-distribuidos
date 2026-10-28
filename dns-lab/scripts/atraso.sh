#!/usr/bin/env bash
# OPCIONAL — Simula distância de rede nos autoritativos (como a raiz real, que fica longe).
# Deixa a diferença "cache vazio x cache" bem visível no E9 e no vídeo.
# Uso: scripts/atraso.sh 20ms   |   scripts/atraso.sh off
# Precisa do módulo netem no kernel do Docker (Linux e Docker Desktop costumam ter).
source "$(dirname "$0")/_comum.sh"
VAL=${1:-20ms}
for s in root tld-lab sd-primary sd-secondary; do
  if [ "$VAL" = "off" ]; then
    srv "$s" tc qdisc del dev eth0 root 2>/dev/null && echo "  $s: sem atraso" || echo "  $s: já estava sem atraso"
  else
    if srv "$s" tc qdisc replace dev eth0 root netem delay "$VAL" 2>/dev/null; then echo "  $s: +$VAL"
    else echo "  $s: netem indisponível neste kernel — siga sem o atraso (o E9 continua válido)"; fi
  fi
done
