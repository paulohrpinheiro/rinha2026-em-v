// normalize_test.v — Testes unitários e benchmarks para quantize, Manhattan e normalize.
// Cobre valores de borda, sentinel, vetores idênticos, e cenários reais.

module internal

// ── quantize ──────────────────────────────────────────────────────────────

fn test_quantize_zero() {
	assert quantize(0.0) == 0
}

fn test_quantize_one() {
	assert quantize(1.0) == 127
}

fn test_quantize_half() {
	// 0.5 * 127 = 63.5 → round = 64
	assert quantize(0.5) == 64
}

fn test_quantize_sentinel() {
	assert quantize(-1.0) == -1
}

fn test_quantize_overflow() {
	assert quantize(2.0) == 127
	assert quantize(100.0) == 127
}

fn test_quantize_underflow() {
	assert quantize(-0.5) == 0
	assert quantize(-100.0) == 0
}

fn test_quantize_small_positive() {
	assert quantize(0.001) == 0
	assert quantize(0.004) == 1
}

fn test_quantize_near_one() {
	assert quantize(0.996) == 126
	assert quantize(0.999) == 127
}

// ── manhattan_distance ────────────────────────────────────────────────────

fn test_manhattan_identical() {
	a := [i8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	assert manhattan_distance(a, a) == 0
}

fn test_manhattan_opposite() {
	a := [i8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	b := [i8(127), 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127]!
	assert manhattan_distance(a, b) == 1778
}

fn test_manhattan_sentinel() {
	a := [i8(0), 0, 0, 0, 0, -1, -1, 0, 0, 0, 0, 0, 0, 0]!
	b := [i8(0), 0, 0, 0, 0, -1, -1, 0, 0, 0, 0, 0, 0, 0]!
	assert manhattan_distance(a, b) == 0

	c := [i8(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
	assert manhattan_distance(a, c) == 2
}

fn test_manhattan_symmetry() {
	a := [i8(10), 50, 0, 127, 64, -1, 100, 30, 80, 0, 127, 0, 50, 90]!
	b := [i8(90), 30, 127, 0, 10, 100, -1, 80, 20, 127, 0, 127, 90, 40]!
	dist_ab := manhattan_distance(a, b)
	dist_ba := manhattan_distance(b, a)
	assert dist_ab == dist_ba
}

// ── normalize ─────────────────────────────────────────────────────────────

fn test_normalize_legitimate_transaction() {
	payload := &PayloadData{
		amount:               41.12,
		installments:         2,
		avg_amount:           82.24,
		requested_at:         1773254753,
		has_last_transaction: false,
		km_from_home:         29.23,
		tx_count_24h:         3,
		is_online:            false,
		card_present:         true,
		merchant_is_unknown:  false,
		mcc_risk:             0.15,
		merchant_avg_amount:  60.25,
	}

	config := &NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
	}

	v := normalize(payload, config)

	assert v[0] == 1
	assert v[1] == 21
	assert v[2] == 6
	assert v[3] == 99
	assert v[4] == 42
	assert v[5] == -1
	assert v[6] == -1
	assert v[7] == 4
	assert v[8] == 19
	assert v[9] == 0
	assert v[10] == 127
	assert v[11] == 0
	assert v[12] == 19
	assert v[13] == 1
}

fn test_normalize_fraudulent_transaction() {
	payload := &PayloadData{
		amount:               9505.97,
		installments:         10,
		avg_amount:           81.28,
		requested_at:         1773465312,
		has_last_transaction: false,
		km_from_home:         952.27,
		tx_count_24h:         20,
		is_online:            false,
		card_present:         true,
		merchant_is_unknown:  true,
		mcc_risk:             0.75,
		merchant_avg_amount:  54.86,
	}

	config := &NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
	}

	v := normalize(payload, config)

	assert v[0] == 121
	assert v[1] == 106
	assert v[2] == 127
	assert v[3] == 28
	assert v[4] == 106
	assert v[5] == -1
	assert v[6] == -1
	assert v[7] == 121
	assert v[8] == 127
	assert v[9] == 0
	assert v[10] == 127
	assert v[11] == 127
	assert v[12] == 95
	assert v[13] == 1
}

fn test_normalize_with_last_transaction() {
	payload := &PayloadData{
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

	config := &NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
	}

	v := normalize(payload, config)

	assert v[5] == 29
	assert v[6] == 2
	assert v[5] != -1
	assert v[6] != -1
}

// ── Benchmarks ────────────────────────────────────────────────────────────

fn bench_manhattan_distance() {
	a := [i8(0), 127, 64, 32, 96, -1, -1, 80, 50, 0, 127, 0, 64, 100]!
	b := [i8(127), 0, 32, 64, 10, -1, -1, 40, 90, 127, 0, 127, 32, 50]!
	mut total := i32(0)
	for _ in 0 .. 1_000_000 {
		total += manhattan_distance(a, b)
	}
	assert total > 0
}

fn bench_quantize() {
	mut total := i8(0)
	for _ in 0 .. 1_000_000 {
		total += quantize(0.5)
	}
	assert total > 0
}

fn bench_normalize() {
	payload := &PayloadData{
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
	config := &NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
	}
	mut total := i8(0)
	for _ in 0 .. 100_000 {
		v := normalize(payload, config)
		total += v[0]
	}
	assert total > 0
}
