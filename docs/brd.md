# BRD — Corporate Credit Transfer

## Purpose
Provide a simple, reliable way to create payments, avoid duplicates, view status, and support reconciliation.

## Problem
Finance and operations need a clear, testable flow to start payments and confirm outcomes. Duplicates and unclear errors create risk and support load.

## Goals
- Reduce duplicate payment attempts with idempotency
- Improve transparency with clear status and data
- Support daily controls with basic reconciliation signals

## In scope
- Create payment and get payment by id
- Idempotency via header
- Simple cut‑off flag (next business day indicator)
- Reconciliation queries (examples)

## Out of scope (v1)
- Webhooks and batch files
- AML/KYC screening
- Settlement and FX flows

## Stakeholders
- Business users (Payment Operators, Finance)
- Product Owner
- Engineering and QA
- Support/Incident
- Compliance/Audit

## Success metrics
- <1% duplicate initiation attempts per quarter
- p95 Create Payment < 300ms (baseline)
- Reconciliation variances identified during daily checks
