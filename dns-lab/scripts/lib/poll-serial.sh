#!/bin/sh
# Roda DENTRO do cliente. Espera um servidor passar a responder com o serial novo.
# Uso: poll-serial.sh SERIAL_NOVO IP   ->   imprime o instante (ns) em que o serial apareceu
NEW=$1; IP=${2:-10.53.0.31}
FIM=$(( $(date +%s) + 30 ))
while :; do
  s=$(dig @"$IP" sd.lab SOA +short +time=1 +tries=1 2>/dev/null | awk '{print $3}')
  if [ "$s" = "$NEW" ]; then date +%s%N; exit 0; fi
  if [ "$(date +%s)" -gt "$FIM" ]; then echo "TIMEOUT"; exit 1; fi
done
