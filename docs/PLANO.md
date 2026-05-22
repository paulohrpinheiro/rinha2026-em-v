# Plano de Implementação — Versão V

> Data: 2026-05-21
> Stack: V 0.5.1 · nginx:alpine
> Base: Go v44 (+1076 score, platô estável)

---

## Visão Geral

Reimplementar o sistema de detecção de fraude da Rinha de Backend 2026 em
**V (Vlang) 0.5.1**, preservando todas as decisões arquiteturais comprovadas
da versão Go. O proxy reverso será **nginx:alpine** (~10 MB) em vez de
proxy customizado — eliminando ~200 linhas de código e risco de bugs sob carga.

---

## Fase 1 — Fundação: Tipos, Vetores e Normalização

### 1.1 Modelagem de dados (`internal/model.v`)

Definir as structs equivalentes às do Go, usando tipos nativos de V:

```v
struct TransactionPayload {
    id              string
    transaction     TransactionData
    customer        CustomerData
    merchant        MerchantData
    terminal        TerminalData
    last_transaction ?LastTransactionData  // V: Option type para nullable
}
```

**Decisão V**: Usar `?Type` (Option) para `last_transaction` em vez de ponteiro
nulo — mais idiomático e seguro em V 0.5.1.

### 1.2 Vetor e quantização (`internal/normalize.v`)

```v
type Vector14 = [14]i8  // array fixo, i8 = int8 em V

fn quantize(v f64) i8 {
    if v == -1.0 { return -1 }
    if v <= 0.0 { return 0 }
    if v >= 1.0 { return 127 }
    return i8(math.round(v * 127.0))
}

fn manhattan_distance(a &Vector14, b &Vector14) i32 {
    // Unroll manual (14 dimensões) — V pode auto-vetorizar
    mut sum := i32(0)
    // ... mesmo padrão do Go com abs manual
    return sum
}
```

**Decisão V**: `[14]i8` é nativo em V assim como `[14]int8` em Go. A função
`manhattan_distance` será idêntica em estrutura — desenrolada manualmente.

### 1.3 Normalização (`internal/normalize.v`)

Mesma lógica do Go (`Normalize` recebe `&Payload` + `&NormalizationConfig`),
adaptando:
- `time.Time` → `time.Time` em V
- Option types para `HasLastTransaction`

---

## Fase 2 — Parsing JSON Manual

### 2.1 Parser byte-a-byte (`internal/parser.v`)

A versão Go usa parsing manual para zero alocações. Em V, a abordagem será
similar, com suporte nativo a slicing:

```v
struct Payload {
mut:
    amount             f64
    installments       int
    // ... campos extraídos diretamente
    has_last_transaction bool
    last_timestamp     time.Time
    last_km_from_current f64
}

fn parse_payload(body []byte) !Payload {
    // byte-a-byte scanning, campos resolvidos por switch no tamanho da chave
    // switch body[pos..pos+len] {
    //     'amount' { ... }
    //     'customer' { ... }
    // }
}
```

**Decisão V**: V tem suporte nativo a slices `[]byte` similares a Go, então o
parsing byte-a-byte é portável diretamente. A macro `$for` de V pode ser usada
para otimizar a busca de chaves conhecidas.

### 2.2 Extração de floats e inteiros

Implementar `parse_float_fast` e `parse_int_fast` sem alocação, similares às
versões Go.

---

## Fase 3 — IVF Index

### 3.1 Estrutura (`internal/ivf.v`)

```v
struct IVFIndex {
    vectors   []Vector14
    labels    []u8       // 0=legit, 1=fraud
    centroids []Vector14
    offsets   []int      // offsets[c] = start, offsets[c+1] = end
    n_clusters int
}
```

### 3.2 Busca (`Search`)

Implementação idêntica à Go:
- Encontrar `nprobe=2` centroides mais próximos (partial selection sort)
- Buscar K=5 vizinhos mais próximos nos clusters candidatos
- `maxScanPerCluster=5000`
- Retornar `fraudCount`

**Early termination (lição do 1º colocado)**: Se todos os K=5 vizinhos têm o
mesmo label, interromper a busca imediatamente — acelera casos óbvios.

```v
// Dentro do loop de busca, após cada cluster:
if fraud_count == 0 || fraud_count == 5 {
    return fraud_count, nil  // early termination
}
```

