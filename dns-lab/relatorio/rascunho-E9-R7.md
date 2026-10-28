# Rascunho — E9 (ênfase A) e R7 (medições)

Rascunho para colar no relatório (Seção 10). Todos os números vêm da rodada de 28/10/2026 no Docker Desktop (Windows 11), com os arquivos em `evidencias/`. Se a equipe rodar de novo, os números mudam um pouco; conferir antes de colar.

## E9 — Hierarquia e delegação

### Previsão (escrita antes de rodar)

1. A raiz não responde `www.sd.lab`: devolve uma referência para `.lab` com o endereço do `ns1.nic.lab` (glue). O `.lab` faz o mesmo para `sd.lab`. Só o servidor de `sd.lab` responde com a flag `aa`.
2. Com o cache vazio, o resolvedor consulta raiz, `.lab` e `sd.lab`. Nas consultas seguintes, responde do cache em cerca de 0 ms, nenhum autoritativo recebe consulta e o TTL vai caindo.
3. Outro nome de `sd.lab` vai direto ao servidor de `sd.lab`, porque as delegações já estão em cache.
4. Quando o TTL chega a zero, o resolvedor volta ao autoritativo.
5. Com o glue errado, a delegação quebra e o resolvedor devolve SERVFAIL.

### Procedimento

```bash
./scripts/atraso.sh 20ms    # 20 ms em cada autoritativo, simulando distância de rede
./scripts/e9.sh
./scripts/e9-glue.sh
./scripts/atraso.sh off
```

O ambiente tem 6 contêineres (raiz `10.53.0.10`, TLD `.lab` `10.53.0.20`, primário e secundário de `sd.lab` `10.53.0.30` e `.31`, resolvedor `10.53.0.53` e cliente `10.53.0.100`). Todas as consultas partem do cliente. O resolvedor só conhece a nossa raiz (root hints próprios). A contagem de "quem foi consultado" sai do `querylog` de cada autoritativo, filtrado pela janela de tempo de cada consulta.

### Evidências

| Arquivo | O que deu |
| --- | --- |
| `e9-1-delegacao.txt` | Raiz: `flags: qr` (sem `aa`), ANSWER 0, autoridade `lab NS ns1.nic.lab` e adicional `ns1.nic.lab A 10.53.0.20` (glue). `.lab`: ANSWER 0, 2 NS (`ns1`/`ns2.sd.lab`) e 2 glue (`10.53.0.30` e `.31`). `sd.lab`: `flags: qr aa`, resposta `www.sd.lab 300 A 10.53.0.80` |
| `e9-2-trace.txt` | 4 saltos: resolvedor (24 ms), `a.root-servers.lab` (24 ms), `ns1.nic.lab` (24 ms), `ns2.sd.lab` (20 ms). Os ~20 ms de cada salto são o atraso artificial |
| `e9-3-cache.txt` | Tabela abaixo |
| `e9-4-ttl.txt` | Tabela abaixo |
| `e9-5-cache-dump.txt` | Delegações e glue guardados com TTL de 86400 s; `www.sd.lab` com 300 s; `sd.lab NS` com 300 s (ver análise); AAAA dos servidores em cache negativo (`NXRRSET`) |
| `e9-6-glue.txt` | Sem glue: `named-checkzone` acusa "has no REQUIRED GLUE" para `ns1` e `ns2.sd.lab`. Glue apontando para `10.53.0.98`/`.99`: **SERVFAIL** após 10001 ms. Restaurado: NOERROR em 43 ms |

**Cache: 1ª consulta x seguintes** (`e9-3-cache.txt`, com 20 ms de atraso)

| Consulta | Tempo (ms) | TTL | Consultas recebidas pelos autoritativos |
| --- | --- | --- | --- |
| 1 (cache vazio) | 64 | 300 | raiz 5, `.lab` 4, ns1 1, ns2 2 |
| 2 a 6 (cache) | 0 | 298 → 294 | nenhuma |
| `api.sd.lab` (outro nome) | 20 | 300 | só ns1 (1) |

**Expiração do TTL** (`e9-4-ttl.txt`, `curto.sd.lab` com TTL 10 s)

