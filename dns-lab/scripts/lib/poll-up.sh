#!/bin/sh
# Roda DENTRO do cliente. Espera um servidor voltar a responder a zona sd.lab.
# Uso: poll-up.sh IP   ->   imprime o instante (ns) da primeira resposta válida
IP=$1; FIM=$(( $(date +%s) + 60 ))
while :; do
  if [ -n "$(dig @"$IP" sd.lab SOA +short +time=1 +tries=1 2>/dev/null)" ]; then date +%s%N; exit 0; fi
  if [ "$(date +%s)" -gt "$FIM" ]; then echo "TIMEOUT"; exit 1; fi
done
