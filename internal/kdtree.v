// kdtree.v — KD-tree para busca exata dos K=5 vizinhos mais próximos.
// Estrutura array-based (serializável), split por mediana, poda por eixo.
module internal

import encoding.binary
import os

// KDNode representa um nó da KD-tree (interno ou folha).
struct KDNode {
pub:
	dim       u8   // eixo de divisão (0-13) para nós internos
	val       i8   // valor de divisão para nós internos
	left      u32  // índice do filho esquerdo no array nodes
	right     u32  // índice do filho direito
	vec_start u32  // intervalo em indices[] (folhas)
	vec_end   u32  // exclusive
}

// KDTree é a estrutura completa da KD-tree.
pub struct KDTree {
pub:
	nodes     []KDNode // todos os nós (raiz = nodes[0])
	indices   []int    // índices dos vetores reordenados (folhas contíguas)
	vectors   []Vector14
	labels    []u8
}

// build_kdtree constrói uma KD-tree sobre todos os vetores.
pub fn build_kdtree(vv []Vector14, ll []u8, leaf_size int) !&KDTree {
	n := vv.len
	if n == 0 { return error('no vectors') }
	ls := if leaf_size < 1 { 100 } else { leaf_size }

	// Índices dos vetores (0..n-1)
	mut indices := []int{len: n, init: 0}
	for i in 0 .. n { indices[i] = i }

	mut nodes := []KDNode{cap: n * 2 / ls}
	build_rec(vv, mut indices, 0, n, 0, ls, mut nodes)!

	return &KDTree{nodes: nodes, indices: indices, vectors: vv, labels: ll}
}

fn build_rec(vv []Vector14, mut indices []int, start int, end int, depth int, leaf_size int, mut nodes []KDNode) !u32 {
	n := end - start
	if n <= leaf_size {
		// Nó folha: guarda intervalo em indices[]
		node := KDNode{
			dim: u8(depth % 14)
			vec_start: u32(start)
			vec_end: u32(end)
		}
		idx := u32(nodes.len)
		nodes << node
		return idx
	}

	dim := depth % 14
	mid := start + n / 2
	// nth_element: coloca a mediana na posição "mid" (in-place)
	nth_element_by_dim(vv, mut indices, start, end, mid, dim)

	// Valor da mediana
	median := vv[indices[mid]]

	left_idx := build_rec(vv, mut indices, start, mid, depth + 1, leaf_size, mut nodes)!
	right_idx := build_rec(vv, mut indices, mid + 1, end, depth + 1, leaf_size, mut nodes)!

	node := KDNode{
		dim:   u8(dim)
		val:   median[dim]
		left:  left_idx
		right: right_idx
	}
	idx := u32(nodes.len)
	nodes << node
	return idx
}

// nth_element_by_dim rearranja indices[start..end] tal que o elemento na
// posição "mid" é o que estaria lá se o array estivesse ordenado por dim.
// Implementa quickselect com partição Hoare.
fn nth_element_by_dim(vv []Vector14, mut indices []int, start int, end int, mid int, dim int) {
	mut lo := start
	mut hi := end - 1
	for lo < hi {
		pivot := vv[indices[lo + (hi - lo) / 2]][dim]
		mut i := lo - 1
		mut j := hi + 1
		for i < j {
			i++
			for vv[indices[i]][dim] < pivot { i++ }
			j--
			for vv[indices[j]][dim] > pivot { j-- }
			if i < j {
				indices[i], indices[j] = indices[j], indices[i]
			}
		}
		if j < mid { lo = j + 1 }
		else if j > mid { hi = j - 1 }
		else { break }
	}
}

// KDSearchResult armazena o resultado da busca.
pub struct KDSearchResult {
pub:
	fraud_count int
}

// search_linear busca os K=5 vizinhos em idxs[start..end] e mescla em best.
fn search_linear(query &Vector14, vv []Vector14, ll []u8, idxs []int, start int, end int, mut best [5]Neighbor) {
	for pos in start .. end {
		i := idxs[pos]
		dist := manhattan_distance(query, vv[i])
		if dist < best[4].dist {
			mut p := 4
			for p > 0 && dist < best[p - 1].dist {
				best[p] = best[p - 1]
				p--
			}
			best[p] = Neighbor{dist: dist, label: ll[i]}
		}
	}
}

// search_brute busca exaustiva em todos os vetores (força bruta).
fn search_brute(query &Vector14, vv []Vector14, ll []u8) [5]Neighbor {
	mut top_k := [5]Neighbor{}
	for i in 0 .. 5 { top_k[i] = Neighbor{dist: i32(2147483647)} }
	for i in 0 .. vv.len {
		dist := manhattan_distance(query, vv[i])
		if dist < top_k[4].dist {
			mut p := 4
			for p > 0 && dist < top_k[p - 1].dist {
				top_k[p] = top_k[p - 1]
				p--
			}
			top_k[p] = Neighbor{dist: dist, label: ll[i]}
		}
	}
	return top_k
}

