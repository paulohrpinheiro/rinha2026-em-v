// bench_recall.v — Compara recall do IVF vs busca exata (força bruta).
// Uso: v -prod run cmd/api/bench_recall.v
// Carrega o índice IVF e testa N vetores aleatórios, comparando
// o resultado do IVF (top-5) com a busca exata (todos os vetores).
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
	println('Index loaded: ${idx.vectors.len} vectors, ${idx.n_clusters} clusters')

	mut rng := rand.new_default()
	n_tests := 2000
	mut ivf_correct := 0
	mut exact_fraud_ivf_legit := 0  // FN do IVF
	mut exact_legit_ivf_fraud := 0  // FP do IVF
	mut total_ivf_time := i64(0)
	mut total_exact_time := i64(0)

	for t in 0 .. n_tests {
		// Pega um vetor aleatório do índice como query
		qv := rng.int_in_range(0, idx.vectors.len) or { continue }
		_ := idx.labels[qv]
		mut query := idx.vectors[qv]

		// IVF search (nprobe=4, maxScan=10000, ET)
		sw := time.new_stopwatch()
		ivf_fraud, _ := idx.search(&query)
		ivf_us := sw.elapsed().microseconds()
		total_ivf_time += ivf_us
		ivf_label := if ivf_fraud >= 3 { u8(1) } else { u8(0) }

		// Busca exata (força bruta em todos os vetores)
		sw2 := time.new_stopwatch()
		mut exact_top5 := [5]internal.Neighbor{}
		for i in 0 .. 5 { exact_top5[i] = internal.Neighbor{dist: i32(2147483647)} }
		for i in 0 .. idx.vectors.len {
			if i == qv { continue } // ignora o próprio vetor
			dist := internal.manhattan_distance(query, idx.vectors[i])
			if dist < exact_top5[4].dist {
				mut pos := 4
				for pos > 0 && dist < exact_top5[pos - 1].dist {
					exact_top5[pos] = exact_top5[pos - 1]
					pos--
				}
				exact_top5[pos] = internal.Neighbor{dist: dist, label: idx.labels[i]}
			}
		}
		exact_us := sw2.elapsed().microseconds()
		total_exact_time += exact_us

		mut exact_fraud := 0
		for n in exact_top5 { if n.label == 1 { exact_fraud++ } }
		exact_label := if exact_fraud >= 3 { u8(1) } else { u8(0) }

		if ivf_label == exact_label {
			ivf_correct++
		} else {
			if exact_label == 1 { exact_fraud_ivf_legit++ }   // IVF disse legit mas era fraud (FN)
			else { exact_legit_ivf_fraud++ }                    // IVF disse fraud mas era legit (FP)
		}

		if (t + 1) % 500 == 0 {
			progress := f64(t + 1) / f64(n_tests) * 100.0
			println('  [${t + 1}/${n_tests}] ${progress:.0f}%  IVF recall: ${f64(ivf_correct) / f64(t + 1) * 100:.2f}%')
		}
	}

	recall := f64(ivf_correct) / f64(n_tests) * 100.0
	ivf_avg := f64(total_ivf_time) / f64(n_tests)
	exact_avg := f64(total_exact_time) / f64(n_tests)

	println('\n========================================')
	println('  Comparação IVF vs Busca Exata')
	println('========================================')
	println('  Amostra:      ${n_tests} vetores')
	println('  IVF correto:  ${ivf_correct} (${recall:.2f}%)')
	println('  FN do IVF:    ${exact_fraud_ivf_legit} (IVF disse legítimo, era fraude)')
	println('  FP do IVF:    ${exact_legit_ivf_fraud} (IVF disse fraude, era legítimo)')
	println('  Latência IVF:     ${ivf_avg:.1f} μs avg')
	println('  Latência exata:   ${exact_avg:.1f} μs avg (brute-force 3M)')
	println('  IVF vs exato:     ${f64(exact_avg) / f64(ivf_avg):.1f}x mais lento')
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