// parser.v — Parsing JSON manual byte-a-byte, zero alocações.
// V 0.5.1: struct Parser com pos mutável, []u8
// Key lengths verified: amount=6 installments=12 requested_at=12
// is_online=9 card_present=12 km_from_home=12 km_from_current=15
// known_merchants=15 timestamp=9 tx_count_24h=12

module internal

import time

struct Parser {
	body []u8
mut:
	pos                int
	merchant_id_start  int
	merchant_id_len    int
}

fn new_parser(body []u8) Parser { return Parser{body: body, pos: 0} }
fn (mut p Parser) skip_ws() { for p.pos < p.body.len && (p.body[p.pos] == ` ` || p.body[p.pos] == `\t` || p.body[p.pos] == `\n` || p.body[p.pos] == `\r`) { p.pos++ } }
fn (mut p Parser) skip_comma() { p.skip_ws(); if p.pos < p.body.len && p.body[p.pos] == `,` { p.pos++ } }
fn (mut p Parser) expect(ch u8) ! { p.skip_ws(); if p.pos >= p.body.len || p.body[p.pos] != ch { return error('expected ${ch:c}') } p.pos++ }
fn (mut p Parser) key() !int {
	p.skip_ws()
	if p.pos >= p.body.len || p.body[p.pos] != `"` { return error('expected string key') }
	p.pos++; start := p.pos
	for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ }
	end := p.pos
	if p.pos >= p.body.len { return error('unterminated key') }
	p.pos++; p.expect(`:`)!; return end - start
}
fn (p &Parser) is_key(start int, s string) bool {
	if start + s.len > p.body.len { return false }
	for i in 0 .. s.len { if p.body[start + i] != s[i] { return false } }
	return true
}
fn (mut p Parser) skip_str() { if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }; for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ }; if p.pos < p.body.len { p.pos++ } }
fn (mut p Parser) skip_any() {
	p.skip_ws(); if p.pos >= p.body.len { return }
	match p.body[p.pos] {
		`"` { p.skip_str() }
		`{` { p.skip_obj() }
		`[` { p.skip_arr() }
		`t`, `f` { p.pos += if p.body[p.pos] == `t` { 4 } else { 5 } }
		`n` { p.pos += 4 }
		else { for p.pos < p.body.len && (p.body[p.pos].is_digit() || p.body[p.pos] == `.` || p.body[p.pos] == `-` || p.body[p.pos] == `e` || p.body[p.pos] == `E` || p.body[p.pos] == `+`) { p.pos++ } }
	}
}
fn (mut p Parser) skip_obj() {
	p.pos++
	mut d := 1
	for p.pos < p.body.len && d > 0 {
		match p.body[p.pos] {
			`{` { d++ }
			`}` { d-- }
			`"` { p.pos++; for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ } }
			else {}
		}
		p.pos++
	}
}
fn (mut p Parser) skip_arr() {
	p.pos++
	mut d := 1
	for p.pos < p.body.len && d > 0 {
		match p.body[p.pos] {
			`[` { d++ }
			`]` { d-- }
			`"` { p.pos++; for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ } }
			else {}
		}
		p.pos++
	}
}
fn (mut p Parser) num_f64() f64 {
	p.skip_ws(); mut ip := u64(0); mut fp := u64(0); mut fd := 0; mut neg := false
	if p.pos < p.body.len && p.body[p.pos] == `-` { neg = true; p.pos++ }
	for p.pos < p.body.len && p.body[p.pos].is_digit() { ip = ip * 10 + u64(p.body[p.pos] - `0`); p.pos++ }
	if p.pos < p.body.len && p.body[p.pos] == `.` { p.pos++; for p.pos < p.body.len && p.body[p.pos].is_digit() { fp = fp * 10 + u64(p.body[p.pos] - `0`); fd++; p.pos++ } }
	mut r := f64(ip); if fd > 0 { mut div := 1.0; for _ in 0 .. fd { div *= 10.0 }; r += f64(fp) / div }
	if neg { r = -r }; return r
}
fn (mut p Parser) num_int() int { p.skip_ws(); mut r := 0; mut neg := false; if p.pos < p.body.len && p.body[p.pos] == `-` { neg = true; p.pos++ }; for p.pos < p.body.len && p.body[p.pos].is_digit() { r = r * 10 + int(p.body[p.pos] - `0`); p.pos++ }; return if neg { -r } else { r } }
fn (mut p Parser) bool_val() bool { p.skip_ws(); if p.pos + 4 <= p.body.len && p.body[p.pos] == `t` { p.pos += 4; return true }; p.pos += 5; return false }
fn (mut p Parser) ts_iso() !time.Time { p.skip_ws(); if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }; start := p.pos; for p.pos < p.body.len && p.body[p.pos] != `"` && p.body[p.pos] != ` ` && p.body[p.pos] != `}` { p.pos++ }; end := p.pos; if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }; return time.parse_rfc3339(p.body[start..end].bytestr())! }

