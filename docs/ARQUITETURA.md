# Decisões Arquiteturais — Versão V

> Data: 2026-05-21
> Stack: V 0.5.1 · nginx:alpine
> Base: Go v44 (ADR-01 a ADR-81)

---

## ADR-V01: Quantização i8 (equivalente ADR-01 Go)

**Contexto**: Dataset tem 3M vetores de 14 dimensões. Com f64 seriam 336 MB.

**Decisão**: Quantizar cada dimensão para `i8` (0-127, com -1 sentinel para
dados ausentes), ocupando 14 bytes por vetor → 42 MB para os 3M vetores.

**Em V 0.5.1**: `type Vector14 = [14]i8` — array fixo, mesmo footprint do Go.

---

## ADR-V02: IVF (Inverted File Index) com 1.000 clusters

**Decisão**: Mesma do ADR-02 Go. IVF com **mini-batch K-means** (portado da
estratégia Go v44). Inicialização: K-means++ nos primeiros 100 centroides sobre
amostra de 5% (~150K vetores); centroides restantes via amostragem uniforme
espaçada. Refinamento: 25 iterações de mini-batch com 20% do dataset cada
(~600K vetores/iteração). Assign final no dataset completo com reordenação por
cluster. Busca: nprobe=2, maxScanPerCluster=5000, K=5, threshold=0.6.

**Motivação**: O K-means++ original sobre o dataset completo (3M vetores, 1000
clusters) tinha complexidade O(n·k²) ≈ 1.5 trilhão de distâncias Manhattan,
levando ~6 horas em single core. O mini-batch reduz para ~5 minutos.

**Em V 0.5.1**: Struct `IVFIndex` com slices `[]Vector14`, `[]u8`, `[]int` —
similares ao Go. Função `init_centroids` para inicialização híbrida
(K-means++ parcial + amostragem uniforme).

---

## ADR-V03: Distância Manhattan (L1) desenrolada

**Decisão**: Manhattan com `abs` manual desenrolado para 14 dimensões, usando
inteiros. V pode auto-vetorizar melhor que Go devido ao backend C com `-O3`.

---

## ADR-V04: Proxy reverso via nginx:alpine

**Contexto**: A versão Go usa proxy customizado em Go. Para a versão V,
temos duas opções: implementar proxy em V (~200 linhas, risco de bugs) ou
usar uma solução pronta.

**Alternativas consideradas**:

| Solução | Tamanho | Código | Maturidade |
|---------|:-------:|:------:|:----------:|
| **nginx:alpine** | ~10 MB | Configuração declarativa (~30 linhas) | 20+ anos, battle-tested |
| haproxy:alpine | ~15 MB | Configuração declarativa | 20+ anos |
| caddy:alpine | ~40 MB | Caddyfile (~10 linhas) | 10 anos |
| traefik | ~50 MB | Labels/rules | 8 anos |
| Proxy em V | ~1 MB | ~200 linhas de código | 0 (novo) |

**Decisão**: Usar **nginx:alpine** — imagem de ~10 MB, configuração declarativa
mínima, round-robin ou least_conn nativo, suporte a Unix sockets, timeouts
configuráveis, zero código para manter.

**Consequências**:
- Positivas: confiabilidade comprovada, elimina ~200 linhas de código, reduz
  superfície de bugs.
- Negativas: sem `/debug/vars` próprio no proxy (cada API ainda expõe o seu
  na porta 8080).
- Mitigação: métricas podem ser obtidas diretamente das APIs via
  `GET /debug/vars` na porta 8080 ou via nginx stub_status.

**Configuração**:

```nginx
upstream api_backends {
    least_conn;
    server unix:/run/sock/api-1.sock;
    server unix:/run/sock/api-2.sock;
}

server {
    listen 9999;
    location /ready {
        proxy_pass http://api_backends/ready;
    }
    location /fraud-score {
        proxy_pass http://api_backends/fraud-score;
        proxy_read_timeout 200ms;
        proxy_send_timeout 200ms;
    }
}
```

---

## ADR-V05: Compilação estática com -prod e -cflags '-static'

**Decisão**: Compilar com `v -prod -skip-unused -cflags '-static'`.
Equivalente ao `-ldflags="-s -w"` do Go, mas gerando binário statically linked
contra musl (imagem base Alpine) para compatibilidade com scratch.

**Nota**: `-autofree` foi removido — causava segfault com `map[string]f64`
alocado na stack e retornado por valor em `load_config()`. O autofree liberava
o mapa prematuramente.

**Consequências**: Binário estático de ~400 KB, compatível com scratch sem
dependência de libc externa.

---

## ADR-V06: Docker multi-stage com scratch + index.bin commitado

**Decisão**: Mesma do ADR-06 Go, com duas diferenças:
1. Stage builder: `vlang/vlang:alpine` (imagem oficial) com `-cflags '-static'`
2. Stage runtime: `scratch`
3. **Index.bin é commitado no repositório** (43 MB), não gerado durante o build

