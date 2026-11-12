# KOINOS · SOMOS JÓVENES LDA

Aplicación web completa para la comunidad **SOMOS JÓVENES LDA**. Diseñada mobile-first para usarse desde el celular en encuentros presenciales: registro de miembros, perfil tipo CV, carnet con QR, eventos, escáner de asistencia, alertas pastorales y cuadros de asistencia exportables a Excel.

**Stack:** React 19 · Vite · Tailwind CSS · Supabase (PostgreSQL, Auth, Storage, Realtime) · html5-qrcode · SheetJS · Sonner · Lucide.

---

## 1. Cómo ejecutar

```bash
cd "KOINOS-App"
npm install
npm run dev
```

Abre la URL que muestra Vite (normalmente `http://localhost:5173`).

La app arranca en **modo demostración** si no hay variables de Supabase configuradas. Esto permite probar todo el flujo sin backend:

| Rol | Correo | Contraseña |
| --- | --- | --- |
| Líder | `lider@koinos.app` | `lider123` |
| Maestro | `maestro@koinos.app` | `master123` |

> El modo demo guarda los datos en `localStorage`. El botón **Reiniciar demo** del pie de página restaura los datos iniciales.

Para producción:

```bash
cp .env.example .env
# Edita .env con las credenciales de tu proyecto Supabase
npm run build
npm run preview
```

---

## 2. Conectar Supabase

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. Ve a **SQL Editor** y ejecuta completo el archivo [`supabase/schema.sql`](./supabase/schema.sql). Crea:
   - tablas `members`, `events`, `event_registrations`, `attendance`, `alerts`
   - enums, índices de búsqueda, trigger de alertas por inasistencia
   - políticas RLS
   - buckets `avatars`, `event-covers`, `event-attachments`
   - publicación Realtime
3. Ve a **Project Settings → API** y copia:
   - Project URL
   - Anon public key
4. Crea tu `.env`:

```env
VITE_SUPABASE_URL=https://TU-PROYECTO.supabase.co
VITE_SUPABASE_ANON_KEY=TU_ANON_KEY
VITE_DATA_MODE=supabase
```

5. Crea los usuarios del equipo en **Authentication → Users** (correo + contraseña segura).
6. Vincula cada usuario Auth con su fila en `members` y asígnale rol `leader` o `master`:

```sql
update public.members
set auth_user_id = (select id from auth.users where email = 'lider@tu-dominio.com'),
    role = 'leader'
where lower(trim(full_name)) = lower('Carlos Mendoza');

update public.members
set auth_user_id = (select id from auth.users where email = 'maestro@tu-dominio.com'),
    role = 'master'
where lower(trim(full_name)) = lower('Eduin López');
```

Si todavía no existen esas filas, créalas primero desde la app con el usuario maestro o insértalas manualmente.

7. Ejecuta una vez para calcular alertas históricas:

```sql
select public.refresh_attendance_alerts();
```

### Variables de entorno

| Variable | Descripción |
| --- | --- |
| `VITE_SUPABASE_URL` | URL del proyecto Supabase. |
| `VITE_SUPABASE_ANON_KEY` | Clave pública `anon` (nunca uses `service_role` en el frontend). |
| `VITE_DATA_MODE` | `demo`, `supabase` o `auto`. En `auto` usa Supabase si hay credenciales. |

---

## 3. Roles y reglas de acceso

### Miembro (público, sin contraseña)
- Consulta el directorio completo de personas registradas.
- Crea su perfil con foto carnet, datos personales y CV de comunidad.
- Obtiene un UUID único (`qr_code_data`) y su QR descargable.
- Ve eventos activos y se registra con un clic.
- **No** puede escanear QR ni crear miembros de forma manual.

### Líder (Supabase Auth)
- Todo lo del miembro.
- Botón **ESCANEAR QR DE MIEMBRO** justo después del hero.
- Escáner con cámara (`html5-qrcode`), validación de QR y check verde con foto/nombre.
- Registro manual de nuevos miembros.
- Puede consultar asistencias (lectura) si se habilitan políticas adicionales, pero la matriz está reservada al maestro en la interfaz.

### Maestro (Supabase Auth)
- Todo lo del líder.
- Acceso **siempre** a Eventos, incluso cuando no hay eventos creados.
- Crear / editar / eliminar eventos con portada, adjunto, fechas, hora, lugar y descripción.
- Sección **VER CUADROS DE ASISTENCIA**:
  - matriz de miembros × miércoles/eventos
  - navegación por mes y año
  - edición de celdas (asistió / faltó)
  - alertas por 2 miércoles consecutivos sin asistir
  - exportación `.xlsx`
