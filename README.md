# Rinha de Backend 2026 — Implementação em V

Versão em **V (Vlang)** do sistema de detecção de fraude por busca vetorial,
portando a implementação Go v44 (`+1076` score, platô estável) com as mesmas
decisões arquiteturais comprovadas.

> **Stack**: V 0.5.1 · IVF · Manhattan · int8 quantization · nginx
> **Limites**: 1 CPU · 350 MB RAM · 3 serviços (nginx + 2 APIs)
> **Porta**: 9999 (nginx)
> **Ref. externa**: [1º colocado](https://github.com/daniloitagyba/rinha-2026-dotnet) — KD-tree exato + C fd handoff + AVX2
> **Resultado oficial**: score **+6.000** (máximo) · p99 **0.96ms** · **zero** FP/FN/erros
> **Lições**: [REFERENCIA.md](docs/REFERENCIA.md) · [resultBest.json](benchs/benchs/resultBest.json)

---

## Objetivo

Reimplementar em V o pipeline completo de detecção de fraude, preservando
todas as decisões que levaram ao platô de score `+1076` na versão Go:

- IVF com 1.000 clusters, nprobe=2, K=5, threshold=0.6
- Distância Manhattan sobre vetores int8 (14 bytes/vetor)
- Parsing JSON manual byte-a-byte (zero alocações, zero reflection)
- Índice pré-construído no Docker build (startup < 1s)
- Proxy reverso que encaminha JSON bruto (sem parsing), APIs processam direto
- Comunicação nginx↔API via Unix sockets
- Semáforo não-bloqueante com capacidade 1024
- Respostas pré-alocadas (6 respostas possíveis)
- Binário da API stripped em scratch (multi-stage Docker build)
- Proxy reverso via **nginx:alpine** (~10 MB, zero código)

---

## Arquitetura

```
Client → nginx → API #1 e API #2 (round-robin)
```

| Serviço | CPU  | Memória | Função |
|---------|:----:|:-------:|--------|
| nginx   | 0.19 | 20 MB   | Load balancer round-robin + /ready (health check) |
| api-1   | 0.405 | 165 MB | Detecção de fraude (IVF, parser JSON manual, /debug/vars) |
| api-2   | 0.405 | 165 MB | Detecção de fraude (IVF, parser JSON manual, /debug/vars) |
| Total   | 1.0  | 350 MB  | — |

**Por que nginx em vez de proxy customizado em V?**

| Abordagem | Prós | Contras |
|-----------|------|---------|
| **nginx:alpine** | Battle-tested, ~10 MB, zero código, round-robin + health check nativos, Unix socket suporte | Sem `/debug/vars` próprio (APIs expõem individualmente) |
| Proxy em V | Métricas customizadas, controle total | ~200 linhas de código para manter, risco de bugs sob carga |

O `/debug/vars` era conveniente na versão Go para diagnóstico, mas não faz
parte do contrato da API (apenas `GET /ready` e `POST /fraud-score`). Cada
API ainda expõe `/debug/vars` na porta 8080 individualmente.

---

## Estrutura do Projeto

```
cmd/
  api/
    main.v           # Servidor HTTP da API
nginx/
  nginx.conf          # Configuração do nginx (upstream + health check)
internal/
  model.v            # Tipos: payload, vetor, respostas
  normalize.v        # Vetor 14-dim + quantização int8 + Manhattan
  ivf.v              # IVF Index (Inverted File Index)
  handler.v          # Handlers HTTP (/ready, /fraud-score, /debug/vars)
  parser.v           # Parsing JSON manual byte-a-byte
  loader.v           # Carregamento streaming + clustering IVF + serialização binária
  responses.v        # Respostas pré-alocadas
  debug.v            # Contadores para /debug/vars
  *_test.v           # Testes unitários e benchmarks
docs/
  PLANO.md           # Plano de implementação detalhado
  ARQUITETURA.md     # Decisões arquiteturais específicas da versão V
  API.md             # Contrato da API (referência)
  REGRAS_DE_DETECCAO.md  # Fórmulas das 14 dimensões
  REFERENCIA.md      # Referência rápida das decisões do projeto Go
scripts/
  stress.v           # Teste de stress realista (simula k6 oficial)
resources/           # Dataset + índice pré-construído
  references.json.gz # 3M vetores rotulados (apenas para build)
  mcc_risk.json      # Risco por MCC
  normalization.json # Constantes de normalização
  index.bin          # Índice IVF pré-construído (gerado no docker build)
Dockerfile.api       # Multi-stage: vlang → scratch
docker-compose.yml   # Orquestração local (com build)
v.mod                # Módulo V (zero dependências externas)
info.json            # Metadados da submissão
Makefile             # build, test, docker, push
```

---

## Pré-requisitos

- V 0.5.1 (instalado via https://github.com/vlang/v) — **versão confirmada no ambiente**
- Docker Engine + Compose
- make

### Recursos do Dataset

Baixe do [repositório oficial da Rinha](https://github.com/zanfranceschi/rinha-de-backend-2026) e coloque em `resources/`:

- `references.json.gz`
- `mcc_risk.json`
- `normalization.json`

---

## Comandos Make

| Comando | Descrição |
|---------|-----------|
| `make build` | Compila binário stripped da API em bin/ |
| `make test` | Roda todos os testes |
| `make bench` | Roda benchmarks nativos |
| `make stress` | Teste de stress realista (5 min, 180 req/s) |
| `make stress-smoke` | Smoke test rápido (1 min) |
| `make docker-build VERSION=v1` | Constrói imagem Docker da API |
| `make docker-push VERSION=v1` | Envia imagem para o Docker Hub |
| `make docker-up` | docker compose up -d |
| `make docker-down` | docker compose down |
| `make docker-logs` | docker compose logs -f |
| `make clean` | Remove bin/ |
| `make profile` | Profiling de CPU da API (v -prof) |
| `make profile-stress` | Profiling sob carga (stress + profile) |
| `make all` | build + test |

---

## Diretiva de Testabilidade e Profiling

**Todo código deve ser testável e perfilável.** Nenhuma função entra em produção
sem cobertura de testes e sem evidência de performance. O pipeline de qualidade
tem quatro níveis:

### Nível 0 — Profiling (`make profile`, `make profile-stress`)

Antes de qualquer teste, o hot path deve ser perfilado. V oferece profiling
nativo via `-prof` (similar ao pprof do Go, via backend C):

```bash
# Profiling de CPU — compila com instrumentação, executa e gera relatório
v -prof profile.txt run cmd/api/main.v

# Profiling filtrado — apenas funções específicas do hot path
v -profile-fns manhattan_distance,normalize,search -prof profile.txt run cmd/api/main.v

# Profiling sem funções inline (mais granular)
v -profile-no-inline -prof profile.txt run cmd/api/main.v

# Profiling sob carga real (anexa ao container em execução)
make docker-up
make profile-stress  # executa stress + profiling simultâneo
```

**Uso programático** — controle granular dentro do código V:

```v
import v.profile

// Desliga profiling durante inicialização (ruído)
profile.on(false)
index := loader.load_index(config.index_path)!
profile.on(true)  // liga apenas no hot path

// ... requisições processadas ...
```

**Flags relevantes**:

| Flag | Função |
|------|--------|
| `v -prof arquivo.txt` | CPU profiling — contagem de chamadas por função |
| `v -profile-fns fn1,fn2` | Filtra profiling para funções específicas |
| `v -profile-no-inline` | Pula funções inline (análise mais granular) |
| `-d no_profile_startup` | Ignora código antes de `main()` |

**Ferramentas externas** (V compila para C — binários compatíveis com):

| Ferramenta | Uso |
|------------|-----|
| `perf record ./api && perf report` | Linux perf — sampling de hardware, cache misses, branch prediction |
| `valgrind --tool=callgrind ./api` | Call graph completo com contagem de instruções |
| `valgrind --tool=massif ./api` | Heap profiling — rastreia alocações e picos de memória |
| `heaptrack ./api` | Perfil de heap com timeline gráfica |

### Nível 1 — Testes unitários (`make test`)

Cada módulo com `*_test.v` usando o framework nativo `assert` de V:

```
v test internal/
```

| Módulo | O que cobre |
|--------|------------|
| `normalize_test.v` | `quantize()`, `manhattan_distance()`, `normalize()` — todas as 14 dimensões, valores de borda, sentinela -1 |
| `ivf_test.v` | `search()` — índice vazio, vizinho exato, K=5, nprobe=2, maxScanPerCluster |
| `handler_test.v` | `GET /ready`, `POST /fraud-score`, JSON inválido, payload sem `last_transaction` |
| `parser_test.v` | `parse_payload()` — cada campo do JSON, floats negativos, null, chaves ausentes |
| `loader_test.v` | Carregamento streaming, K-means (centroides estáveis), serialização binária round-trip |
| `responses_test.v` | `fraud_response()` para cada valor 0-5 |

### Nível 2 — Benchmarks nativos (`make bench`)

Funções `bench_*` no próprio `*_test.v`, executadas com `v -bench` (similar ao
`go test -bench`). Cobrem o **hot path** completo:

| Benchmark | Objetivo | Meta (vs Go) |
|-----------|----------|:------------:|
| `bench_manhattan` | 14 dimensões desenroladas | < 10 ns (Go: 14 ns) |
| `bench_normalize` | Payload → vetor 14-dim | < 80 ns (Go: 100 ns) |
| `bench_ivf_search` | Normalize + Search completo | < 70 µs (Go: 90 µs) |

Devem reportar zero alocações no hot path (equivalente a `0 B/op` do Go).

### Nível 3 — Teste de stress (`make stress`)

Simula o mais próximo possível do teste oficial da Rinha (k6). Deve ser um
script separado em V (`scripts/stress.v`) que:

- **Padrão de carga**: 180 req/s sustentado por 5 minutos, com ramp-up de 30s
- **4 payloads** variados idênticos aos do benchmark realista Go (fraudulento,
  legítimo, sem `last_transaction`, online com km alto)
- **Workers concorrentes**: 50 workers HTTP reutilizando conexões
- **Coleta**: p50, p95, p99, erros HTTP, erros de conexão, throughput
- **Julgamento automático**: 🟢 passou / 🔴 falhou baseado em p99 < 2000ms
  e taxa de sucesso ≥ 85%
- **Pré-condição**: espera `GET /ready` responder 200 antes de iniciar

```bash
# Ambiente local (com constraints Docker)
make docker-up
v run scripts/stress.v -target http://localhost:9999 -duration 5m -rate 180 -ramp-up 30s

# Smoke test rápido (1 minuto)
v run scripts/stress.v -target http://localhost:9999 -duration 1m -rate 180 -ramp-up 5s
```

O script consulta `/debug/vars` das APIs (porta 8080) ao final para expor
contadores internos e facilitar diagnóstico.

> ⚠️ Assim como no benchmark Go, o teste de stress local é um **smoke test** —
> não prevê o resultado oficial. A diferença está no ambiente de rede e perfil de
> ramp-up do k6 oficial. Ele serve para detectar regressões grosseiras antes do
> push, não para cravar o score final.

---

## Como V se compara a Go neste contexto

| Aspecto | Go | V | Impacto |
|---------|:--:|:--:|:-------:|
| Compilação nativa | ✅ | ✅ | Sem runtime, binário statically linked |
| Tamanho do binário | ~5 MB (stripped) | Esperado ~1-3 MB | Menor ainda |
| GC | Sim (GOGC=off) | Opcional (autofree) | Pode eliminar GC overhead |
| Arrays fixos | [14]int8 | [14]i8 | Sintaxe similar |
| Standard library HTTP | net/http | net.http ou x.vweb | Ambos suportam |
| JSON parsing | encoding/json | json module | Similar |
| Generics | Go 1.18+ | Sim (com limitações) | — |
| C interop | CGO | Nativo (C ↔ V bidirecional) | — |
| Cross-compilation | GOOS/GOARCH | `v -os linux -arch amd64` | Mais simples |
| Docker scratch | ✅ | ✅ (statically linked) | — |
| Maturidade | 15+ anos | ~5 anos | Risco em edge cases |

### Vantagens potenciais de V

1. **Binário menor**: V compila direto para C/assembly, sem runtime Go.
2. **Sem GC obrigatório**: `-autofree` ou `-gc none` podem eliminar pausas de GC.
3. **Compilação rápida**: V compila ~100k linhas/s.
4. **Sintaxe limpa**: Similar a Go, mas com menos verbosidade.
5. **C interop nativo**: Se precisar otimizar trechos críticos em C.

### Riscos

1. **Maturidade da stdlib**: `net.http` pode não ser tão robusto quanto `net/http` do Go.
2. **Ecossistema**: Menos bibliotecas, menos exemplos de produção.
3. **Edge cases**: Comportamento sob carga extrema pode ter surpresas.
4. **Ferramentas de profiling**: V tem `-prof` nativo (similar ao pprof), mas com menos
   ferramentas de visualização. Mitigação: binário compila para C → `perf`, `valgrind`
   e `heaptrack` do Linux funcionam diretamente.

---

## Endpoints (porta 9999)

### `GET /ready`

Verificação de prontidão. O nginx faz health check passivo dos backends:

| Estado dos backends | Resposta |
|---|---|
| Todos respondem 2xx | HTTP 200 (nginx retorna da API) |
| Backend indisponível | HTTP 502/503 (nginx) |

### `GET /debug/vars` (APIs, porta 8080)

Cada API expõe contadores internos em JSON individualmente.

### `POST /fraud-score`

Processa a transação e retorna a decisão de fraude. O nginx distribui em
round-robin entre api-1 e api-2, encaminhando o JSON bruto sem parsing.

---

## Licença

MIT — mesmo espírito da Rinha: aprendizado coletivo.
