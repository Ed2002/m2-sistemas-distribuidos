# Funções compartilhadas pelos scripts (não execute este arquivo diretamente).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# Git Bash (Windows) reescreve argumentos como /scripts/x.sh para C:/Program Files/Git/...
# antes de passá-los ao docker; isto desliga essa conversão (não afeta Linux/macOS).
export MSYS_NO_PATHCONV=1

RAIZ=10.53.0.10; TLD=10.53.0.20; NS1=10.53.0.30; NS2=10.53.0.31; RESOLVER=10.53.0.53
EVID=evidencias
mkdir -p "$EVID"

dc()  { docker compose "$@"; }
cli() { docker compose exec -T client "$@"; }      # roda um comando no contêiner cliente
srv() { local s=$1; shift; docker compose exec -T "$s" "$@"; }

# Relógio de referência = relógio dos contêineres (vale também no Docker Desktop)
agora_ns()  { cli date +%s%N; }
agora_iso() { cli date -u +%Y-%m-%dT%H:%M:%S.%NZ; }

flush_cache() { srv resolver rndc flush >/dev/null; }

# Tempo de consulta informado pelo dig (ms)
query_ms() { cli dig "$@" +stats | awk '/Query time:/ {print $4}'; }

# Conta quantas consultas cada autoritativo recebeu numa janela de tempo
contar_consultas() {   # $1 = início ISO, $2 = fim ISO
  local s n
  for s in root tld-lab sd-primary sd-secondary; do
    n=$(dc logs --no-log-prefix --since "$1" --until "$2" "$s" 2>/dev/null | grep -c 'query:' || true)
    printf '%s=%s ' "$s" "$n"
  done
}

titulo() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
