;; BitVault Options Protocol
;;
;; Title: BitVault - Decentralized Bitcoin Options Trading Protocol
;;
;; Summary: A comprehensive DeFi protocol enabling secure, collateralized 
;;          options trading on Bitcoin-backed assets through Stacks Layer 2
;;
;; Description: BitVault revolutionizes Bitcoin DeFi by providing a trustless,
;;              decentralized platform for trading Bitcoin options contracts.
;;              Built on Stacks Layer 2, it leverages Bitcoin's security while
;;              offering sophisticated financial instruments including calls,
;;              puts, and advanced collateral management. The protocol features
;;              real-time price oracles, governance mechanisms, and rigorous
;;              security validations to ensure safe, efficient options trading
;;              for the Bitcoin ecosystem.
;;

;; TRAIT DEFINITIONS

;; SIP-010 Fungible Token Standard Implementation
(define-trait sip-010-trait (
    (transfer
        (uint principal principal (optional (buff 34)))
        (response bool uint)
    )
    (get-balance
        (principal)
        (response uint uint)
    )
    (get-total-supply
        ()
        (response uint uint)
    )
    (get-decimals
        ()
        (response uint uint)
    )
    (get-token-uri
        ()
        (response (optional (string-utf8 256)) uint)
    )
    (get-name
        ()
        (response (string-ascii 32) uint)
    )
    (get-symbol
        ()
        (response (string-ascii 32) uint)
    )
))

;; ERROR CONSTANTS

;; Core Protocol Errors
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-EXPIRY (err u1002))
(define-constant ERR-INVALID-STRIKE-PRICE (err u1003))
(define-constant ERR-OPTION-NOT-FOUND (err u1004))
(define-constant ERR-OPTION-EXPIRED (err u1005))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1006))
(define-constant ERR-ALREADY-EXERCISED (err u1007))
(define-constant ERR-INVALID-PREMIUM (err u1008))

;; Validation Errors
(define-constant ERR-INVALID-TOKEN (err u1009))
(define-constant ERR-INVALID-SYMBOL (err u1010))
(define-constant ERR-INVALID-TIMESTAMP (err u1011))
(define-constant ERR-INVALID-ADDRESS (err u1012))
(define-constant ERR-ZERO-ADDRESS (err u1013))
(define-constant ERR-EMPTY-SYMBOL (err u1014))

;; UTILITY FUNCTIONS

(define-private (get-min
        (a uint)
        (b uint)
    )
    (if (< a b)
        a
        b
    )
)

;; DATA STRUCTURES

;; Options Registry - Core contract data structure
(define-map options
    uint
    {
        writer: principal,
        holder: (optional principal),
        collateral-amount: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        is-exercised: bool,
        option-type: (string-ascii 4), ;; "CALL" or "PUT"
        state: (string-ascii 9), ;; "ACTIVE" or "EXERCISED"
    }
)

;; User Position Tracking
(define-map user-positions
    principal
    {
        written-options: (list 10 uint),
        held-options: (list 10 uint),
        total-collateral-locked: uint,
    }
)

;; Token Whitelist for Security
(define-map approved-tokens
    principal
    bool
)

;; Price Oracle Symbol Whitelist
(define-map allowed-symbols
    (string-ascii 10)
    bool
)

;; Real-time Price Feed Integration
(define-map price-feeds
    (string-ascii 10)
    {
        price: uint,
        timestamp: uint,
        source: principal,
    }
)

;; STATE VARIABLES

;; Option ID Counter
(define-data-var next-option-id uint u1)

;; Protocol Governance
(define-data-var contract-owner principal tx-sender)
(define-data-var protocol-fee-rate uint u100) ;; 1% = 100 basis points

;; CORE PROTOCOL FUNCTIONS

