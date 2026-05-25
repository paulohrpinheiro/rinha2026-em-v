// ivf.v — IVF Index para busca vetorial.
// V 0.5.1

module internal

import rand
import os
import encoding.binary

// IVFIndex é um Inverted File Index.
pub struct IVFIndex {
pub:
	vectors   []Vector14
	labels    []u8
	centroids []Vector14
	offsets   []int
pub mut:
	n_clusters int
}

pub fn new_ivf(vv []Vector14, ll []u8, cc []Vector14, oo []int) &IVFIndex {
	return &IVFIndex{
		vectors: vv, labels: ll, centroids: cc, offsets: oo, n_clusters: cc.len
	}
}

pub fn (idx &IVFIndex) search(query &Vector14) (int, int) {
	if idx.n_clusters == 0 { return 0, 0 }
	mut nearest := [4]CentroidDist{}
	for i in 0 .. 4 {
		nearest[i] = CentroidDist{dist: i32(2147483647)}
	}
	for c in 0 .. idx.n_clusters {
		d := manhattan_distance(query, idx.centroids[c])
		if d < nearest[3].dist {
			mut pos := 3
			for pos > 0 && d < nearest[pos - 1].dist {
				nearest[pos] = nearest[pos - 1]
				pos--
			}
			nearest[pos] = CentroidDist{id: c, dist: d}
		}
	}
	mut top_k := [5]Neighbor{}
	for i in 0 .. 5 { top_k[i] = Neighbor{dist: i32(2147483647)} }
	for nc in nearest {
		if nc.id < 0 || nc.dist == i32(2147483647) { continue }
		start := idx.offsets[nc.id]
		end := idx.offsets[nc.id + 1]
		if start >= end { continue }
		mut stop := start + 5000
		if stop > end { stop = end }
		for i in start .. stop {
			dist := manhattan_distance(query, idx.vectors[i])
			if dist < top_k[4].dist {
				mut pos := 4
				for pos > 0 && dist < top_k[pos - 1].dist {
					top_k[pos] = top_k[pos - 1]
					pos--
				}
				top_k[pos] = Neighbor{dist: dist, label: idx.labels[i]}
			}
		}
		// Early termination: se K=5 vizinhos concordam, interrompe aqui
		mut fraud_count := 0
		for n in top_k { if n.label == 1 { fraud_count++ } }
		if fraud_count == 0 || fraud_count == 5 { return fraud_count, idx.vectors.len }
	}
	mut fraud_count := 0
	for n in top_k { if n.label == 1 { fraud_count++ } }
	return fraud_count, idx.vectors.len
}

struct CentroidDist { id int
dist i32 }
pub struct Neighbor {
pub:
	dist  i32
	label u8
}

// build_ivf constrói um IVF index usando mini-batch K-means.
// Estratégia (portada da versão Go v44):
//   - K-means++ nos primeiros 100 centroides usando amostra de 5%
//   - Centroides restantes via amostragem uniforme espaçada
//   - 25 iterações de mini-batch (20% do dataset cada)
//   - Assign final no dataset completo + reordenação por cluster
pub fn build_ivf(vectors []Vector14, labels []u8, nc int, _ int) !&IVFIndex {
	if vectors.len == 0 { return error('no vectors') }
	if nc < 1 { return error('need at least 1 cluster') }
	n := vectors.len
	mut rng := rand.new_default()

	// 1. Inicialização de centroides
	kpp_count := if 100 < nc { 100 } else { nc }
	mut sample_size := n / 20 // 5%
	if sample_size < 50000 { sample_size = 50000 }
	if sample_size > n { sample_size = n }

	mut centroids := init_centroids(vectors, n, nc, kpp_count, sample_size, mut rng)!

	// 2. Mini-batch K-means (25 iterações, 20% do dataset cada)
	mut batch_size := n / 5 // 20%
	if batch_size < nc * 10 { batch_size = nc * 10 }
	if batch_size > n { batch_size = n }

	mut cluster_assign := []int{len: n, init: 0}

	for _ in 0 .. 25 {
		// Pick random batch
		mut batch := []int{len: batch_size}
		for i in 0 .. batch_size { batch[i] = rng.int_in_range(0, n)! }

		// Assign batch vectors to nearest centroid
		for idx in batch {
			mut best_c := 0
			mut best_d := manhattan_distance(vectors[idx], centroids[0])
			for c in 1 .. nc {
				d := manhattan_distance(vectors[idx], centroids[c])
				if d < best_d { best_d = d; best_c = c }
			}
			cluster_assign[idx] = best_c
		}

		// Recompute centroids via float64 averages, then re-quantize
		mut accums_sum := [][14]f64{len: nc, init: [14]f64{}}
		mut accums_cnt := []int{len: nc, init: 0}
		for idx in batch {
			c := cluster_assign[idx]
			accums_cnt[c]++
			for d in 0 .. 14 { accums_sum[c][d] += f64(vectors[idx][d]) }
		}
		for c in 0 .. nc {
			if accums_cnt[c] > 0 {
				for d in 0 .. 14 {
					avg := accums_sum[c][d] / f64(accums_cnt[c])
					centroids[c][d] = quantize(avg / 127.0)
				}
			}
		}
	}

	// 3. Assign final: todos os vetores ao centroide mais próximo
	for i in 0 .. n {
		mut best_c := 0
		mut best_d := manhattan_distance(vectors[i], centroids[0])
		for c in 1 .. nc {
			d := manhattan_distance(vectors[i], centroids[c])
			if d < best_d { best_d = d; best_c = c }
		}
		cluster_assign[i] = best_c
	}

	// 4. Contar vetores por cluster para calcular offsets
	mut counts := []int{len: nc, init: 0}
	for i in 0 .. n { counts[cluster_assign[i]]++ }
	mut off := []int{len: nc + 1}
	mut total := 0
	for c in 0 .. nc { off[c] = total; total += counts[c] }
	off[nc] = total

	// 5. Reordenar vetores por cluster
	mut fv := []Vector14{len: n}
	mut fl := []u8{len: n}
	mut cursor := off.clone()
	for i in 0 .. n {
		c := cluster_assign[i]
		pos := cursor[c]
		fv[pos] = vectors[i]
		fl[pos] = labels[i]
		cursor[c]++
	}

	return &IVFIndex{vectors: fv, labels: fl, centroids: centroids, offsets: off, n_clusters: nc}
}

