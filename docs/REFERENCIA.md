# Referência Rápida — Decisões e Comparações

> Mapeamento das ADRs da versão Go e comparação com o 1º colocado da Rinha 2026.

---

## Referência externa: 1º colocado (atualizado)

| Campo | Valor |
|-------|-------|
| Repositório | [dalvorsn/cpp-rinha-backend-2026](https://github.com/dalvorsn/cpp-rinha-backend-2026) |
| Stack | **C++** nativo |
| Algoritmo | **KD-tree** exato |
| Distância | Manhattan |
| Load balancer | **C++ TCP proxy** |
| CPU proxy | 0.10 |
| Memória proxy | 30 MB |
| CPU cada API | 0.45 |
| Memória cada API | 120 MB |
| Memória total | **270 MB** (80 MB abaixo do limite) |
| Score | **5.986** |
| p99 | **1.03ms** |
| FP | **0** |
| FN | **0** |

*Nota: a organização atualizou as regras — os valores esperados agora são os mesmos dos nossos testes (fraud=23959, legit=30141, edge=645).*

### Comparação arquitetural: V vs 1º colocado (C++)

| Aspecto | V (v11) | 1º colocado (C++) |
|---------|:-------:|:-----------------:|
| **Algoritmo** | IVF aproximado (1000 clusters, nprobe=8) | KD-tree exato |
| **Recall** | ~98% | 100% (exato) |
| **Distância** | Manhattan L1 (int8) | Manhattan |
| **Proxy/LB** | nginx stream (zero parsing HTTP) | C++ TCP proxy |
| **Hot path** | V 0.5.1 | C++ nativo |
| **Busca por query** | até 40.000 vetores (8×5000) | ~todos |
| **FP** | 615 | **0** |
| **FN** | 339 | **0** |
| **Memória total** | 350 MB | **270 MB** |
| **Score** | **3.331** | **5.986** 🏆 |

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
| Proxy reverso | **nginx:alpine** (stream mode, zero parsing HTTP) | ADR-V20 |
| Proxy CPU | 0.19 | ADR-28 |
| API CPU (cada) | 0.405 | ADR-09 |
| Proxy RAM | 20 MB | ADR-09 |
| API RAM (cada) | 165 MB | ADR-09 |
| CPU total | 1.0 | — |
| RAM total | 350 MB | — |
| Rede | bridge + volume compartilhado | — |
| Comunicação interna | Unix sockets | ADR-17 |
| Volume compartilhado | `/sockets` | ADR-17 |

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

## Resultados oficiais (atualizado)

| Métrica | Go v44 | V v02 | V v07 | V v09 | V v10 | **C++ (1º)** |
|---------|:------:|:-----:|:-----:|:-----:|:-----:|:------------:|
| HTTP errors | 67 | 1 | 0 | 0 | 0 | **0** |
| TP | — | 23.606 | 23.606 | 23.594 | 23.603 | **23.942** |
| TN | — | 29.483 | 29.484 | 29.493 | 29.502 | **30.117** |
| FP | ~734 | 633 | 633 | 624 | 615 | **0** |
| FN | ~412 | 336 | 336 | 348 | 339 | **0** |
| Failure rate | 2,3% | 1,79% | 1,79% | 1,8% | 1,76% | **0%** |
| p99 | 192ms | 10,58ms | 18,92ms | **1,47ms** | 1,68ms | **1,03ms** |
| p99 score | +709 | +1.976 | +1.723 | +2.832 | +2.775 | **+2.986** |
| Detection score | +373 | +551 | +553 | +544 | +556 | **+3.000** |
| **Score final** | **+1.076** | **+2.527** | **+2.276** | **+3.376** | **+3.331** | **+5.986** 🏆 |

### Alocação de recursos (comparativo)

| Serviço | V (v10) | C++ (1º) |
|---------|:-------:|:---------:|
| Proxy/LB | nginx: 0.19 CPU / 20 MB | C++ TCP: 0.10 CPU / 30 MB |
| api-1 | V: 0.405 CPU / 165 MB | C++: 0.45 CPU / 120 MB |
| api-2 | V: 0.405 CPU / 165 MB | C++: 0.45 CPU / 120 MB |
| **Total** | **1.00 CPU / 350 MB** | **1.00 CPU / 270 MB** |

Fonte: [`benchs/resultBest.json`](../benchs/resultBest.json), [`benchs/result10.json`](../benchs/result10.json)
