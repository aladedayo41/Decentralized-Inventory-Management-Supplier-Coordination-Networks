;; Delivery Tracking Contract
;; Tracks shipments and deliveries in real-time

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-TRACKING-NOT-FOUND (err u401))
(define-constant ERR-INVALID-STATUS (err u402))
(define-constant ERR-INVALID-INPUT (err u403))
(define-constant ERR-TRACKING-EXISTS (err u404))

;; Data Variables
(define-data-var next-tracking-id uint u1)

;; Data Maps
(define-map deliveries
  uint
  {
    order-id: uint,
    supplier: principal,
    buyer: principal,
    tracking-number: (string-ascii 50),
    current-location: (string-ascii 100),
    status: (string-ascii 20),
    estimated-delivery: uint,
    actual-delivery: (optional uint),
    created-at: uint,
    last-updated: uint
  }
)

(define-map delivery-milestones
  { tracking-id: uint, milestone-id: uint }
  {
    location: (string-ascii 100),
    status: (string-ascii 50),
    timestamp: uint,
    notes: (string-ascii 200)
  }
)

(define-map tracking-by-order
  uint
  uint
)

(define-map milestone-counter
  uint
  uint
)

(define-map delivery-confirmations
  uint
  {
    confirmed-by: principal,
    confirmation-status: (string-ascii 20),
    confirmed-at: uint,
    signature: (string-ascii 100)
  }
)

;; Public Functions

;; Create delivery tracking
(define-public (create-delivery-tracking (order-id uint) (buyer principal) (tracking-number (string-ascii 50)) (estimated-delivery uint))
  (let
    (
      (supplier tx-sender)
      (current-id (var-get next-tracking-id))
    )
    (asserts! (is-none (map-get? tracking-by-order order-id)) ERR-TRACKING-EXISTS)
    (asserts! (> (len tracking-number) u0) ERR-INVALID-INPUT)
    (asserts! (> estimated-delivery block-height) ERR-INVALID-INPUT)

    (map-set deliveries current-id {
      order-id: order-id,
      supplier: supplier,
      buyer: buyer,
      tracking-number: tracking-number,
      current-location: "Origin",
      status: "shipped",
      estimated-delivery: estimated-delivery,
      actual-delivery: none,
      created-at: block-height,
      last-updated: block-height
    })

    (map-set tracking-by-order order-id current-id)
    (map-set milestone-counter current-id u0)

    (var-set next-tracking-id (+ current-id u1))

    (ok current-id)
  )
)

;; Update delivery location
(define-public (update-location (tracking-id uint) (new-location (string-ascii 100)))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier delivery-data)) ERR-NOT-AUTHORIZED)

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          current-location: new-location,
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Update delivery status
(define-public (update-delivery-status (tracking-id uint) (new-status (string-ascii 20)))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier delivery-data)) ERR-NOT-AUTHORIZED)

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          status: new-status,
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Add delivery milestone
(define-public (add-milestone (tracking-id uint) (location (string-ascii 100)) (status (string-ascii 50)) (notes (string-ascii 200)))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
      (current-milestone-count (default-to u0 (map-get? milestone-counter tracking-id)))
      (new-milestone-id (+ current-milestone-count u1))
    )
    (asserts! (is-eq tx-sender (get supplier delivery-data)) ERR-NOT-AUTHORIZED)

    (map-set delivery-milestones { tracking-id: tracking-id, milestone-id: new-milestone-id } {
      location: location,
      status: status,
      timestamp: block-height,
      notes: notes
    })

    (map-set milestone-counter tracking-id new-milestone-id)

    ;; Update current location in main delivery record
    (map-set deliveries tracking-id
      (merge delivery-data
        {
          current-location: location,
          last-updated: block-height
        }
      )
    )

    (ok new-milestone-id)
  )
)

;; Mark as delivered
(define-public (mark-delivered (tracking-id uint))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier delivery-data)) ERR-NOT-AUTHORIZED)

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          status: "delivered",
          actual-delivery: (some block-height),
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Confirm delivery (buyer only)
(define-public (confirm-delivery (tracking-id uint) (signature (string-ascii 100)))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get buyer delivery-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status delivery-data) "delivered") ERR-INVALID-STATUS)

    (map-set delivery-confirmations tracking-id {
      confirmed-by: tx-sender,
      confirmation-status: "confirmed",
      confirmed-at: block-height,
      signature: signature
    })

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          status: "confirmed",
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Report delivery issue
(define-public (report-issue (tracking-id uint) (issue-description (string-ascii 200)))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get buyer delivery-data)) (is-eq tx-sender (get supplier delivery-data))) ERR-NOT-AUTHORIZED)

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          status: "issue-reported",
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Update estimated delivery time
(define-public (update-estimated-delivery (tracking-id uint) (new-estimate uint))
  (let
    (
      (delivery-data (unwrap! (map-get? deliveries tracking-id) ERR-TRACKING-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get supplier delivery-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> new-estimate block-height) ERR-INVALID-INPUT)

    (map-set deliveries tracking-id
      (merge delivery-data
        {
          estimated-delivery: new-estimate,
          last-updated: block-height
        }
      )
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get delivery info
(define-read-only (get-delivery (tracking-id uint))
  (map-get? deliveries tracking-id)
)

;; Get delivery by order ID
(define-read-only (get-delivery-by-order (order-id uint))
  (match (map-get? tracking-by-order order-id)
    tracking-id (map-get? deliveries tracking-id)
    none
  )
)

;; Get milestone info
(define-read-only (get-milestone (tracking-id uint) (milestone-id uint))
  (map-get? delivery-milestones { tracking-id: tracking-id, milestone-id: milestone-id })
)

;; Get delivery confirmation
(define-read-only (get-delivery-confirmation (tracking-id uint))
  (map-get? delivery-confirmations tracking-id)
)

;; Get milestone count
(define-read-only (get-milestone-count (tracking-id uint))
  (default-to u0 (map-get? milestone-counter tracking-id))
)

;; Check if delivery is confirmed
(define-read-only (is-delivery-confirmed (tracking-id uint))
  (match (map-get? delivery-confirmations tracking-id)
    confirmation-data (is-eq (get confirmation-status confirmation-data) "confirmed")
    false
  )
)

;; Get total deliveries count
(define-read-only (get-total-deliveries)
  (- (var-get next-tracking-id) u1)
)

;; Check if delivery is overdue
(define-read-only (is-delivery-overdue (tracking-id uint))
  (match (map-get? deliveries tracking-id)
    delivery-data (and
      (< (get estimated-delivery delivery-data) block-height)
      (not (is-eq (get status delivery-data) "delivered"))
      (not (is-eq (get status delivery-data) "confirmed"))
    )
    false
  )
)
