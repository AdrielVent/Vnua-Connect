// Public by design: the anon key only allows what the database's row-level security rules allow.
// NEVER put the service_role key here.
window.VNUA_CONFIG = {
  supabaseUrl: 'https://mjxriwbyvfyndrwtqeeh.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qeHJpd2J5dmZ5bmRyd3RxZWVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ2MDE0NzQsImV4cCI6MjExMDE3NzQ3NH0.Xq-pJQpIufLprvihQI-dXV7i-TVa-HSHI5gWrgl3HeE',
  campus: { id: 'hofstra', name: 'Hofstra University', emailDomains: ['hofstra.edu'] },
  // What the sign-in email actually contains: 'code' since Nov 14, 2026 (Gmail SMTP + code-only template,
  // verified with a real code by supabase/setup_gmail_smtp.sh). Use 'link' only if the code template is removed.
  signInEmail: 'code',
};
