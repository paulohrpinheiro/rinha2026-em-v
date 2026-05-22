// profile_runner.v — Script standalone para profiling do hot path.
// Executa 10M iterações de cada função crítica e gera perfil via v -prof.

module main

import internal

fn main() {
	// Configuração de normalização
	config := &internal.NormalizationConfig{
		max_amount:             10000.0,
		max_installments:       12.0,
		amount_vs_avg_ratio:    10.0,
		max_minutes:            1440.0,
		max_km:                 1000.0,
		max_tx_count_24h:       20.0,
		max_merchant_avg_amount: 10000.0,
	}

	// Payload realista (transação com last_transaction)
	payload := &internal.PayloadData{
		amount:               384.88,
		installments:         3,
		avg_amount:           769.76,
		requested_at:         1773260615,
		has_last_transaction: true,
		last_timestamp_unix:  1773241115,
		last_km_from_current: 18.86,
		km_from_home:         13.71,
		tx_count_24h:         3,
		is_online:            false,
		card_present:         true,
		merchant_is_unknown:  false,
		mcc_risk:             0.20,
		merchant_avg_amount:  298.95,
	}

	a := [i8(0), 127, 64, 32, 96, -1, -1, 80, 50, 0, 127, 0, 64, 100]!
	b := [i8(127), 0, 32, 64, 10, -1, -1, 40, 90, 127, 0, 127, 32, 50]!

	// Warmup — evita cold cache no perfil
	for _ in 0 .. 100 {
		internal.manhattan_distance(a, b)
		internal.quantize(0.5)
		internal.normalize(payload, config)
	}

	// Hot path: 10M iterações cada
	mut sum_dist := i32(0)
	for _ in 0 .. 10_000_000 {
		sum_dist += internal.manhattan_distance(a, b)
	}

	mut sum_quant := i8(0)
	for _ in 0 .. 10_000_000 {
		sum_quant += internal.quantize(0.5)
	}

	mut sum_norm := i8(0)
	for _ in 0 .. 5_000_000 {
		v := internal.normalize(payload, config)
		sum_norm += v[0]
	}

	// Evita que o compilador remova os loops
	println('dist=${sum_dist} quant=${sum_quant} norm=${sum_norm}')
}