// ── Helpers para capturar strings ────────────────────────────────────────

fn (mut p Parser) parse_mcc(mut pl PayloadData) {
	p.skip_ws()
	if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }
	for i in 0 .. 4 {
		if p.pos < p.body.len && p.body[p.pos] != `"` {
			pl.mcc_code[i] = p.body[p.pos]
			p.pos++
		}
	}
	// skip restante da string (caso MCC tenha mais de 4 chars)
	for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ }
	if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }
}

fn (mut p Parser) parse_string_to() (int, int) {
	p.skip_ws()
	if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }
	start := p.pos
	for p.pos < p.body.len && p.body[p.pos] != `"` { p.pos++ }
	length := p.pos - start
	if p.pos < p.body.len && p.body[p.pos] == `"` { p.pos++ }
	return start, length
}

fn (mut p Parser) parse_string_array(mut arr []string) {
	p.skip_ws()
	if p.pos >= p.body.len || p.body[p.pos] != `[` { return }
	p.pos++ // skip '['
	for p.pos < p.body.len {
		p.skip_ws()
		if p.pos >= p.body.len { break }
		if p.body[p.pos] == `]` { p.pos++; break }
		if p.body[p.pos] == `,` { p.pos++; continue }
		sstart, slen := p.parse_string_to()
		if slen > 0 {
			arr << p.body[sstart..sstart + slen].bytestr()
		}
	}
}

// ── Main ─────────────────────────────────────────────────────────────────

pub fn parse_payload(body []u8, config &NormalizationConfig) !PayloadData {
	mut p := new_parser(body)
	mut pl := PayloadData{}
	// known_merchants será preenchido se existir no JSON
	mut known_merchants := []string{}

	p.expect(`{`)!
	mut ft := false; mut fc := false; mut fm := false; mut ft2 := false
	for p.pos < p.body.len {
		p.skip_ws()
		if p.pos >= p.body.len { break }
		if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			11 { if p.is_key(ks, 'transaction') { p.tx(mut pl)!; ft = true } else { p.skip_any() } }
			16 { if p.is_key(ks, 'last_transaction') { p.last_tx(mut pl)! } else { p.skip_any() } }
			8 {
				if p.is_key(ks, 'customer') { p.cust(mut pl, mut known_merchants)!; fc = true }
				else if p.is_key(ks, 'merchant') { p.merc(mut pl)!; fm = true }
				else if p.is_key(ks, 'terminal') { p.term(mut pl)!; ft2 = true }
				else { p.skip_any() }
			}
			else { p.skip_any() }
		}
		p.skip_comma()
	}
	if !ft || !fc || !fm || !ft2 { return error('missing required fields') }

	// Resolve mcc_risk
	pl.mcc_risk = config.mcc_risk[pl.mcc_code[..].bytestr()] or { 0.0 }

	// Resolve merchant_is_unknown: true se merchant.id NÃO está em known_merchants
	if p.merchant_id_len > 0 {
		merchant_id := p.body[p.merchant_id_start..p.merchant_id_start + p.merchant_id_len].bytestr()
		mut found := false
		for km in known_merchants {
			if km == merchant_id { found = true; break }
		}
		pl.merchant_is_unknown = !found
	}

	return pl
}

