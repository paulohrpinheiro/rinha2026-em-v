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

**Decisão**: Mesma do ADR-02 Go. IVF com K-means++ (n_clusters=1000, n_iter=20).
Busca com nprobe=2, maxScanPerCluster=5000, K=5, threshold=0.6.

**Em V 0.5.1**: Struct `IVFIndex` com slices `[]Vector14`, `[]u8`, `[]int` —
similares ao Go. Sem overhead de GC com `-autofree`.

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

## ADR-V05: Binários stripped com -prod

**Decisão**: Compilar com `v -prod -autofree -skip-unused`. Equivalente ao
`-ldflags="-s -w"` do Go.

**Consequências**: Binário esperado de ~1-3 MB, significativamente menor que
os ~5 MB do Go.

---

## ADR-V06: Docker multi-stage com scratch + índice pré-construído

**Decisão**: Mesma do ADR-06 Go, adaptando a imagem base:
1. Stage builder: `vlang/vlang:alpine` (imagem oficial)
2. Stage runtime: `scratch`

O índice IVF é gerado durante o build com `RUN /api -build-index`.

**Nota**: V 0.5.1 compila para binários statically linked (backend C),
compatíveis com scratch. Diferente de Go, não precisa de `CGO_ENABLED=0` —
V pode usar C interop se necessário.

---

## ADR-V07: Estrutura de branches idêntica

**Decisão**: Mesmo padrão do ADR-07 Go:
- `main`: código-fonte completo + nginx.conf
- `submission`: apenas arquivos de deploy (orphan branch, inclui nginx.conf)

---

## ADR-V08: Carregamento streaming

**Decisão**: Mesma do ADR-13 Go. Processar `references.json.gz` em modo
streaming durante o Docker build, quantizando cada vetor imediatamente.

**Em V 0.5.1**: `compress.gzip` + parsing JSON token a token. V não tem um
`json.Decoder.Token()` tão flexível quanto Go — pode ser necessário
implementar tokenização manual do JSON.

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

## ADR-V15: K=5, threshold=0.6, nprobe=2

**Decisão**: Configuração de platô confirmada (ADR-42, ADR-81 Go). Uso de
respostas pré-alocadas (6 possíveis) para zero alocações de serialização.

---

## ADR-V16: GC e gerenciamento de memória

**Contexto**: Go usa `GOGC=off` + `GOMEMLIMIT=60MiB`. V 0.5.1 tem opções
diferentes.

**Decisão**: Usar `-autofree` (libera memória automaticamente no escopo)
combinado com `-skip-unused`. V não tem um equivalente direto ao `GOMEMLIMIT`,
então o controle de memória depende de:
1. Pré-alocação de slices (`[]Vector14{len: 3_000_000}`)
2. `-autofree` para liberar memória de escopos finalizados
3. Monitoramento via `/debug/vars` (implementado manualmente)

**Risco**: Sem um mecanismo de soft memory limit, um pico de alocação pode
estourar o limite de 165 MB sem aviso. Mitigação: pré-alocar tudo durante
o startup e evitar alocações no hot path.

---

## ADR-V17: Timeouts HTTP

**Decisão**: Mesmos valores do ADR-15/ADR-37 Go:
- API Server: ReadTimeout=200ms, WriteTimeout=200ms, IdleTimeout=200ms
- nginx→API: proxy_read_timeout=200ms, proxy_send_timeout=200ms
- `/ready` health check: timeout implícito do nginx

---

## Riscos Específicos da Versão V

| Risco | Probabilidade | Impacto | Mitigação |
|-------|:------------:|:-------:|-----------|
| `net.http` em V 0.5.1 instável sob carga | Média | Alto | V 0.5.1 é mais maduro que 0.4.x; testar com k6 |
| Parsing JSON token a token imaturo | Média | Médio | Tokenização manual se necessário |
| `-autofree` causar double-free | Baixa | Alto | Testar com `-gc boehm` como fallback |
| Compilador V crash em edge cases | Baixa | Médio | Isolar código problemático em módulo C |
| Docker scratch com V compilado via C | Muito baixa | Baixo | V compila estaticamente, sem libc necessária |
| nginx ser single-point-of-failure | Baixa | Baixo | nginx é extremamente estável; não é gargalo com 0.19 CPU |
