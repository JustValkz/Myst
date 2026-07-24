import { createClient } from '@supabase/supabase-js';

const supabaseUrl =
  process.env.SUPABASE_URL || 'https://nxgjwtrqhrgpszpuzmkp.supabase.co';

const supabaseKey =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54Z2p3dHJxaHJncHN6cHV6bWtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NDA0NzAsImV4cCI6MjA5OTIxNjQ3MH0.NvHzqLnM8PygEwezUt3m4GqmL8sNjnbEG0YJyEkK-IE';

export const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false
  }
});
