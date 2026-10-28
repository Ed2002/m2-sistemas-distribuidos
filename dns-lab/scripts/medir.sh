#!/usr/bin/env bash
# R7 — Medições com repetição (padrão: 5 rodadas), com média e desvio padrão amostral.
#   latencia_fria     resolução com cache vazio (percorre raiz -> .lab -> sd.lab)
#   latencia_quente   mesma consulta respondida do cache
#   propagacao        primário publica serial novo -> secundário passa a servir (NOTIFY + IXFR)
#   recuperacao       secundário reiniciado -> volta a responder a zona (inclui nova transferência)
#   failover          resolução com o primário (ns1) fora do ar, só o secundário respondendo
# "Eleição" não se aplica ao DNS: o primário é fixo por configuração (ver resumo).
source "$(dirname "$0")/_comum.sh"
N=${N:-5}
CSV="$EVID/medicoes.csv"; RES="$EVID/medicoes-resumo.txt"
echo "metrica,rodada,valor_ms" > "$CSV"
reg() { echo "$1,$2,$3" >> "$CSV"; printf '  %-16s rodada %d: %s ms\n' "$1" "$2" "$3"; }

titulo "Latência de resolução (fria x quente)"
for i in $(seq 1 "$N"); do
  flush_cache; sleep 0.5
  reg latencia_fria   "$i" "$(query_ms @$RESOLVER www.sd.lab A)"
  reg latencia_quente "$i" "$(query_ms @$RESOLVER www.sd.lab A)"
done

titulo "Propagação primário -> secundário (reload no primário até o secundário servir o serial novo)"
# Rodadas espaçadas em 6 s: o BIND agrupa NOTIFYs da mesma zona em janelas de 5 s (notify-delay).
TMP=$(mktemp)
for i in $(seq 1 "$N"); do
  atual=$(cli dig @$NS1 sd.lab SOA +short | awk '{print $3}')
  novo=$((atual + 1))
  cli sh /scripts/poll-serial.sh "$novo" $NS2 > "$TMP" &
  pid=$!; sleep 0.5
  t0=$(srv sd-primary sh -c "sed -i -E 's/[0-9]{10} ; serial/$novo ; serial/; s/^versao .*/versao      IN TXT   \"$novo\"/' \
                             /var/lib/bind/db.sd.lab && date +%s%N && rndc reload sd.lab >/dev/null")
  wait "$pid" || true
  t1=$(cat "$TMP")
  if [ "$t1" = "TIMEOUT" ]; then reg propagacao "$i" "TIMEOUT"; else reg propagacao "$i" "$(( (t1 - t0) / 1000000 ))"; fi
  sleep 6
done
rm -f "$TMP"

titulo "Recuperação do secundário (stop -> start -> zona servida de novo)"
for i in $(seq 1 "$N"); do
  dc stop sd-secondary >/dev/null 2>&1
  t0=$(agora_ns)
  dc start sd-secondary >/dev/null 2>&1
  t1=$(cli sh /scripts/poll-up.sh $NS2)
  if [ "$t1" = "TIMEOUT" ]; then reg recuperacao "$i" "TIMEOUT"; else reg recuperacao "$i" "$(( (t1 - t0) / 1000000 ))"; fi
  sleep 1
done

titulo "Failover: resolução com o primário (ns1) fora do ar"
dc stop sd-primary >/dev/null 2>&1
for i in $(seq 1 "$N"); do
  flush_cache; sleep 0.5
  reg failover "$i" "$(query_ms @$RESOLVER www.sd.lab A +time=15 +tries=1)"
done
dc start sd-primary >/dev/null 2>&1
cli sh /scripts/poll-up.sh $NS1 >/dev/null

titulo "Resumo (média e desvio padrão amostral)"
awk -F, -v n="$N" '
  NR>1 && $3 ~ /^[0-9]+$/ { s[$1]+=$3; q[$1]+=$3*$3; c[$1]++; if(!($1 in o)){o[$1]=++k; nome[k]=$1} }
  END {
    printf "%-16s %4s %10s %10s\n", "metrica", "n", "media_ms", "desvio_ms"
    for (j=1;j<=k;j++) { m=nome[j]; mu=s[m]/c[m]
      sd=(c[m]>1)? sqrt((q[m]-c[m]*mu*mu)/(c[m]-1)) : 0; if (sd<0) sd=0
      printf "%-16s %4d %10.1f %10.1f\n", m, c[m], mu, sd }
    print ""
    print "eleicao: nao se aplica. No DNS o primario e definido na configuracao (type primary/secondary);"
    print "nao ha eleicao de lider. A medida analoga e o failover: com ns1 fora, o resolvedor usa ns2."
    print "Resolucao: o dig informa o tempo em ms inteiros; os polls de propagacao/recuperacao tem resolucao de poucos ms."
  }' "$CSV" | tee "$RES"

echo; echo "Dados brutos: $CSV | Resumo: $RES"
