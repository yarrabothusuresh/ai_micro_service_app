const baseUrl = (import.meta.env.VITE_API_BASE_URL || '').replace(/\/$/, '');

async function request(path, options = {}) {
  let response;
  try {
    response = await fetch(`${baseUrl}${path}`, { ...options, signal: options.signal || AbortSignal.timeout(95000) });
  } catch (error) {
    if (error.name === 'AbortError') throw error;
    throw new Error('The service could not be reached. Please retry; your request will not be duplicated.');
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(data?.errors?.join('. ') || data?.detail || 'The request could not be completed. Please try again.');
  }
  return data;
}

export const getDashboard = (signal) => request('/api/ui/dashboard', { signal });
export const createPosting = (posting, key) => request('/api/postings', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
  body: JSON.stringify(posting),
});

export function money(amount, currency) {
  return new Intl.NumberFormat('en-IN', { style: 'currency', currency, minimumFractionDigits: 2 }).format(Number(amount));
}
