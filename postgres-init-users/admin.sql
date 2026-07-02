-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  permissions TEXT NOT NULL,
  password TEXT NOT NULL
);

-- adds default admin user
-- password is bcrypt('admin') — CHANGE IT immediately after first login
INSERT INTO users (name, permissions, password)
VALUES ('admin', 'admin', '$2b$12$tq2tmdtnhR5/UJu/74CZX.SRqLBCED2llJzYUPNNNe7gv6lYR8DoS')
ON CONFLICT (name) DO NOTHING;
