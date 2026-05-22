// debug.v — Contadores para /debug/vars (acesso single-thread via handler).

module internal

pub struct DebugCounters {
pub mut:
	requests_received i64
	responses_sent    i64
	parse_errors      i64
	search_errors     i64
	semaphore_503s    i64
	search_total_ns   i64
}

pub fn (dc &DebugCounters) snapshot() string {
	mut buf := []u8{}
	buf << '{"requests_received":'.bytes()
	buf << dc.requests_received.str().bytes()
	buf << ',"responses_sent":'.bytes()
	buf << dc.responses_sent.str().bytes()
	buf << ',"parse_errors":'.bytes()
	buf << dc.parse_errors.str().bytes()
	buf << ',"search_errors":'.bytes()
	buf << dc.search_errors.str().bytes()
	buf << ',"semaphore_503s":'.bytes()
	buf << dc.semaphore_503s.str().bytes()
	buf << ',"search_total_ns":'.bytes()
	buf << dc.search_total_ns.str().bytes()
	buf << '}'.bytes()
	return buf.bytestr()
}
