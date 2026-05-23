# Makefile — Rinha de Backend 2026 em V
# Duas imagens Docker: API (rinha-api-v) e Proxy (rinha-api-vproxy),
# ambas versionadas com o mesmo $(VERSION).
.PHONY: build test bench docker-build docker-push docker-up docker-down \
        clean all perf-stat

BINARY_API   := bin/api
VFLAGS       := -prod -skip-unused
IMAGE_API    := paulohrpinheiro/rinha-api-v
IMAGE_PROXY  := paulohrpinheiro/rinha-api-vproxy
VERSION      ?= v1

# ── Compilação local ──────────────────────────────────────────────────────

build:
	@mkdir -p bin
	v $(VFLAGS) -o $(BINARY_API) cmd/api/main.v

proxy-build:
	v $(VFLAGS) -o bin/vproxy cmd/vproxy/main.v

test:
	v test internal/

bench:
	v $(VFLAGS) run cmd/api/bench_varied.v

perf-stat: build
	perf stat -e cycles,instructions,cache-references,cache-misses,branch-misses \
		./bin/bench_varied

# ── Docker build (ambas imagens, mesmo VERSION) ────────────────────────────

docker-build:
	docker build -t $(IMAGE_API):$(VERSION) -f Dockerfile.api .
	docker build -t $(IMAGE_PROXY):$(VERSION) -f Dockerfile.vproxy .

docker-push:
	docker push $(IMAGE_API):$(VERSION)
	docker push $(IMAGE_PROXY):$(VERSION)

# ── Docker Compose ────────────────────────────────────────────────────────

docker-up:
	docker compose up -d

docker-down:
	docker compose down

docker-logs:
	docker compose logs -f

# ── Limpeza ───────────────────────────────────────────────────────────────

clean:
	rm -rf bin/

all: build test