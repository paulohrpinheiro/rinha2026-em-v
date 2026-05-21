# API — Contrato (referência)

> Transcrito de `rinha-de-backend-2026/docs/API.md`.
> A versão V implementa este mesmo contrato.

---

## `GET /ready`

Verificação de prontidão. Deve responder com `HTTP 2xx` quando estiver pronta
para receber requisições.

---

## `POST /fraud-score`

Endpoint de detecção de fraudes.

### Requisição

```json
{
  "id": "tx-3576980410",
  "transaction": {
    "amount": 384.88,
    "installments": 3,
    "requested_at": "2026-03-11T20:23:35Z"
  },
  "customer": {
    "avg_amount": 769.76,
    "tx_count_24h": 3,
    "known_merchants": ["MERC-009", "MERC-001", "MERC-001"]
  },
  "merchant": {
    "id": "MERC-001",
    "mcc": "5912",
    "avg_amount": 298.95
  },
  "terminal": {
    "is_online": false,
    "card_present": true,
    "km_from_home": 13.7090520965
  },
  "last_transaction": {
    "timestamp": "2026-03-11T14:58:35Z",
    "km_from_current": 18.8626479774
  }
}
```

### Campos

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | string | Identificador da transação |
| `transaction.amount` | number | Valor da transação |
| `transaction.installments` | integer | Número de parcelas |
| `transaction.requested_at` | string ISO | Timestamp UTC |
| `customer.avg_amount` | number | Média histórica de gasto |
| `customer.tx_count_24h` | integer | Transações nas últimas 24h |
| `customer.known_merchants` | string[] | Comerciantes já utilizados |
| `merchant.id` | string | Identificador do comerciante |
| `merchant.mcc` | string | Código MCC da categoria |
| `merchant.avg_amount` | number | Ticket médio do comerciante |
| `terminal.is_online` | boolean | Transação online? |
| `terminal.card_present` | boolean | Cartão presente? |
| `terminal.km_from_home` | number | Distância do endereço (km) |
| `last_transaction` | object ou `null` | Dados da transação anterior |
| `last_transaction.timestamp` | string ISO | Timestamp UTC anterior |
| `last_transaction.km_from_current` | number | Distância entre transações (km) |

### Resposta

```json
{
  "approved": false,
  "fraud_score": 1.0
}
```

### Decisão

- `fraud_score`: fração de fraudes entre os K=5 vizinhos mais próximos
- `approved`: `fraud_score < 0.6` (threshold fixo)
