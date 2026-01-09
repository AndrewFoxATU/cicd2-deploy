-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  permissions TEXT NOT NULL,
  password TEXT NOT NULL
);

-- adds default admin user
INSERT INTO users (name, permissions, password)
VALUES ('admin', 'admin', 'admin')
ON CONFLICT (name) DO NOTHING;
