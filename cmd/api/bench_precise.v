module main

import internal
import json
import os
import time

fn main() {
	payload := '{"id":"tx-3576980410","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.7090520965},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.8626479774}}'

	mut dir := os.getenv('RESOURCES_DIR')
	if dir == '' { dir = './resources' }

	config := load_config(dir)!

	body := payload.bytes()

	// Warmup
	for _ in 0 .. 100 {
		_ = internal.parse_payload(body, &config) or { continue }
	}

	// Benchmark parse
	mut times := []f64{cap: 10000}
	for _ in 0 .. 10000 {
		sw := time.new_stopwatch()
		_ = internal.parse_payload(body, &config) or { continue }
		us := f64(sw.elapsed().microseconds())
		times << us
	}

	mut total := f64(0)
	mut max := f64(0)
	mut min := f64(999999)
	for t in times {
		total += t
		if t > max { max = t }
		if t < min { min = t }
	}
	avg := total / times.len
	println('Parse benchmark (${times.len} iterations):')
	println('  min: ${min:.1} us')
	println('  avg: ${avg:.1} us')
	println('  max: ${max:.1} us')
	println('  p50: ${percentile(times, 50):.1} us')
	println('  p95: ${percentile(times, 95):.1} us')
	println('  p99: ${percentile(times, 99):.1} us')
}

fn percentile(data []f64, p int) f64 {
	mut sorted := data.clone()
	sorted.sort()
	mut pidx := (sorted.len * p) / 100
	if pidx >= sorted.len { pidx = sorted.len - 1 }
	return sorted[pidx]
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