**Nota sobre KD-tree**: O 1º colocado usa KD-tree exato com 256 partições,
provando que busca exata é viável nos limites da Rinha. Após o baseline
IVF funcionar, migrar para KD-tree com partições é a evolução natural para
eliminar os ~3% de erro de recall.

**Nota sobre performance**: Em V, o compilador pode auto-vetorizar o loop
desenrolado de Manhattan. Compilar com `v -prod -skip-unused -cflags '-static'`.

---

## Fase 4 — HTTP Handlers

### 4.1 Servidor HTTP (`cmd/api/main.v`)

V 0.5.1 oferece `net.http` na stdlib. Usaremos esta — zero dependências
externas, mesmo princípio da versão Go (ADR-10).

### 4.2 Handlers (`internal/handler.v`)

```v
fn ready_handler(mut ctx http.Context) {
    ctx.send_json(http.Status.ok, {'status': 'ok'})
}

fn fraud_score_handler(mut ctx http.Context) {
    body := ctx.req.data  // []byte direto, sem io.ReadAll
    payload := parser.parse_payload(body) or {
        ctx.send(http.Status.bad_request, 'invalid json')
        return
    }
    vector := normalize(&payload, &config)
    fraud_count, _ := index.search(&vector)
    response := responses.fraud_response(fraud_count)
    ctx.send(http.Status.ok, response)
}
```

### 4.3 Respostas pré-alocadas (`internal/responses.v`)

Mesmo princípio: 6 respostas possíveis como `[]byte` estático:

```v
const fraud_responses = [
    []byte(`{"approved":true,"fraud_score":0.0}`),   // 0 fraudes
    []byte(`{"approved":true,"fraud_score":0.2}`),   // 1 fraude
    []byte(`{"approved":true,"fraud_score":0.4}`),   // 2 fraudes
    // ...
    []byte(`{"approved":false,"fraud_score":1.0}`),  // 5 fraudes
]
```

### 4.4 Semáforo não-bloqueante

Implementar com `sync` module de V, similar ao `sync/atomic` do Go:

```v
import sync

struct Semaphore {
    count &sync.AtomicInt
    max    int
}

fn (mut s Semaphore) try_acquire() bool {
    for {
        current := s.count.load()
        if current >= s.max { return false }
        if s.count.cas(current, current + 1) { return true }
    }
}
```

---

## Fase 5 — Loader e Índice Pré-construído

### 5.1 Carregamento streaming (`internal/loader.v`)

Processar `references.json.gz` em modo streaming:
1. Descomprimir gzip
2. JSON token a token (similar ao `json.Decoder` do Go)
3. Quantizar cada vetor imediatamente
4. Atribuir ao cluster mais próximo

**Decisão V**: V 0.5.1 tem `compress.gzip` na stdlib. O parsing streaming pode
usar o módulo `json` em modo manual (similar a `Decoder.Token()`).

### 5.2 K-means para clustering

Implementação com **mini-batch K-means** (portado da versão Go v44):
- Inicialização: K-means++ nos primeiros 100 centroides sobre amostra de 5% (~150K vetores)
- Centroides restantes via amostragem uniforme espaçada
- Refinamento: 25 iterações de mini-batch com 20% do dataset cada (~600K vetores/iteração)
- Assign final no dataset completo com reordenação por cluster
- `n_clusters=1000`

> **Por que mini-batch?** O K-means++ original sobre o dataset completo (3M vetores)
> tinha complexidade O(n·k²) ≈ 1.5 trilhão de distâncias Manhattan (~6 horas).
> O mini-batch reduz para ~5 minutos.

### 5.3 Serialização binária (`index.bin`)

Formato binário compatível com a versão Go (ver ADR-V15):
- Magic header (formato Go): `IVF\x01` (4 bytes) — detectado automaticamente
- Header: n_vectors (4 bytes LE), n_clusters (4 bytes LE)
- Vectors: 14 bytes × n_vectors (int8)
- Labels: n_vectors bytes (uint8)
- Centroids: 14 bytes × n_clusters (int8)
- Offsets: 4 bytes × (n_clusters + 1) (int32 LE)

```v
fn ivf_index.save(path string) ! {
    mut buf := []byte{cap: 8 + n_vectors*15 + n_clusters*14 + (n_clusters+1)*4}
    // binary encoding via encoding.binary (stdlib)
}
```

---

