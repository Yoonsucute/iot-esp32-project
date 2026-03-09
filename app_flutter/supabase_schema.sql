-- ============================================
-- BƯỚC 1: XÓA BẢNG CŨ
-- ============================================
DROP TABLE IF EXISTS dht_data CASCADE;
DROP TABLE IF EXISTS gas_data CASCADE;
DROP TABLE IF EXISTS device_states CASCADE;

-- ============================================
-- BƯỚC 2: TẠO BẢNG MỚI
-- ============================================

CREATE TABLE public.dht_data (
  id BIGSERIAL PRIMARY KEY,
  temperature DECIMAL(5,2) NOT NULL,
  humidity DECIMAL(5,2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.gas_data (
  id BIGSERIAL PRIMARY KEY,
  mq_ao INTEGER NOT NULL,
  threshold INTEGER NOT NULL,
  gas_alarm BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.device_states (
  id BIGSERIAL PRIMARY KEY,
  device_name VARCHAR(50) NOT NULL,
  state BOOLEAN NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- BƯỚC 3: CẤP QUYỀN CHO ANON ROLE
-- ============================================

-- Cấp quyền sử dụng schema public
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Cấp quyền đầy đủ cho các bảng
GRANT ALL ON public.dht_data TO anon;
GRANT ALL ON public.gas_data TO anon;
GRANT ALL ON public.device_states TO anon;

GRANT ALL ON public.dht_data TO authenticated;
GRANT ALL ON public.gas_data TO authenticated;
GRANT ALL ON public.device_states TO authenticated;

-- Cấp quyền cho sequences (để tự động tăng ID)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================
-- BƯỚC 4: TẮT RLS (Row Level Security)
-- ============================================
ALTER TABLE public.dht_data DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_data DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_states DISABLE ROW LEVEL SECURITY;

-- ============================================
-- BƯỚC 5: TẠO INDEX
-- ============================================
CREATE INDEX idx_dht_created_at ON public.dht_data(created_at DESC);
CREATE INDEX idx_gas_created_at ON public.gas_data(created_at DESC);
CREATE INDEX idx_gas_alarm ON public.gas_data(gas_alarm);
CREATE INDEX idx_device_created_at ON public.device_states(created_at DESC);
CREATE INDEX idx_device_name ON public.device_states(device_name);
