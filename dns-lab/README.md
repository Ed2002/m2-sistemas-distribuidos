# Laboratório DNS — Hierarquia e Delegação (T1 · Ênfase A)

Ambiente com BIND 9 em contêineres que monta uma **raiz fictícia**, o **TLD `.lab`** e a zona **`sd.lab`** com delegação real (registros NS + glue), um **resolvedor recursivo com cache** e um **cliente** para os testes.

```
                 ┌──────────────────────┐
                 │ raiz  "."            │ a.root-servers.lab   10.53.0.10
                 └──────────┬───────────┘
                     NS + glue de .lab
                 ┌──────────▼───────────┐
                 │ TLD  "lab"           │ ns1.nic.lab          10.53.0.20
                 └──────────┬───────────┘
                     NS + glue de sd.lab
          ┌─────────────────┴──────────────────┐
┌─────────▼──────────┐   NOTIFY + IXFR  ┌───────▼────────────┐
│ sd.lab  primário   │ ───────────────▶ │ sd.lab  secundário │
│ ns1.sd.lab         │                  │ ns2.sd.lab         │
│ 10.53.0.30         │                  │ 10.53.0.31         │
└────────────────────┘                  └────────────────────┘
          ▲ consultas iterativas (raiz → .lab → sd.lab)
┌─────────┴──────────┐        ┌────────────────────┐
│ resolvedor (cache) │ ◀───── │ cliente (dig)      │
│ 10.53.0.53         │        │ 10.53.0.100        │
└────────────────────┘        └────────────────────┘
```

| Serviço | Papel | IP | Limite de memória |
|---|---|---|---|
| `root` | Autoritativo da raiz `.` | 10.53.0.10 | 128 MB |
| `tld-lab` | Autoritativo do TLD `.lab` | 10.53.0.20 | 128 MB |
| `sd-primary` | Primário de `sd.lab` | 10.53.0.30 | 128 MB |
| `sd-secondary` | Secundário de `sd.lab` | 10.53.0.31 | 128 MB |
| `resolver` | Resolvedor recursivo com cache | 10.53.0.53 | 128 MB (cache limitado a 32 MB) |
| `client` | Ferramentas de teste (`dig`) | 10.53.0.100 | 64 MB |

Na prática cada `named` usa entre 5 e 6 MB no Linux e uns 23 MB no Docker Desktop (Windows); confira com `docker stats`.

## Requisitos

- Docker com Compose v2 (`docker compose version`)
- Um terminal `bash` para os scripts: Linux, macOS, WSL ou Git Bash no Windows

## Subir do zero

```bash
git clone <url-do-repositorio> dns-lab && cd dns-lab
docker compose up -d --build
./scripts/verificar.sh
```

O `verificar.sh` confere cada servidor, as duas delegações, o glue, a sincronização primário/secundário, o resolvedor e mostra o uso de memória de cada contêiner. Deve terminar com **"Tudo certo."**

Para derrubar: `docker compose down`. Para recomeçar limpo: `docker compose down && docker compose up -d`.

## Experimentos

### E9 — Ênfase A: hierarquia e delegação

```bash
./scripts/e9.sh          # cadeia de delegação, dig +trace, cache 1ª x seguintes, TTL, dump do cache
./scripts/e9-glue.sh     # extra: quebra o glue de propósito e mostra o SERVFAIL
```

O que cada parte gera em `evidencias/`:

| Arquivo | O que mostra |
|---|---|
| `e9-1-delegacao.txt` | Cada nível respondendo sem recursão: a raiz indica `.lab` (com glue), o `.lab` indica `sd.lab` (com glue) e o `sd.lab` responde com a flag `aa` |
| `e9-2-trace.txt` | `dig +trace` descendo raiz → `.lab` → `sd.lab` |
| `e9-3-cache.txt` | Tempo e TTL da 1ª consulta (cache vazio) x seguintes, e **quantas consultas chegaram a cada autoritativo** em cada caso. Mostra também um outro nome da mesma zona indo direto para `sd.lab` |
| `e9-4-ttl.txt` | `curto.sd.lab` (TTL 10 s) contando até 0 e o resolvedor voltando ao autoritativo |
| `e9-5-cache-dump.txt` | O que o resolvedor guardou (NS, glue, respostas, com TTL restante) |
| `e9-6-glue.txt` | Zona sem glue rejeitada pelo `named-checkzone`; glue com IP errado gerando SERVFAIL; restauração |

**Opcional — atraso de rede:** `./scripts/atraso.sh 20ms` coloca 20 ms em cada autoritativo, como se estivessem longe. A diferença entre a 1ª consulta e as seguintes fica muito mais visível no vídeo. Desliga com `./scripts/atraso.sh off`. Depende do módulo `netem` no kernel do Docker; se não houver, o script avisa e nada muda.

### R7 — Medições com repetição

```bash
./scripts/medir.sh          # 5 rodadas (padrão)
N=10 ./scripts/medir.sh     # mais rodadas
```

