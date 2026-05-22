// model.v — Tipos de dados para o sistema de detecção de fraude.
// Mapeamento direto do contrato API.md e das regras REGRAS_DE_DETECCAO.md.

module internal

import time

// TransactionPayload representa o JSON de entrada do POST /fraud-score.
pub struct TransactionPayload {
pub mut:
	id               string
	transaction      TransactionData
	customer         CustomerData
	merchant         MerchantData
	terminal         TerminalData
	last_transaction ?LastTransactionData // Option type para nullable
}

pub struct TransactionData {
pub mut:
	amount        f64
	installments  int
	requested_at  time.Time
}

pub struct CustomerData {
pub mut:
	avg_amount       f64
	tx_count_24h     int
	known_merchants  []string
}

pub struct MerchantData {
pub mut:
	id         string
	mcc        string
	avg_amount f64
}

pub struct TerminalData {
pub mut:
	is_online     bool
	card_present  bool
	km_from_home  f64
}

pub struct LastTransactionData {
pub mut:
	timestamp        time.Time
	km_from_current  f64
}

// FraudResponse representa a resposta JSON do POST /fraud-score.
pub struct FraudResponse {
pub mut:
	approved    bool
	fraud_score f64
}

// NormalizationConfig armazena as constantes de normalização e o mapa de risco MCC.
pub struct NormalizationConfig {
pub mut:
	max_amount             f64
	max_installments       f64
	amount_vs_avg_ratio    f64
	max_minutes            f64
	max_km                 f64
	max_tx_count_24h       f64
	max_merchant_avg_amount f64
	mcc_risk               map[string]f64
}
