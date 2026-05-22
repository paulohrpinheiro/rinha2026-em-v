// responses.v — Respostas pré-alocadas para o endpoint /fraud-score.
// 6 respostas possíveis (fraud_count 0..5), zero alocações de serialização.

module internal

// fraud_response retorna o []u8 com JSON pré-computado para cada fraud_count.
pub fn fraud_response(fraud_count int) []u8 {
	return match fraud_count {
		0 { fraud_0 }
		1 { fraud_1 }
		2 { fraud_2 }
		3 { fraud_3 }
		4 { fraud_4 }
		5 { fraud_5 }
		else { fraud_5 }
	}
}

const fraud_0 = '{"approved":true,"fraud_score":0.0}'.bytes()
const fraud_1 = '{"approved":true,"fraud_score":0.2}'.bytes()
const fraud_2 = '{"approved":true,"fraud_score":0.4}'.bytes()
const fraud_3 = '{"approved":false,"fraud_score":0.6}'.bytes()
const fraud_4 = '{"approved":false,"fraud_score":0.8}'.bytes()
const fraud_5 = '{"approved":false,"fraud_score":1.0}'.bytes()
