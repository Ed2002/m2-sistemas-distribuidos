#!/usr/bin/env bash
# E9 (extra) — Por que o glue existe? Quebra a delegação de propósito e mostra o efeito.
#   a) zona .lab SEM glue: o named-checkzone acusa "no REQUIRED GLUE" (é aviso: a zona ainda carrega)
#   b) glue com IP ERRADO: a delegação quebra e o resolvedor devolve SERVFAIL
#   c) restaura o .lab original e confere que voltou a funcionar
# A alteração é feita só dentro do contêiner; o repositório não é modificado.
source "$(dirname "$0")/_comum.sh"
OUT="$EVID/e9-6-glue.txt"
: > "$OUT"

titulo "a) Zona .lab sem os registros de glue de sd.lab"
srv tld-lab sh -c "grep -vE '^ns[12]\.sd' /var/lib/bind/db.lab > /tmp/db.lab.semglue; \
                   named-checkzone lab /tmp/db.lab.semglue" 2>&1 | tee -a "$OUT" || true

titulo "b) Glue apontando para IPs que não existem (10.53.0.98 e .99)"
srv tld-lab sh -c "sed -i -E 's/^(ns1\.sd .*)10\.53\.0\.30/\110.53.0.98/; s/^(ns2\.sd .*)10\.53\.0\.31/\110.53.0.99/; \
                   s/[0-9]{10} ; serial/2026102899 ; serial/' /var/lib/bind/db.lab && rndc reload lab" | tee -a "$OUT"
sleep 1; flush_cache
{
  echo "### Glue publicado agora pelo .lab:"
  cli dig @$TLD www.sd.lab A +norecurse +noall +additional
  echo "### Resolução via resolvedor (espera os timeouts):"
  cli dig @$RESOLVER www.sd.lab A +time=15 +tries=1 | grep -E 'status:|Query time|ANSWER SECTION' || true
} 2>&1 | tee -a "$OUT"

titulo "c) Restaurando o .lab original"
dc restart tld-lab >/dev/null; sleep 2; flush_cache
cli dig @$RESOLVER www.sd.lab A | grep -E 'status:|Query time|^www' | tee -a "$OUT"

echo; echo "Evidência salva em $OUT"
