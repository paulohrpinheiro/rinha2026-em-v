# Makefile — Rinha de Backend 2026 em V
.PHONY: build test bench docker-build docker-push docker-up docker-down clean all perf-stat

BINARY_API := bin/api
VFLAGS     := -prod -skip-unused
IMAGE      := paulohrpinheiro/rinha-api-v
VERSION    ?= v1

build:
	@mkdir -p bin
	v $(VFLAGS) -o $(BINARY_API) cmd/api/main.v

test:
	v test internal/

bench:
	v $(VFLAGS) run cmd/api/bench_varied.v

perf-stat: build
	perf stat -e cycles,instructions,cache-references,cache-misses,branch-misses ./bin/bench_varied

docker-build:
	docker build -t $(IMAGE):$(VERSION) -f Dockerfile.api .

docker-push:
	docker push $(IMAGE):$(VERSION)

docker-up:
	docker compose up -d

docker-down:
	docker compose down

docker-logs:
	docker compose logs -f

proxy-build:
	v -prod -skip-unused -o bin/vproxy cmd/vproxy/main.v

proxy-docker-build:
	docker build -t $(IMAGE):vproxy -f Dockerfile.vproxy .

clean:
	rm -rf bin/

all: build test