## Fase 6 — nginx (Proxy Reverso)

### 6.1 Configuração (`nginx/nginx.conf`)

Configuração mínima, sem lógica de negócio:

```nginx
upstream api_backends {
    least_conn;  # alternativa ao round-robin: menor carga primeiro
    server unix:/run/sock/api-1.sock;
    server unix:/run/sock/api-2.sock;
}

server {
    listen 9999;

    location /ready {
        proxy_pass http://api_backends/ready;
        proxy_http_version 1.1;
    }

    location /fraud-score {
        proxy_pass http://api_backends/fraud-score;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_read_timeout 200ms;
        proxy_send_timeout 200ms;
    }
}
```

**Decisão**: `least_conn` em vez de round-robin puro — envia para o backend
com menos conexões ativas, reduzindo filas. Timeouts alinhados com a versão
Go (200ms).

### 6.2 Docker (nginx:alpine)

Sem Dockerfile necessário — usa imagem oficial `nginx:alpine` diretamente
no docker-compose, com bind mount do `nginx.conf` e volume `sock`.

```yaml
nginx:
  image: nginx:alpine
  ports:
    - "9999:9999"
  volumes:
    - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - sock:/run/sock
  deploy:
    resources:
      limits:
        cpus: "0.19"
        memory: "20MB"
```

**Tamanho**: nginx:alpine tem ~10 MB (vs ~3 MB do proxy Go). Cabe
folgadamente nos 20 MB alocados.

---

## Fase 7 — Docker e Deploy

### 7.1 Dockerfile.api

Multi-stage build:
1. **Stage builder**: `vlang/vlang:alpine` — compilar binário + gerar índice
2. **Stage runtime**: `scratch` — apenas binário + índice + resources

```dockerfile
FROM vlang/vlang:alpine AS builder
RUN apk add --no-cache ca-certificates
WORKDIR /src
COPY v.mod .
COPY internal/ ./internal/
COPY cmd/ ./cmd/
COPY resources/ /resources/
RUN v -prod -skip-unused -cflags '-static' -o /api cmd/api/main.v

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /api /api
COPY --from=builder /resources/ /resources/
EXPOSE 8080
ENTRYPOINT ["/api"]
```

### 7.2 docker-compose.yml

Estrutura com nginx:alpine em vez de proxy customizado:

```yaml
volumes:
  sock:
    driver: local

services:
  nginx:
    image: nginx:alpine
    ports:
      - "9999:9999"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - sock:/run/sock
    depends_on:
      - api-1
      - api-2
    networks:
      - rinha-net
    deploy:
      resources:
        limits:
          cpus: "0.19"
          memory: "20MB"

  api-1:
    hostname: api-1
    image: paulohrpinheiro/rinha-api-v:v1
    environment:
      - PORT=8080
      - RESOURCES_DIR=/resources
      - UNIX_SOCKET_DIR=/run/sock
    networks:
      - rinha-net
    volumes:
      - sock:/run/sock
    deploy:
      resources:
        limits:
          cpus: "0.405"
          memory: "165MB"

  api-2:
    hostname: api-2
    image: paulohrpinheiro/rinha-api-v:v1
    environment:
      - PORT=8080
      - RESOURCES_DIR=/resources
      - UNIX_SOCKET_DIR=/run/sock
    networks:
      - rinha-net
    volumes:
      - sock:/run/sock
    deploy:
      resources:
        limits:
          cpus: "0.405"
          memory: "165MB"

networks:
  rinha-net:
    driver: bridge
```

### 7.3 Otimizações de compilação

Flags V para máxima performance:

```makefile
VFLAGS = -prod -skip-unused -cflags '-static'
# -prod: otimizações máximas
# -skip-unused: remove código não usado
# -cflags '-static': binário statically linked (scratch)
# NOTA: -autofree removido — causa segfault com map[string]f64 (ver ADR-V17)
```

---

## Fase 8 — Testes, Benchmarks e Profiling

**Diretiva**: Todo código deve ser testável e perfilável. Nenhuma função entra
em produção sem cobertura de testes e sem evidência de performance. O pipeline
de qualidade tem quatro níveis — profiling, unitário, benchmark nativo e stress.

### 8.0 Profiling (Nível 0)

Antes de qualquer teste, o hot path deve ser perfilado com as ferramentas
nativas de V e do Linux.