| t (s) | Tempo (ms) | TTL | Consultas recebidas |
| --- | --- | --- | --- |
| 0 | 68 | 10 | raiz 5, `.lab` 4, ns1 2, ns2 1 (cache vazio) |
| 4 | 0 | 7 | nenhuma |
| 8 | 0 | 3 | nenhuma |
| 12 | 24 | 10 | só ns2 (1): o TTL venceu, nova consulta direto em `sd.lab` |
| 16 | 0 | 5 | nenhuma |

### Análise

- **Previsões 1 a 5 confirmadas.** A raiz e o `.lab` respondem com referência (seção de resposta vazia, sem `aa`); só o dono da zona responde com autoridade. A 1ª consulta percorre os três níveis; as seguintes saem do cache em 0 ms sem tocar em nenhum autoritativo; `api.sd.lab` vai direto ao `sd.lab`; o TTL vence entre t=8 e t=12 e o resolvedor volta só ao autoritativo final; com glue errado, SERVFAIL.
- **Delegação distribui autoridade e carga.** Cada servidor guarda só a própria zona e o ponteiro para as filhas. A raiz não sabe nada de `sd.lab`; só sabe que `.lab` é do `ns1.nic.lab`. Cada zona pode ser administrada por uma organização diferente.
- **Glue resolve uma dependência circular.** O `ns1.sd.lab` fica dentro de `sd.lab`; para descobrir o endereço dele seria preciso perguntar a ele mesmo. Por isso o `.lab` publica o endereço junto com a referência (seção adicional). Com o glue apontando para IPs que não existem, o resolvedor não tem outro caminho até `sd.lab` e desiste após os timeouts (10 s) com SERVFAIL. O `named-checkzone` acusa a falta do glue obrigatório, mas é só um aviso: a zona sem glue ainda carrega, e o erro só aparece para quem tenta resolver.
- **Cache é consistência eventual.** Uma alteração no autoritativo só chega aos clientes depois que o TTL vence nos caches. O TTL é a troca entre carga nos servidores e frescor dos dados: com 300 s, `www.sd.lab` gera uma consulta ao autoritativo a cada 5 min por resolvedor, não importa quantos clientes perguntem.
- **Ganho do cache.** Com 20 ms em cada autoritativo, a 1ª consulta levou 64–68 ms (três idas sequenciais: raiz, `.lab`, `sd.lab`), e as seguintes 0 ms. Um nome novo da mesma zona custa um salto só (20–24 ms), porque as delegações continuam em cache por 86400 s.
- **QNAME minimization (RFC 9156).** Nos logs da 1ª resolução, a raiz recebeu só `. NS` e `lab NS`, e o `.lab` recebeu só `sd.lab NS`. O nome completo `www.sd.lab` só chegou ao autoritativo final.
- **Por que 5 consultas na raiz e não 1.** Além de `. NS` (atualização dos root hints) e `lab NS`, o resolvedor perguntou o **AAAA** de `ns1.nic.lab`, `ns1.sd.lab` e `ns2.sd.lab`: o glue só traz endereço IPv4 e o BIND tenta descobrir o IPv6 dos servidores. A resposta foi "não existe" (NXRRSET), guardada em cache negativo pelo TTL do SOA da zona: 3600 s para `.lab` e 60 s para `sd.lab`, como aparece no dump (RFC 2308).
- **NS do filho substitui o NS do pai no cache.** No dump, o glue continua com 86400 s, mas `sd.lab NS` está com 300 s. A referência do `.lab` traz o NS com TTL 86400; a resposta autoritativa do próprio `sd.lab` traz o mesmo NS com TTL 300, e o resolvedor fica com a versão do filho porque ela tem mais credibilidade (marcada `authauthority` no dump).

## R7 — Medições

`./scripts/medir.sh`, 5 rodadas, **sem** o atraso artificial (tudo na mesma máquina). Dados brutos em `evidencias/medicoes.csv`, resumo em `evidencias/medicoes-resumo.txt`.

