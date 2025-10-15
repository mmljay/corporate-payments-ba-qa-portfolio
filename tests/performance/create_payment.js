import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '10s',
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01']
  }
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export default function () {
  const payload = JSON.stringify({
    externalId: `${__VU}-${__ITER}-${Date.now()}`,
    debtorIban: 'SE12ABCDE1234567890123',
    creditorIban: 'SE34ABCDE9876543210123',
    currency: 'EUR',
    amountMinor: 1000
  });
  const headers = {
    'Content-Type': 'application/json',
    'Idempotency-Key': `${__VU}-${__ITER}`
  };
  const res = http.post(`${BASE_URL}/payments`, payload, { headers });
  check(res, {
    'status 201': (r) => r.status === 201,
    'has id': (r) => !!r.json('id'),
  });
  sleep(0.2);
}
