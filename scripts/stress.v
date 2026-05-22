// stress.v — Teste de stress via TCP raw.
// Uso: v run scripts/stress.v

module main

import net
import time
import os
import sort
import sync

const payloads = [
	'{"id":"a","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.71},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.86}}',
	'{"id":"b","transaction":{"amount":2911.41,"installments":12,"requested_at":"2026-03-19T02:17:11Z"},"customer":{"avg_amount":411.03,"tx_count_24h":8,"known_merchants":["MERC-221","MERC-010"]},"merchant":{"id":"MERC-551","mcc":"6011","avg_amount":712.22},"terminal":{"is_online":true,"card_present":false,"km_from_home":2.18},"last_transaction":{"timestamp":"2026-03-18T23:51:05Z","km_from_current":1.34}}',
	'{"id":"c","transaction":{"amount":41.12,"installments":2,"requested_at":"2026-03-11T18:45:53Z"},"customer":{"avg_amount":82.24,"tx_count_24h":3,"known_merchants":["MERC-003","MERC-016"]},"merchant":{"id":"MERC-016","mcc":"5411","avg_amount":60.25},"terminal":{"is_online":false,"card_present":true,"km_from_home":29.23},"last_transaction":null}',
	'{"id":"d","transaction":{"amount":87.91,"installments":1,"requested_at":"2026-03-13T14:31:30Z"},"customer":{"avg_amount":703.28,"tx_count_24h":5,"known_merchants":["MERC-003"]},"merchant":{"id":"MERC-512","mcc":"5814","avg_amount":480.5},"terminal":{"is_online":true,"card_present":false,"km_from_home":799.5},"last_transaction":{"timestamp":"2026-03-13T05:37:37Z","km_from_current":793.78}}',
]

fn build_request(payload string) []u8 {
	mut req := []u8{}
	req << 'POST /fraud-score HTTP/1.0\r\n'.bytes()
	req << 'Host: localhost\r\n'.bytes()
	req << 'Content-Type: application/json\r\n'.bytes()
	req << 'Content-Length: ${payload.len}\r\n'.bytes()
	req << '\r\n'.bytes()
	req << payload.bytes()
	return req
}

fn main() {
	mut target := os.getenv('STRESS_TARGET')
	if target == '' { target = 'localhost:9999' }

	mut duration_secs := 10
	mut rate := 180
	mut ramp_up := 2
	mut workers := 20

	println('============================================')
	println('  Rinha 2026 — Stress Test (raw TCP)')
	println('============================================')
	println('  Target:   ${target}')
	println('  Rate:     ${rate} req/s')
	println('  Duration: ${duration_secs}s (ramp-up ${ramp_up}s)')
	println('  Workers:  ${workers}')
	println('')

	// Wait for /ready
	print('  Waiting for /ready... ')
	for i in 0 .. 30 {
		mut conn := net.dial_tcp(target) or {
			time.sleep(1 * time.second)
			continue
		}
		conn.write('GET /ready HTTP/1.0\r\n\r\n'.bytes()) or { continue }
		mut buf := []u8{len: 1024}
		_ := conn.read(mut buf) or { continue }
		if buf.bytestr().contains('200') { conn.close() or {}; break }
		conn.close() or {}
		if i == 29 { println('FAIL'); return }
		time.sleep(1 * time.second)
	}
	println('OK')

	mut samples := []i64{cap: rate * duration_secs}
	mut total_reqs := i64(0)
	mut http_errs := i64(0)
	mut conn_errs := i64(0)
	mu := &sync.Mutex{}

	start_time := time.now()
	deadline := start_time + time.Duration(i64(duration_secs) * time.second)
	ramp_end := start_time + time.Duration(i64(ramp_up) * time.second)

	// Workers
	mut job_ch := make_chan(int, workers * 4)
	for w in 0 .. workers {
		spawn worker(target, job_ch, mu, mut samples, mut total_reqs, mut http_errs, mut conn_errs)
	}

	// Rate generator
	mut seq := i64(0)
	mut last_report := time.now()

	for time.now() < deadline {
		now := time.now()
		elapsed := now - start_time
		mut current_rate := f64(rate)
		if now < ramp_end {
			progress := f64(elapsed) / f64(i64(ramp_up) * time.second)
			if progress > 1.0 { progress = 1.0 }
			current_rate = f64(rate) * progress
		}
		n := int(current_rate * 0.1)
		for _ in 0 .. n {
			job_ch <- int(seq % 4)
			seq++
		}

		if time.now() - last_report > 2 * time.second {
			remaining := deadline - time.now()
			println('  [${(time.now() - start_time).seconds():.0f}s] sent=${seq} processed=${total_reqs} remaining=${remaining.seconds():.0f}s')
			last_report = time.now()
		}

		time.sleep(100 * time.millisecond)
	}
	close(job_ch)
	time.sleep(2 * time.second)

	elapsed := time.now() - start_time
	total := total_reqs
	errs := http_errs + conn_errs
	ok := total - errs
	success_rate := f64(ok) / f64(total) * 100.0

	// Sort for percentiles
	samples.sort()
	n := samples.len
	if n == 0 { println('Zero samples'); return }

	p50 := samples[n * 50 / 100]
	p95 := samples[n * 95 / 100]
	p99 := samples[n * 99 / 100]
	mut sum := i64(0)
	for l in samples { sum += l }
	avg := sum / n

	println('')
	println('============================================')
	println('  Resultados')
	println('============================================')
	println('  Duracao:       ${elapsed}')
	println('  Requisicoes:   ${total}')
	println('  OK (200):      ${ok} (${success_rate:.1f}%)')
	println('  Erros HTTP:    ${http_errs}')
	println('  Erros conexao: ${conn_errs}')
	println('  Latencia avg:  ${avg} us')
	println('  Latencia p50:  ${p50} us')
	println('  Latencia p95:  ${p95} us')
	println('  Latencia p99:  ${p99} us')
	println('============================================')

	if p99 < 2_000_000 && success_rate >= 85.0 {
		println('  🟢 BENCHMARK PASSOU')
	} else {
		println('  🔴 BENCHMARK FALHOU')
	}
}

fn worker(target string, ch chan int, mu &sync.Mutex, mut samples []i64, mut total &i64, mut http_errs &i64, mut conn_errs &i64) {
	for pi in ch {
		start := time.now()
		mut conn := net.dial_tcp(target) or {
			lock(mu) { unsafe { *conn_errs++; *total++ } }
			continue
		}
		req := build_request(payloads[pi])
		conn.write(req) or {
			conn.close() or {}
			lock(mu) { unsafe { *conn_errs++; *total++ } }
			continue
		}
		mut buf := []u8{len: 4096}
		_ := conn.read(mut buf) or {
			conn.close() or {}
			lock(mu) { unsafe { *conn_errs++; *total++ } }
			continue
		}
		conn.close() or {}
		elapsed := time.now() - start
		status_ok := buf.bytestr().contains('200 OK')
		lock(mu) {
			unsafe { *total++ }
			if !status_ok { unsafe { *http_errs++ } }
		}
		samples << elapsed.microseconds()
	}
}

fn lock(mu &sync.Mutex) { mu.@lock() }
fn unlock(mu &sync.Mutex) { mu.unlock() }
fn make_chan(t int, cap int) chan int { return chan int{cap: cap} }