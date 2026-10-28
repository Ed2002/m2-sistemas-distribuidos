# Sistemas Distribuídos — T1: DNS com ênfase em hierarquia e delegação

Laboratório de DNS em contêineres para o trabalho T1 (ênfase A). Ele monta uma hierarquia completa com BIND 9.18: uma raiz fictícia, o TLD `.lab` e a zona `sd.lab`, com primário, secundário, resolvedor com cache e cliente. Os experimentos mostram, com evidências, como funcionam a delegação, o glue, o cache e o TTL.

```
raiz (.) ──delega──▶ TLD .lab ──delega──▶ sd.lab (primário ──NOTIFY+IXFR──▶ secundário)
                                                 ▲
cliente ──▶ resolvedor recursivo (cache) ────────┘
```

## Como rodar

Precisa de Docker com Compose v2 e de um terminal `bash` (Linux, macOS, WSL ou Git Bash no Windows).

```bash
git clone https://github.com/Ed2002/m2-sistemas-distribuidos.git
cd m2-sistemas-distribuidos/dns-lab
docker compose up -d --build
./scripts/verificar.sh        # deve terminar com "Tudo certo."
```

Depois disso:

```bash
./scripts/e9.sh               # E9: delegação, dig +trace, cache, TTL e dump do cache
./scripts/e9-glue.sh          # E9: quebra o glue e mostra o SERVFAIL
./scripts/medir.sh            # R7: 5 rodadas com média e desvio padrão
./scripts/atraso.sh 20ms      # opcional: simula distância de rede (desliga com "off")
```

Os detalhes do ambiente, dos scripts e das decisões de configuração estão no [README do laboratório](dns-lab/README.md).

## O que tem aqui

| Caminho | Conteúdo |
| --- | --- |
| [`dns-lab/docker-compose.yml`](dns-lab/docker-compose.yml) | Os 6 contêineres, a rede `10.53.0.0/24` e os limites de memória |
| [`dns-lab/config/`](dns-lab/config) | `named.conf` e arquivos de zona de cada servidor |
| [`dns-lab/scripts/`](dns-lab/scripts) | Verificação, E9, teste do glue, medições e atraso de rede |
| [`dns-lab/evidencias/`](dns-lab/evidencias) | Saídas geradas pelos scripts, usadas no relatório |
| [`dns-lab/relatorio/rascunho-E9-R7.md`](dns-lab/relatorio/rascunho-E9-R7.md) | Rascunho das seções E9 e R7 do relatório |
| [`dns-lab/apresentacao/seminario-dns.pptx`](dns-lab/apresentacao/seminario-dns.pptx) | Slides do seminário de 10 minutos, com notas do orador |

## Ambiente

| Contêiner | Papel | IP |
| --- | --- | --- |
| `root` | Raiz fictícia, delega `.lab` | 10.53.0.10 |
| `tld-lab` | TLD `.lab`, delega `sd.lab` | 10.53.0.20 |
| `sd-primary` | Primário de `sd.lab` | 10.53.0.30 |
| `sd-secondary` | Secundário de `sd.lab` (NOTIFY + IXFR) | 10.53.0.31 |
| `resolver` | Resolvedor recursivo com cache | 10.53.0.53 |
| `client` | Onde rodam os `dig` | 10.53.0.100 |

Cada servidor tem limite de 128 MB (o cliente, 64 MB). No Docker Desktop, cada um usou uns 23 MB.

## Principais resultados

Rodada de 28/10/2026 no Docker Desktop (Windows 11). Os arquivos estão em [`dns-lab/evidencias/`](dns-lab/evidencias).

**E9 — hierarquia e delegação** (com 20 ms de atraso em cada autoritativo)

- A raiz e o `.lab` respondem só com uma referência (NS + glue, sem a flag `aa`); só o `sd.lab` responde com autoridade.
- A 1ª consulta, com o cache vazio, levou 64 ms e passou pelos três níveis. As seguintes saíram do cache em 0 ms, sem consultar nenhum autoritativo.
- O registro com TTL de 10 s ficou no cache até vencer; depois o resolvedor voltou só ao `sd.lab`.
- Com o glue apontando para IPs errados, a resolução deu SERVFAIL após 10 s.

**R7 — medições** (5 rodadas, sem atraso)

| Métrica | Média (ms) | Desvio (ms) |
| --- | --- | --- |
| Latência fria (cache vazio) | 4,0 | 2,8 |
| Latência quente (do cache) | 0,0 | 0,0 |
| Propagação primário → secundário | 172 | 129 |
| Recuperação do secundário | 3793 | 944 |
| Failover (primário parado) | 483 | 439 |

A recuperação inclui de 1 a 2 s de overhead do Docker Desktop. O failover é bimodal: ~800 ms quando o resolvedor tenta primeiro o primário parado e ~0 ms quando vai direto ao secundário. Não há eleição de líder: no DNS, o primário é fixo na configuração.

## Situação

| Requisito | Situação |
| --- | --- |
| R1 Ambiente com 3+ nós | Pronto |
| R2 Pesquisa | Referências prontas; falta o diagrama próprio e o texto da arquitetura |
| R3 E1 a E8 | Falta rodar e escrever |
| R4 E9 ênfase A | Evidências e rascunho prontos |
| R5 Q1 a Q14 / R6 S1 a S4 | Falta responder |
| R7 Medições | Evidências e rascunho prontos |
| R8 Relatório completo | Em andamento |
| R9 Seminário com vídeos | Slides prontos; faltam os vídeos |
| R10 Domínio da equipe | Ensaio |

## Referências

- MOCKAPETRIS, P.; DUNLAP, K. J. Development of the Domain Name System. ACM SIGCOMM '88, 1988.
- [RFC 1034](https://www.rfc-editor.org/rfc/rfc1034) e [RFC 1035](https://www.rfc-editor.org/rfc/rfc1035): conceitos e especificação do DNS.
- [RFC 1995](https://www.rfc-editor.org/rfc/rfc1995) (IXFR), [RFC 1996](https://www.rfc-editor.org/rfc/rfc1996) (NOTIFY) e [RFC 5936](https://www.rfc-editor.org/rfc/rfc5936) (AXFR).
- [RFC 2308](https://www.rfc-editor.org/rfc/rfc2308): cache negativo.
- [RFC 9156](https://www.rfc-editor.org/rfc/rfc9156): QNAME minimisation.
- [RFC 9471](https://www.rfc-editor.org/rfc/rfc9471): requisitos de glue nas referências.
- [BIND 9 Administrator Reference Manual, versão 9.18](https://bind9.readthedocs.io/en/v9.18.24/).
