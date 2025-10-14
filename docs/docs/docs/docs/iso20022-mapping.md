# ISO 20022 Mapping — API → XML (Simplified)

This document maps API fields to ISO 20022 XML elements for common payment messages. Designed for quick reference.

---

## pain.001 — Customer Credit Transfer Initiation

| API Field               | XML Element                        | Notes                                     |
|-------------------------|-----------------------------------|-------------------------------------------|
| `id`                    | `GrpHdr/MsgId`                    | Unique message ID                         |
| `createdAt`             | `GrpHdr/CreDtTm`                  | ISO datetime format                        |
| `externalId`            | `PmtInf/PmtInfId`                 | Reference ID                               |
| `requestedExecutionDate`| `PmtInf/ReqdExctnDt`              | Requested execution date                   |
| `endToEndId`            | `CdtTrfTxInf/PmtId/EndToEndId`   | End-to-end reference                       |
| `amountMinor+currency`  | `Amt/InstdAmt@Ccy`                | Amount in minor units (divide by 100)      |
| `debtorIban`            | `DbtrAcct/Id/IBAN`                | Debtor IBAN                                |
| `creditorIban`          | `CdtrAcct/Id/IBAN`                | Creditor IBAN                              |

---

## pain.002 — Customer Payment Status Report

| API Field           | XML Element                         | Notes                                   |
|--------------------|-------------------------------------|-----------------------------------------|
| `payment.id`        | `OrgnlGrpInfAndSts/OrgnlMsgId`     | References original initiation message   |
| `payment.endToEndId`| `TxInfAndSts/OrgnlEndToEndId`      | End-to-end reference                     |
| `status`            | `TxInfAndSts/TxSts`                | ACSP (Accepted) or RJCT (Rejected)      |

---

## pacs.008 — FI to FI Credit Transfer

| API Field             | XML Element                        | Notes                         |
|-----------------------|-----------------------------------|-------------------------------|
| `endToEndId`           | `CdtTrfTxInf/PmtId/EndToEndId`   | End-to-end reference           |
| `amountMinor+currency` | `Amt/InstdAmt@Ccy`                | Amount in minor units          |
| `debtorIban`           | `DbtrAcct/Id/IBAN`                | Debtor IBAN                    |
| `creditorIban`         | `CdtrAcct/Id/IBAN`                | Creditor IBAN                  |

---

## pacs.002 — FI Payment Status

| API Field    | XML Element                    | Notes                       |
|--------------|--------------------------------|-----------------------------|
| `endToEndId` | `TxInfAndSts/OrgnlEndToEndId` | End-to-end reference         |
| `status`     | `TxInfAndSts/TxSts`           | ACSP or RJCT                 |

---

## camt.053 — Bank-to-Customer Statement

| Aggregate     | XML Element                 | Notes                     |
|---------------|----------------------------|---------------------------|
| `count/sum`   | `GrpHdr/NbOfMsgs; CtrlSum` | Simplified for demo       |
| `entries`     | `Stmt/Ntry`                | One entry per payment      |

---

## camt.054 — Bank-to-Customer Debit/Credit Notification

| API Field            | XML Element           | Notes                        |
|----------------------|---------------------|-------------------------------|
| `id`                 | `Ntry/NtryRef`       | Entry reference ID           |
| `amountMinor+currency`| `Ntry/Amt@Ccy`      | Amount in minor units        |
| `endToEndId`         | `RmtInf/Ustrd`       | End-to-end reference (demo)  |