- Alertas pastorales y actualización manual del motor de alertas.

---

## 4. Estructura del proyecto

```
KOINOS-App/
├── public/
│   ├── hero-koinos.jpg
│   ├── koinos-mark.svg
│   └── demo/                    # portadas, avatares y PDFs de demostración
├── src/
│   ├── App.jsx                  # composición de vistas y modales
│   ├── main.jsx
│   ├── index.css                # Tailwind + estilos globales
│   ├── components/
│   │   ├── MemberDashboard.jsx
│   │   ├── LeaderDashboard.jsx
│   │   ├── MasterDashboard.jsx
│   │   ├── QRScanner.jsx
│   │   ├── AttendanceMatrix.jsx
│   │   ├── EventManager.jsx
│   │   ├── EventsModal.jsx
│   │   ├── RegisterMemberModal.jsx
│   │   ├── MemberLookupModal.jsx
│   │   ├── LoginModal.jsx
│   │   ├── FeatureGrid.jsx
│   │   ├── Hero.jsx / Header.jsx / Footer.jsx
│   │   ├── MemberQRCard.jsx
│   │   ├── ProfileDetails.jsx
│   │   └── ...
│   ├── context/AppContext.jsx   # estado global, auth, realtime
│   └── lib/
│       ├── supabase.js          # cliente y modo de datos
│       ├── db.js                # capa de acceso demo/Supabase
│       ├── seed.js              # datos de demostración
│       ├── utils.js
│       └── demoCredentials.js
├── supabase/schema.sql
├── .env.example
└── README.md
```

La capa `src/lib/db.js` abstrae el backend. En modo demo opera sobre `localStorage`; en modo Supabase usa las tablas, Storage y Realtime reales. Así la UI es idéntica en ambos entornos.

---

## 5. Modelo de datos

- **members**: `id`, `auth_user_id`, `full_name` único, `email`, `role` (`member|leader|master`), `avatar_url`, `qr_code_data` UUID único, `cv_data` JSONB, `consecutive_absences`, `created_at`.
- **events**: `title`, `description`, `start_date`, `end_date`, `event_time`, `location`, `cover_image_url`, `attachment_url`, `created_by`.
- **event_registrations**: `event_id`, `member_id`, `registered_at`, único por evento/miembro.
- **attendance**: `member_id`, `event_id` opcional, `attendance_date`, `status`, `scanned_by`, único por miembro/fecha/evento.
- **alerts**: alerta de inasistencia, con `missed_dates`, `dedupe_key`, `is_read` y `resolved_at`.

### Motor de alertas

El trigger `attendance_recalculate_alerts` recalcula la racha de cada miembro cada vez que cambia su asistencia. Cuenta los miércoles consecutivos sin check-in desde el más reciente hacia atrás y:

- actualiza `members.consecutive_absences`
- crea/actualiza una alerta en `alerts` cuando la racha llega a **2**
- resuelve automáticamente las alertas activas cuando la racha vuelve a 0/1

La función `refresh_attendance_alerts()` permite recalcular todo el histórico desde el panel maestro.

---

## 6. Funcionalidades destacadas

- **Mobile-first**: hero, tarjetas cuadradas, modales tipo bottom-sheet y matriz con scroll horizontal.
- **Carnet QR**: QR de alta densidad (nivel H), descarga PNG y perfil público con CV.
- **Escáner**: cámara trasera, pausa automática tras lectura, confirmación verde, detección de duplicados, entrada manual de UUID y simulación en demo.
- **Eventos**: tarjetas con portada, adjuntos, registro y gestión completa para maestro.
- **Asistencia**: tabla interactiva, navegación mensual, alertas y exportación Excel.
- **Estados**: loaders, esqueletos, toasts con Sonner, mensajes inline y confirmaciones.
- **Realtime**: Supabase Realtime refresca miembros, eventos, registros, asistencia y alertas.
- **Modo demo**: datos semilla ricos (miembros, eventos, asistencias y alertas) para revisar la app sin backend.

---

## 7. Seguridad y producción

- La `service_role` **nunca** debe llegar al navegador. La app solo usa la clave `anon` + RLS.
- Las políticas RLS del esquema permiten lectura pública del directorio y creación pública de perfiles, tal como pide el flujo sin contraseña. Si la privacidad de datos personales es crítica, se recomienda:
  - exponer solo un `view` público con nombre/foto/QR;
  - mover el CV completo detrás de autenticación;
  - limitar la subida anónima a avatares con validación de tamaño/tipo.
