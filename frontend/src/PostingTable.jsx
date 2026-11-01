import { money } from './api.js';

const labels = { SALE: 'Sale', PURCHASE: 'Purchase', REFUND: 'Refund' };
const dateFormat = new Intl.DateTimeFormat('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export default function PostingTable({ postings, loading, unavailable }) {
  return <div className="table-scroll"><table>
    <caption className="sr-only">The 50 most recent saved postings with account decisions</caption>
    <thead><tr><th scope="col">Reference</th><th scope="col">Type</th><th scope="col">Account</th><th scope="col" className="amount-cell">Amount</th><th scope="col">Created</th></tr></thead>
    <tbody>
      {postings?.length ? postings.map(posting => <tr key={posting.id}>
        <td><strong className="reference">{posting.reference}</strong>{posting.narration ? <span className="cell-secondary narration" title={posting.narration}>{posting.narration}</span> : null}</td>
        <td>{labels[posting.transactionType]}</td>
        <td><span>{posting.accountCode}</span><span className="cell-secondary">{posting.accountName}</span><details className="decision-detail"><summary>Rule details</summary><span>{posting.ruleId}</span><span>{posting.ruleVersion}</span></details></td>
        <td className="amount-cell">{money(posting.amount, posting.currency)}</td>
        <td className="date-cell">{dateFormat.format(new Date(posting.createdAt))}</td>
      </tr>) : <tr><td colSpan="5" className="empty-cell"><div className="empty-state" role="status">
        {unavailable ? <><h3>Postings could not be loaded</h3><p>Use Refresh to try again.</p></> : loading ? <><h3>Loading postings…</h3><p>This may take a moment while the services start.</p></> : <><h3>No postings yet</h3><p>Create your first posting using the form.</p></>}
      </div></td></tr>}
    </tbody>
  </table></div>;
}
