-- =====================================================================
-- LotC4Pa — CAMINO 1 (seguridad), ETAPA 3
-- "Cerrar permisos RLS tabla por tabla, probando cada una antes de seguir"
-- =====================================================================
--
-- QUÉ HACE ESTE ARCHIVO
-- Hoy cualquiera que copie la llave pública de Supabase (que está a la
-- vista en el código, como en toda app 100% frontend) puede ESCRIBIR y
-- BORRAR libremente en `vendedores`, `sorteos`, `resultados` y
-- `app_config`. Esta etapa cierra exactamente eso: después de correrlo,
-- solo quien entró con una CUENTA REAL de Supabase (las que se crearon en
-- la etapa 1) puede modificar esas tablas — y solo si es el administrador
-- (o un vendedor con el módulo de Resultados delegado).
--
-- QUÉ **NO** HACE (a propósito)
-- No cierra la LECTURA de ninguna tabla. Mientras el login viejo siga
-- encendido, la app necesita leer `vendedores` y `app_config` ANTES de que
-- alguien inicie sesión (así es como compara la contraseña). Cerrar la
-- lectura es justamente la etapa 4, junto con apagar el login viejo.
-- Tampoco toca `folio_counter`, `ventas`, `liquidaciones`, `deudas_equipo`,
-- `asistencia_equipo`, `coberturas`, `registro_cambios` ni
-- `push_subscriptions`: en esas escriben los vendedores en cada venta, y
-- muchos todavía entran por el login viejo (sin cuenta real). Cerrarlas
-- ahora dejaría a un vendedor sin poder vender — el peor error posible.
-- Ver el bloque final "LO QUE QUEDA PARA LA ETAPA 4".
--
-- CÓMO CORRERLO  ⚠️ NO lo pegues todo de una vez.
-- 1. Corre el BLOQUE 0 (funciones de apoyo). No cambia ningún permiso.
-- 2. Corre el BLOQUE 1 (sorteos). Prueba en la app (ver "PRUEBA" del
--    bloque). Si algo falla, corre el "DESHACER" de ese bloque y avisa.
-- 3. Recién cuando el bloque 1 quedó probado, sigue con el 2, luego el 3
--    y el 4. Uno por vez, probando entre uno y otro.
-- 4. Antes de empezar: sube primero el `index.html` de esta misma entrega.
--    Trae los avisos claros de "no tienes permiso" y el probador de
--    permisos (Administración → Seguridad). Con el HTML viejo, un permiso
--    cerrado se ve como si hubiera guardado bien cuando en realidad no
--    guardó nada.
-- 5. Hazlo en un rato de poca venta y con la app abierta para probar.
--
-- REQUISITO: el administrador tiene que entrar con su CUENTA REAL
-- (la que se creó en la etapa 1, usuario `admin`). Si entra por el login
-- viejo, después de esta etapa no va a poder guardar nada — la app se lo
-- va a avisar con un letrero amarillo arriba.
-- =====================================================================


-- =====================================================================
-- BLOQUE 0 — FUNCIONES DE APOYO (no cambia ningún permiso todavía)
-- =====================================================================

-- Columna opcional: si la cuenta real del administrador usa un correo que
-- NO es admin@lotc4pa.app (por ejemplo un Gmail), agrégalo a esta lista y
-- seguirá siendo reconocido como admin. Ejemplo al final del bloque.
alter table public.app_config
  add column if not exists admins_auth jsonb not null default '[]'::jsonb;

-- Columna opcional: si un vendedor tiene su cuenta real con un correo
-- distinto de usuario@lotc4pa.app, se anota aquí para poder relacionarlo.
alter table public.vendedores
  add column if not exists auth_email text;

-- Correo completo de quien está haciendo la petición ('' si es anónimo).
create or replace function public.correo_auth()
returns text
language sql
stable
as $$
  select lower(coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''))
$$;

-- La parte de antes del @ (así se creó cada cuenta en la etapa 1:
-- usuario@lotc4pa.app), que es lo que relaciona la cuenta real con la
-- fila de `vendedores`.
create or replace function public.usuario_auth()
returns text
language sql
stable
as $$
  select lower(split_part(public.correo_auth(), '@', 1))
$$;

-- ¿Quien pide es el administrador?
-- Se acepta como admin si su cuenta real es:
--   a) usuario "admin", o
--   b) el usuario de admin guardado en app_config (por si se cambió), o
--   c) un correo anotado a mano en app_config.admins_auth.
-- Es SECURITY DEFINER para poder leer app_config sin depender de las
-- políticas de esa tabla (si no, se mordería la cola).
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.correo_auth() <> ''
    and (
      public.usuario_auth() = 'admin'
      or exists (
        select 1 from public.app_config c
        where c.id = 1 and lower(c.admin_username) = public.usuario_auth()
      )
      or exists (
        select 1 from public.app_config c
        where c.id = 1 and c.admins_auth ? public.correo_auth()
      )
    )
