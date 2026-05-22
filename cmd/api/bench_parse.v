module main

import internal
import time

fn main() {
	sw := time.new_stopwatch()
	println('Loading + parsing references.json.gz...')
	vectors, labels := internal.load_references('./resources/references.json.gz')!
	elapsed := sw.elapsed().milliseconds()
	println('Parsed ${vectors.len} vectors in ${elapsed}ms (${elapsed / 1000}s)')
	println('Labels: ${labels.len}')
}
