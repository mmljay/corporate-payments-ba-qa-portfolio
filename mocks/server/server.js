import express from 'express';
import cors from 'cors';
import { v4 as uuidv4 } from 'uuid';
import dayjs from 'dayjs';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory stores
const payments = new Map();
const idemKeys = new Map();

// Validators
const isIbanLike = (s) => typeof s === 'string' && /^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$/.test(s);
const isCurrency = (s) => ['EUR', 'SEK', 'USD'].includes(s);
const isPositiveInt = (n) => Number.isInteger(n) && n > 0;

// Cut-off utility: after 16:00 local => schedule next business day
function isAfterCutoff() {
  const now = dayjs();
  const cutoff = now.hour(16).minute(0).second(0);
  return now.isAfter(cutoff);
}

function majorAmount(p) {
  return (p.amountMinor / 100).toFixed(2);
}

function xmlHeader(ns) {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<Document xmlns="${ns}">`;
}

// Health
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }));

// Create payment
app.post('/payments', (req, res) => {
  const idem = req.header('Idempotency-Key');
  if (!idem) return res.status(400).json({ error: 'Missing Idempotency-Key header' });

  if (idemKeys.has(idem)) {
    const existingId = idemKeys.get(idem);
    const existing = payments.get(existingId);
    return res.status(201).json(existing);
  }

  const { externalId, debtorIban, creditorIban, currency, amountMinor, endToEndId, requestedExecutionDate } = req.body || {};
  const errors = [];
  if (!externalId) errors.push('externalId required');
  if (!isIbanLike(debtorIban)) errors.push('debtorIban invalid');
  if (!isIbanLike(creditorIban)) errors.push('creditorIban invalid');
  if (!isCurrency(currency)) errors.push('currency invalid');
  if (!isPositiveInt(amountMinor)) errors.push('amountMinor invalid');
  if (errors.length) return res.status(400).json({ error: 'validation', details: errors });

  const id = uuidv4();
  const now = dayjs().toISOString();
  const scheduledNextBusinessDay = isAfterCutoff();

  const payment = {
    id,
    externalId,
    debtorIban,
    creditorIban,
    currency,
    amountMinor,
    endToEndId: endToEndId || uuidv4(),
    requestedExecutionDate: requestedExecutionDate || dayjs().format('YYYY-MM-DD'),
    status: 'INITIATED',
    scheduledNextBusinessDay,
    createdAt: now
  };

  payments.set(id, payment);
  idemKeys.set(idem, id);

  // Simulate async move to PENDING
  setTimeout(() => {
    const p = payments.get(id);
    if (p && p.status === 'INITIATED') {
      p.status = 'PENDING';
      payments.set(id, p);
    }
  }, 50);

  return res.status(201).json(payment);
});

// Get payment
app.get('/payments/:id', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).json({ error: 'not_found' });
  res.json(p);
});

// pain.001
app.get('/payments/:id/pain001', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.001.001.03';
  const xml = `${xmlHeader(ns)}
  <CstmrCdtTrfInitn>
    <GrpHdr>
      <MsgId>${p.id}</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <PmtInf>
      <PmtInfId>${p.externalId}</PmtInfId>
      <BtchBookg>false</BtchBookg>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
      <ReqdExctnDt>${p.requestedExecutionDate}</ReqdExctnDt>
      <Dbtr><Nm>Debtor</Nm></Dbtr>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtTrfTxInf>
        <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
        <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
        <Cdtr><Nm>Creditor</Nm></Cdtr>
        <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
      </CdtTrfTxInf>
    </PmtInf>
  </CstmrCdtTrfInitn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
}