**Motivação**: O parser JSON byte-a-byte em V 0.5.1 levava ~33 minutos para
carregar 3M de vetores (o parser Go leva 13 segundos). Gerar o índice durante
o Docker build era inviável. O index.bin é gerado uma vez com a ferramenta Go
e versionado.

**Procedimento para rebuild do índice** (quando o dataset mudar):
```bash
cd ../rinha-de-backend-2026
go build -o bin/api ./cmd/api
RESOURCES_DIR=./resources REFERENCES_PATH=./resources/references.json.gz \
  ./bin/api -build-index ./resources/index.bin
cp resources/index.bin ../rinha2026-em-v/resources/
```

**Nota**: O `load_ivf()` do V detecta e suporta tanto o formato Go (magic
header `IVF\x01`) quanto o formato V puro, mantendo compatibilidade futura.

---

## ADR-V07: Estrutura de branches idêntica

**Decisão**: Mesmo padrão do ADR-07 Go:
- `main`: código-fonte completo + nginx.conf
- `submission`: apenas arquivos de deploy (orphan branch, inclui nginx.conf)

---

## ADR-V08: Carregamento streaming (parser manual + fallback Go)

**Decisão**: Mesma do ADR-13 Go. Processar `references.json.gz` com parsing
JSON manual byte-a-byte, quantizando cada vetor imediatamente.

**Em V 0.5.1**: Implementado parser manual (`loader.v`, `parser.v`) similar
ao Go — `skip_ws`, `parse_float`, `skip_value`, campos identificados por
tamanho da chave. Funcional mas **~150× mais lento** que o `encoding/json`
do Go (33+ minutos vs 13 segundos para 3M vetores).

**Status**: O parser V é usado apenas para o hot path (requisições de
fraud-score, payloads de ~1 KB). Para o carregamento do dataset de
referência (3M vetores), o `index.bin` é pré-construído com a ferramenta
Go e commitado (ver ADR-V06). Otimização do parser V é trabalho futuro
(benchmark em `cmd/api/bench_parse.v`).

---

## ADR-V09: Distribuição de recursos

| Serviço | CPU  | Memória |
|---------|:----:|:-------:|
| nginx   | 0.19 | 20 MB   |
| api-1   | 0.405 | 165 MB |
| api-2   | 0.405 | 165 MB |
| Total   | 1.0  | 350 MB  |

Mesma distribuição do ADR-09/ADR-28 Go (proxy → nginx 0.19 CPU).

---

## ADR-V10: Zero dependências externas

**Decisão**: `v.mod` apenas com `Module`, sem `dependencies`. A API é V puro.
nginx é a única dependência externa e é imagem oficial Docker, não módulo V.

Pacotes usados da stdlib de V 0.5.1:
- `net.http` — servidor HTTP
- `net` — Unix sockets
- `compress.gzip` — descompressão de referências
- `encoding.binary` — serialização do índice
- `encoding.json` — parsing de arquivos de configuração
- `sync` — semáforo atômico
- `math` — round, operações
- `rand` — K-means++
- `time` — parsing de timestamps
- `os` — arquivos, variáveis de ambiente

---

## ADR-V11: nginx com least_conn

**Contexto**: A versão Go usa round-robin com `sync/atomic`. nginx oferece
`least_conn` como alternativa.

**Decisão**: Usar `least_conn` — envia para o backend com menos conexões ativas,
reduzindo filas e balanceando melhor sob carga variável.

**Consequências**:
- Backend mais rápido recebe mais requisições (justo)
- Reduz probabilidade de fila em um backend enquanto o outro está ocioso
- Sem custo adicional de configuração

---

## ADR-V12: Semáforo não-bloqueante 1024

**Decisão**: Mesma do ADR-16/ADR-30 Go. Implementar com `sync.AtomicInt` de V,
compatível com `sync/atomic` do Go.

---

## ADR-V13: Unix sockets nginx↔API

**Decisão**: Mesma do ADR-17 Go. Volume compartilhado `sock`, sockets em
`/run/sock/<hostname>.sock`. nginx suporta Unix sockets nativamente na
diretiva `upstream`.

---

## ADR-V14: Parser JSON manual

**Decisão**: Mesma do ADR-34 Go. Parsing byte-a-byte sem alocações, campos
resolvidos por tamanho da chave.

**Em V 0.5.1**: A macro `$for` pode ser usada para switch em tempo de compilação
sobre as strings de chave conhecidas.

---

## ADR-V15: Formato binário compatível com Go (magic header)

**Decisão**: O `index.bin` é gerado pela ferramenta Go, que usa magic header
`IVF\x01` (4 bytes) antes dos campos de metadata. O `load_ivf()` do V detecta
automaticamente o formato:
- Se os primeiros 4 bytes forem `IVF\x01` → formato Go (pula magic)
- Caso contrário → formato V puro (8 bytes: nVectors + nCentroids)