- El QR contiene únicamente el UUID público del miembro, no datos personales.
- Los buckets son públicos para lectura (necesario para mostrar fotos/portadas/adjuntos). Si necesitas adjuntos privados, cambia el bucket a privado y usa URLs firmadas.
- Para escanear cámara en producción se requiere **HTTPS** (o `localhost`).
- Configura un dominio permitido en Supabase Auth y revisa los límites de subida de Storage.

---

## 8. Scripts

```bash
npm run dev       # desarrollo
npm run build     # build de producción
npm run preview   # previsualizar build
npm run lint      # oxlint
```

---

## 9. Despliegue en GitHub Pages

El repositorio incluye el workflow [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml). En cada push a `main` compila la app y la publica en GitHub Pages.

### 9.1 Crear el repositorio

El proyecto no está inicializado como repositorio Git. Desde `KOINOS-App`:

```bash
git init
git add .
git commit -m "KOINOS: app completa con Supabase"
git branch -M main
git remote add origin https://github.com/TU-USUARIO/koinos-app.git
```

Crea antes el repositorio vacío en GitHub. **No** marques “Add a README” para evitar conflictos. El repositorio debe ser público (Pages en repos privados requiere GitHub Pro/Team).

> Usa un nombre de repositorio sin espacios, por ejemplo `koinos-app`. El workflow toma ese nombre automáticamente para el `base path` de Vite.

### 9.2 Configurar GitHub Pages

1. En GitHub ve a **Settings → Pages**.
2. En **Build and deployment → Source**, selecciona **GitHub Actions**.
3. Ve a **Settings → Secrets and variables → Actions → New repository secret** y crea:
   - `VITE_SUPABASE_URL` → URL del proyecto Supabase.
   - `VITE_SUPABASE_ANON_KEY` → clave `anon public`.
4. Sube el código:

```bash
git push -u origin main
```

5. Abre la pestaña **Actions** y espera el workflow **Deploy KOINOS to GitHub Pages**.
6. La URL queda como `https://TU-USUARIO.github.io/koinos-app/`.

Si cambias el nombre del repositorio, vuelve a ejecutar el workflow (`Actions → Deploy KOINOS to GitHub Pages → Run workflow`) para regenerar el `base path`.

### 9.3 Autorizar la URL en Supabase

En Supabase ve a **Authentication → URL Configuration**:

- **Site URL:** `https://TU-USUARIO.github.io/koinos-app/`
- **Redirect URLs:** agrega la misma URL y, para desarrollo, `http://localhost:5173/**`.

El login por correo/contraseña no necesita OAuth, pero esta configuración evita bloqueos si más adelante agregas recuperación de contraseña o magic links.

### 9.4 Primer usuario maestro en producción

La base de datos de Supabase arranca vacía (los datos demo solo existen en `localStorage`). Después de crear los usuarios en **Authentication → Users**, ejecuta esto una vez en el **SQL Editor**:

```sql
-- Líder
insert into public.members (auth_user_id, full_name, email, role)
select u.id, 'Carlos Mendoza', u.email, 'leader'
from auth.users u
where u.email = 'lider@tu-dominio.com'
on conflict (auth_user_id) do update
  set role = 'leader',
      full_name = excluded.full_name,
      email = excluded.email;

-- Maestro
insert into public.members (auth_user_id, full_name, email, role)
select u.id, 'Eduin López', u.email, 'master'
from auth.users u
where u.email = 'maestro@tu-dominio.com'
on conflict (auth_user_id) do update
  set role = 'master',
      full_name = excluded.full_name,
      email = excluded.email;

select public.refresh_attendance_alerts();
```

Luego entra a la URL de Pages con esas credenciales. El usuario maestro ya puede crear eventos y registrar miembros; los miembros se registran desde la vista pública.

### 9.5 Problemas frecuentes

| Síntoma | Causa / solución |
| --- | --- |
| Página en blanco o assets 404 | `base path` incorrecto. Verifica que el workflow defina `VITE_BASE_PATH` y vuelve a ejecutarlo. |
| El workflow falla en “Verify Supabase secrets” | Faltan los secrets en GitHub o tienen espacios. |
| Login rechazado | El usuario Auth no está vinculado en `members` o su rol no es `leader`/`master`. |
| La app abre en modo demo | El build no recibió las variables de Supabase. Revisa los secrets y el paso Build. |
| No suben fotos/portadas | Verifica que `supabase/schema.sql` se ejecutó completo (buckets y políticas de Storage). |
| La cámara no abre | GitHub Pages ya usa HTTPS; revisa permisos del navegador. |
| Dominio propio en la raíz | Cambia en el workflow `VITE_BASE_PATH` a `/` y configura el dominio en Pages. |

---

Hecho para la comunidad **SOMOS JÓVENES LDA** · KOINOS.