// pain.002
app.get('/payments/:id/pain002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pain.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <CstmrPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-status</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}</OrgnlMsgId>
      <OrgnlMsgNmId>pain.001.001.03</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <OrgnlPmtInfAndSts>
      <TxInfAndSts>
        <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
        <TxSts>${status}</TxSts>
      </TxInfAndSts>
    </OrgnlPmtInfAndSts>
  </CstmrPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.008
app.get('/payments/:id/pacs008', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.008.001.02';
  const xml = `${xmlHeader(ns)}
  <FIToFICstmrCdtTrf>
    <GrpHdr>
      <MsgId>${p.id}-pacs008</MsgId>
      <CreDtTm>${p.createdAt}</CreDtTm>
      <NbOfTxs>1</NbOfTxs>
      <CtrlSum>${amt}</CtrlSum>
    </GrpHdr>
    <CdtTrfTxInf>
      <PmtId><EndToEndId>${p.endToEndId}</EndToEndId></PmtId>
      <Amt><InstdAmt Ccy="${p.currency}">${amt}</InstdAmt></Amt>
      <DbtrAcct><Id><IBAN>${p.debtorIban}</IBAN></Id></DbtrAcct>
      <CdtrAcct><Id><IBAN>${p.creditorIban}</IBAN></Id></CdtrAcct>
    </CdtTrfTxInf>
  </FIToFICstmrCdtTrf>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// pacs.002
app.get('/payments/:id/pacs002', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const ns = 'urn:iso:std:iso:20022:tech:xsd:pacs.002.001.03';
  const status = p.status === 'REJECTED' ? 'RJCT' : 'ACSP';
  const xml = `${xmlHeader(ns)}
  <FIToFIPmtStsRpt>
    <GrpHdr>
      <MsgId>${p.id}-pacs002</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <OrgnlGrpInfAndSts>
      <OrgnlMsgId>${p.id}-pacs008</OrgnlMsgId>
      <OrgnlMsgNmId>pacs.008.001.02</OrgnlMsgNmId>
    </OrgnlGrpInfAndSts>
    <TxInfAndSts>
      <OrgnlEndToEndId>${p.endToEndId}</OrgnlEndToEndId>
      <TxSts>${status}</TxSts>
    </TxInfAndSts>
  </FIToFIPmtStsRpt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.054
app.get('/payments/:id/camt054', (req, res) => {
  const p = payments.get(req.params.id);
  if (!p) return res.status(404).send('Not Found');
  const amt = majorAmount(p);
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.054.001.04';
  const xml = `${xmlHeader(ns)}
  <BkToCstmrDbtCdtNtfctn>
    <GrpHdr>
      <MsgId>${p.id}-camt054</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
    </GrpHdr>
    <Ntfctn>
      <Id>${p.id}</Id>
      <NtfctnPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></NtfctnPgntn>
      <Ntry>
        <NtryRef>${p.id}</NtryRef>
        <Amt Ccy="${p.currency}">${amt}</Amt>
        <CdtDbtInd>CRDT</CdtDbtInd>
        <BkTxCd><Prtry>TRF</Prtry></BkTxCd>
        <NtryDtls>
          <TxDtls>
            <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
            <RmtInf><Ustrd>${p.endToEndId}</Ustrd></RmtInf>
          </TxDtls>
        </NtryDtls>
      </Ntry>
    </Ntfctn>
  </BkToCstmrDbtCdtNtfctn>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// camt.053
app.get('/statements/camt053', (_req, res) => {
  const ns = 'urn:iso:std:iso:20022:tech:xsd:camt.053.001.02';
  const all = Array.from(payments.values());
  const count = all.length;
  const sum = all.reduce((acc, p) => acc + p.amountMinor, 0) / 100;
  const xmlEntries = all.map((p) => {
    return `<Ntry>
      <Amt Ccy="${p.currency}">${(p.amountMinor/100).toFixed(2)}</Amt>
      <CdtDbtInd>CRDT</CdtDbtInd>
      <NtryRef>${p.id}</NtryRef>
      <NtryDtls>
        <TxDtls>
          <Refs><EndToEndId>${p.endToEndId}</EndToEndId></Refs>
        </TxDtls>
      </NtryDtls>
    </Ntry>`;
  }).join('\n');

  const xml = `${xmlHeader(ns)}
  <BkToCstmrStmt>
    <GrpHdr>
      <MsgId>statement-${dayjs().format('YYYYMMDDHHmmss')}</MsgId>
      <CreDtTm>${dayjs().toISOString()}</CreDtTm>
      <NbOfMsgs>${count}</NbOfMsgs>
      <CtrlSum>${(sum).toFixed(2)}</CtrlSum>
    </GrpHdr>
    <Stmt>
      <Id>${uuidv4()}</Id>
      ${xmlEntries}
    </Stmt>
  </BkToCstmrStmt>
</Document>`;
  res.set('Content-Type', 'application/xml').status(200).send(xml);
});

// Test-only reset
app.post('/__reset', (_req, res) => {
  payments.clear();
  idemKeys.clear();
  res.status(204).end();
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Mock API on http://localhost:${port}`);
});