| Métrica | O que mede | Rodadas (ms) | Média (ms) | Desvio (ms) |
| --- | --- | --- | --- | --- |
| `latencia_fria` | Resolução com cache vazio (raiz → `.lab` → `sd.lab`) | 0, 4, 4, 4, 8 | 4,0 | 2,8 |
| `latencia_quente` | Mesma consulta, do cache | 0, 0, 0, 0, 0 | 0,0 | 0,0 |
| `propagacao` | `rndc reload` no primário até o secundário servir o serial novo (NOTIFY + IXFR) | 388, 73, 149, 174, 76 | 172,0 | 128,7 |
| `recuperacao` | `docker compose start` do secundário até ele voltar a servir a zona (AXFR completa) | 3590, 3610, 3805, 5287, 2673 | 3793,0 | 943,6 |
| `failover` | Resolução com o primário (ns1) parado | 808, 4, 0, 800, 804 | 483,2 | 439,3 |

### Análise

- **Cache.** Sem distância de rede, percorrer a hierarquia custa só uns 4 ms; do cache, 0 ms (o `dig` arredonda para ms inteiros, então "0" quer dizer menos de 1 ms). Com 20 ms por autoritativo (E9), a diferença sobe para 64 ms x 0 ms. Na internet, com a raiz e o TLD a dezenas de ms, o ganho é dessa ordem.
- **Propagação.** O secundário passou a servir o serial novo entre 73 e 388 ms depois do `reload`, porque o primário avisa por NOTIFY e o secundário puxa só a diferença (IXFR). Sem o NOTIFY, o secundário só perceberia a mudança no próximo `refresh` do SOA (3600 s nesta zona). É a janela de inconsistência entre primário e secundário.
- **Recuperação.** Os ~3,8 s incluem a lentidão do Docker Desktop no Windows: cada `docker compose start`/`exec` custa 1–2 s e entra na medição. O que é do DNS em si é o BIND subir e fazer uma transferência completa (AXFR), porque o secundário não guarda a zona em disco. Num Linux o número deve sair bem menor; se der, rodar lá e comparar.
- **Failover.** A distribuição é bimodal: 3 rodadas em ~800 ms e 2 em ~0–4 ms. Com o cache limpo, o resolvedor escolhe um dos dois NS de `sd.lab`. Quando escolhe o ns1 (parado), espera o timeout inicial do BIND (~800 ms) e tenta o ns2; quando escolhe o ns2, responde na hora. Por isso a média (483 ms) com desvio de 439 ms descreve mal o comportamento: vale apresentar os dois grupos separados. Nenhuma consulta falhou: o secundário sozinho mantém a zona no ar, e continuaria assim até o `expire` do SOA (86400 s).
- **Por que não há eleição.** No DNS, o papel de primário é definido na configuração (`type primary` no ns1, `type secondary` com `primaries { 10.53.0.30; }` no ns2). Não há líder escolhido em tempo de execução nem consenso: com o primário parado, o secundário continua respondendo, mas ninguém passa a aceitar alterações na zona até o ns1 voltar. A medida análoga à eleição é o failover do lado do resolvedor, que só troca de servidor para leitura.

## Divergências em relação ao plano (para o Eduardo)

- **Memória.** `docker stats` mostrou uns 23 MB por servidor no Docker Desktop (Windows), e não 5 MB. Continua muito abaixo do limite de 128 MB.
- **Consultas na 1ª resolução.** O plano previa "2 na raiz, 1 no `.lab`, 1 no `sd.lab`"; aqui deu 5, 4 e 3 por causa das consultas AAAA dos servidores (explicado na análise do E9).
- **`named-checkzone` sem glue** acusa o erro, mas a zona ainda carrega: não é recusa.
- **Cache dump.** `sd.lab NS` fica com 300 s (TTL do filho), não 86400; só o glue fica com 86400.
- **Scripts corrigidos para Windows/Git Bash.** No Docker Desktop cada `docker compose exec` leva ~2 s, então a parte 4 do `e9.sh` amostrava o TTL a cada ~14 s e o cache de 10 s já tinha vencido em todas as amostras. As partes 3 e 4 agora rodam as consultas dentro do cliente (`scripts/lib/amostrar.sh`). E o Git Bash convertia `/scripts/...` em `C:/Program Files/Git/scripts/...`, o que quebrava o `medir.sh`; o `_comum.sh` agora exporta `MSYS_NO_PATHCONV=1`.
