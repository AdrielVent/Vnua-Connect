// Public by design: the anon key only allows what the database's row-level security rules allow.
// NEVER put the service_role key here.
window.VNUA_CONFIG = {
  supabaseUrl: 'https://mjxriwbyvfyndrwtqeeh.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qeHJpd2J5dmZ5bmRyd3RxZWVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ2MDE0NzQsImV4cCI6MjExMDE3NzQ3NH0.Xq-pJQpIufLprvihQI-dXV7i-TVa-HSHI5gWrgl3HeE',
  campus: { id: 'hofstra', name: 'Hofstra University', emailDomains: ['hofstra.edu'] },
  // What the sign-in email actually contains. 'link' = Supabase's built-in email (today).
  // Switch to 'code' ONLY after custom SMTP + the code template are set up and a real code has been received.
  signInEmail: 'link',
};
