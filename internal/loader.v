// loader.v — Carregamento streaming do references.json.gz + build do índice IVF.

module internal

import compress.gzip
import os

pub fn load_references(path string) !([]Vector14, []u8) {
	data := os.read_bytes(path)!
	raw := gzip.decompress(data)!
	return parse_references(raw)
}

fn parse_references(body []u8) !([]Vector14, []u8) {
	mut pos := 0
	pos = skip_ws(body, pos)
	if pos >= body.len || body[pos] != `[` { return error('expected array opening') }
	pos++

	mut vectors := []Vector14{cap: 3_000_000}
	mut labels := []u8{cap: 3_000_000}

	for pos < body.len {
		pos = skip_ws(body, pos)
		if pos >= body.len { break }
		if body[pos] == `]` { pos++; break }
		if body[pos] != `{` {
			pos = skip_value(body, pos)
			pos = skip_ws(body, pos)
			if pos < body.len && body[pos] == `,` { pos++ }
			continue
		}
		pos++

		mut v := Vector14{}
		mut label := u8(0)
		mut found_vector := false
		mut found_label := false

		for pos < body.len {
			pos = skip_ws(body, pos)
			if pos >= body.len { break }
			if body[pos] == `}` { pos++; break }
			if body[pos] != `"` {
				pos = skip_value(body, pos)
				pos = skip_ws(body, pos)
				if pos < body.len && body[pos] == `,` { pos++ }
				continue
			}
			pos++
			ks := pos
			for pos < body.len && body[pos] != `"` { pos++ }
			kl := pos - ks
			pos++
			pos = skip_ws(body, pos)
			if pos < body.len && body[pos] == `:` { pos++ }
			pos = skip_ws(body, pos)

			match kl {
				6 {
					if is_key_slice(body, ks, 'vector') {
						pos = parse_vector_array(body, pos, mut v)!
						found_vector = true
						continue
					}
				}
				5 {
					if is_key_slice(body, ks, 'label') {
						new_pos, lbl := parse_label(body, pos)!
						pos = new_pos
						label = lbl
						found_label = true
						continue
					}
				}
				else { pos = skip_value(body, pos) }
			}
			pos = skip_ws(body, pos)
			if pos < body.len && body[pos] == `,` { pos++ }
		}

		if found_vector && found_label {
			vectors << v
			labels << label
		}

		pos = skip_ws(body, pos)
		if pos < body.len && body[pos] == `,` { pos++ }
	}

	return vectors, labels
}

fn parse_vector_array(body []u8, pos int, mut v Vector14) !int {
	mut p := pos
	p = skip_ws(body, p)
	if p >= body.len || body[p] != `[` { return error('expected array') }
	p++
	for d in 0 .. 14 {
		p = skip_ws(body, p)
		if p >= body.len { break }
		if body[p] == `]` { p++; break }
		new_p, val := parse_float(body, p)
		p = new_p
		v[d] = quantize(val)
		p = skip_ws(body, p)
		if p < body.len && body[p] == `,` { p++ }
	}
	return p
}

fn parse_label(body []u8, pos int) !(int, u8) {
	mut p := pos
	p = skip_ws(body, p)
	if p < body.len && body[p] == `"` { p++ }
	ls := p
	for p < body.len && body[p] != `"` { p++ }
	le := p
	if p < body.len && body[p] == `"` { p++ }
	mut lbl := u8(1)
	if le - ls == 5 && is_key_slice(body, ls, 'legit') { lbl = 0 }
	return p, lbl
}

fn skip_ws(body []u8, pos int) int {
	mut p := pos
	for p < body.len && (body[p] == ` ` || body[p] == `\t` || body[p] == `\n` || body[p] == `\r`) { p++ }
	return p
}

fn is_key_slice(body []u8, start int, s string) bool {
	if start + s.len > body.len { return false }
	for i in 0 .. s.len { if body[start + i] != s[i] { return false } }
	return true
}

fn parse_float(body []u8, start int) (int, f64) {
	mut p := start
	mut ip := u64(0)
	mut fp := u64(0)
	mut fd := 0
	mut neg := false
	if p < body.len && body[p] == `-` { neg = true; p++ }
	for p < body.len && body[p].is_digit() { ip = ip * 10 + u64(body[p] - `0`); p++ }
	if p < body.len && body[p] == `.` { p++; for p < body.len && body[p].is_digit() { fp = fp * 10 + u64(body[p] - `0`); fd++; p++ } }
	mut r := f64(ip)
	if fd > 0 { mut div := 1.0; for _ in 0 .. fd { div *= 10.0 }; r += f64(fp) / div }
	if neg { r = -r }
	return p, r
}

fn skip_value(body []u8, pos int) int {
	mut p := skip_ws(body, pos)
	if p >= body.len { return p }
	match body[p] {
		`"` {
			p++
			for p < body.len && body[p] != `"` { p++ }
			if p < body.len { p++ }
		}
		`[` {
			p++
			mut d := 1
			for p < body.len && d > 0 {
				match body[p] {
					`[` { d++ }
					`]` { d-- }
					`"` { p++; for p < body.len && body[p] != `"` { p++ } }
					else {}
				}
				p++
			}
		}
		`{` {
			p++
			mut d := 1
			for p < body.len && d > 0 {
				match body[p] {
					`{` { d++ }
					`}` { d-- }
					`"` { p++; for p < body.len && body[p] != `"` { p++ } }
					else {}
				}
				p++
			}
		}
		`t`, `f` { p += if body[p] == `t` { 4 } else { 5 } }
		`n` { p += 4 }
		else {
			for p < body.len && (body[p].is_digit() || body[p] == `.` || body[p] == `-` || body[p] == `e` || body[p] == `E` || body[p] == `+`) { p++ }
		}
	}
	return p
}
