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