module main

import internal
import os
import json

fn main() {
	payload := '{"id":"test","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.71},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.86}}'

	mut dir := os.getenv('RESOURCES_DIR')
	if dir == '' { dir = './resources' }

	// Load config
	config := load_config(dir)!
	println('Config:')
	println('  max_amount: ${config.max_amount}')
	println('  max_installments: ${config.max_installments}')
	println('  amount_vs_avg_ratio: ${config.amount_vs_avg_ratio}')
	println('  max_minutes: ${config.max_minutes}')
	println('  max_km: ${config.max_km}')
	println('  max_tx_count_24h: ${config.max_tx_count_24h}')
	println('  max_merchant_avg_amount: ${config.max_merchant_avg_amount}')
	println('  mcc_risk keys: ${config.mcc_risk.keys()}')

	pl := internal.parse_payload(payload.bytes(), &config)!
	println('Payload:')
	println('  amount: ${pl.amount}')
	println('  installments: ${pl.installments}')
	println('  avg_amount: ${pl.avg_amount}')
	println('  requested_at: ${pl.requested_at}')
	println('  has_last: ${pl.has_last_transaction}')
	println('  last_timestamp: ${pl.last_timestamp_unix}')
	println('  last_km: ${pl.last_km_from_current}')
	println('  km_from_home: ${pl.km_from_home}')
	println('  tx_count_24h: ${pl.tx_count_24h}')
	println('  is_online: ${pl.is_online}')
	println('  card_present: ${pl.card_present}')
	println('  merchant_is_unknown: ${pl.merchant_is_unknown}')
	println('  mcc_risk: ${pl.mcc_risk}')
	println('  merchant_avg_amount: ${pl.merchant_avg_amount}')

	vector := internal.normalize(&pl, &config)
	println('Vector (14 dims):')
	for d in 0 .. 14 {
		print('  [${d}]=${vector[d]}')
	}
	println('')

	// Search
	idx := load_index(dir)!
	fraud_count, total := idx.search(&vector)
	println('Search: fraud_count=${fraud_count} total=${total}')
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
