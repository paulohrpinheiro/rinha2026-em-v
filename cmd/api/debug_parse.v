module main

import internal

fn main() {
	s := '{"id":"tx-1329056812","transaction":{"amount":41.12,"installments":2},"customer":{"avg_amount":100.0,"tx_count_24h":1,"known_merchants":[]},"merchant":{"id":"MERC-X","mcc":"5411","avg_amount":50.0},"terminal":{"is_online":false,"card_present":true,"km_from_home":1.0},"last_transaction":null}'
	b := s.bytes()
	println('Input: ${b.len} bytes')

	cfg := &internal.NormalizationConfig{
		max_amount:             10000,
		max_installments:       12,
		amount_vs_avg_ratio:    10,
		max_minutes:            1440,
		max_km:                 1000,
		max_tx_count_24h:       20,
		max_merchant_avg_amount: 10000,
		mcc_risk:               {'5411': 0.3},
	}

	payload := internal.parse_payload(b, cfg) or {
		println('ERROR: ${err}')
		return
	}
	println('OK: amount=${payload.amount} installments=${payload.installments} mcc_risk=${payload.mcc_risk} unknown=${payload.merchant_is_unknown}')
}
