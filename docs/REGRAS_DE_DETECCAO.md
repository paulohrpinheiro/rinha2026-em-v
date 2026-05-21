# Regras de Detecção de Fraude (referência)

> Transcrito de `rinha-de-backend-2026/docs/REGRAS_DE_DETECCAO.md`.
> A versão V implementa estas mesmas regras.

---

## As 14 dimensões do vetor

| índice | dimensão | fórmula |
|--------|----------|---------|
| 0 | `amount` | `clamp(transaction.amount / max_amount)` |
| 1 | `installments` | `clamp(transaction.installments / max_installments)` |
| 2 | `amount_vs_avg` | `clamp((transaction.amount / customer.avg_amount) / amount_vs_avg_ratio)` |
| 3 | `hour_of_day` | `hour(transaction.requested_at) / 23` (0-23, UTC) |
| 4 | `day_of_week` | `weekday(transaction.requested_at) / 6` (seg=0, dom=6) |
| 5 | `minutes_since_last_tx` | `clamp(minutes / max_minutes)` ou `-1` se `last_transaction: null` |
| 6 | `km_from_last_tx` | `clamp(last_transaction.km_from_current / max_km)` ou `-1` se `last_transaction: null` |
| 7 | `km_from_home` | `clamp(terminal.km_from_home / max_km)` |
| 8 | `tx_count_24h` | `clamp(customer.tx_count_24h / max_tx_count_24h)` |
| 9 | `is_online` | `1` se `terminal.is_online`, senão `0` |
| 10 | `card_present` | `1` se `terminal.card_present`, senão `0` |
| 11 | `unknown_merchant` | `1` se `merchant.id` não está em `customer.known_merchants`, senão `0` |
| 12 | `mcc_risk` | `mcc_risk.json[merchant.mcc]` (padrão `0.5`) |
| 13 | `merchant_avg_amount` | `clamp(merchant.avg_amount / max_merchant_avg_amount)` |

`clamp(x)` = min(max(x, 0.0), 1.0)

---

## Constantes de normalização

Do arquivo `normalization.json`:

```json
{
  "max_amount": 10000,
  "max_installments": 12,
  "amount_vs_avg_ratio": 10,
  "max_minutes": 1440,
  "max_km": 1000,
  "max_tx_count_24h": 20,
  "max_merchant_avg_amount": 10000
}
```

---

## Decisão

1. Vetorizar a transação (14 dimensões)
2. Buscar K=5 vizinhos mais próximos no dataset de referência
3. `fraud_score = fraud_count / 5`
4. `approved = fraud_score < 0.6`

---

## Sentinela -1

Índices 5 e 6 usam `-1` quando `last_transaction` é `null`. O dataset de
referência segue a mesma convenção.
