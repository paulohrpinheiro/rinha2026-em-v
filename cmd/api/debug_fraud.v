module main

import internal
import os
import json

fn main() {
	// Payload fraudulento
	payload := '{"id":"fraud-test","transaction":{"amount":9505.97,"installments":10,"requested_at":"2026-03-14T05:15:12Z"},"customer":{"avg_amount":81.28,"tx_count_24h":20,"known_merchants":["MERC-008","MERC-007","MERC-005"]},"merchant":{"id":"MERC-068","mcc":"7802","avg_amount":54.86},"terminal":{"is_online":false,"card_present":true,"km_from_home":952.27},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.86}}'

	mut dir := os.getenv('RESOURCES_DIR')
	if dir == '' { dir = './resources' }

	config := load_config(dir)!
	pl := internal.parse_payload(payload.bytes(), &config)!
	println('=== Payload fraudulento ===')
	println('  amount: ${pl.amount}')
	println('  installments: ${pl.installments}')
	println('  km_from_home: ${pl.km_from_home}')
	println('  tx_count_24h: ${pl.tx_count_24h}')
	println('  mcc_risk: ${pl.mcc_risk}')
	println('  merchant_is_unknown: ${pl.merchant_is_unknown}')

	vector := internal.normalize(&pl, &config)
	print('Vector:')
	for d in 0 .. 14 { print(' ${vector[d]}') }
	println('')

	idx := load_index(dir)!
	fraud_count, total := idx.search(&vector)
	println('Search: fraud_count=${fraud_count}/5 total=${total}')
	println('  approved: ${fraud_count < 3}') // threshold 0.6
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