;; Write Option Contract
;; Allows users to create new options by locking collateral
(define-public (write-option
        (token <sip-010-trait>)
        (collateral-amount uint)
        (strike-price uint)
        (premium uint)
        (expiry uint)
        (option-type (string-ascii 4))
    )
    (let (
            (option-id (var-get next-option-id))
            (current-time stacks-block-height)
            (token-principal (contract-of token))
        )
        ;; Security Validations
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (> expiry current-time) ERR-INVALID-EXPIRY)
        (asserts! (> strike-price u0) ERR-INVALID-STRIKE-PRICE)
        (asserts! (> premium u0) ERR-INVALID-PREMIUM)
        (asserts!
            (check-collateral-requirement collateral-amount strike-price
                option-type
            )
            ERR-INSUFFICIENT-COLLATERAL
        )
        ;; Lock Collateral in Contract
        (try! (contract-call? token transfer collateral-amount tx-sender
            (as-contract tx-sender) none
        ))
        ;; Create Option Entry
        (map-set options option-id {
            writer: tx-sender,
            holder: none,
            collateral-amount: collateral-amount,
            strike-price: strike-price,
            premium: premium,
            expiry: expiry,
            is-exercised: false,
            option-type: option-type,
            state: "ACTIVE",
        })
        ;; Update Writer's Position
        (let ((current-position (default-to {
                written-options: (list),
                held-options: (list),
                total-collateral-locked: u0,
            }
                (map-get? user-positions tx-sender)
            )))
            (map-set user-positions tx-sender
                (merge current-position {
                    written-options: (unwrap-panic (as-max-len?
                        (append (get written-options current-position) option-id)
                        u10
                    )),
                    total-collateral-locked: (+ (get total-collateral-locked current-position)
                        collateral-amount
                    ),
                })
            )
        )
        ;; Increment Option Counter
        (var-set next-option-id (+ option-id u1))
        (ok option-id)
    )
)

;; Purchase Option Contract
;; Allows users to buy existing options by paying premium
(define-public (buy-option
        (token <sip-010-trait>)
        (option-id uint)
    )
    (let (
            (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
            (premium (get premium option))
            (token-principal (contract-of token))
        )
        ;; Security Validations
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-none (get holder option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        ;; Transfer Premium to Writer
        (try! (contract-call? token transfer premium tx-sender (get writer option) none))
        ;; Update Option Holder
        (map-set options option-id (merge option { holder: (some tx-sender) }))
        ;; Update Buyer's Position
        (let ((current-position (default-to {
                written-options: (list),
                held-options: (list),
                total-collateral-locked: u0,
            }
                (map-get? user-positions tx-sender)
            )))
            (map-set user-positions tx-sender
                (merge current-position { held-options: (unwrap-panic (as-max-len?
                    (append (get held-options current-position) option-id)
                    u10
                )) }
                ))
        )
        (ok true)
    )
)

;; Exercise Option Contract
;; Allows option holders to exercise their contracts
(define-public (exercise-option
        (token <sip-010-trait>)
        (option-id uint)
    )
    (let (
            (option (unwrap! (map-get? options option-id) ERR-OPTION-NOT-FOUND))
            (current-price (get-current-price))
            (token-principal (contract-of token))
        )
        ;; Security Validations
        (asserts! (is-approved-token token-principal) ERR-INVALID-TOKEN)
        (asserts! (is-eq (some tx-sender) (get holder option)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-exercised option)) ERR-ALREADY-EXERCISED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-OPTION-EXPIRED)
        ;; Execute Exercise Logic Based on Option Type
        (if (is-eq (get option-type option) "CALL")
            (exercise-call token option current-price)
            (exercise-put token option current-price)
        )
    )
)

;; PRIVATE HELPER FUNCTIONS

;; Validate Collateral Requirements
(define-private (check-collateral-requirement
        (amount uint)
        (strike uint)
        (option-type (string-ascii 4))
    )
    (if (is-eq option-type "CALL")
        (>= amount strike)
        (>= amount (/ (* strike u100000000) (get-current-price)))
    )
)

;; Execute Call Option Exercise
(define-private (exercise-call
        (token <sip-010-trait>)
        (option {
            writer: principal,
            holder: (optional principal),
            collateral-amount: uint,
            strike-price: uint,
            premium: uint,
            expiry: uint,
            is-exercised: bool,
            option-type: (string-ascii 4),
            state: (string-ascii 9),
        })
        (current-price uint)
    )
    (let (
            (profit (- current-price (get strike-price option)))
            (payout (get-min profit (get collateral-amount option)))
        )
        ;; Transfer Payout to Holder
        (try! (as-contract (contract-call? token transfer payout tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
        )))
        ;; Return Remaining Collateral to Writer
        (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
            tx-sender (get writer option) none
        )))
        ;; Update Option State
        (map-set options (get-option-id option)
            (merge option {
                is-exercised: true,
                state: "EXERCISED",
            })
        )
        (ok true)
    )
)

