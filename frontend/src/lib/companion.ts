import { Settings } from 'lucide-svelte';

export function isCompanionMode(): boolean {
  if (typeof sessionStorage === 'undefined') return false;
  return sessionStorage.getItem('companion_mode') === '1';
}

export const companionMenuItem = {
  label: 'Printer Settings',
  icon: Settings,
  path: '',
  onclick: () => { window.location.href = 'tauri://localhost'; },
};
