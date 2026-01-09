CREATE TABLE IF NOT EXISTS tyres (
  id SERIAL PRIMARY KEY,
  size TEXT NOT NULL,
  load_rate INT,
  speed_rate TEXT,
  brand TEXT,
  model TEXT,
  season TEXT,
  supplier TEXT,
  fuel_efficiency TEXT,
  noise_level INT,
  weather_efficiency TEXT,
  ev_approved BOOLEAN,
  cost NUMERIC(10,2),
  quantity INT
);

CREATE UNIQUE INDEX IF NOT EXISTS tyres_unique_idx
ON tyres (size, load_rate, speed_rate, brand, model, season, supplier, cost);

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

INSERT INTO tyres (
  size, load_rate, speed_rate, brand, model, season, supplier,
  fuel_efficiency, noise_level, weather_efficiency, ev_approved, cost, quantity
)
SELECT
  size,
  NULLIF(load_rate, '')::INT,
  NULLIF(speed_rate, ''),
  NULLIF("Brand", ''),
  NULLIF("Model", ''),
  NULLIF("Season", ''),
  NULLIF("Supplier", ''),
  NULLIF("Fuel_Efficiency", ''),
  NULLIF(noise_level, '')::INT,
  NULLIF(weather_efficiency, ''),
  CASE
    WHEN lower(coalesce(ev_approved,'')) IN ('true','t','1','yes','y') THEN TRUE
    ELSE FALSE
  END,
  NULLIF(cost, '')::NUMERIC(10,2),
  NULLIF(quantity, '')::INT
FROM tyres_staging
ON CONFLICT (size, load_rate, speed_rate, brand, model, season, supplier, cost)
DO UPDATE SET quantity = EXCLUDED.quantity;
