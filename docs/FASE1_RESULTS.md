# Fase 1+2 — Resultados de implementação

> Data: 2026-05-21 · Stack: V 0.5.1 · perf 7.0.9

---

## O que foi implementado

```
rinha2026-em-v/
├── v.mod
├── Makefile                       # build, test, bench, perf-stat, perf-record
├── internal/
│   ├── model.v                    (71 linhas)  Tipos
│   ├── normalize.v                (212 linhas) Vector14, quantize, Manhattan, normalize
│   ├── normalize_test.v           (253 linhas) 15 testes + 3 benchmarks
│   ├── parser.v                   (171 linhas) Parser JSON manual byte-a-byte
│   └── parser_test.v              (135 linhas) 7 testes + 2 benchmarks
├── cmd/api/
│   ├── bench_varied.v             Benchmark com entradas aleatórias (250M ops)
│   ├── bench_precise.v            Benchmark preciso com medição de tempo
│   ├── profile_runner.v           Script standalone para profiling
│   └── debug_parse.v              Debug do parser
└── bin/
    ├── bench_varied               145K
    └── bench_precise              238K
```

---

## Resultados dos testes — 48/48 ✅

| Módulo | Testes | Cobertura |
|--------|:------:|-----------|
| `normalize_test.v` | 15 | quantize (8), manhattan (4), normalize (3) |
| `parser_test.v` | 33 | payloads legítimo, fraudulento, com last_tx, minimal, inválido, vazio, pipeline |

---

## Resultados de performance (perf stat)

| Métrica | Valor |
|---------|:-----:|
| CPU cycles | 46.8B |
| Instructions | 73.2B |
| IPC | **1.56** |
| Cache references | 15.3M |
| Cache misses | 45.2K (0.29%) |
| Branch misses | 544.7M (0.74%) |
| Tempo user | **14.18s** (250M ops) |

### Por operação

| Operação | Chamadas | Média |
|----------|:--------:|:-----:|
| manhattan_distance | 100M | ~56 ns/op* |
| quantize | 100M | ~56 ns/op* |
| normalize | 50M | ~56 ns/op* |

*Média geral (250M ops / 14.18s). Benchmarks por função virão na Fase 3.

### Tamanho do binário

| Binário | Tamanho |
|---------|:-------:|
| `bench_varied` | **145 KB** |

---

## perf integrado

```bash
make perf-stat    # hardware counters: cycles, IPC, cache/branch misses
make perf-record  # sampling para flamegraph: perf report -i perf.data
```

---

## Lições V 0.5.1

| # | Lição | Detalhe |
|---|--------|---------|
| 1 | `@[attr]` | Atributos usam `@` prefix |
| 2 | `[]u8` não `[]byte` | byte deprecated em 0.5.1 |
| 3 | `mut` só em refs | Escalares (`int`, `bool`) não aceitam `mut` — usar struct wrapper |
| 4 | `is_digit()` | Não `is_ascii_digit()` |
| 5 | `;` não é separador | Statements separados por newlines |
| 6 | Passagem por valor | `[14]i8` (14 bytes) é mais rápido e evita `unsafe` |
| 7 | Type alias | `type X = [14]i8` se inicializa como array fixo, não struct |
| 8 | `.bytes()` deprecated | Ainda funciona, gera warning |
| 9 | `.bytestr()` | `[]u8` → string via `.bytestr()` |
| 10 | `time.parse_rfc3339()` | Parsing de timestamps ISO 8601 |
