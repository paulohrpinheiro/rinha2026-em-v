module main

import internal
import net.unix
import os
import time
import json

struct PrebuiltResponses {
mut:
	fraud_score [6][]u8
	ready       []u8
	resp_503    []u8
	resp_400    []u8
}

fn build_prebuilt() PrebuiltResponses {
	mut r := PrebuiltResponses{}
	for i in 0 .. 6 {
		body := internal.fraud_response(i)
		header := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: keep-alive\r\n\r\n'
		mut resp := []u8{cap: header.len + body.len}
		resp << header.bytes()
		resp << body
		r.fraud_score[i] = resp
	}
	r.ready = 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: keep-alive\r\n\r\n{"status":"ok"}'.bytes()
	r.resp_503 = 'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n'.bytes()
	r.resp_400 = 'HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'.bytes()
	return r
}

fn main() {
	args := os.args
	if args.len >= 3 && args[1] == '-build-index' {
		build_index(args[2])!
		return
	}

	mut dir := os.getenv('RESOURCES_DIR')
	if dir == '' { dir = './resources' }
	mut config := load_config(dir)!
	idx := load_index(dir)!

	dc := &internal.DebugCounters{}
	sem := internal.new_semaphore(1024)
	mut handler := internal.new_handler(idx, &config, dc, sem)

	for _ in 0 .. 48 {
		handler.handle_fraud_score(warmup_payload.bytes())
	}

	prebuilt := build_prebuilt()

	mut socket_path := os.getenv('SOCKET_PATH')
	if socket_path == '' { socket_path = '/run/sock/api.sock' }
	mut listener := unix.listen_stream(socket_path)!
	println('API ready on ${socket_path}')

	for {
		mut conn := listener.accept()!
		spawn handle_conn(mut conn, mut handler, dc, prebuilt)
	}
}

fn handle_conn(mut conn unix.StreamConn, mut handler internal.Handler, dc &internal.DebugCounters, prebuilt PrebuiltResponses) {
	defer { conn.close() or {} }
	mut buf := []u8{len: 4096}
	mut req_count := 0
	for req_count < 256 {
		conn.set_read_timeout(50 * time.millisecond)
		n := conn.read(mut buf) or { break }
		if n == 0 { break }
		body := unsafe { buf[..n] }
		req_count++
		body_str := body.bytestr()

		if body_str.starts_with('GET /ready') {
			conn.write(prebuilt.ready) or { break }
		} else if body_str.starts_with('GET /debug/vars') {
			snap_str := dc.snapshot()
			snap := snap_str.bytes()
			header := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${snap.len}\r\nConnection: keep-alive\r\n\r\n'
			mut resp := []u8{cap: header.len + snap.len}
			resp << header.bytes()
			resp << snap
			conn.write(resp) or { break }
		} else if body_str.starts_with('POST /fraud-score') {
			header_end := body_str.index('\r\n\r\n') or { body.len - 1 }
			json_body := body[header_end + 4..]
			fraud_count, ok := handler.handle_fraud_score(json_body)
			if !ok {
				conn.write(prebuilt.resp_503) or { break }
			} else {
				conn.write(prebuilt.fraud_score[fraud_count]) or { break }
			}
		} else {
			conn.write(prebuilt.resp_400) or { break }
			break
		}
	}
}

fn build_index(output_path string) ! {
	mut refs_path := os.getenv('REFERENCES_PATH')
	if refs_path == '' { refs_path = './resources/references.json.gz' }
	println('Loading references from ${refs_path}...')
	vectors, labels := internal.load_references(refs_path)!
	println('Loaded ${vectors.len} vectors. Building IVF index (1000 clusters, 20 iters)...')
	idx := internal.build_ivf(vectors, labels, 1000, 20)!
	println('Saving index to ${output_path}...')
	idx.save(output_path)!
	println('Done.')
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
	return error('index.bin not found at ${path}')
}

const warmup_payload = '{"id":"warmup","transaction":{"amount":384.88,"installments":3,"requested_at":"2026-03-11T20:23:35Z"},"customer":{"avg_amount":769.76,"tx_count_24h":3,"known_merchants":["MERC-009","MERC-001"]},"merchant":{"id":"MERC-001","mcc":"5912","avg_amount":298.95},"terminal":{"is_online":false,"card_present":true,"km_from_home":13.71},"last_transaction":{"timestamp":"2026-03-11T14:58:35Z","km_from_current":18.86}}'