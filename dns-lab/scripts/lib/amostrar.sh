#!/bin/sh
# Roda DENTRO do cliente. Faz uma série de consultas ao resolvedor em instantes fixos,
# medidos pelo relógio do contêiner (no Docker Desktop cada `docker compose exec` custa ~2 s,
# então cronometrar do lado de fora atrasa as amostras e estraga a contagem do TTL).
# Uso: amostrar.sh SEG:NOME [SEG:NOME ...]   ex.: amostrar.sh 0:curto.sd.lab 4:curto.sd.lab
# Saída (uma linha por amostra, separada por tab): inicio_iso fim_iso nome tempo_ms ttl
RESOLVER=${RESOLVER:-10.53.0.53}
T0=$(date +%s%N)
for item in "$@"; do
  seg=${item%%:*}; nome=${item#*:}
  falta=$(( (T0 + seg * 1000000000 - $(date +%s%N)) / 1000000 ))
  [ "$falta" -gt 0 ] && sleep "$(printf '%d.%03d' $((falta / 1000)) $((falta % 1000)))"
  a=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  out=$(dig @"$RESOLVER" "$nome" A +noall +answer +stats)
  sleep "${JANELA:-1}"   # janela em que a consulta pode chegar aos autoritativos
  b=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  ms=$(echo "$out" | awk '/Query time/{print $4}')
  ttl=$(echo "$out" | awk '$4=="A"{print $2; exit}')
  printf '%s\t%s\t%s\t%s\t%s\n' "$a" "$b" "$nome" "$ms" "$ttl"
done
