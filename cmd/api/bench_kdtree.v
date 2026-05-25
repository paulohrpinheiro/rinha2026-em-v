// bench_kdtree.v — Testa build + search da KD-tree contra busca exata.
// Uso: v -prod run cmd/api/bench_kdtree.v
// Constrói KD-tree sobre N vetores, testa recall e latência.

module main

import internal
import os
import json
import time
import rand

fn main() {
	mut dir := os.getenv('RESOURCES_DIR')
	if dir == '' { dir = './resources' }
	_ := load_config(dir)!
	idx := load_index(dir)!
	println('Index loaded: ${idx.vectors.len} vectors')

	// Usa uma amostra de 100K vetores para construir a KD-tree
	n_sample := 100_000
	println('\nConstruindo KD-tree sobre ${n_sample} vetores...')
	mut rng := rand.new_default()
	mut sample_vectors := []internal.Vector14{cap: n_sample}
	mut sample_labels := []u8{cap: n_sample}
	for i in 0 .. n_sample {
		ri := rng.int_in_range(0, idx.vectors.len) or { i % idx.vectors.len }
		mut v := idx.vectors[ri]
		sample_vectors << v
		sample_labels << idx.labels[ri]
	}

	sw := time.new_stopwatch()
	kt := internal.build_kdtree(sample_vectors, sample_labels, 100)!
	build_us := sw.elapsed().microseconds()
	println('  Construção: ${build_us / 1000} ms')
	println('  Nós: ${kt.nodes.len}')
	println('  Index size: ${kt.indices.len}')

	// Testa recall em 500 queries aleatórias
	n_tests := 500
	mut kd_correct := 0
	mut total_kd_us := i64(0)
	mut total_brute_us := i64(0)

	println('\nTestando ${n_tests} queries...')
	for t in 0 .. n_tests {
		qv := rng.int_in_range(0, n_sample) or { t % n_sample }
		mut query := sample_vectors[qv]

		// KD-tree search
		sw2 := time.new_stopwatch()
		res := kt.search(&query)
		kd_us := sw2.elapsed().microseconds()
		total_kd_us += kd_us
		kd_label := if res.fraud_count >= 3 { u8(1) } else { u8(0) }

		// Busca exata (força bruta)
		sw3 := time.new_stopwatch()
		mut exact_top5 := [5]internal.Neighbor{}
		for i in 0 .. 5 { exact_top5[i] = internal.Neighbor{dist: i32(2147483647)} }
		for i in 0 .. n_sample {
			if i == qv { continue }
			dist := internal.manhattan_distance(query, sample_vectors[i])
			if dist < exact_top5[4].dist {
				mut pos := 4
				for pos > 0 && dist < exact_top5[pos - 1].dist {
					exact_top5[pos] = exact_top5[pos - 1]
					pos--
				}
				exact_top5[pos] = internal.Neighbor{dist: dist, label: sample_labels[i]}
			}
		}
		brute_us := sw3.elapsed().microseconds()
		total_brute_us += brute_us

		mut exact_fraud := 0
		for n in exact_top5 { if n.label == 1 { exact_fraud++ } }
		exact_label := if exact_fraud >= 3 { u8(1) } else { u8(0) }

		if kd_label == exact_label { kd_correct++ }

		if (t + 1) % 100 == 0 {
			println('  [${t + 1}/${n_tests}] KD-tree recall: ${f64(kd_correct) / f64(t + 1) * 100:.2f}%')
		}
	}

	recall := f64(kd_correct) / f64(n_tests) * 100.0
	kd_avg := f64(total_kd_us) / f64(n_tests)
	brute_avg := f64(total_brute_us) / f64(n_tests)

	println('\n========================================')
	println('  Comparação KD-tree vs Busca Exata')
	println('========================================')
	println('  Dataset:      ${n_sample} vetores')
	println('  KD-tree recall: ${recall:.2f}% (${kd_correct}/${n_tests})')
	println('  KD-tree:     ${kd_avg:.1f} μs avg')
	println('  Exato:       ${brute_avg:.1f} μs avg')
	println('  Speedup:     ${f64(brute_avg) / f64(kd_avg):.1f}x')
	println('========================================')
}

fn load_config(dir string) !internal.NormalizationConfig {
	norm_data := os.read_bytes('${dir}/normalization.json')!
	norm := json.decode(internal.NormalizationConfig, norm_data.bytestr())!
	mcc_data := os.read_bytes('${dir}/mcc_risk.json')!
	mcc := json.decode(map[string]f64, mcc_data.bytestr())!
	return internal.NormalizationConfig{
		max_amount: norm.max_amount, max_installments: norm.max_installments,
		amount_vs_avg_ratio: norm.amount_vs_avg_ratio, max_minutes: norm.max_minutes,
		max_km: norm.max_km, max_tx_count_24h: norm.max_tx_count_24h,
		max_merchant_avg_amount: norm.max_merchant_avg_amount, mcc_risk: mcc.clone(),
	}
}

fn load_index(dir string) !&internal.IVFIndex {
	path := '${dir}/index.bin'
	if os.exists(path) { return internal.load_ivf(path) }
	return error('not found')
}