**V `-prof`** (CPU profiling nativo):

```bash
# Profiling completo
v -prof profile.txt run cmd/api/main.v

# Apenas funções do hot path
v -profile-fns manhattan_distance,normalize,search -prof profile.txt run cmd/api/main.v

# Mais granularidade (sem inline)
v -profile-no-inline -prof profile.txt run cmd/api/main.v
```

**Controle programático** — reduz ruído de inicialização no perfil:

```v
import v.profile

profile.on(false)  // desliga durante load
index := loader.load_index(config.index_path)!
profile.on(true)   // liga só no hot path
```

**Ferramentas externas** (binário V compila para C — compatível com):

| Ferramenta | Comando | O que revela |
|------------|---------|-------------|
| `perf` | `perf record ./api && perf report` | CPU sampling, cache misses, branch mispredicts |
| `callgrind` | `valgrind --tool=callgrind ./api` | Call graph + contagem de instruções por função |
| `massif` | `valgrind --tool=massif ./api` | Heap profile — picos de memória, alocações |
| `heaptrack` | `heaptrack ./api` | Heap com timeline gráfica |

**Makefile**:

```makefile
profile:
    v -profile-no-inline -profile-fns manhattan_distance,normalize,search \
      -prof profile.txt run cmd/api/main.v

profile-stress:
    # Stress com profiling — verifica hot path sob carga real
    v -prof stress_profile.txt run scripts/stress.v -duration 1m -rate 180
```

### 8.1 Testes unitários (Nível 1)

Cada módulo com `*_test.v` usando o framework nativo `assert` de V. Executados
com `v test internal/`.

| Módulo | O que cobre |
|--------|------------|
| `normalize_test.v` | `quantize()`, `manhattan_distance()`, `normalize()` — todas as 14 dimensões, valores de borda (0.0, 1.0, overflow), sentinela -1 |
| `ivf_test.v` | `search()` — índice vazio, vizinho exato, K=5, nprobe=2, maxScanPerCluster, clusters vazios |
| `handler_test.v` | `GET /ready` (200), `POST /fraud-score` (payloads válidos e inválidos), JSON malformado, sem `last_transaction` |
| `parser_test.v` | `parse_payload()` — cada campo do JSON, floats negativos, null, chaves ausentes, strings vazias, escapes |
| `loader_test.v` | Carregamento streaming de `references.json.gz`, K-means (centroides estáveis entre runs), serialização binária round-trip (`save` → `load`) |
| `responses_test.v` | `fraud_response()` para cada valor 0-5, bytes exatos, sem alocações |

```v
fn test_quantize() {
    assert quantize(0.0) == 0
    assert quantize(0.5) == 64  // 0.5 * 127 = 63.5 → 64
    assert quantize(1.0) == 127
    assert quantize(-1.0) == -1  // sentinel
    assert quantize(2.0) == 127  // overflow → clamp
    assert quantize(-0.5) == 0   // underflow → clamp
}

fn test_manhattan_identical() {
    v := Vector14{i8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
    assert manhattan_distance(&v, &v) == 0
}
```

### 8.2 Benchmarks nativos (Nível 2)

Funções `bench_*` no próprio `*_test.v`, executadas com `v -bench` (equivalente
ao `go test -bench`). Cobrem o **hot path** completo com medição de alocações.

```v
fn bench_manhattan_distance(b &testing.B) {
    a := Vector14{i8(0), 127, 64, 32, 96, -1, -1, 80, 50, 0, 127, 0, 64, 100}
    b2 := Vector14{i8(127), 0, 32, 64, 10, -1, -1, 40, 90, 127, 0, 127, 32, 50}
    for _ in 0..b.n {
        manhattan_distance(&a, &b2)
    }
}

fn bench_normalize(b &testing.B) {
    payload := parser.parse_payload(test_payload_bytes)!
    for _ in 0..b.n {
        normalize(&payload, &test_config)
    }
}

fn bench_ivf_search(b &testing.B) {
    payload := parser.parse_payload(test_payload_bytes)!
    vector := normalize(&payload, &test_config)
    for _ in 0..b.n {
        test_index.search(&vector)
    }
}
```

Metas (comparação com Go):

| Operação | Go | Meta V |
|----------|:---:|:------:|
| Manhattan (14 dims) | ~14 ns | ~10 ns |
| Normalize | ~100 ns | ~80 ns |
| IVF Search | ~90 µs | ~70 µs |

