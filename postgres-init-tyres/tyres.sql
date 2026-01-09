CREATE TABLE IF NOT EXISTS tyres (
  id SERIAL PRIMARY KEY,
  brand TEXT,
  model TEXT,
  size TEXT NOT NULL,
  load_rate INT,
  speed_rate TEXT,
  season TEXT,
  supplier TEXT,
  fuel_efficiency TEXT,
  noise_level INT,
  weather_efficiency TEXT,
  ev_approved BOOLEAN,
  cost NUMERIC(10,2),
    retail_cost NUMERIC(10,2),
  quantity INT
);

CREATE UNIQUE INDEX IF NOT EXISTS tyres_unique_idx
ON tyres (brand, model, size, load_rate, speed_rate, season, supplier, cost);

CREATE TABLE IF NOT EXISTS tyres_staging (
  size TEXT,
  load_rate TEXT,
  speed_rate TEXT,
  "Brand" TEXT,
  "Model" TEXT,
  "Season" TEXT,
  "Supplier" TEXT,
  "Fuel_Efficiency" TEXT,
  noise_level TEXT,
  weather_efficiency TEXT,
  ev_approved TEXT,
  cost TEXT,
  quantity TEXT
);

TRUNCATE tyres_staging;

COPY tyres_staging
FROM '/docker-entrypoint-initdb.d/tyredatabase.csv'
WITH (FORMAT csv, HEADER true);

-- Insert cleaned + compute retail_cost = cost * 1.35
INSERT INTO tyres (
  brand, model, size, load_rate, speed_rate, season, supplier,
  fuel_efficiency, noise_level, weather_efficiency, ev_approved,
  cost, quantity, retail_cost
)
SELECT
  NULLIF(trim("Brand"), ''),
  NULLIF(trim("Model"), ''),
  NULLIF(trim(size), ''),
  NULLIF(trim(load_rate), '')::INT,
  NULLIF(trim(speed_rate), ''),
  NULLIF(trim("Season"), ''),
  NULLIF(trim("Supplier"), ''),
  NULLIF(trim("Fuel_Efficiency"), ''),
  NULLIF(trim(noise_level), '')::INT,
  NULLIF(trim(weather_efficiency), ''),
  CASE
    WHEN lower(coalesce(ev_approved,'')) IN ('true','t','1','yes','y') THEN TRUE
    ELSE FALSE
  END,
  NULLIF(trim(cost), '')::NUMERIC(10,2),
  NULLIF(trim(quantity), '')::INT,
  ROUND((NULLIF(trim(cost), '')::NUMERIC(10,2) * 1.35), 2)
FROM tyres_staging
ON CONFLICT (brand, model, size, load_rate, speed_rate, season, supplier, cost)
DO UPDATE SET
  quantity = EXCLUDED.quantity,
  retail_cost = EXCLUDED.retail_cost;
