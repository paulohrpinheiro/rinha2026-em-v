module internal

import sync

pub struct Semaphore {
pub mut:
	mu    sync.Mutex
	count int
	max   int
}

pub fn new_semaphore(max int) &Semaphore {
	return &Semaphore{max: max}
}

pub fn (mut s Semaphore) try_acquire() bool {
	s.mu.@lock()
	if s.count >= s.max { s.mu.unlock(); return false }
	s.count++
	s.mu.unlock()
	return true
}

pub fn (mut s Semaphore) release() {
	s.mu.@lock()
	s.count--
	s.mu.unlock()
}

pub struct Handler {
pub mut:
	index  &IVFIndex
	config &NormalizationConfig
	debug  &DebugCounters
	sem    &Semaphore
}

pub fn new_handler(idx &IVFIndex, cfg &NormalizationConfig, dc &DebugCounters, sem &Semaphore) &Handler {
	unsafe { return &Handler{index: idx, config: cfg, debug: dc, sem: sem} }
}

pub fn (mut h Handler) handle_fraud_score(body []u8) []u8 {
	if !h.sem.try_acquire() { unsafe { h.debug.semaphore_503s++ }; return []u8{} }
	defer { h.sem.release() }
	unsafe { h.debug.requests_received++ }
	payload := parse_payload(body, h.config) or { unsafe { h.debug.parse_errors++ }; return []u8{} }
	vector := normalize(&payload, h.config)
	fraud_count, _ := h.index.search(&vector)
	unsafe { h.debug.responses_sent++ }
	return fraud_response(fraud_count)
}
