// ivf.v — IVF Index para busca vetorial.
// V 0.5.1

module internal

import rand
import os
import encoding.binary

// IVFIndex é um Inverted File Index.
pub struct IVFIndex {
pub:
	vectors   []Vector14
	labels    []u8
	centroids []Vector14
	offsets   []int
pub mut:
	n_clusters int
}

pub fn new_ivf(vv []Vector14, ll []u8, cc []Vector14, oo []int) &IVFIndex {
	return &IVFIndex{
		vectors: vv, labels: ll, centroids: cc, offsets: oo, n_clusters: cc.len
	}
}

pub fn (idx &IVFIndex) search(query &Vector14) (int, int) {
	if idx.n_clusters == 0 { return 0, 0 }
	mut nearest := [2]CentroidDist{}
	nearest[0] = CentroidDist{dist: i32(2147483647)}
	nearest[1] = CentroidDist{dist: i32(2147483647)}
	for c in 0 .. idx.n_clusters {
		d := manhattan_distance(query, idx.centroids[c])
		if d < nearest[1].dist {
			mut pos := 1
			for pos > 0 && d < nearest[pos - 1].dist {
				nearest[pos] = nearest[pos - 1]
				pos--
			}
			nearest[pos] = CentroidDist{id: c, dist: d}
		}
	}
	mut top_k := [5]Neighbor{}
	for i in 0 .. 5 { top_k[i] = Neighbor{dist: i32(2147483647)} }
	for nc in nearest {
		if nc.id < 0 || nc.dist == i32(2147483647) { continue }
		start := idx.offsets[nc.id]
		end := idx.offsets[nc.id + 1]
		if start >= end { continue }
		mut stop := start + 5000
		if stop > end { stop = end }
		for i in start .. stop {
			dist := manhattan_distance(query, idx.vectors[i])
			if dist < top_k[4].dist {
				mut pos := 4
				for pos > 0 && dist < top_k[pos - 1].dist {
					top_k[pos] = top_k[pos - 1]
					pos--
				}
				top_k[pos] = Neighbor{dist: dist, label: idx.labels[i]}
			}
		}
	}
	mut fraud_count := 0
	for n in top_k { if n.label == 1 { fraud_count++ } }
	return fraud_count, idx.vectors.len
}

struct CentroidDist { id int
dist i32 }
struct Neighbor { dist i32
label u8 }

pub fn build_ivf(vectors []Vector14, labels []u8, nc int, ni int) !&IVFIndex {
	if vectors.len == 0 { return error('no vectors') }
	if nc < 1 { return error('need at least 1 cluster') }
	n := vectors.len
	mut centroids := kmeans_pp(vectors, nc)!
	for _ in 0 .. ni {
		mut assigns := []int{len: n, init: 0}
		for i in 0 .. n {
			mut bd := i32(i32(2147483647))
			mut bc := 0
			for c in 0 .. nc {
				d := manhattan_distance(vectors[i], centroids[c])
				if d < bd { bd = d
				bc = c }
			}
			assigns[i] = bc
		}
		mut sums := [][]i32{len: nc, init: []i32{len: 14, init: 0}}
		mut cnts := []int{len: nc, init: 0}
		for i in 0 .. n {
			c := assigns[i]
			cnts[c]++
			for d in 0 .. 14 { sums[c][d] += i32(vectors[i][d]) }
		}
		mut newc := []Vector14{len: nc}
		for c in 0 .. nc {
			if cnts[c] > 0 {
				mut v := Vector14{}
				for d in 0 .. 14 { v[d] = i8(sums[c][d] / cnts[c]) }
				newc[c] = v
			} else { newc[c] = centroids[c] }
		}
		centroids = newc.clone()
	}
	mut cv := [][]Vector14{len: nc}
	mut cl := [][]u8{len: nc}
	for i in 0 .. n {
		mut bd := i32(i32(2147483647))
		mut bc := 0
		for c in 0 .. nc {
			d := manhattan_distance(vectors[i], centroids[c])
			if d < bd { bd = d
			bc = c }
		}
		cv[bc] << vectors[i]
		cl[bc] << labels[i]
	}
	mut fv := []Vector14{cap: n}
	mut fl := []u8{cap: n}
	mut off := []int{len: nc + 1}
	for c in 0 .. nc {
		off[c] = fv.len
		fv << cv[c]
		fl << cl[c]
	}
	off[nc] = fv.len
	return &IVFIndex{vectors: fv, labels: fl, centroids: centroids, offsets: off, n_clusters: nc}
}

fn kmeans_pp(vectors []Vector14, k int) ![]Vector14 {
	mut rng := rand.new_default()
	n := vectors.len
	mut centroids := []Vector14{cap: k}
	centroids << vectors[rng.int_in_range(0, n)!]
	for _ in 1 .. k {
		mut dists := []f64{len: n}
		mut td := f64(0)
		for i in 0 .. n {
			mut md := i32(i32(2147483647))
			for c in centroids { d := manhattan_distance(vectors[i], c)
			if d < md { md = d } }
			dd := f64(md) + 1.0
			dists[i] = dd
			td += dd
		}
		t := rng.f64_in_range(0.0, td)!
		mut cum := f64(0)
		mut ch := 0
		for i in 0 .. n { cum += dists[i]
		if cum >= t { ch = i
		break } }
		centroids << vectors[ch]
	}
	return centroids
}

pub fn (idx &IVFIndex) save(path string) ! {
	mut buf := []u8{cap: 8 + idx.vectors.len * 15 + idx.centroids.len * 14 + (idx.n_clusters + 1) * 4}
	mut h := [8]u8{}
	binary.little_endian_put_u32(mut h[0..4], u32(idx.vectors.len))
	binary.little_endian_put_u32(mut h[4..8], u32(idx.n_clusters))
	for x in h { buf << x }
	for v in idx.vectors { for d in 0 .. 14 { buf << u8(v[d]) } }
	for l in idx.labels { buf << l }
	for c in idx.centroids { for d in 0 .. 14 { buf << u8(c[d]) } }
	for o in idx.offsets { mut ob := [4]u8{}
	binary.little_endian_put_u32(mut ob[..], u32(o))
	for x in ob { buf << x } }
	os.write_bytes(path, buf)!
}

pub fn load_ivf(path string) !&IVFIndex {
	data := os.read_bytes(path)!
	mut pos := 0
	nv := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	nc := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	mut vectors := []Vector14{cap: nv}
	for _ in 0 .. nv { mut v := Vector14{}
	for d in 0 .. 14 { v[d] = i8(data[pos])
	pos++ }
	vectors << v }
	mut labels := []u8{cap: nv}
	for _ in 0 .. nv { labels << data[pos]
	pos++ }
	mut centroids := []Vector14{cap: nc}
	for _ in 0 .. nc { mut c := Vector14{}
	for d in 0 .. 14 { c[d] = i8(data[pos])
	pos++ }
	centroids << c }
	mut offsets := []int{len: nc + 1}
	for i in 0 .. nc + 1 { offsets[i] = int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4 }
	return new_ivf(vectors, labels, centroids, offsets)
}


pub fn generate_test_data(n int) ([]Vector14, []u8) {
	mut rng := rand.new_default()
	mut vectors := []Vector14{cap: n}
	mut labels := []u8{cap: n}
	for _ in 0 .. n {
		mut v := Vector14{}
		for d in 0 .. 14 {
			v[d] = i8(rng.int_in_range(0, 128) or { 0 })
		}
		vectors << v
		labels << u8(rng.int_in_range(0, 2) or { 0 })
	}
	return vectors, labels
}
