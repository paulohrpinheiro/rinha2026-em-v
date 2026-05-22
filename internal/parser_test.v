// parser_test.v — Testes unitários para o parser JSON manual.

module internal

const test_payload_legit = '{"id":"tx-1329056812","transaction":{"amount":41.12,"installments":2,"requested_at":"2026-03-11T18:45:53Z"},"customer":{"avg_amount":82.24,"tx_count_24h":3,"known_merchants":["MERC-003","MERC-016"]},"merchant":{"id":"MERC-016","mcc":"5411","avg_amount":60.25},"terminal":{"is_online":false,"card_present":true,"km_from_home":29.23},"last_transaction":null}'

const test_payload_fraud = '{"id":"tx-3330991687","transaction":{"amount":9505.97,"installments":10,"requested_at":"2026-03-14T05:15:12Z"},"customer":{"avg_amount":81.28,"tx_count_24h":20,"known_merchants":["MERC-008","MERC-007","MERC-005"]},"merchant":{"id":"MERC-068","mcc":"7802","avg_amount":54.86},"terminal":{"is_online":false,"card_present":true,"km_from_home":952.27},"last_transaction":null}'

const test_payload_with_last = '{"id":"tx-3576980410","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.71},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.86}}'

const test_payload_minimal = '{"id":"tx-min","transaction":{"amount":1.0,"installments":1,"requested_at":"2026-03-01T00:00:00Z"},"customer":{"avg_amount":100.0,"tx_count_24h":0,"known_merchants":[]},"merchant":{"id":"MERC-X","mcc":"0000","avg_amount":0.0},"terminal":{"is_online":true,"card_present":false,"km_from_home":0.0},"last_transaction":null}'

fn make_config() &NormalizationConfig {
	mut mcc := map[string]f64{}
	mcc['5411'] = 0.3
	mcc['5912'] = 0.5
	mcc['7802'] = 0.8
	mcc['0000'] = 0.0
	return &NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
		mcc_risk:               mcc,
	}
}

fn test_parse_legitimate() {
	body := test_payload_legit.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg)!
	assert payload.amount == 41.12
	assert payload.installments == 2
	assert payload.avg_amount == 82.24
	assert payload.tx_count_24h == 3
	assert payload.is_online == false
	assert payload.card_present == true
	assert payload.km_from_home == 29.23
	assert payload.has_last_transaction == false
	// merchant MERC-016 NOT in known_merchants [MERC-003, MERC-016] → false
	assert payload.merchant_is_unknown == false
}

fn test_parse_fraudulent() {
	body := test_payload_fraud.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg)!
	assert payload.amount == 9505.97
	assert payload.installments == 10
	assert payload.avg_amount == 81.28
	assert payload.tx_count_24h == 20
	assert payload.is_online == false
	assert payload.card_present == true
	assert payload.km_from_home == 952.27
	assert payload.has_last_transaction == false
	// merchant MERC-068 NOT in known_merchants [MERC-008, MERC-007, MERC-005] → true
	assert payload.merchant_is_unknown == true
}

fn test_parse_with_last_transaction() {
	body := test_payload_with_last.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg)!
	assert payload.amount == 384.88
	assert payload.installments == 3
	assert payload.avg_amount == 769.76
	assert payload.tx_count_24h == 3
	assert payload.has_last_transaction == true
	assert payload.last_timestamp_unix == 1773241115
	assert payload.last_km_from_current > 18.0
	assert payload.last_km_from_current < 19.0
}

fn test_parse_minimal() {
	body := test_payload_minimal.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg)!
	assert payload.amount == 1.0
	assert payload.installments == 1
	assert payload.is_online == true
	assert payload.card_present == false
	// merchant MERC-X NOT in known_merchants [] → true
	assert payload.merchant_is_unknown == true
}

fn test_parse_invalid_json() {
	body := 'not json'.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg) or {
		assert true
		return
	}
	_ = payload
	assert false, 'should have returned error'
}

fn test_parse_empty() {
	body := ''.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg) or {
		assert true
		return
	}
	_ = payload
	assert false, 'should have returned error'
}

fn test_parse_pipeline() {
	body := test_payload_legit.bytes()
	cfg := make_config()
	payload := parse_payload(body, cfg)!

	v := normalize(&payload, cfg)

	assert v[0] > 0
	assert v[5] == -1
	assert v[6] == -1
	// mcc 5411 → risk 0.3
	assert payload.mcc_risk == 0.3
}

// ── Benchmarks ────────────────────────────────────────────────────────────

fn bench_parse_payload() {
	body := test_payload_with_last.bytes()
	cfg := make_config()
	mut total := f64(0)
	for _ in 0 .. 50_000 {
		p := parse_payload(body, cfg) or { panic('unexpected error') }
		total += p.amount
	}
	assert total > 0
}

fn bench_parse_and_normalize() {
	body := test_payload_with_last.bytes()
	cfg := make_config()
	mut total := i8(0)
	for _ in 0 .. 20_000 {
		p := parse_payload(body, cfg) or { panic('unexpected error') }
		v := normalize(&p, cfg)
		total += v[0]
	}
	assert total > 0
}
