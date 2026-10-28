#!/usr/bin/env bash
# Confere se o ambiente subiu certo: cada servidor, cada delegação e o resolvedor.
source "$(dirname "$0")/_comum.sh"

FALHAS=0
checar() {   # $1 = descrição, demais = comando dig a rodar no cliente
  local desc=$1; shift
  local out; out=$(cli dig "$@" 2>/dev/null | tr -s ' \t\n' ' ' | sed 's/ $//' || true)
  if [ -n "$out" ]; then printf '  \033[32m[OK]\033[0m    %-42s %s\n' "$desc" "$out"
  else printf '  \033[31m[FALHA]\033[0m %-42s\n' "$desc"; FALHAS=$((FALHAS+1)); fi
}

titulo "Servidores autoritativos"
checar "raiz responde por ."          @$RAIZ . SOA +short +norec
checar "raiz delega .lab"             @$RAIZ lab NS +norec +noall +authority
checar ".lab delega sd.lab"           @$TLD sd.lab NS +norec +noall +authority
checar "glue de sd.lab no .lab"       @$TLD www.sd.lab A +norec +noall +additional
checar "primário (ns1) responde"      @$NS1 www.sd.lab A +short +norec
checar "secundário (ns2) responde"    @$NS2 www.sd.lab A +short +norec

titulo "Consistência primário x secundário"
s1=$(cli dig @$NS1 sd.lab SOA +short | awk '{print $3}')
s2=$(cli dig @$NS2 sd.lab SOA +short | awk '{print $3}')
if [ -n "$s1" ] && [ "$s1" = "$s2" ]; then echo "  [OK]    serial igual nos dois: $s1"
else echo "  [FALHA] serial primário=$s1 secundário=$s2"; FALHAS=$((FALHAS+1)); fi

titulo "Resolvedor recursivo"
checar "resolve www.sd.lab"           @$RESOLVER www.sd.lab A +short
checar "resolve app.sd.lab (CNAME)"   @$RESOLVER app.sd.lab A +short

titulo "Limites de memória (R1)"
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' $(dc ps -q)

echo
if [ "$FALHAS" -eq 0 ]; then echo "Tudo certo."; else echo "$FALHAS verificação(ões) falharam — veja 'docker compose logs'."; fi
exit "$FALHAS"
