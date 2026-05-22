module main

import internal
import rand

fn main() {
	config := &internal.NormalizationConfig{
		max_amount: 10000.0, max_installments: 12.0, amount_vs_avg_ratio: 10.0,
		max_minutes: 1440.0, max_km: 1000.0, max_tx_count_24h: 20.0,
		max_merchant_avg_amount: 10000.0,
	}

	// Manhattan: 100M com vetores variados (evita constant folding)
	mut rng := rand.new_default()
	n := i64(100_000_000)
	mut sum := i64(0)
	for _ in 0 .. n {
		x0 := i8(rng.int_in_range(0, 128)!)
		x5 := i8(rng.int_in_range(-1, 128)!)
		a := [x0, i8(0), 64, 32, 96, x5, x5, 80, 50, i8(0), 127, i8(0), 64, 100]!
		b := [i8(127), i8(0), 32, 64, 10, x5, x5, 40, 90, 127, i8(0), 127, 32, 50]!
		sum += internal.manhattan_distance(a, b)
	}
	println('manhattan_100M_checksum: ${sum}')

	// Quantize: 100M com valores variados
	mut sq := i64(0)
	for _ in 0 .. n {
		v := rng.f64_in_range(0.0, 1.0)!
		sq += internal.quantize(v)
	}
	println('quantize_100M_checksum: ${sq}')

	// Normalize: 50M com valores variados
	mut sn := i64(0)
	for _ in 0 .. n / 2 {
		payload := &internal.PayloadData{
			amount: rng.f64_in_range(1.0, 5000.0)!,
			installments: rng.int_in_range(1, 13)!,
			avg_amount: rng.f64_in_range(1.0, 5000.0)!,
			requested_at: 1773260615,
			has_last_transaction: rng.int_in_range(0, 2)! == 1,
			last_timestamp_unix: 1773241115,
			last_km_from_current: rng.f64_in_range(0.0, 500.0)!,
			km_from_home: rng.f64_in_range(0.0, 500.0)!,
			tx_count_24h: rng.int_in_range(0, 21)!,
			is_online: rng.int_in_range(0, 2)! == 1,
			card_present: rng.int_in_range(0, 2)! == 1,
			merchant_is_unknown: rng.int_in_range(0, 2)! == 1,
			mcc_risk: rng.f64_in_range(0.0, 1.0)!,
			merchant_avg_amount: rng.f64_in_range(1.0, 5000.0)!,
		}
		sn += internal.normalize(payload, config)[0]
	}
	println('normalize_50M_checksum: ${sn}')
}