;; Execute Put Option Exercise
(define-private (exercise-put
        (token <sip-010-trait>)
        (option {
            writer: principal,
            holder: (optional principal),
            collateral-amount: uint,
            strike-price: uint,
            premium: uint,
            expiry: uint,
            is-exercised: bool,
            option-type: (string-ascii 4),
            state: (string-ascii 9),
        })
        (current-price uint)
    )
    (let (
            (profit (- (get strike-price option) current-price))
            (payout (get-min profit (get collateral-amount option)))
        )
        ;; Transfer Payout to Holder
        (try! (as-contract (contract-call? token transfer payout tx-sender
            (unwrap! (get holder option) ERR-NOT-AUTHORIZED) none
        )))
        ;; Return Remaining Collateral to Writer
        (try! (as-contract (contract-call? token transfer (- (get collateral-amount option) payout)
            tx-sender (get writer option) none
        )))
        ;; Update Option State
        (map-set options (get-option-id option)
            (merge option {
                is-exercised: true,
                state: "EXERCISED",
            })
        )
        (ok true)
    )
)

;; ORACLE & VALIDATION UTILITIES

;; Get Current BTC Price from Oracle
(define-private (get-current-price)
    (get price (unwrap! (map-get? price-feeds "BTC-USD") u0))
)

;; Get Option ID Helper
(define-private (get-option-id (option {
    writer: principal,
    holder: (optional principal),
    collateral-amount: uint,
    strike-price: uint,
    premium: uint,
    expiry: uint,
    is-exercised: bool,
    option-type: (string-ascii 4),
    state: (string-ascii 9),
}))
    (var-get next-option-id)
)

;; Token Approval Validation
(define-private (is-approved-token (token principal))
    (default-to false (map-get? approved-tokens token))
)

;; Symbol Validation
(define-private (is-allowed-symbol (symbol (string-ascii 10)))
    (default-to false (map-get? allowed-symbols symbol))
)

;; Address Validation
(define-private (is-valid-principal (address principal))
    (and
        (not (is-eq address (as-contract tx-sender)))
        (not (is-eq address .base))
        (not (is-eq address tx-sender))
        true
    )
)

;; Symbol Format Validation
(define-private (is-valid-symbol (symbol (string-ascii 10)))
    (and
        (not (is-eq symbol ""))
        (not (is-eq symbol " "))
        (>= (len symbol) u2)
    )
)

;; Critical Token Protection
(define-private (is-critical-token (token principal))
    (or
        (is-eq token .wrapped-btc)
        (is-eq token .wrapped-stx)
    )
)

;; Critical Symbol Protection
(define-private (is-critical-symbol (symbol (string-ascii 10)))
    (or
        (is-eq symbol "BTC-USD")
        (is-eq symbol "STX-USD")
    )
)

;; READ-ONLY FUNCTIONS

;; Get Option Details
(define-read-only (get-option (option-id uint))
    (map-get? options option-id)
)

;; Get User Position Information
(define-read-only (get-user-position (user principal))
    (map-get? user-positions user)
)

;; Get Current Protocol Fee Rate
(define-read-only (get-protocol-fee-rate)
    (var-get protocol-fee-rate)
)

;; GOVERNANCE & ADMIN FUNCTIONS

;; Update Protocol Fee Rate
(define-public (set-protocol-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= new-rate u1000) ERR-INVALID-PREMIUM) ;; Max 10%
        (var-set protocol-fee-rate new-rate)
        (ok true)
    )
)

;; Update Price Oracle Feed
(define-public (update-price-feed
        (symbol (string-ascii 10))
        (price uint)
        (timestamp uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-allowed-symbol symbol) ERR-INVALID-SYMBOL)
        (asserts! (>= timestamp stacks-block-height) ERR-INVALID-TIMESTAMP)
        (asserts! (> price u0) ERR-INVALID-STRIKE-PRICE)
        (map-set price-feeds symbol {
            price: price,
            timestamp: timestamp,
            source: tx-sender,
        })
        (ok true)
    )
)