Isso permite rebuild do índice com qualquer uma das ferramentas, sem
lock-in. Ver implementação em `internal/ivf.v:load_ivf()`.

---

## ADR-V16: K=5, threshold=0.6, nprobe=2

**Decisão**: Configuração de platô confirmada (ADR-42, ADR-81 Go). Uso de
respostas pré-alocadas (6 possíveis) para zero alocações de serialização.

---

## ADR-V17: GC e gerenciamento de memória

**Contexto**: Go usa `GOGC=off` + `GOMEMLIMIT=60MiB`. V 0.5.1 tem opções
diferentes.

**Decisão**: Compilar com `-skip-unused` (elimina código morto) mas **sem
`-autofree`**. O `-autofree` causava segfault com `map[string]f64` alocado
na stack — o autofree liberava o mapa prematuramente quando retornado por
valor de `load_config()`. V não tem um equivalente direto ao `GOMEMLIMIT`,
então o controle de memória depende de:
1. Pré-alocação de slices (`[]Vector14{len: 3_000_000}`)
2. Index pré-carregado no startup (~43 MB em memória)
3. Monitoramento via `/debug/vars` (implementado manualmente)

**Risco**: Sem um mecanismo de soft memory limit, um pico de alocação pode
estourar o limite de 165 MB sem aviso. Mitigação: pré-alocar tudo durante
o startup e evitar alocações no hot path.

---

## ADR-V18: Timeouts HTTP

**Decisão**: Mesmos valores do ADR-15/ADR-37 Go:
- API Server: ReadTimeout=200ms, WriteTimeout=200ms, IdleTimeout=200ms
- nginx→API: proxy_read_timeout=200ms, proxy_send_timeout=200ms
- `/ready` health check: timeout implícito do nginx

---

## ADR-V19: Versionamento de imagens Docker

**Decisão**: Duas imagens Docker independentes no Docker Hub, ambas
versionadas com o mesmo tag semântico (`v01`, `v02`, …).

| Imagem | Repositório | Função |
|--------|-------------|--------|
| API | `paulohrpinheiro/rinha-api-v` | Servidor HTTP de detecção de fraude |
| Proxy | `paulohrpinheiro/rinha-api-vproxy` | Proxy TCP (substitui nginx) |

**Build unificado** — um comando constrói ambas:
```bash
make docker-build VERSION=v05
```

**Push unificado** — um comando envia ambas:
```bash
make docker-push VERSION=v05
```

**docker-compose.yml** referencia as imagens por tag (`image:` + `build:`),
permitindo tanto `docker compose up` local com rebuild quanto pull do registry.

---

## ADR-V20: Proxy TCP em V (substituição do nginx)

**Decisão**: Substituir `nginx:alpine` por um proxy TCP customizado em V,
eliminando o overhead de HTTP parsing no proxy.

**Motivação**: O nginx fazia parsing HTTP completo para cada requisição
recebida. O proxy em V apenas copia bytes entre os sockets (client↔backend),
eliminando uma camada de processamento. Além disso, a comunicação com as
APIs é via Unix sockets nativos (sem TCP bridge), reduzindo latência.

**Ganhos esperados**:
- Proxy ~10 MB → ~6 MB (scratch vs nginx:alpine)
- CPU do proxy 0.19 → 0.10 (libera 0.09 para as APIs)
- APIs ganham 11% de CPU (0.405 → 0.45 cada)
- Latência reduzida pela eliminação do parsing HTTP duplicado

**Desvantagens**:
- Proxy em V não faz HTTP health check próprio (delega às APIs)
- Round-robin simples em vez de least_conn com health check do nginx

---

## Riscos Específicos da Versão V

| Risco | Probabilidade | Impacto | Mitigação |
|-------|:------------:|:-------:|-----------|
| `net` em V 0.5.1 instável sob carga | Média | Alto | V 0.5.1 é mais maduro que 0.4.x; testar com k6 |
| Parser JSON manual lento (150× Go) | **Confirmado** | Médio | Index.bin pré-construído com Go; parser V só no hot path |
| `-autofree` + stack ref = segfault | **Confirmado** | Alto | **Removido** `-autofree`; compilação com `-skip-unused` apenas |
| Compilador V crash em edge cases | Baixa | Médio | Isolar código problemático em módulo C |
| K-means++ dataset completo (~6h) | **Confirmado** | Alto | **Corrigido**: mini-batch K-means (~5 min) |
| nginx ser single-point-of-failure | Baixa | Baixo | nginx é extremamente estável; não é gargalo com 0.19 CPU |
| Binário não-estático incompatível com scratch | **Confirmado** | Alto | **Corrigido**: `-cflags '-static'` (Alpine/musl) |
