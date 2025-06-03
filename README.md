# BitVault

## Decentralized Bitcoin Options Trading Protocol on Stacks

---

## Overview

**BitVault** is a decentralized finance (DeFi) protocol enabling secure, trustless, and collateralized options trading on Bitcoin-backed assets. Built on **Stacks Layer 2**, it brings sophisticated financial instruments to the Bitcoin ecosystem, including:

* **European-style call and put options**
* **Collateral locking mechanisms**
* **Premium-based option purchasing**
* **Real-time BTC price feed via on-chain oracle**
* **Full protocol governance and permissioned access controls**

---

## Features

* ✅ **Trustless Options Contracts**: Write and purchase Bitcoin options without intermediaries.
* 🔐 **Collateral Enforcement**: Smart contract enforces collateral rules and payouts.
* 📈 **Price Oracle Integration**: Real-time BTC/USD prices from whitelisted sources.
* 🧠 **Governance Controls**: Adjust protocol fee, manage token and symbol whitelists.
* 📊 **User Position Tracking**: Maintain real-time portfolios of written and held options.
* 💸 **Protocol Fee Mechanism**: Adjustable fee system collected on exercise.

---

## Core Architecture

```text
+-----------------------+       +---------------------+       +---------------------+
|   Option Writer       |<----->|     BitVault SC     |<----->|   Option Holder     |
|  (Collateral Locked)  |       |   (Smart Contract)  |       |   (Buys & Exercises)|
+-----------------------+       +---------------------+       +---------------------+
                                      |
                                      |
                         +------------v-----------+
                         |   SIP-010 Token SC     |
                         | (Transfer, Balances)   |
                         +------------+-----------+
                                      |
                         +------------v-----------+
                         |     Price Oracle       |
                         |   (BTC/USD Feed)       |
                         +------------------------+
```

---

## Smart Contract Components

### 1. **Traits & Standards**

Implements the [SIP-010 fungible token trait](https://github.com/stacksgov/sips/blob/main/sips/sip-010/sip-010-ft-standard.md) for token compatibility.

### 2. **Core Maps & Variables**

* `options`: Tracks all option contracts.
* `user-positions`: Maps user addresses to written and held options.
* `approved-tokens`: Whitelisted SIP-010 tokens.
* `price-feeds`: Stores oracle-fed BTC/USD price and metadata.

### 3. **Key Public Functions**

* `write-option`: Write a new option and lock collateral.
* `buy-option`: Purchase an existing option.
* `exercise-option`: Exercise an in-the-money option.
* `set-protocol-fee-rate`: Admin function to update protocol fee.
* `update-price-feed`: Admin oracle update function.
* `set-approved-token`: Add/remove tokens from whitelist.
* `set-allowed-symbol`: Whitelist oracle price symbols.

---

## Error Handling

BitVault defines a wide set of semantic error codes:

* `ERR-NOT-AUTHORIZED`: u1000 – Unauthorized access
* `ERR-INSUFFICIENT-COLLATERAL`: u1006 – Not enough funds locked
* `ERR-OPTION-EXPIRED`: u1005 – Attempted action after expiry
* `ERR-INVALID-TOKEN`, `ERR-INVALID-SYMBOL`: Whitelist-related issues

---

## Collateral Logic

Collateral is enforced based on option type:

* **CALL**: Collateral ≥ strike price
* **PUT**: Collateral ≥ value relative to BTC/USD price

Each option is identified by a unique `option-id` and has full lifecycle tracking from creation to exercise.

---

## Oracle Integration

The contract uses a modular on-chain price oracle model:

* Only admin-approved symbols are accepted (`BTC-USD`, `STX-USD`).
* Price updates are only valid if submitted by the owner and timestamped with the current block height.

---

## Governance

The contract owner (initially `tx-sender`) can:

* Adjust protocol fee (capped at 10% or `u1000` basis points)
* Whitelist or blacklist tokens/symbols
* Submit BTC/USD price feed updates

**Security Measures:**

* Prevents removal of critical tokens or symbols.
* Validates all principal addresses and symbol formats.

---

## Deployment Considerations

* Requires deployment of SIP-010 compliant tokens (e.g., xBTC).
* Price oracle updates must be integrated via off-chain trusted relayer or decentralized oracle network.
* Governance control should eventually be transitioned to a DAO for full decentralization.

---

## Example Workflow

1. **Writer** calls `write-option` with collateral and terms.
2. **Buyer** calls `buy-option` and pays the premium.
3. If ITM before expiry, **holder** calls `exercise-option`.
4. Payout is calculated based on current BTC/USD from `price-feeds`.