// init_centroids inicializa centroides com K-means++ nos primeiros kpp_count
// usando uma amostra, e o restante via amostragem uniforme espaçada.
fn init_centroids(vectors []Vector14, n int, nc int, kpp_count int, sample_size int, mut rng rand.PRNG) ![]Vector14 {
	mut centroids := []Vector14{cap: nc}

	// Amostra aleatória
	mut sample := []int{len: sample_size}
	for i in 0 .. sample_size { sample[i] = rng.int_in_range(0, n)! }

	// Primeiro centroide: aleatório da amostra
	centroids << vectors[sample[rng.int_in_range(0, sample_size)!]]

	// K-means++ para os próximos kpp_count-1 centroides (na amostra)
	for c in 1 .. kpp_count {
		mut min_dists := []f64{len: sample_size}
		mut total_weight := f64(0)
		for i in 0 .. sample_size {
			mut best_d := i32(i32(2147483647))
			for j in 0 .. c {
				d := manhattan_distance(vectors[sample[i]], centroids[j])
				if d < best_d { best_d = d }
			}
			w := f64(best_d) * f64(best_d) // D² weighting
			min_dists[i] = w
			total_weight += w
		}
		threshold := rng.f64_in_range(0.0, total_weight)!
		mut cum := f64(0)
		mut selected := sample[0]
		for i in 0 .. sample_size {
			cum += min_dists[i]
			if cum >= threshold { selected = sample[i]; break }
		}
		centroids << vectors[selected]
	}

	// Centroides restantes: amostragem uniforme espaçada
	for c := kpp_count; c < nc; c++ {
		mut idx := c * n / nc
		if idx >= n { idx = n - 1 }
		centroids << vectors[idx]
	}

	return centroids
}

pub fn (idx &IVFIndex) save(path string) ! {
	mut buf := []u8{cap: 8 + idx.vectors.len * 15 + idx.centroids.len * 14 + (idx.n_clusters + 1) * 4}
	mut h := [8]u8{}
	binary.little_endian_put_u32(mut h[0..4], u32(idx.vectors.len))
	binary.little_endian_put_u32(mut h[4..8], u32(idx.n_clusters))
	for x in h { buf << x }
	for v in idx.vectors { for d in 0 .. 14 { buf << u8(v[d]) } }
	for l in idx.labels { buf << l }
	for c in idx.centroids { for d in 0 .. 14 { buf << u8(c[d]) } }
	for o in idx.offsets { mut ob := [4]u8{}
	binary.little_endian_put_u32(mut ob[..], u32(o))
	for x in ob { buf << x } }
	os.write_bytes(path, buf)!
}

pub fn load_ivf(path string) !&IVFIndex {
	data := os.read_bytes(path)!
	mut pos := 0
	// Detecta magic header "IVF\x01" (formato Go) vs formato V puro
	if data.len >= 4 && data[0] == `I` && data[1] == `V` && data[2] == `F` && data[3] == 1 {
		pos = 4 // pula magic
	}
	nv := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	nc := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	mut vectors := []Vector14{cap: nv}
	for _ in 0 .. nv { mut v := Vector14{}
	for d in 0 .. 14 { v[d] = i8(data[pos])
	pos++ }
	vectors << v }
	mut labels := []u8{cap: nv}
	for _ in 0 .. nv { labels << data[pos]
	pos++ }
	mut centroids := []Vector14{cap: nc}
	for _ in 0 .. nc { mut c := Vector14{}
	for d in 0 .. 14 { c[d] = i8(data[pos])
	pos++ }
	centroids << c }
	mut offsets := []int{len: nc + 1}
	for i in 0 .. nc + 1 { offsets[i] = int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4 }
	return new_ivf(vectors, labels, centroids, offsets)
}


pub fn generate_test_data(n int) ([]Vector14, []u8) {
	mut rng := rand.new_default()
	mut vectors := []Vector14{cap: n}
	mut labels := []u8{cap: n}
	for _ in 0 .. n {
		mut v := Vector14{}
		for d in 0 .. 14 {
			v[d] = i8(rng.int_in_range(0, 128) or { 0 })
		}
		vectors << v
		labels << u8(rng.int_in_range(0, 2) or { 0 })
	}
	return vectors, labels
}
