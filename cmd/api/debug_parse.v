module main

import internal

fn main() {
	s := '{"id":"tx-1329056812","transaction":{"amount":41.12,"installments":2}}'
	b := s.bytes()
	println('Input: ${b.len} bytes')
	payload := internal.parse_payload(b) or {
		println('ERROR: ${err}')
		return
	}
	println('OK: amount=${payload.amount} installments=${payload.installments}')
}
