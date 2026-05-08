// Also create PL/frontend/.env with:
//   VITE_PB_URL=http://localhost:8090

import PocketBase from 'pocketbase';

export type { AuthUser } from '$lib/schemas';

// This detects the current URL the user is visiting and uses it as the base
export const PB_URL = import.meta.env.VITE_PB_URL && import.meta.env.VITE_PB_URL !== '/'
    ? import.meta.env.VITE_PB_URL
    : window.location.origin;

export const pb = new PocketBase(PB_URL);

/** Authenticated fetch against /api/custom/* routes */
export const customFetch = async (path: string, options: RequestInit = {}): Promise<any> => {
  const res = await fetch(`${PB_URL}/api/custom${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': pb.authStore.token || '',
      ...((options.headers as Record<string, string>) || {}),
    },
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(err.message || 'Request failed');
  }
  if (res.status === 204) return null;
  return res.json();
};

/** Map PocketBase role → frontend role */
export const mapRole = (role: string): 'admin' | 'manager' | 'billing' | 'stock' => {
  const m: Record<string, 'admin' | 'manager' | 'billing' | 'stock'> = {
    admin: 'admin',
    manager: 'manager',
    pos: 'billing',
    stock_entry: 'stock',
  };
  return m[role] || 'billing';
};