fn (mut p Parser) tx(mut pl PayloadData) ! {
	p.expect(`{`)!
	for p.pos < p.body.len { p.skip_ws(); if p.pos >= p.body.len { break }; if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			6 { if p.is_key(ks, 'amount') { pl.amount = p.num_f64() } else { p.skip_any() } }
			12 {
				if p.is_key(ks, 'installments') { pl.installments = p.num_int() }
				else if p.is_key(ks, 'requested_at') { pl.requested_at = int(p.ts_iso()!.unix()) }
				else { p.skip_any() }
			}
			else { p.skip_any() }
		}
		p.skip_comma()
	}
}

fn (mut p Parser) cust(mut pl PayloadData, mut known_merchants []string) ! {
	p.expect(`{`)!
	for p.pos < p.body.len { p.skip_ws(); if p.pos >= p.body.len { break }; if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			10 { if p.is_key(ks, 'avg_amount') { pl.avg_amount = p.num_f64() } else { p.skip_any() } }
			12 { if p.is_key(ks, 'tx_count_24h') { pl.tx_count_24h = p.num_int() } else { p.skip_any() } }
			15 { if p.is_key(ks, 'known_merchants') { p.parse_string_array(mut known_merchants) } else { p.skip_any() } }
			else { p.skip_any() }
		}
		p.skip_comma()
	}
}

fn (mut p Parser) merc(mut pl PayloadData) ! {
	p.expect(`{`)!
	for p.pos < p.body.len { p.skip_ws(); if p.pos >= p.body.len { break }; if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			2 { if p.is_key(ks, 'id') { p.merchant_id_start, p.merchant_id_len = p.parse_string_to() } else { p.skip_any() } }
			3 { if p.is_key(ks, 'mcc') { p.parse_mcc(mut pl) } else { p.skip_any() } }
			10 { if p.is_key(ks, 'avg_amount') { pl.merchant_avg_amount = p.num_f64() } else { p.skip_any() } }
			else { p.skip_any() }
		}
		p.skip_comma()
	}
}

fn (mut p Parser) term(mut pl PayloadData) ! {
	p.expect(`{`)!
	for p.pos < p.body.len { p.skip_ws(); if p.pos >= p.body.len { break }; if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			9 { if p.is_key(ks, 'is_online') { pl.is_online = p.bool_val() } else { p.skip_any() } }
			12 {
				if p.is_key(ks, 'card_present') { pl.card_present = p.bool_val() }
				else if p.is_key(ks, 'km_from_home') { pl.km_from_home = p.num_f64() }
				else { p.skip_any() }
			}
			else { p.skip_any() }
		}
		p.skip_comma()
	}
}

fn (mut p Parser) last_tx(mut pl PayloadData) ! {
	p.skip_ws()
	if p.pos >= p.body.len { return }
	if p.body[p.pos] == `n` { p.pos += 4; pl.has_last_transaction = false; return }
	p.expect(`{`)!; pl.has_last_transaction = true
	for p.pos < p.body.len { p.skip_ws(); if p.pos >= p.body.len { break }; if p.body[p.pos] == `}` { p.pos++; break }
		ks := p.pos + 1; kl := p.key()!; p.skip_ws()
		match kl {
			9 { if p.is_key(ks, 'timestamp') { pl.last_timestamp_unix = p.ts_iso()!.unix() } else { p.skip_any() } }
			15 { if p.is_key(ks, 'km_from_current') { pl.last_km_from_current = p.num_f64() } else { p.skip_any() } }
			else { p.skip_any() }
		}
		p.skip_comma()
	}
}