// search_kdtree busca os K=5 vizinhos na KD-tree com poda por eixo.
pub fn (kt &KDTree) search(query &Vector14) KDSearchResult {
	mut best := [5]Neighbor{}
	for i in 0 .. 5 { best[i] = Neighbor{dist: i32(2147483647)} }
	search_rec(kt, query, 0, mut best)
	mut fraud := 0
	for n in best { if n.label == 1 { fraud++ } }
	return KDSearchResult{fraud_count: fraud}
}

fn search_rec(kt &KDTree, query &Vector14, node_idx u32, mut best [5]Neighbor) {
	node := kt.nodes[node_idx]

	// Nó folha: varredura linear do intervalo
	if node.left == 0 && node.right == 0 {
		search_linear(query, kt.vectors, kt.labels, kt.indices,
			int(node.vec_start), int(node.vec_end), mut best)
		return
	}

	// Decide qual lado visitar primeiro
	qval := unsafe { query[node.dim] }
	mut diff := f64(qval) - f64(node.val)
	// lado "near" primeiro (mesmo lado do split)
	mut near := node.left
	mut far := node.right
	if qval > node.val {
		near = node.right
		far = node.left
	}

	// Visita o lado near
	search_rec(kt, query, near, mut best)

	// Poda: se a distância até o split >= best[4], não visita o far side
	if diff < 0 { diff = -diff }
	if diff < f64(best[4].dist) {
		search_rec(kt, query, far, mut best)
	}
}

// ── Serialização ──────────────────────────────────────────────────────────

pub fn (kt &KDTree) save(path string) ! {
	mut buf := []u8{}
	// Magic: "KDTR"
	buf << u8(`K`); buf << u8(`D`); buf << u8(`T`); buf << u8(`R`)
	// Número de nós
	mut nb := [4]u8{}
	binary.little_endian_put_u32(mut nb[..], u32(kt.nodes.len))
	for b in nb { buf << b }
	// Nós
	for node in kt.nodes {
		buf << u8(node.dim)
		buf << u8(node.val)
		binary.little_endian_put_u32(mut nb[..], node.left)
		for b in nb { buf << b }
		binary.little_endian_put_u32(mut nb[..], node.right)
		for b in nb { buf << b }
		binary.little_endian_put_u32(mut nb[..], node.vec_start)
		for b in nb { buf << b }
		binary.little_endian_put_u32(mut nb[..], node.vec_end)
		for b in nb { buf << b }
	}
	// Número de índices
	binary.little_endian_put_u32(mut nb[..], u32(kt.indices.len))
	for b in nb { buf << b }
	// Índices
	for idx in kt.indices {
		binary.little_endian_put_u32(mut nb[..], u32(idx))
		for b in nb { buf << b }
	}
	// Vetores no formato IVF (reutiliza código existente)
	mut h := [8]u8{}
	binary.little_endian_put_u32(mut h[0..4], u32(kt.vectors.len))
	binary.little_endian_put_u32(mut h[4..8], u32(0)) // n_clusters=0 para KD-tree
	for x in h { buf << x }
	for v in kt.vectors {
		for d in 0 .. 14 { buf << u8(v[d]) }
	}
	for l in kt.labels { buf << l }
	os.write_bytes(path, buf)!
}

pub fn load_kdtree(path string, vectors []Vector14, labels []u8) !&KDTree {
	data := os.read_bytes(path)!
	if data.len < 4 || data[0] != `K` || data[1] != `D` || data[2] != `T` || data[3] != `R` {
		return error('invalid KD-tree file')
	}
	mut pos := 4
	n_nodes := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	mut nodes := []KDNode{cap: n_nodes}
	for _ in 0 .. n_nodes {
		dim := data[pos]; pos++
		val := i8(data[pos]); pos++
		left := binary.little_endian_u32(data[pos..pos + 4]); pos += 4
		right := binary.little_endian_u32(data[pos..pos + 4]); pos += 4
		vs := binary.little_endian_u32(data[pos..pos + 4]); pos += 4
		ve := binary.little_endian_u32(data[pos..pos + 4]); pos += 4
		nodes << KDNode{dim: dim, val: val, left: left, right: right, vec_start: vs, vec_end: ve}
	}
	n_indices := int(binary.little_endian_u32(data[pos..pos + 4]))
	pos += 4
	mut indices := []int{len: n_indices}
	for i in 0 .. n_indices {
		indices[i] = int(binary.little_endian_u32(data[pos..pos + 4]))
		pos += 4
	}
	return &KDTree{nodes: nodes, indices: indices, vectors: vectors, labels: labels}
}