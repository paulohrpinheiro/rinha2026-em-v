# Referência Rápida — Decisões e Comparações

> Mapeamento das ADRs da versão Go e comparação com o 1º colocado da Rinha 2026.

---

## Referência externa: 1º colocado

| Campo | Valor |
|-------|-------|
| Repositório | [daniloitagyba/rinha-2026-dotnet](https://github.com/daniloitagyba/rinha-2026-dotnet) |
| Stack | .NET 10 Native AOT + C nativo (P/Invoke) |
| Algoritmo | **KD-tree** exato particionado (256 partições) |
| Distância | **Euclidiana** com AVX2 (int16, escala 10000) |
| Load balancer | **C TCP fd handoff** (SCM_RIGHTS) |
| Busca | Spatial bucketing (4096 buckets, coarse + fine) |
| Early termination | Sim — interrompe quando os 5 vizinhos concordam |

### Comparação arquitetural: Nós (Go/V) vs 1º colocado

| Aspecto | Go v44 / Plano V | 1º colocado (.NET + C) |
|---------|:-----------------:|:----------------------:|
| **Algoritmo** | IVF aproximado (1000 clusters) | KD-tree exato (256 partições) |
| **Recall** | ~97% (nprobe=2) | 100% (exato) |
| **Distância** | Manhattan L1 (int8) | Euclidiana AVX2 (int16) |
| **Precisão** | int8 (0-127, ~0.4% erro) | int16 (escala 10000, ~0.01% erro) |
| **Proxy/LB** | nginx HTTP reverso | C TCP fd handoff |
| **Hot path** | V puro | C nativo + AVX2 |
| **CPU proxy** | 0.19 | Mínimo (só aceita e passa fd) |
| **Busca por query** | ~3.000-15.000 vetores | ~12.000 vetores (1/256) |
| **Index size** | ~45 MB | Binário embedded |
| **FP** | ~734 | **0** |
| **FN** | ~412 | **0** |
| **HTTP errors** | 67 | **0** |
| **Score** | +1.076 | **+6.000** (máximo) |

---

## Lições do 1º colocado para a versão V

### 1. KD-tree exato vs IVF aproximado

O 1º lugar prova que **busca exata é viável** dentro dos limites de CPU/memória
da Rinha. Com 256 partições, cada query varre apenas ~12K vetores — comparável
aos nossos ~3K-15K do IVF, mas com **recall 100%**.

**Para V**: V compila para C. Implementar uma KD-tree exata em V (ou em C
chamado de V via interop nativo) eliminaria os ~3% de erro de recall do IVF.
Vale considerar como **evolução futura** após o baseline IVF funcionar.

### 2. AVX2 para distância

O uso de `_mm256_sub_epi16` + `_mm256_madd_epi16` processa 16 dimensões em
poucos ciclos. Com int16 (escala 10000), a precisão é 80× maior que int8.

**Para V**: V pode fazer C interop diretamente. O hot path `manhattan_distance`
poderia ser substituído por uma função C com AVX2 chamada de V. Alternativa:
usar `-cflags '-mavx2'` e deixar o compilador C auto-vetorizar o loop
desenrolado.

### 3. fd handoff elimina o proxy como gargalo

O LB em C apenas aceita TCP e passa o file descriptor para a API. A API lê
HTTP direto do socket do cliente. **Resultado**: LB com apenas 0.12 CPU e
32 MB processa 54.100 requisições com p99 de 0.96ms.

**Para V**: Nosso nginx já é eficiente (~10 MB, zero código), mas ainda faz
proxy HTTP completo (recebe → encaminha → recebe resposta → devolve). Um
LB com fd handoff seria mais rápido. **Não prioritário** para o baseline,
mas é o caminho para score máximo.

### 4. Early termination

Se todos os K=5 vizinhos têm o mesmo label, interrompe a busca imediatamente.
Isso acelera casos "óbvios" (fraude clara ou legítima clara).

**Para V**: Fácil de implementar no `IVFIndex.search()`. Após cada cluster
escaneado, verificar se `fraudCount == 0 || fraudCount == 5` e retornar cedo.

### 5. int16 > int8

A quantização int8 (0-127) introduz erro de arredondamento de ~0.4% por
dimensão. Com 14 dimensões, o erro acumulado pode inverter a ordem de
vizinhos próximos. O 1º lugar usa int16 com escala 10000 — virtualmente
sem perda.

**Para V**: Mudar `Vector14` de `[14]i8` para `[14]i16` aumentaria o index
de 42 MB para 84 MB — ainda cabe nos 165 MB. **Vale considerar** se o recall
do IVF com int8 for insuficiente.

---

## Configuração de produção (platô v44)

| Parâmetro | Valor | ADR Go |
|-----------|:-----:|:------:|
| Algoritmo | IVF | ADR-02 |
| Clusters | 1.000 | ADR-02 |
| nprobe | 2 | ADR-44 |
| maxScanPerCluster | 5.000 | ADR-44 |
| K (vizinhos) | 5 | — |
| Threshold | 0.6 | ADR-42 |
| Distância | Manhattan (L1) | ADR-03 |
| Quantização | int8 (0-127) | ADR-01 |
| Sentinela | -1 | — |
| Iterações K-means | 20 | ADR-02 |

---

## Infraestrutura

| Parâmetro | Valor | ADR Go |
|-----------|:-----:|:------:|
| Proxy reverso | **nginx:alpine** (least_conn) | ADR-04 (substituído) |
| Proxy CPU | 0.19 | ADR-28 |
| API CPU (cada) | 0.405 | ADR-09 |
| Proxy RAM | 20 MB | ADR-09 |
| API RAM (cada) | 165 MB | ADR-09 |
| CPU total | 1.0 | — |
| RAM total | 350 MB | — |
| Rede | bridge | — |
| Comunicação interna | Unix sockets | ADR-17 |
| Volume compartilhado | `/run/sock` | ADR-17 |

---

## HTTP

| Parâmetro | Valor | ADR Go |
|-----------|:-----:|:------:|
| Porta externa | 9999 | — |
| Porta interna API | 8080 | — |
| ReadTimeout (API) | 200ms | ADR-15 |
| WriteTimeout (API) | 200ms | ADR-15 |
| IdleTimeout (API) | 200ms | ADR-37 |
| proxy_read_timeout (nginx) | 200ms | ADR-37 |
| proxy_send_timeout (nginx) | 200ms | ADR-37 |
| Semáforo | Não-bloqueante 1024 | ADR-16, ADR-30 |

---

## Docker

| Parâmetro | Valor |
|-----------|:-----:|
| Imagem base API (build) | vlang/vlang:alpine |
| Imagem runtime API | scratch |
| Imagem proxy | nginx:alpine (~10 MB) |
| Índice pré-construído | index.bin (~45 MB) |
| Docker Hub API | paulohrpinheiro/rinha-api-v |

---

## Otimizações

| Técnica | Origem |
|---------|:------:|
| Parsing JSON manual byte-a-byte | ADR-34 Go |
| Respostas pré-alocadas (6) | ADR-34 + 1º colocado |
| Warmup no startup | MELHORIAS#7 |
| Forward bruto no proxy (sem parsing) | ADR-34 (nginx não inspeciona payload) |
| GC desabilitado | GOGC=off (em V: -autofree) |
| Early termination no search | **Novo — lição do 1º colocado** |

---

## Resultados oficiais

| Métrica | Go v44 | 1º colocado |
|---------|:------:|:-----------:|
| HTTP errors | 67 | **0** |
| TP | — | **24.037** |
| TN | — | **30.022** |
| FP | ~734 | **0** |
| FN | ~412 | **0** |
| Failure rate | 2.3% | **0%** |
| p99 | 192ms | **0.96ms** |
| p99 score | +709 | **+3.000** |
| Detection score | +373 | **+3.000** |
| **Score final** | **+1.076** | **+6.000** 🏆 |

### Alocação real de recursos (1º colocado)

| Serviço | CPU | Memória |
|---------|:---:|:-------:|
| lb (fd handoff) | 0.12 | 32 MB |
| api-1 | 0.44 | 156 MB |
| api-2 | 0.44 | 156 MB |
| **Total** | **1.00** | **344 MB** |

Fonte: [`benchs/benchs/resultBest.json`](../benchs/benchs/resultBest.json)
