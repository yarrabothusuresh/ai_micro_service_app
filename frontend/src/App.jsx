import { useCallback, useEffect, useRef, useState } from 'react';
import { getDashboard } from './api.js';
import PostingForm from './PostingForm.jsx';
import PostingTable from './PostingTable.jsx';
import Summary from './Summary.jsx';

export default function App() {
  const [dashboard, setDashboard] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const refreshSequence = useRef(0);

  const refresh = useCallback(async (signal) => {
    const sequence = ++refreshSequence.current;
    setLoading(true);
    setError('');
    try {
      const data = await getDashboard(signal);
      if (sequence === refreshSequence.current) setDashboard(data);
    } catch (failure) {
      if (sequence === refreshSequence.current && failure.name !== 'AbortError') setError(failure.message);
    } finally {
      if (sequence === refreshSequence.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    refresh(controller.signal);
    return () => controller.abort();
  }, [refresh]);

  return <>
    <header className="app-header"><div className="header-inner"><a className="brand" href="#main">Ledger Manager</a><a className="nav-link" href="#main" aria-current="page">Dashboard</a></div></header>
    <main id="main" className="page">
      <div className="page-heading"><h1>Postings</h1><p>Create a posting and review its account decision.</p></div>
      <Summary dashboard={dashboard} loading={loading} />
      {error ? <div className="notice error" role="alert">{error} {dashboard ? 'Previously loaded data is shown below.' : ''}</div> : null}
      <div className="workspace">
        <section className="panel postings-panel" aria-labelledby="postings-title">
          <div className="panel-header"><h2 id="postings-title">Recent postings</h2><button type="button" onClick={() => refresh()} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button></div>
          <PostingTable postings={dashboard?.recentPostings} loading={loading} unavailable={!!error && !dashboard} />
        </section>
        <PostingForm onSaved={() => refresh()} />
      </div>
    </main>
  </>;
}