$$;

-- ¿Quien pide es un vendedor con un módulo delegado?
-- (`permisos_extra` es la misma lista que se marca en Administración →
-- Usuarios; se usa to_jsonb para que funcione igual si la columna es
-- jsonb o si es text[]).
create or replace function public.tiene_modulo(p_modulo text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.correo_auth() <> ''
    and exists (
      select 1 from public.vendedores v
      where (
              lower(v.username) = public.usuario_auth()
              or lower(coalesce(v.auth_email, '')) = public.correo_auth()
            )
        and coalesce(to_jsonb(v.permisos_extra), '[]'::jsonb) ? p_modulo
    )
$$;

-- Migración de contraseñas viejas (camino 2) para cuando `vendedores` y
-- `app_config` ya no acepten escrituras desde el login viejo.
-- Solo cambia la contraseña si quien llama YA demostró saber la
-- contraseña vieja (la manda en texto y tiene que coincidir con la que
-- está guardada). Si no coincide, no hace nada y devuelve false.
create or replace function public.migrar_password_legacy(
  p_usuario text,
  p_password_plano text,
  p_password_hash text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_user text;
  v_guardada text;
  v_id public.vendedores.id%type;
begin
  if coalesce(p_usuario,'') = '' or coalesce(p_password_plano,'') = ''
     or coalesce(p_password_hash,'') = '' then
    return false;
  end if;

  select admin_username, admin_password into v_admin_user, v_guardada
    from public.app_config where id = 1;

  if v_admin_user is not null and v_admin_user = p_usuario then
    if v_guardada = p_password_plano then
      update public.app_config set admin_password = p_password_hash where id = 1;
      return true;
    end if;
    return false;
  end if;

  select v.id, v.password into v_id, v_guardada
    from public.vendedores v where v.username = p_usuario limit 1;

  if v_id is not null and v_guardada = p_password_plano then
    update public.vendedores set password = p_password_hash where id = v_id;
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.migrar_password_legacy(text, text, text) from public;
grant execute on function public.migrar_password_legacy(text, text, text) to anon, authenticated;
grant execute on function public.es_admin() to anon, authenticated;
grant execute on function public.tiene_modulo(text) to anon, authenticated;
grant execute on function public.correo_auth() to anon, authenticated;
grant execute on function public.usuario_auth() to anon, authenticated;

-- PRUEBA DEL BLOQUE 0 (opcional, en el editor SQL):
--   select public.es_admin();          -- false acá (el editor no es un usuario de la app)
--   select public.usuario_auth();      -- '' acá
-- Nada de la app cambia todavía con este bloque.
--
-- Si la cuenta real del admin usa OTRO correo, agrégalo así (una sola vez):
--   update public.app_config
--      set admins_auth = '["elcorreoquesea@gmail.com"]'::jsonb
--    where id = 1;
--
-- DESHACER BLOQUE 0 (casi nunca hace falta: no cierra nada):
--   drop function if exists public.migrar_password_legacy(text, text, text);
--   drop function if exists public.tiene_modulo(text);
--   drop function if exists public.es_admin();
--   drop function if exists public.usuario_auth();
--   drop function if exists public.correo_auth();


-- =====================================================================
-- BLOQUE 1 — TABLA `sorteos`
-- Leer: cualquiera (igual que hoy — se cierra en la etapa 4).
-- Crear / editar / borrar: SOLO el admin con cuenta real.
-- =====================================================================

alter table public.sorteos enable row level security;

-- Borra las políticas viejas (las abiertas de par en par). Si quedara una
-- sola con `using (true)`, seguiría dejando pasar todo — por eso se
-- limpian todas antes de crear las nuevas.
do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'sorteos'
  loop
    execute format('drop policy %I on public.sorteos', p.policyname);
  end loop;
end $$;

create policy sorteos_leer_todos on public.sorteos
  for select using (true);

create policy sorteos_insertar_admin on public.sorteos
  for insert with check ((select public.es_admin()));

create policy sorteos_actualizar_admin on public.sorteos
  for update using ((select public.es_admin()))
  with check ((select public.es_admin()));

create policy sorteos_borrar_admin on public.sorteos
  for delete using ((select public.es_admin()));

-- Cinturón y tirantes: además de las políticas, se le quita al rol
-- anónimo el permiso de escribir en la tabla.
revoke insert, update, delete, truncate on public.sorteos from anon;

-- PRUEBA DEL BLOQUE 1 (en la app, no en el editor SQL):
--   1. Entra como admin CON LA CUENTA REAL. Administración → Seguridad →
--      "Probar permisos": `sorteos` debe salir en verde (lectura y
--      escritura).
--   2. Edita cualquier sorteo (por ejemplo cambia una nota) y guarda:
--      debe guardar y quedar igual al refrescar.
--   3. Entra como VENDEDOR (da igual si es cuenta real o vieja): debe
--      seguir viendo la lista de sorteos y poder anotar normalmente.
--   4. Cierra sesión y vuelve a entrar como admin POR EL LOGIN VIEJO:
--      al intentar editar un sorteo debe salir el aviso "tu cuenta no
--      tiene permiso…". Eso es lo esperado, no un error.
--
-- DESHACER BLOQUE 1:
--   grant insert, update, delete, truncate on public.sorteos to anon;
--   drop policy if exists sorteos_insertar_admin on public.sorteos;
--   drop policy if exists sorteos_actualizar_admin on public.sorteos;
--   drop policy if exists sorteos_borrar_admin on public.sorteos;
--   create policy sorteos_todo_abierto on public.sorteos
--     for all using (true) with check (true);


-- =====================================================================
-- BLOQUE 2 — TABLA `resultados`
-- Leer: cualquiera (se cierra en la etapa 4).
-- Guardar / corregir / borrar: el admin, o un vendedor que tenga el
-- módulo "🏆 Resultados y premiación" delegado (Administración →
-- Usuarios). Ese vendedor necesita su CUENTA REAL para que funcione.
-- =====================================================================

alter table public.resultados enable row level security;

do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'resultados'
  loop
    execute format('drop policy %I on public.resultados', p.policyname);
  end loop;
end $$;

create policy resultados_leer_todos on public.resultados
  for select using (true);

create policy resultados_insertar on public.resultados
  for insert with check ((select public.es_admin()) or (select public.tiene_modulo('resultados')));

create policy resultados_actualizar on public.resultados
  for update using ((select public.es_admin()) or (select public.tiene_modulo('resultados')))
  with check ((select public.es_admin()) or (select public.tiene_modulo('resultados')));

create policy resultados_borrar on public.resultados
  for delete using ((select public.es_admin()) or (select public.tiene_modulo('resultados')));

revoke insert, update, delete, truncate on public.resultados from anon;

-- PRUEBA DEL BLOQUE 2:
--   1. Admin con cuenta real: guarda el resultado de un sorteo de prueba
--      (o vuelve a guardar uno ya cargado con los mismos números). Debe
--      decir "Resultado guardado" y verse en la lista al refrescar.
--   2. Revisa que las filas automáticas de Independientes se sigan
--      generando al guardar el resultado (Balance de cuentas).
--   3. Si tienes un vendedor con el módulo de Resultados delegado, pídele
--      que entre CON SU CUENTA REAL y guarde uno. Si entra por el login
--      viejo, le va a salir el aviso de permiso — es lo esperado.
--   4. Un vendedor normal no debe poder guardar resultados (ni le aparece
--      la pantalla).
--
-- DESHACER BLOQUE 2:
--   grant insert, update, delete, truncate on public.resultados to anon;
--   drop policy if exists resultados_insertar on public.resultados;
--   drop policy if exists resultados_actualizar on public.resultados;
--   drop policy if exists resultados_borrar on public.resultados;
--   create policy resultados_todo_abierto on public.resultados
--     for all using (true) with check (true);


-- =====================================================================
-- BLOQUE 3 — TABLA `vendedores`
-- Leer: cualquiera (el login viejo lo necesita; se cierra en la etapa 4).
-- Crear / editar / borrar: SOLO el admin con cuenta real.
-- La migración de contraseñas viejas a cifradas sigue funcionando: la app
-- la hace por la función `migrar_password_legacy` del bloque 0.
-- =====================================================================

alter table public.vendedores enable row level security;

do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'vendedores'
  loop
    execute format('drop policy %I on public.vendedores', p.policyname);
  end loop;
end $$;

create policy vendedores_leer_todos on public.vendedores
  for select using (true);

create policy vendedores_insertar_admin on public.vendedores
  for insert with check ((select public.es_admin()));

create policy vendedores_actualizar_admin on public.vendedores
  for update using ((select public.es_admin()))
  with check ((select public.es_admin()));

create policy vendedores_borrar_admin on public.vendedores
  for delete using ((select public.es_admin()));

revoke insert, update, delete, truncate on public.vendedores from anon;

-- PRUEBA DEL BLOQUE 3:
--   1. Admin con cuenta real: crea un vendedor de prueba, edítalo
--      (cambia el nombre), cámbiale la comisión y bórralo. Todo debe
--      funcionar y quedar guardado al refrescar.
--   2. Cambia los permisos de un usuario (Administración → Usuarios) y la
--      tarifa de alguien de equipo: también debe guardar.
--   3. Un vendedor entrando (cuenta real o vieja) debe poder iniciar
--      sesión y vender igual que siempre.
--   4. Un vendedor que todavía tenga la contraseña sin cifrar debe poder
--      entrar y quedar migrado (revisa en la tabla que su `password` ya
--      no se lea en texto claro después de que entre).
--
-- DESHACER BLOQUE 3:
--   grant insert, update, delete, truncate on public.vendedores to anon;
--   drop policy if exists vendedores_insertar_admin on public.vendedores;
--   drop policy if exists vendedores_actualizar_admin on public.vendedores;
--   drop policy if exists vendedores_borrar_admin on public.vendedores;
--   create policy vendedores_todo_abierto on public.vendedores
--     for all using (true) with check (true);


-- =====================================================================
-- BLOQUE 4 — TABLA `app_config`
-- Leer: cualquiera (el login viejo del admin y la tabla de premios se
-- leen antes de iniciar sesión; se cierra en la etapa 4).
-- Editar: SOLO el admin con cuenta real. Nadie inserta ni borra: es una
-- fila única (id = 1).
-- =====================================================================

alter table public.app_config enable row level security;

do $$
declare p record;
begin
  for p in select policyname from pg_policies
           where schemaname = 'public' and tablename = 'app_config'
  loop
    execute format('drop policy %I on public.app_config', p.policyname);
  end loop;
end $$;

create policy app_config_leer_todos on public.app_config
  for select using (true);

create policy app_config_actualizar_admin on public.app_config
  for update using ((select public.es_admin()))
  with check ((select public.es_admin()));

revoke insert, update, delete, truncate on public.app_config from anon;

-- PRUEBA DEL BLOQUE 4:
--   1. Admin con cuenta real: cambia un monto de la tabla de premios y
--      guarda. Refresca: debe seguir el monto nuevo.
--   2. Revisa que un ticket con premio se siga calculando igual.
--   3. OJO: cambiar usuario/contraseña del admin (Administración →
--      Seguridad) escribe en esta tabla; también hay que hacerlo con la
--      cuenta real. Y recuerda que eso cambia el login VIEJO, no la
--      contraseña de la cuenta real de Supabase (esa se cambia desde el
--      panel de Supabase → Authentication).
--
-- DESHACER BLOQUE 4:
--   grant insert, update, delete, truncate on public.app_config to anon;
--   drop policy if exists app_config_actualizar_admin on public.app_config;
--   create policy app_config_todo_abierto on public.app_config
--     for all using (true) with check (true);


-- =====================================================================
-- REVISIÓN FINAL (para ver cómo quedó todo)
-- =====================================================================
-- select tablename, policyname, cmd, qual, with_check
--   from pg_policies
--  where schemaname = 'public'
--    and tablename in ('vendedores','sorteos','resultados','app_config')
--  order by tablename, cmd;
--
-- select relname, relrowsecurity
--   from pg_class
--  where relnamespace = 'public'::regnamespace
--    and relname in ('vendedores','sorteos','resultados','app_config');


-- =====================================================================
-- LO QUE QUEDA PARA LA ETAPA 4 (no correr todavía)
-- =====================================================================
-- 1. Apagar el login viejo en la app (que solo entre quien tenga cuenta
--    real). Antes de eso, TODOS los vendedores tienen que tener su cuenta
--    real creada y probada.
-- 2. Recién ahí se puede cerrar la LECTURA:
--      alter policy vendedores_leer_todos  on public.vendedores  using (auth.uid() is not null);
--      alter policy app_config_leer_todos  on public.app_config  using (auth.uid() is not null);
--      alter policy sorteos_leer_todos     on public.sorteos     using (auth.uid() is not null);
--      alter policy resultados_leer_todos  on public.resultados  using (auth.uid() is not null);
--      revoke select on public.vendedores, public.app_config,
--                       public.sorteos, public.resultados from anon;
--    (Y en la app: cargar los datos DESPUÉS de iniciar sesión, no antes.)
-- 3. Cerrar las tablas donde escriben los vendedores, ya con todos en
--    cuenta real: `folio_counter`, `ventas`, `liquidaciones`,
--    `deudas_equipo`, `asistencia_equipo`, `coberturas`,
--    `registro_cambios`, `push_subscriptions`.
-- 4. Cuando ya no quede nadie con contraseña sin cifrar, borrar la
--    función de migración:
--      drop function if exists public.migrar_password_legacy(text, text, text);
