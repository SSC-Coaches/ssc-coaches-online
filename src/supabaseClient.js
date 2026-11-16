import { createClient } from '@supabase/supabase-js';

const url = (import.meta.env.VITE_SUPABASE_URL || '').trim();
const key = (import.meta.env.VITE_SUPABASE_ANON_KEY || '').trim();

function isValidSupabaseUrl(value) {
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' && !parsed.hostname.includes('YOUR_PROJECT');
  } catch {
    return false;
  }
}

const isPlaceholderKey = !key || key.startsWith('YOUR_');

export const missingSupabaseConfig = [
  !isValidSupabaseUrl(url) && 'VITE_SUPABASE_URL',
  isPlaceholderKey && 'VITE_SUPABASE_ANON_KEY',
].filter(Boolean);

export const supabaseConfigured = missingSupabaseConfig.length === 0;

export const supabase = supabaseConfigured
  ? createClient(url, key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
    })
  : null;