Devem reportar **zero alocações** no hot path — equivalente ao `0 B/op` do Go.

### 8.3 Teste de stress realista (Nível 3)

Script em V (`scripts/stress.v`) que simula o mais próximo possível do teste
oficial da Rinha (k6). Deve ser executável com `v run scripts/stress.v`.

**Parâmetros** (via flags):

| Flag | Padrão | Descrição |
|------|:------:|-----------|
| `-target` | `http://localhost:9999` | URL base |
| `-duration` | `5m` | Duração total |
| `-rate` | `180` | req/s em regime |
| `-ramp-up` | `30s` | Tempo de ramp-up linear |
| `-workers` | `50` | Workers HTTP concorrentes |

**4 payloads** (idênticos aos do `bench_realista.go` da versão Go):

| Payload | Perfil |
|---------|--------|
| A | Presencial, com cartão, última transação presente (fraudulento) |
| B | Online, sem cartão, última transação presente |
| C | Presencial, com cartão, sem última transação (legítimo) |
| D | Online, sem cartão, km alto, última transação presente |

**Fluxo do script**:

1. Aguardar `GET /ready` responder 200 (até 60 tentativas, 1s intervalo)
2. Iniciar ramp-up linear de 0 → 180 req/s em 30s
3. Manter 180 req/s estáveis até o fim da duração
4. Workers consomem jobs de um canal com capacidade `workers × 4`
5. Cada worker: `http.new_request()` → `client.do()` → medir latência → `discard body` → `close`
6. Coletar todas as amostras em slice protegido por mutex

**Métricas coletadas**:

```
Duracao:       5m0s
Requisicoes:   54000
OK (200):      53500 (99.1%)
Erros HTTP:    300
Erros conexao: 200
Throughput:    180.0 req/s
Latencia avg:  1.2ms
Latencia p50:  0.8ms
Latencia p95:  1.9ms
Latencia p99:  3.5ms
```

**Julgamento automático**:

- 🟢 `p99 < 2000ms && taxa_sucesso >= 85%` → BENCHMARK PASSOU
- 🔴 caso contrário → BENCHMARK FALHOU

**Pós-teste**: consulta `GET /debug/vars` em cada API (porta 8080) e exibe
contadores internos para diagnóstico.

> ⚠️ O teste de stress local é um **smoke test** — não prevê o resultado
> oficial. A diferença está no ambiente de rede e perfil de ramp-up do k6
> oficial. Serve para detectar regressões grosseiras antes do push.

---

## Cronograma

| Fase | Descrição | Estimativa |
|:----:|:----------|:----------:|
| 1 | Tipos, vetores, normalização | 2-3h |
| 2 | Parser JSON manual | 4-6h |
| 3 | IVF index | 3-4h |
| 4 | HTTP handlers + semáforo + respostas | 3-4h |
| 5 | Loader + índice pré-construído | 4-6h |
| 6 | nginx (configuração) | 0.5-1h |
| 7 | Docker + deploy | 1-2h |
| 8 | Testes + benchmarks + ajustes | 4-6h |
| **Total** | | **22-32h** |

Redução de ~3h em relação ao plano original (24-35h → 22-32h) graças ao
nginx eliminar a implementação do proxy customizado.

---

## Referência: Decisões da versão Go preservadas

| ADR | Decisão | Status |
|:---:|:--------|:------:|
| 01 | Quantização uint8 → i8 | Mantida |
| 02 | IVF com 1.000 clusters | Mantida |
| 03 | Distância Manhattan (L1) | Mantida |
| 04 | Proxy stdlib | **Substituído por nginx:alpine** |
| 05 | Binários stripped | Mantida (-prod) |
| 06 | Docker multi-stage scratch | Mantida (API apenas) |
| 07 | Branch submission | Mantida |
| 08 | Índice pré-construído | Mantida |
| 09 | Distribuição CPU/RAM | Mantida |
| 10 | Zero dependências externas | Mantida |
| 13 | Carregamento streaming | Mantida |
| 15 | Timeouts HTTP (200ms) | Mantida |
| 16 | Semáforo não-bloqueante 1024 | Mantida |
| 17 | Unix sockets | Mantida |
| 34 | Parser JSON manual | Mantida |
| 42 | K=5, threshold=0.6, nprobe=2 | Mantida |
