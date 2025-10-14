# Corporate Payments — Credit Transfer & Reconciliation (BA + QA Portfolio)

[![Python](https://img.shields.io/badge/Python-3.10+-blue)](https://www.python.org/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green)](https://nodejs.org/)
[![CI](https://img.shields.io/badge/CI-Passing-brightgreen)](#)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](#)

This project demonstrates my **end-to-end Business Analysis (BA) and Quality Assurance (QA) skills**, focusing on credit transfer functionality and reconciliation processes. It combines comprehensive BA documentation with hands-on QA deliverables, supported by a minimal payments API mock that can run locally or in CI pipelines.  

---

## **Project Demo**
![Demo GIF](https://via.placeholder.com/600x300.png?text=Demo+GIF+or+Screenshot+Here)  
*Replace the placeholder above with a GIF or screenshot showing your API tests or CI pipeline in action.*

---

## **Project Scope**

### **Business Analysis**
- Requirements gathering and documentation (BRD/PRD)  
- Stakeholder mapping and RACI matrix  
- Process modeling using BPMN flows  
- User personas, stories, and acceptance criteria  
- Backlog prioritization and UAT planning  
- Risk identification and success metrics (KPIs)

### **Quality Assurance**
- Test strategy and detailed test plan  
- Traceability matrix covering all user stories  
- API testing using **pytest**  
- Performance smoke testing with **k6**  
- Data integrity and reconciliation checks via SQL

### **Domain**
- Credit transfer initiation and status lifecycle  
- Idempotency handling and cut-off flag management  
- Reconciliation patterns for financial transactions  

### **Standards**
- **ISO 20022** message formats supported:  
  - pain.001 (Customer Credit Transfer Initiation)  
  - pain.002 (Customer Payment Status Report)  
  - pacs.008 (FI to FI Credit Transfer)  
  - pacs.002 (FI Payment Status)  
  - camt.053 (Bank to Customer Statement)  
  - camt.054 (Credit/Debit Notification)  

---

## **Quick Start**

**Prerequisites:** Node.js 18+, Python 3.10+, pip  

### 1️⃣ Start the Mock API
```bash
cd mocks/server
npm ci
npm start

Health check: http://localhost:3000/health

2️⃣ Run API Tests
Health check: http://localhost:3000/health

pip install -r requirements.txt
pytest -q

3️⃣ Optional: Performance Smoke Test

Install k6: https://k6.io/docs/get-started/installation/
k6 run tests/performance/create_payment.js

Repository Structure

docs/
  brd.md
  prd.md
  stakeholders-and-raci.md
  process-flows-bpmn.md
  user-personas.md
  user-stories-and-backlog.md
  acceptance-criteria.md
  uat-plan.md
  test-strategy.md
  test-plan.md
  traceability-matrix.md
  risk-register.md
  metrics-and-kpis.md
  architecture.md
  iso20022-overview.md
  iso20022-mapping.md

api/openapi.yaml          # API contract
mocks/server/             # Minimal Node/Express API
tests/api/                # Functional & ISO 20022 API tests
tests/performance/        # k6 smoke tests
sql/                      # Schema, seed data, and reconciliation queries
.github/workflows/ci.yml  # CI pipeline

## **Key Highlights**

Business Analysis: Complete documentation covering requirements, stakeholders, processes, personas, backlog, acceptance criteria, and UAT planning

Quality Assurance: Automated API tests, idempotency verification, validation coverage, performance smoke, and reconciliation checks

ISO 20022 Expertise: Export endpoints and tests for pain.001, pain.002, pacs.008, pacs.002, camt.053, and camt.054

Author

GitHub: mmljay

