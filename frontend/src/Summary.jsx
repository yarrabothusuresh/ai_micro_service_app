import { money } from './api.js';

export default function Summary({ dashboard, loading }) {
  const totals = dashboard ? (dashboard.totals.length ? dashboard.totals : [{ currency: 'INR', amount: '0.00' }]) : [];
  return <section className="summary" aria-label="Posting totals" aria-busy={loading}>
    <div className="summary-item"><span>Total postings</span><strong>{dashboard?.totalPostings ?? '—'}</strong></div>
    {totals.length ? totals.map(total => <div className="summary-item" key={total.currency}><span>{total.currency} volume</span><strong>{money(total.amount, total.currency)}</strong></div>) : <div className="summary-item"><span>INR volume</span><strong>—</strong></div>}
  </section>;
}
