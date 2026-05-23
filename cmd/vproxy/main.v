// vproxy — Proxy TCP em V substituindo nginx.
// Aceita conexões TCP na porta 9999 e encaminha para APIs via Unix sockets.
// Cada conexão de cliente é roteada em round-robin entre api-1 e api-2.
// Zero parsing HTTP — forward bruto de bytes.

module main

import net
import net.unix
import os
import time

const buf_size = 4096

fn main() {
	mut backends := os.getenv('BACKENDS')
	if backends == '' { backends = '/sockets/api-1.sock,/sockets/api-2.sock' }

	mut backend_list := backends.split(',')
	if backend_list.len < 1 {
		eprintln('VProxy: no backends configured')
		return
	}

	mut backend_idx := 0
	mut listener := net.listen_tcp(.ip6, '[::]:9999') or {
		net.listen_tcp(.ip, '0.0.0.0:9999')!
	}
	println('VProxy ready on :9999 -> ${backends}')

	for {
		mut client := listener.accept() or {
			eprintln('VProxy: accept error: ${err}')
			time.sleep(10 * time.millisecond)
			continue
		}
		backend := backend_list[backend_idx % backend_list.len]
		backend_idx++
		spawn handle_client(mut client, backend)
	}
}

fn handle_client(mut client net.TcpConn, backend_path string) {
	defer { client.close() or {} }

	mut backend := unix.connect_stream(backend_path) or {
		client.close() or {}
		return
	}
	defer { backend.close() or {} }

	spawn forward_tcp_to_stream(mut client, mut backend)
	forward_stream_to_tcp(mut backend, mut client)
}

fn forward_tcp_to_stream(mut src net.TcpConn, mut dst unix.StreamConn) {
	mut buf := []u8{len: buf_size}
	for {
		n := src.read(mut buf) or { break }
		if n == 0 { break }
		dst.write(buf[..n]) or { break }
	}
	src.close() or {}
	dst.close() or {}
}

fn forward_stream_to_tcp(mut src unix.StreamConn, mut dst net.TcpConn) {
	mut buf := []u8{len: buf_size}
	for {
		n := src.read(mut buf) or { break }
		if n == 0 { break }
		dst.write(buf[..n]) or { break }
	}
	dst.close() or {}
	src.close() or {}
}