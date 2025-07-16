;; Order Coordination Contract
;; Coordinates orders between suppliers and buyers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-ORDER-NOT-FOUND (err u301))
(define-constant ERR-INVALID-STATUS (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-INSUFFICIENT-FUNDS (err u304))
(define-constant ERR-ORDER-EXISTS (err u305))

;; Data Variables
(define-data-var next-order-id uint u1)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Data Maps
(define-map orders
  uint
  {
    buyer: principal,
    supplier: principal,
    product-id: uint,
    quantity: uint,
    unit-price: uint,
    total-amount: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    delivery-deadline: uint
  }
)

(define-map order-by-buyer
  { buyer: principal, order-id: uint }
  bool
)

(define-map order-by-supplier
  { supplier: principal, order-id: uint }
  bool
)

(define-map order-payments
  uint
  {
    amount-paid: uint,
    payment-status: (string-ascii 20),
    escrow-amount: uint,
    released-amount: uint
  }
)

(define-map order-disputes
  uint
  {
    dispute-reason: (string-ascii 200),
    disputed-by: principal,
    dispute-status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

;; Public Functions

;; Create new order
(define-public (create-order (supplier principal) (product-id uint) (quantity uint) (unit-price uint) (delivery-deadline uint))
  (let
    (
      (buyer tx-sender)
      (current-id (var-get next-order-id))
      (total-amount (* quantity unit-price))
    )
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (> unit-price u0) ERR-INVALID-INPUT)
    (asserts! (> delivery-deadline block-height) ERR-INVALID-INPUT)

    (map-set orders current-id {
      buyer: buyer,
      supplier: supplier,
      product-id: product-id,
      quantity: quantity,
      unit-price: unit-price,
      total-amount: total-amount,
      status: "pending",
      created-at: block-height,
      updated-at: block-height,
      delivery-deadline: delivery-deadline
    })

    (map-set order-by-buyer { buyer: buyer, order-id: current-id } true)
    (map-set order-by-supplier { supplier: supplier, order-id: current-id } true)

    (map-set order-payments current-id {
      amount-paid: u0,
      payment-status: "pending",
      escrow-amount: u0,
      released-amount: u0
    })

    (var-set next-order-id (+ current-id u1))

    (ok current-id)
  )
)

;; Accept order (supplier only)
(define-public (accept-order (order-id uint))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier order-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status order-data) "pending") ERR-INVALID-STATUS)

    (map-set orders order-id
      (merge order-data
        {
          status: "accepted",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Reject order (supplier only)
(define-public (reject-order (order-id uint) (reason (string-ascii 200)))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier order-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status order-data) "pending") ERR-INVALID-STATUS)

    (map-set orders order-id
      (merge order-data
        {
          status: "rejected",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Update order status
(define-public (update-order-status (order-id uint) (new-status (string-ascii 20)))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get buyer order-data)) (is-eq tx-sender (get supplier order-data))) ERR-NOT-AUTHORIZED)

    (map-set orders order-id
      (merge order-data
        {
          status: new-status,
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Process payment for order
(define-public (process-payment (order-id uint) (amount uint))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
      (payment-data (unwrap! (map-get? order-payments order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get buyer order-data)) ERR-NOT-AUTHORIZED)
    (asserts! (>= amount (get total-amount order-data)) ERR-INSUFFICIENT-FUNDS)

    (map-set order-payments order-id
      (merge payment-data
        {
          amount-paid: amount,
          payment-status: "paid",
          escrow-amount: amount
        }
      )
    )

    (map-set orders order-id
      (merge order-data
        {
          status: "paid",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Release payment to supplier
(define-public (release-payment (order-id uint))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
      (payment-data (unwrap! (map-get? order-payments order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get buyer order-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get payment-status payment-data) "paid") ERR-INVALID-STATUS)

    (map-set order-payments order-id
      (merge payment-data
        {
          payment-status: "released",
          released-amount: (get escrow-amount payment-data),
          escrow-amount: u0
        }
      )
    )

    (map-set orders order-id
      (merge order-data
        {
          status: "completed",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Cancel order
(define-public (cancel-order (order-id uint))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get buyer order-data)) (is-eq tx-sender (get supplier order-data))) ERR-NOT-AUTHORIZED)

    (map-set orders order-id
      (merge order-data
        {
          status: "cancelled",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Create dispute
(define-public (create-dispute (order-id uint) (reason (string-ascii 200)))
  (let
    (
      (order-data (unwrap! (map-get? orders order-id) ERR-ORDER-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get buyer order-data)) (is-eq tx-sender (get supplier order-data))) ERR-NOT-AUTHORIZED)

    (map-set order-disputes order-id {
      dispute-reason: reason,
      disputed-by: tx-sender,
      dispute-status: "open",
      created-at: block-height,
      resolved-at: none
    })

    (map-set orders order-id
      (merge order-data
        {
          status: "disputed",
          updated-at: block-height
        }
      )
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get order info
(define-read-only (get-order (order-id uint))
  (map-get? orders order-id)
)

;; Get order payment info
(define-read-only (get-order-payment (order-id uint))
  (map-get? order-payments order-id)
)

;; Get order dispute info
(define-read-only (get-order-dispute (order-id uint))
  (map-get? order-disputes order-id)
)

;; Check if order exists for buyer
(define-read-only (buyer-has-order (buyer principal) (order-id uint))
  (default-to false (map-get? order-by-buyer { buyer: buyer, order-id: order-id }))
)

;; Check if order exists for supplier
(define-read-only (supplier-has-order (supplier principal) (order-id uint))
  (default-to false (map-get? order-by-supplier { supplier: supplier, order-id: order-id }))
)

;; Get total orders count
(define-read-only (get-total-orders)
  (- (var-get next-order-id) u1)
)

;; Get platform fee rate
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)
