-- ═══════════════════════════════════════════════════════════════════
-- SUEÑOS INMOBILIARIOS — CRM COMPLETO
-- Setup SQL para Supabase
-- Ejecuta en: Supabase → SQL Editor → New Query → Run
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 0. EXTENSIONES
-- ─────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────
-- 1. USUARIOS (perfil extendido de auth.users)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usuarios (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  nombre        TEXT,
  rol           TEXT NOT NULL DEFAULT 'asesor' CHECK (rol IN ('admin','asesor','editor')),
  activo        BOOLEAN DEFAULT true,
  avatar_url    TEXT,
  telefono      TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  ultimo_acceso TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-crear perfil al registrarse
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO usuarios (id, email, nombre, rol)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'nombre', split_part(NEW.email,'@',1)), 'asesor')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ─────────────────────────────────────────────
-- 2. PROPIETARIOS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS propietarios (
  id                    BIGSERIAL PRIMARY KEY,
  nombre                TEXT NOT NULL,
  telefono              TEXT,
  email                 TEXT,
  ciudad                TEXT,
  direccion_propiedad   TEXT,
  descripcion_propiedad TEXT,
  precio_pedido         NUMERIC(15,0),
  precio_negociado      NUMERIC(15,0),
  estado                TEXT DEFAULT 'contactado'
                        CHECK (estado IN ('contactado','negociacion','contrato','cerrado','inactivo')),
  exclusividad          BOOLEAN DEFAULT false,
  fecha_exclusividad    DATE,
  notas                 TEXT,
  asesor_id             UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 3. PROPIEDADES (ampliada)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS propiedades (
  id                BIGSERIAL PRIMARY KEY,
  titulo            TEXT NOT NULL,
  descripcion       TEXT,
  tipo              TEXT DEFAULT 'Apartamento',
  ciudad            TEXT,
  barrio            TEXT,
  direccion         TEXT,
  precio            NUMERIC(15,0),
  precio_negociable BOOLEAN DEFAULT false,
  area              INTEGER,
  habitaciones      INTEGER DEFAULT 0,
  banos             INTEGER DEFAULT 1,
  estrato           TEXT,
  parqueadero       TEXT,
  piso              TEXT,
  antiguedad        TEXT,
  permuta           BOOLEAN DEFAULT false,
  caracteristicas   TEXT,   -- JSON array
  imagenes          TEXT,   -- JSON array de URLs
  videos            TEXT,   -- JSON array de URLs
  activo            BOOLEAN DEFAULT true,
  vendido           BOOLEAN DEFAULT false,
  destacado         BOOLEAN DEFAULT false,
  seo_titulo        TEXT,
  seo_desc          TEXT,
  slug              TEXT,
  negociacion       TEXT,
  asesor_id         UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  propietario_id    BIGINT REFERENCES propietarios(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 4. CLIENTES
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
  id                BIGSERIAL PRIMARY KEY,
  nombre            TEXT NOT NULL,
  apellido          TEXT,
  email             TEXT,
  telefono          TEXT,
  whatsapp          TEXT,
  tipo              TEXT DEFAULT 'comprador'
                    CHECK (tipo IN ('comprador','vendedor','inversionista')),
  estado            TEXT DEFAULT 'activo'
                    CHECK (estado IN ('activo','en_proceso','cerrado','inactivo')),
  ciudad            TEXT,
  presupuesto_min   NUMERIC(15,0),
  presupuesto_max   NUMERIC(15,0),
  tipo_busqueda     TEXT,   -- "3 hab, Pereira, estrato 4"
  notas             TEXT,
  score             INTEGER DEFAULT 0 CHECK (score >= 0 AND score <= 100),
  asesor_id         UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 5. LEADS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS leads (
  id           BIGSERIAL PRIMARY KEY,
  nombre       TEXT NOT NULL,
  telefono     TEXT,
  email        TEXT,
  ciudad       TEXT,
  interes      TEXT,
  presupuesto  TEXT,
  origen       TEXT DEFAULT 'landing'
               CHECK (origen IN ('landing','whatsapp','instagram','facebook','referido','llamada','otro')),
  estado       TEXT DEFAULT 'nuevo'
               CHECK (estado IN ('nuevo','contactado','calificado','propuesta','negociacion','cerrado','perdido')),
  notas        TEXT,
  utm_source   TEXT,
  utm_medium   TEXT,
  utm_campaign TEXT,
  cliente_id   BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  asesor_id    UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 6. NEGOCIOS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS negocios (
  id                    BIGSERIAL PRIMARY KEY,
  titulo                TEXT NOT NULL,
  tipo                  TEXT DEFAULT 'venta' CHECK (tipo IN ('venta','permuta')),
  estado                TEXT DEFAULT 'abierto'
                        CHECK (estado IN ('abierto','en_proceso','ganado','perdido','cancelado')),
  etapa_pipeline        TEXT DEFAULT 'inicio',
  valor_estimado        NUMERIC(15,0),
  valor_final           NUMERIC(15,0),
  comision_pct          NUMERIC(5,2) DEFAULT 3.0,
  comision_valor        NUMERIC(15,0),
  cliente_id            BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  propiedad_id          BIGINT REFERENCES propiedades(id) ON DELETE SET NULL,
  asesor_id             UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  fecha_cierre_estimada DATE,
  fecha_cierre_real     DATE,
  notas                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 7. INTERACCIONES (historial CRM)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS interacciones (
  id           BIGSERIAL PRIMARY KEY,
  tipo         TEXT DEFAULT 'nota'
               CHECK (tipo IN ('llamada','whatsapp','email','visita','nota','reunion')),
  descripcion  TEXT NOT NULL,
  duracion_min INTEGER,
  cliente_id   BIGINT NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  negocio_id   BIGINT REFERENCES negocios(id) ON DELETE SET NULL,
  asesor_id    UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 8. EVENTOS (Agenda/Calendario)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS eventos (
  id                      BIGSERIAL PRIMARY KEY,
  titulo                  TEXT NOT NULL,
  tipo                    TEXT DEFAULT 'visita'
                          CHECK (tipo IN ('visita','reunion','llamada','tarea','otro')),
  fecha                   DATE NOT NULL,
  hora_inicio             TIME,
  hora_fin                TIME,
  estado                  TEXT DEFAULT 'pendiente'
                          CHECK (estado IN ('pendiente','completado','cancelado')),
  cliente_id              BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  propiedad_id            BIGINT REFERENCES propiedades(id) ON DELETE SET NULL,
  negocio_id              BIGINT REFERENCES negocios(id) ON DELETE SET NULL,
  asesor_id               UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  notas                   TEXT,
  recordatorio_enviado    BOOLEAN DEFAULT false,
  google_calendar_event_id TEXT,  -- Reservado para integración futura
  created_at              TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 9. TAREAS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tareas (
  id               BIGSERIAL PRIMARY KEY,
  titulo           TEXT NOT NULL,
  descripcion      TEXT,
  prioridad        TEXT DEFAULT 'media' CHECK (prioridad IN ('alta','media','baja')),
  estado           TEXT DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','en_proceso','completada','cancelada')),
  fecha_vencimiento DATE,
  asignado_a       UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  creado_por       UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  cliente_id       BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  negocio_id       BIGINT REFERENCES negocios(id) ON DELETE SET NULL,
  propiedad_id     BIGINT REFERENCES propiedades(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 10. DOCUMENTOS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS documentos (
  id                BIGSERIAL PRIMARY KEY,
  nombre            TEXT NOT NULL,
  tipo              TEXT DEFAULT 'otro'
                    CHECK (tipo IN ('contrato','promesa','escritura','identificacion','certificado','otro')),
  url               TEXT NOT NULL,
  tamaño_bytes      BIGINT,
  mime_type         TEXT,
  cliente_id        BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  negocio_id        BIGINT REFERENCES negocios(id) ON DELETE SET NULL,
  propiedad_id      BIGINT REFERENCES propiedades(id) ON DELETE SET NULL,
  subido_por        UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  firma_digital_id  TEXT,  -- Reservado para integración futura (DocuSign, etc.)
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 11. TESTIMONIOS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS testimonios (
  id               BIGSERIAL PRIMARY KEY,
  nombre_cliente   TEXT NOT NULL,
  tipo_operacion   TEXT,
  puntuacion       INTEGER DEFAULT 5 CHECK (puntuacion BETWEEN 1 AND 5),
  comentario       TEXT,
  visible          BOOLEAN DEFAULT true,
  cliente_id       BIGINT REFERENCES clientes(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 12. ARTÍCULOS (Blog)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS articulos (
  id             BIGSERIAL PRIMARY KEY,
  titulo         TEXT NOT NULL,
  slug           TEXT,
  categoria      TEXT DEFAULT 'Consejos',
  estado         TEXT DEFAULT 'borrador' CHECK (estado IN ('borrador','publicado','archivado')),
  resumen        TEXT,
  contenido      TEXT,
  imagen_portada TEXT,
  seo_titulo     TEXT,
  seo_desc       TEXT,
  autor_id       UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 13. VIDEOS (Academia)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS videos (
  id             BIGSERIAL PRIMARY KEY,
  titulo         TEXT NOT NULL,
  descripcion    TEXT,
  duracion       TEXT,
  nivel          TEXT DEFAULT 'Básico' CHECK (nivel IN ('Básico','Intermedio','Avanzado')),
  url_video      TEXT,
  url_miniatura  TEXT,
  orden          INTEGER DEFAULT 0,
  activo         BOOLEAN DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- 14. NOTIFICACIONES
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notificaciones (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  UUID REFERENCES usuarios(id) ON DELETE CASCADE,
  tipo        TEXT,
  titulo      TEXT NOT NULL,
  mensaje     TEXT,
  leida       BOOLEAN DEFAULT false,
  link        TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════
-- TRIGGERS: updated_at automático
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['propiedades','propietarios','clientes','leads','negocios','tareas','articulos','usuarios']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_updated_at ON %I', tbl);
    EXECUTE format('CREATE TRIGGER trg_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()', tbl);
  END LOOP;
END $$;

-- Auto-calcular comision_valor en negocios
CREATE OR REPLACE FUNCTION calc_comision()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.valor_final IS NOT NULL AND NEW.comision_pct IS NOT NULL THEN
    NEW.comision_valor := ROUND(NEW.valor_final * NEW.comision_pct / 100);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_comision ON negocios;
CREATE TRIGGER trg_comision
  BEFORE INSERT OR UPDATE ON negocios
  FOR EACH ROW EXECUTE FUNCTION calc_comision();

-- ═══════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════

-- Habilitar RLS en todas las tablas
ALTER TABLE usuarios       ENABLE ROW LEVEL SECURITY;
ALTER TABLE propiedades    ENABLE ROW LEVEL SECURITY;
ALTER TABLE propietarios   ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads          ENABLE ROW LEVEL SECURITY;
ALTER TABLE negocios       ENABLE ROW LEVEL SECURITY;
ALTER TABLE interacciones  ENABLE ROW LEVEL SECURITY;
ALTER TABLE eventos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tareas         ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos     ENABLE ROW LEVEL SECURITY;
ALTER TABLE testimonios    ENABLE ROW LEVEL SECURITY;
ALTER TABLE articulos      ENABLE ROW LEVEL SECURITY;
ALTER TABLE videos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;

-- ── FUNCIÓN HELPER: obtener rol del usuario actual ──
CREATE OR REPLACE FUNCTION get_my_rol()
RETURNS TEXT AS $$
  SELECT rol FROM usuarios WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ── PROPIEDADES ──
-- Lectura pública (landing): solo activas y no vendidas
DROP POLICY IF EXISTS "props_public_read"   ON propiedades;
DROP POLICY IF EXISTS "props_auth_read"     ON propiedades;
DROP POLICY IF EXISTS "props_auth_insert"   ON propiedades;
DROP POLICY IF EXISTS "props_auth_update"   ON propiedades;
DROP POLICY IF EXISTS "props_admin_delete"  ON propiedades;

CREATE POLICY "props_public_read"  ON propiedades FOR SELECT
  USING (activo = true AND vendido = false);

CREATE POLICY "props_auth_read"    ON propiedades FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "props_auth_insert"  ON propiedades FOR INSERT
  TO authenticated WITH CHECK (true);

CREATE POLICY "props_auth_update"  ON propiedades FOR UPDATE
  TO authenticated USING (
    get_my_rol() = 'admin'
    OR asesor_id = auth.uid()
    OR get_my_rol() = 'editor'
  );

CREATE POLICY "props_admin_delete" ON propiedades FOR DELETE
  TO authenticated USING (get_my_rol() = 'admin');

-- ── CLIENTES ──
DROP POLICY IF EXISTS "clientes_read"   ON clientes;
DROP POLICY IF EXISTS "clientes_insert" ON clientes;
DROP POLICY IF EXISTS "clientes_update" ON clientes;
DROP POLICY IF EXISTS "clientes_delete" ON clientes;

CREATE POLICY "clientes_read" ON clientes FOR SELECT
  TO authenticated USING (
    get_my_rol() = 'admin'
    OR asesor_id = auth.uid()
  );

CREATE POLICY "clientes_insert" ON clientes FOR INSERT
  TO authenticated WITH CHECK (true);

CREATE POLICY "clientes_update" ON clientes FOR UPDATE
  TO authenticated USING (
    get_my_rol() = 'admin' OR asesor_id = auth.uid()
  );

CREATE POLICY "clientes_delete" ON clientes FOR DELETE
  TO authenticated USING (get_my_rol() = 'admin');

-- ── LEADS ──
DROP POLICY IF EXISTS "leads_read"   ON leads;
DROP POLICY IF EXISTS "leads_insert" ON leads;
DROP POLICY IF EXISTS "leads_update" ON leads;
DROP POLICY IF EXISTS "leads_delete" ON leads;

CREATE POLICY "leads_read" ON leads FOR SELECT
  TO authenticated USING (
    get_my_rol() = 'admin' OR asesor_id = auth.uid()
  );

CREATE POLICY "leads_insert" ON leads FOR INSERT
  TO authenticated WITH CHECK (true);

-- También permite que la landing inserte leads (anon)
CREATE POLICY "leads_public_insert" ON leads FOR INSERT
  WITH CHECK (true);

CREATE POLICY "leads_update" ON leads FOR UPDATE
  TO authenticated USING (
    get_my_rol() = 'admin' OR asesor_id = auth.uid()
  );

CREATE POLICY "leads_delete" ON leads FOR DELETE
  TO authenticated USING (get_my_rol() = 'admin');

-- ── NEGOCIOS ──
DROP POLICY IF EXISTS "negocios_read"   ON negocios;
DROP POLICY IF EXISTS "negocios_write"  ON negocios;
DROP POLICY IF EXISTS "negocios_delete" ON negocios;

CREATE POLICY "negocios_read" ON negocios FOR SELECT
  TO authenticated USING (
    get_my_rol() = 'admin' OR asesor_id = auth.uid()
  );

CREATE POLICY "negocios_write" ON negocios FOR ALL
  TO authenticated USING (
    get_my_rol() = 'admin' OR asesor_id = auth.uid()
  ) WITH CHECK (true);

-- ── TODAS LAS DEMÁS TABLAS: solo autenticados ──
DO $$
DECLARE tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['propietarios','interacciones','eventos','tareas','documentos','notificaciones']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "auth_all" ON %I', tbl);
    EXECUTE format('CREATE POLICY "auth_all" ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)', tbl);
  END LOOP;
END $$;

-- Testimonios: lectura pública de visibles
DROP POLICY IF EXISTS "test_public"  ON testimonios;
DROP POLICY IF EXISTS "test_auth"    ON testimonios;
CREATE POLICY "test_public" ON testimonios FOR SELECT USING (visible = true);
CREATE POLICY "test_auth"   ON testimonios FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Artículos: lectura pública de publicados
DROP POLICY IF EXISTS "arts_public" ON articulos;
DROP POLICY IF EXISTS "arts_auth"   ON articulos;
CREATE POLICY "arts_public" ON articulos FOR SELECT USING (estado = 'publicado');
CREATE POLICY "arts_auth"   ON articulos FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Videos: lectura pública de activos
DROP POLICY IF EXISTS "videos_public" ON videos;
DROP POLICY IF EXISTS "videos_auth"   ON videos;
CREATE POLICY "videos_public" ON videos FOR SELECT USING (activo = true);
CREATE POLICY "videos_auth"   ON videos FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Usuarios: cada uno ve el suyo; admin ve todos
DROP POLICY IF EXISTS "usuarios_read"   ON usuarios;
DROP POLICY IF EXISTS "usuarios_update" ON usuarios;
CREATE POLICY "usuarios_read" ON usuarios FOR SELECT
  TO authenticated USING (id = auth.uid() OR get_my_rol() = 'admin');
CREATE POLICY "usuarios_update" ON usuarios FOR UPDATE
  TO authenticated USING (id = auth.uid() OR get_my_rol() = 'admin');

-- ═══════════════════════════════════════════════════════════════════
-- STORAGE BUCKETS
-- ═══════════════════════════════════════════════════════════════════

-- Fotos de propiedades (público)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('propiedades-fotos', 'propiedades-fotos', true, 10485760,
  ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO NOTHING;

-- Documentos CRM (privado)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('documentos-crm', 'documentos-crm', false, 52428800,
  ARRAY['application/pdf','image/jpeg','image/png','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
ON CONFLICT (id) DO NOTHING;

-- Políticas storage
DROP POLICY IF EXISTS "fotos_public_read"  ON storage.objects;
DROP POLICY IF EXISTS "fotos_auth_upload"  ON storage.objects;
DROP POLICY IF EXISTS "fotos_auth_delete"  ON storage.objects;
DROP POLICY IF EXISTS "docs_auth_all"      ON storage.objects;

CREATE POLICY "fotos_public_read"  ON storage.objects FOR SELECT
  USING (bucket_id = 'propiedades-fotos');
CREATE POLICY "fotos_auth_upload"  ON storage.objects FOR INSERT
  TO authenticated WITH CHECK (bucket_id = 'propiedades-fotos');
CREATE POLICY "fotos_auth_delete"  ON storage.objects FOR DELETE
  TO authenticated USING (bucket_id = 'propiedades-fotos');
CREATE POLICY "docs_auth_all"      ON storage.objects FOR ALL
  TO authenticated USING (bucket_id = 'documentos-crm') WITH CHECK (bucket_id = 'documentos-crm');

-- ═══════════════════════════════════════════════════════════════════
-- DATOS DE EJEMPLO
-- ═══════════════════════════════════════════════════════════════════

-- Propiedades de ejemplo
INSERT INTO propiedades (titulo,tipo,ciudad,barrio,precio,area,habitaciones,banos,estrato,parqueadero,descripcion,activo,vendido,destacado,caracteristicas,imagenes)
VALUES
  ('Apartamento Pinares','Apartamento','Pereira','Pinares',380000000,85,3,2,'Estrato 4','1 parqueadero','Hermoso apartamento en el exclusivo sector de Pinares con acabados premium y vista panorámica.',true,false,true,'["🚗 Garaje","🔐 Conjunto cerrado","🛗 Ascensor","🌇 Vista panorámica"]','[]'),
  ('Casa El Poblado','Casa','Pereira','El Poblado',650000000,180,4,3,'Estrato 5','2 parqueaderos','Amplia casa en conjunto residencial cerrado con jardín privado y estudio.',true,false,false,'["🚗 Garaje doble","🌿 Jardín privado","🔐 Conjunto cerrado","⚡ Planta eléctrica"]','[]'),
  ('Finca Vereda Termales','Finca','Santa Rosa de Cabal','Vereda Termales',750000000,320,4,3,'Rural','Amplio','Espectacular finca rodeada de naturaleza con cultivos y zona de descanso.',true,false,true,'["🌿 Jardín extenso","🏊 Zona piscina","🌾 Cultivos","🏔️ Vista montañas"]','[]'),
  ('Apartamento Dosquebradas','Apartamento','Dosquebradas','Centro',220000000,55,2,1,'Estrato 3','1 parqueadero','Moderno apartamento cerca de centros comerciales.',false,true,false,'["🚗 Parqueadero","🛗 Ascensor","🔆 Balcón"]','[]'),
  ('Oficina Álamos','Oficina','Pereira','Álamos',310000000,65,0,2,'Estrato 4','2 parqueaderos','Moderna oficina en edificio corporativo con sala de juntas.',true,false,false,'["🚗 2 Parqueaderos","🛗 Ascensor","🌇 Vista ciudad"]','[]')
ON CONFLICT DO NOTHING;

-- Testimonios de ejemplo
INSERT INTO testimonios (nombre_cliente,tipo_operacion,puntuacion,comentario,visible)
VALUES
  ('Carlos M.','Compra apartamento',5,'Excelente servicio, muy profesionales. Encontraron el apartamento perfecto para mi familia.',true),
  ('Ana R.','Venta casa',5,'Vendieron mi casa en 30 días al precio que pedía. Increíble equipo.',true),
  ('Roberto S.','Inversión finca',5,'Tercera propiedad que compro con ellos. La mejor inmobiliaria del Eje Cafetero.',true)
ON CONFLICT DO NOTHING;

-- Videos academia de ejemplo
INSERT INTO videos (titulo,nivel,duracion,url_video,orden,activo)
VALUES
  ('Cómo comprar tu primera propiedad','Básico','12 min','',1,true),
  ('Crédito hipotecario paso a paso','Intermedio','18 min','',2,true),
  ('¿Qué es una permuta inmobiliaria?','Básico','10 min','',3,true),
  ('Cómo invertir en bienes raíces','Avanzado','22 min','',4,true),
  ('Cómo valuar correctamente un inmueble','Avanzado','15 min','',5,true)
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN FINAL
-- ═══════════════════════════════════════════════════════════════════
SELECT
  tablename AS tabla,
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_name = t.tablename AND table_schema = 'public') AS columnas
FROM pg_tables t
WHERE schemaname = 'public'
  AND tablename IN ('usuarios','propiedades','propietarios','clientes','leads',
                    'negocios','interacciones','eventos','tareas','documentos',
                    'testimonios','articulos','videos','notificaciones')
ORDER BY tablename;
