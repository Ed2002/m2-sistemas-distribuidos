#!/usr/bin/env bash
# E9 — Ênfase A: hierarquia e delegação.
# Gera as evidências em evidencias/e9-*.txt:
#   1. cadeia de delegação (referências com NS + glue de cada nível)
#   2. resolução completa com dig +trace
#   3. cache do resolvedor: 1ª consulta x seguintes (tempo + quem foi consultado)
#   4. expiração do TTL (registro curto.sd.lab com TTL de 10 s)
#   5. conteúdo do cache do resolvedor (rndc dumpdb)
source "$(dirname "$0")/_comum.sh"
N=${N:-5}

# ---------------------------------------------------------------- 1
titulo "1) Cadeia de delegação: raiz -> .lab -> sd.lab"
{
  echo "### Pergunta à RAIZ ($RAIZ), sem recursão: ela não sabe a resposta, só indica quem sabe (.lab)"
  cli dig @$RAIZ www.sd.lab A +norecurse
  echo; echo "### Pergunta ao TLD .lab ($TLD): indica os servidores de sd.lab + glue (endereços)"
  cli dig @$TLD www.sd.lab A +norecurse
  echo; echo "### Pergunta ao autoritativo de sd.lab ($NS1): resposta final com flag aa"
  cli dig @$NS1 www.sd.lab A +norecurse
} | tee "$EVID/e9-1-delegacao.txt" | grep -E '^###|flags:|IN\s+(NS|A)\s' || true

# ---------------------------------------------------------------- 2
titulo "2) Resolução completa: dig +trace www.sd.lab"
cli dig +trace +additional www.sd.lab @$RESOLVER | tee "$EVID/e9-2-trace.txt"

# ---------------------------------------------------------------- 3
# As consultas rodam todas dentro do cliente (lib/amostrar.sh), em instantes fixos;
# a contagem nos logs dos autoritativos é feita depois, com os horários registrados.
linha() {   # $1 = rótulo; lê "inicio fim nome ms ttl" e imprime a linha da tabela
  local a b nome ms ttl
  IFS=$'	' read -r a b nome ms ttl
  printf '%-24s %10s %6s   %s
' "$1" "$ms" "$ttl" "$(contar_consultas "$a" "$b")"
}

titulo "3) Cache do resolvedor: 1ª consulta x seguintes"
flush_cache; sleep 1
{
  amostras="0:www.sd.lab"
  for i in $(seq 2 $((N+1))); do amostras+=" $i:www.sd.lab"; done
  amostras+=" $((N+2)):api.sd.lab"
  mapfile -t res < <(cli sh /scripts/amostrar.sh $amostras)
  printf '%-24s %10s %6s   %s
' "consulta" "tempo(ms)" "TTL" "consultas que chegaram aos autoritativos"
  linha "1 (cache vazio)" <<<"${res[0]}"
  for i in $(seq 2 $((N+1))); do linha "$i (cache)" <<<"${res[$((i-1))]}"; done
  linha "api.sd.lab (outro nome)" <<<"${res[$((N+1))]}"
  IFS=$'	' read -r t0 t1 _ <<<"${res[0]}"
  echo
  echo "Consultas que os autoritativos receberam na 1ª resolução (cache vazio), em ordem de chegada:"
  dc logs --no-log-prefix --timestamps --since "$t0" --until "$t1" root tld-lab sd-primary sd-secondary 2>/dev/null     | grep 'query:' | sort -k1,1 | sed -E 's/^([^ ]+) .*client @0x[0-9a-f]+ /  /'
} | tee "$EVID/e9-3-cache.txt"

# ---------------------------------------------------------------- 4
titulo "4) Expiração do TTL (curto.sd.lab, TTL = 10 s)"
flush_cache; sleep 1
{
  mapfile -t res < <(cli sh /scripts/amostrar.sh 0:curto.sd.lab 4:curto.sd.lab 8:curto.sd.lab                                                   12:curto.sd.lab 16:curto.sd.lab)
  printf '%-6s %10s %6s   %s
' "t(s)" "tempo(ms)" "TTL" "consultas que chegaram aos autoritativos"
  i=0
  for t in 0 4 8 12 16; do
    IFS=$'	' read -r a b _ ms ttl <<<"${res[$i]}"; i=$((i+1))
    printf '%-6s %10s %6s   %s
' "$t" "$ms" "$ttl" "$(contar_consultas "$a" "$b")"
  done
  echo "Quando o TTL chega a 0, a entrada sai do cache e o resolvedor volta a consultar o autoritativo."
} | tee "$EVID/e9-4-ttl.txt"

# ---------------------------------------------------------------- 5
titulo "5) O que ficou no cache do resolvedor"
cli dig @$RESOLVER www.sd.lab A +short >/dev/null
srv resolver rndc dumpdb -cache; sleep 1
srv resolver sh -c "sed -n \"/^; Cache dump of view '_default'/,/^; Cache dump of view '_bind'/p\" /var/cache/bind/named_dump.db" \
  | grep -v "_bind" | tee "$EVID/e9-5-cache-dump.txt"

echo; echo "Evidências salvas em $EVID/e9-*.txt"
