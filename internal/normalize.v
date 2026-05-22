// normalize.v — Vetor 14 dimensões, quantização int8, distância Manhattan, normalização.

module internal

import math

pub type Vector14 = [14]i8

const sentinel = i8(-1)

pub fn quantize(v f64) i8 {
	if v == -1.0 { return sentinel }
	if v <= 0.0 { return 0 }
	if v >= 1.0 { return 127 }
	return i8(math.round(v * 127.0))
}

fn clamp(v f64) f64 {
	if v < 0.0 { return 0.0 }
	if v > 1.0 { return 1.0 }
	return v
}

pub fn manhattan_distance(a Vector14, b Vector14) i32 {
	mut sum := i32(0)
	d0 := i32(a[0]) - i32(b[0])
	if d0 >= 0 { sum += d0 } else { sum -= d0 }
	d1 := i32(a[1]) - i32(b[1])
	if d1 >= 0 { sum += d1 } else { sum -= d1 }
	d2 := i32(a[2]) - i32(b[2])
	if d2 >= 0 { sum += d2 } else { sum -= d2 }
	d3 := i32(a[3]) - i32(b[3])
	if d3 >= 0 { sum += d3 } else { sum -= d3 }
	d4 := i32(a[4]) - i32(b[4])
	if d4 >= 0 { sum += d4 } else { sum -= d4 }
	d5 := i32(a[5]) - i32(b[5])
	if d5 >= 0 { sum += d5 } else { sum -= d5 }
	d6 := i32(a[6]) - i32(b[6])
	if d6 >= 0 { sum += d6 } else { sum -= d6 }
	d7 := i32(a[7]) - i32(b[7])
	if d7 >= 0 { sum += d7 } else { sum -= d7 }
	d8 := i32(a[8]) - i32(b[8])
	if d8 >= 0 { sum += d8 } else { sum -= d8 }
	d9 := i32(a[9]) - i32(b[9])
	if d9 >= 0 { sum += d9 } else { sum -= d9 }
	d10 := i32(a[10]) - i32(b[10])
	if d10 >= 0 { sum += d10 } else { sum -= d10 }
	d11 := i32(a[11]) - i32(b[11])
	if d11 >= 0 { sum += d11 } else { sum -= d11 }
	d12 := i32(a[12]) - i32(b[12])
	if d12 >= 0 { sum += d12 } else { sum -= d12 }
	d13 := i32(a[13]) - i32(b[13])
	if d13 >= 0 { sum += d13 } else { sum -= d13 }
	return sum
}

pub struct PayloadData {
pub mut:
	amount               f64
	installments         int
	avg_amount           f64
	requested_at         int
	has_last_transaction bool
	last_timestamp_unix  i64
	last_km_from_current f64
	km_from_home         f64
	tx_count_24h         int
	is_online            bool
	card_present         bool
	merchant_is_unknown  bool
	mcc_code             [4]u8
	mcc_risk             f64
	merchant_avg_amount  f64
}

pub fn normalize(payload &PayloadData, config &NormalizationConfig) Vector14 {
	mut v := Vector14{}
	v[0] = quantize(clamp(payload.amount / config.max_amount))
	v[1] = quantize(clamp(f64(payload.installments) / config.max_installments))
	ratio := payload.amount / payload.avg_amount
	v[2] = quantize(clamp(ratio / config.amount_vs_avg_ratio))
	hour := (payload.requested_at % 86400) / 3600
	v[3] = quantize(f64(hour) / 23.0)
	days := payload.requested_at / 86400
	wd := (days + 4) % 7
	wm := (wd + 6) % 7
	v[4] = quantize(f64(wm) / 6.0)
	if !payload.has_last_transaction {
		v[5] = sentinel
	} else {
		m := f64(payload.requested_at - int(payload.last_timestamp_unix)) / 60.0
		v[5] = quantize(clamp(m / config.max_minutes))
	}
	if !payload.has_last_transaction {
		v[6] = sentinel
	} else {
		v[6] = quantize(clamp(payload.last_km_from_current / config.max_km))
	}
	v[7] = quantize(clamp(payload.km_from_home / config.max_km))
	v[8] = quantize(clamp(f64(payload.tx_count_24h) / config.max_tx_count_24h))
	if payload.is_online { v[9] = 127 } else { v[9] = 0 }
	if payload.card_present { v[10] = 127 } else { v[10] = 0 }
	if payload.merchant_is_unknown { v[11] = 127 } else { v[11] = 0 }
	v[12] = quantize(clamp(payload.mcc_risk))
	v[13] = quantize(clamp(payload.merchant_avg_amount / config.max_merchant_avg_amount))
	return v
}