| Métrica | O que mede |
|---|---|
| `latencia_fria` | Resolução com cache vazio (percorre a hierarquia toda) |
| `latencia_quente` | A mesma consulta respondida do cache |
| `propagacao` | Do `rndc reload` no primário até o secundário servir o serial novo (NOTIFY + IXFR) |
| `recuperacao` | Do `docker compose start` do secundário até ele voltar a servir a zona (inclui nova transferência) |
| `failover` | Resolução com o primário fora do ar, só o secundário respondendo |

Gera `evidencias/medicoes.csv` (dados brutos) e `evidencias/medicoes-resumo.txt` (média e desvio padrão amostral).

**Eleição** não se aplica: no DNS o primário é fixo por configuração (`type primary` / `type secondary`), não existe eleição de líder. O `failover` é a medida análoga.

## Comandos úteis

```bash
# Consultas a partir do cliente
docker compose exec client dig @10.53.0.53 www.sd.lab                 # via resolvedor
docker compose exec client dig @10.53.0.10 www.sd.lab +norecurse      # direto na raiz: só a referência
docker compose exec client dig +trace www.sd.lab @10.53.0.53          # resolução completa
docker compose exec client dig @10.53.0.30 sd.lab AXFR                # transferência de zona

# Resolvedor
docker compose exec resolver rndc flush                               # limpa o cache
docker compose exec resolver rndc dumpdb -cache                       # despeja o cache em /var/cache/bind/named_dump.db

# Logs (cada consulta recebida aparece aqui)
docker compose logs -f root tld-lab sd-primary sd-secondary
```

## Decisões de configuração (vale citar no relatório)

- **Root hints próprios** (`config/resolver/zones/db.root.hints`): o resolvedor só conhece a nossa raiz, nunca a da internet.
- **`dnssec-validation no`** no resolvedor: a raiz fictícia não é assinada. Com o padrão (`auto`), o BIND usaria a âncora de confiança da raiz real e responderia SERVFAIL para tudo.
- **`prefetch 0`** no resolvedor: desliga a renovação antecipada do cache, para o TTL expirar "limpo" na demonstração.
- **QNAME minimization** (padrão do BIND 9.18): nos logs, a raiz só recebe `lab NS` e o `.lab` só recebe `sd.lab NS`; o nome completo `www.sd.lab` só chega ao autoritativo final (RFC 9156).
- **Secundário sem arquivo de zona**: guarda a zona só em memória; ao reiniciar precisa transferir tudo de novo (é isso que a métrica de recuperação captura).
- **`ixfr-from-differences yes`** no primário: ao recarregar, o primário calcula a diferença e o secundário recebe só ela (IXFR).
- **NOTIFY agrupado**: o BIND junta avisos da mesma zona em janelas de 5 s (`notify-delay`). Por isso as rodadas de propagação ficam espaçadas.
- **Zonas copiadas na inicialização**: os arquivos de `config/*/zones` entram somente leitura em `/zones` e são copiados para `/var/lib/bind`. Os scripts alteram a cópia dentro do contêiner; o repositório nunca é modificado e um `restart` volta ao estado original.

## Problemas comuns

| Sintoma | Causa e solução |
|---|---|
| `Pool overlaps with other one on this address space` | Outra rede Docker já usa `10.53.0.0/24`. Troque a sub-rede no `docker-compose.yml` e todos os IPs `10.53.0.x` (configs, zonas e scripts). |
| `/entrypoint.sh: not found` ou `\r` nos logs | Arquivos com fim de linha do Windows (CRLF). O `.gitattributes` evita isso: clone o repositório de novo depois que ele estiver commitado. |
| Tudo responde SERVFAIL | Veja `docker compose logs resolver`. Normalmente é glue ou IP errado numa zona. |
| Alterei uma zona e nada mudou | Incremente o serial e rode `docker compose restart <serviço>`. |

## Estrutura

```
docker-compose.yml        # 6 serviços, rede 10.53.0.0/24, limites de memória
image/                    # Dockerfile (Ubuntu 24.04 + BIND 9.18) e entrypoint
config/<serviço>/         # named.conf e zonas de cada nó
scripts/                  # verificar, e9, e9-glue, medir, atraso
scripts/lib/              # auxiliares que rodam dentro do cliente (polls e amostragem do E9)
evidencias/               # saídas geradas pelos scripts
relatorio/                # rascunho das seções E9 e R7
apresentacao/             # slides do seminário
```

## Notas para Windows (Docker Desktop + Git Bash)

- Cada `docker compose exec` leva ~2 s. Por isso as partes 3 e 4 do `e9.sh` rodam as consultas dentro do cliente (`scripts/lib/amostrar.sh`), com o relógio do contêiner; cronometradas de fora, as amostras do TTL atrasavam e o cache já tinha vencido.
- O Git Bash reescreve caminhos como `/scripts/x.sh` para `C:/Program Files/Git/...`. O `_comum.sh` desliga isso com `MSYS_NO_PATHCONV=1`.
- O mesmo overhead entra na métrica `recuperacao` do `medir.sh` (1 a 2 s a mais que no Linux).
