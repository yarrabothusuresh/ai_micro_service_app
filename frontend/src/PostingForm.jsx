import { useRef, useState } from 'react';
import { createPosting } from './api.js';

const initial = { reference: '', transactionType: 'SALE', amount: '', currency: 'INR', narration: '' };

export default function PostingForm({ onSaved }) {
  const [form, setForm] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(null);
  const attempt = useRef(null);
  const submitting = useRef(false);
  const referenceInput = useRef(null);

  const update = (event) => {
    const { name, value } = event.target;
    setForm(previous => ({ ...previous, [name]: value }));
    setError('');
    setSaved(null);
  };

  async function submit(event) {
    event.preventDefault();
    if (submitting.current) return;
    const payload = { ...form, reference: form.reference.trim(), narration: form.narration.trim() };
    const fingerprint = JSON.stringify(payload);
    if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
      attempt.current = { key: crypto.randomUUID(), fingerprint };
    }
    submitting.current = true;
    setSaving(true); setError(''); setSaved(null);
    try {
      const result = await createPosting(payload, attempt.current.key);
      setSaved(result);
      setForm(previous => ({ ...initial, currency: previous.currency, transactionType: previous.transactionType }));
      attempt.current = null;
      onSaved();
      referenceInput.current?.focus();
    } catch (failure) {
      setError(failure.message);
    } finally {
      submitting.current = false;
      setSaving(false);
    }
  }

  return <section className="panel form-panel" aria-labelledby="new-posting-title">
    <h2 id="new-posting-title">New posting</h2>
    <form onSubmit={submit}>
      <fieldset disabled={saving}>
        <label htmlFor="reference">Reference</label><input ref={referenceInput} id="reference" name="reference" value={form.reference} onChange={update} required maxLength={80} autoComplete="off" pattern=".*\S.*" />
        <label htmlFor="transactionType">Transaction type</label><select id="transactionType" name="transactionType" value={form.transactionType} onChange={update}><option value="SALE">Sale</option><option value="PURCHASE">Purchase</option><option value="REFUND">Refund</option></select>
        <div className="form-row"><div><label htmlFor="amount">Amount</label><input id="amount" name="amount" type="number" inputMode="decimal" min="0.01" max="999999999999.99" step="0.01" value={form.amount} onChange={update} required /></div><div><label htmlFor="currency">Currency</label><select id="currency" name="currency" value={form.currency} onChange={update}><option>INR</option><option>USD</option><option>EUR</option></select></div></div>
        <label htmlFor="narration">Narration</label><textarea id="narration" name="narration" rows={4} maxLength={500} value={form.narration} onChange={update} />
        <button className="submit-button" type="submit">{saving ? 'Selecting account and saving…' : 'Create posting'}</button>
      </fieldset>
      <p className="form-hint">Account selection happens when you submit.</p>
      {error ? <div className="notice error" role="alert">{error}</div> : null}
      {saved ? <div className="notice success" role="status"><strong>Posting saved</strong><span>{saved.reference} · {saved.accountCode}</span><span>{saved.accountName}</span></div> : null}
    </form>
  </section>;
}
