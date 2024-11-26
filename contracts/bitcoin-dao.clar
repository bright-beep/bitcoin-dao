;; title: Bitcoin-Powered Decentralized Autonomous Organization (DAO)
;; summary: A smart contract for managing a decentralized autonomous organization (DAO) powered by Bitcoin.
;; description: 
;; This contract implements a Bitcoin-powered DAO, allowing members to join, stake tokens, create and vote on proposals, and manage a treasury. 
;; It includes functionalities for membership management, proposal creation and execution, treasury donations, and reputation tracking. 
;; The contract also supports cross-DAO collaborations and decays the reputation of inactive members.

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-INVALID-PROPOSAL (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))

;; Data variables
(define-data-var total-members uint u0)
(define-data-var total-proposals uint u0)
(define-data-var treasury-balance uint u0)

;; Data maps
(define-map members principal 
  {
    reputation: uint,
    stake: uint,
    last-interaction: uint
  }
)

(define-map proposals uint 
  {
    creator: principal,
    title: (string-ascii 50),
    description: (string-utf8 500),
    amount: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 10),
    created-at: uint,
    expires-at: uint
  }
)

(define-map votes {proposal-id: uint, voter: principal} bool)

(define-map collaborations uint 
  {
    partner-dao: principal,
    proposal-id: uint,
    status: (string-ascii 10)
  }
)

;; Private functions

(define-private (is-member (user principal))
  (match (map-get? members user)
    member-data true
    false
  )
)

(define-private (is-active-proposal (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and 
      (< block-height (get expires-at proposal))
      (is-eq (get status proposal) "active")
    )
    false
  )
)

(define-private (calculate-voting-power (user principal))
  (let (
    (member-data (unwrap! (map-get? members user) u0))
    (reputation (get reputation member-data))
    (stake (get stake member-data))
  )
    (+ (* reputation u10) stake)
  )
)

(define-private (update-member-reputation (user principal) (change int))
  (match (map-get? members user)
    member-data 
    (let (
      (new-reputation (to-uint (+ (to-int (get reputation member-data)) change)))
      (updated-data (merge member-data {reputation: new-reputation, last-interaction: block-height}))
    )
      (map-set members user updated-data)
      (ok new-reputation)
    )
    ERR-NOT-MEMBER
  )
)

;; Public functions

;; Membership management

(define-public (join-dao)
  (let (
    (caller tx-sender)
  )
    (asserts! (not (is-member caller)) ERR-ALREADY-MEMBER)
    (map-set members caller {reputation: u1, stake: u0, last-interaction: block-height})
    (var-set total-members (+ (var-get total-members) u1))
    (ok true)
  )
)

(define-public (leave-dao)
  (let (
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (map-delete members caller)
    (var-set total-members (- (var-get total-members) u1))
    (ok true)
  )
)

(define-public (stake-tokens (amount uint))
  (let (
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (match (map-get? members caller)
      member-data 
      (let (
        (new-stake (+ (get stake member-data) amount))
        (updated-data (merge member-data {stake: new-stake, last-interaction: block-height}))
      )
        (map-set members caller updated-data)
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok new-stake)
      )
      ERR-NOT-MEMBER
    )
  )
)

(define-public (unstake-tokens (amount uint))
  (let (
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (map-get? members caller)
      member-data 
      (let (
        (current-stake (get stake member-data))
      )
        (asserts! (>= current-stake amount) ERR-INSUFFICIENT-FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender caller)))
        (let (
          (new-stake (- current-stake amount))
          (updated-data (merge member-data {stake: new-stake, last-interaction: block-height}))
        )
          (map-set members caller updated-data)
          (var-set treasury-balance (- (var-get treasury-balance) amount))
          (ok new-stake)
        )
      )
      ERR-NOT-MEMBER
    )
  )
)

;; Proposal management

(define-public (create-proposal (title (string-ascii 50)) (description (string-utf8 500)) (amount uint))
  (let (
    (caller tx-sender)
    (proposal-id (+ (var-get total-proposals) u1))
  )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (>= (var-get treasury-balance) amount) ERR-INSUFFICIENT-FUNDS)
    (map-set proposals proposal-id
      {
        creator: caller,
        title: title,
        description: description,
        amount: amount,
        yes-votes: u0,
        no-votes: u0,
        status: "active",
        created-at: block-height,
        expires-at: (+ block-height u1440) ;; Proposal expires after 1440 blocks (approx. 10 days)
      }
    )
    (var-set total-proposals proposal-id)
    (try! (update-member-reputation caller 1)) ;; Increase reputation for creating a proposal
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let (
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (is-active-proposal proposal-id) ERR-INVALID-PROPOSAL)
    (asserts! (not (default-to false (map-get? votes {proposal-id: proposal-id, voter: caller}))) ERR-ALREADY-VOTED)
    
    (let (
      (voting-power (calculate-voting-power caller))
      (proposal (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
    )
      (if vote
        (map-set proposals proposal-id (merge proposal {yes-votes: (+ (get yes-votes proposal) voting-power)}))
        (map-set proposals proposal-id (merge proposal {no-votes: (+ (get no-votes proposal) voting-power)}))
      )
      (map-set votes {proposal-id: proposal-id, voter: caller} true)
      (try! (update-member-reputation caller 1)) ;; Increase reputation for voting
      (ok true)
    )
  )
)