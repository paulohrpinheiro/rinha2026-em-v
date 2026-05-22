module main

import internal
import time

fn main() {
	config := &internal.NormalizationConfig{
		max_amount: 10000.0
		max_installments: 12.0
		amount_vs_avg_ratio: 10.0
		max_minutes: 1440.0
		max_km: 1000.0
		max_tx_count_24h: 20.0
		max_merchant_avg_amount: 10000.0
	}
	payload := &internal.PayloadData{
		amount: 384.88
		installments: 3
		avg_amount: 769.76
		requested_at: 1773260615
		has_last_transaction: true
		last_timestamp_unix: 1773241115
		last_km_from_current: 18.86
		km_from_home: 13.71
		tx_count_24h: 3
		is_online: false
		card_present: true
		merchant_is_unknown: false
		mcc_risk: 0.20
		merchant_avg_amount: 298.95
	}
	a := [i8(0), 127, 64, 32, 96, -1, -1, 80, 50, 0, 127, 0, 64, 100]!
	b := [i8(127), 0, 32, 64, 10, -1, -1, 40, 90, 127, 0, 127, 32, 50]!

	// Manhattan: 50M iterações
	n := i64(50_000_000)
	start := time.now()
	mut sum := i64(0)
	for _ in 0 .. n {
		sum += internal.manhattan_distance(a, b)
	}
	elapsed := time.now() - start
	ns_per_op := elapsed.nanoseconds() / n
	println('manhattan_distance: ${ns_per_op} ns/op  (total: ${elapsed})')

	// Quantize: 50M
	mut sq := i64(0)
	start2 := time.now()
	for _ in 0 .. n {
		sq += internal.quantize(0.5)
	}
	elapsed2 := time.now() - start2
	println('quantize:          ${elapsed2.nanoseconds() / n} ns/op  (total: ${elapsed2})')

	// Normalize: 20M
	n3 := i64(20_000_000)
	mut sn := i64(0)
	start3 := time.now()
	for _ in 0 .. n3 {
		sn += internal.normalize(payload, config)[0]
	}
	elapsed3 := time.now() - start3
	println('normalize:         ${elapsed3.nanoseconds() / n3} ns/op  (total: ${elapsed3})')

	println('(checksum: ${sum} ${sq} ${sn})')
}
