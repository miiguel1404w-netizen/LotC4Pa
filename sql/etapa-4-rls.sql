-- =====================================================================
-- LotC4Pa — CAMINO 1 (seguridad), ETAPA 4  ·  EL PASO DE RIESGO
-- "Apagar el login viejo y cerrar todo lo que queda"
-- =====================================================================
--
-- QUÉ HACE
-- Después de esto, la llave pública que está a la vista en el código
-- **no sirve absolutamente para nada** sin haber iniciado sesión: ni para
-- leer ni para escribir, en ninguna tabla. Hoy todavía se puede leer
-- (nombres de vendedores, contraseñas cifradas, ventas, resultados) con
-- solo copiar esa llave del código fuente. Eso es lo que se termina acá.
--
-- REQUISITO QUE YA SE CUMPLIÓ (22/08/2026)
-- Los 5 vendedores tienen cuenta real y TODOS ya estaban entrando con
-- ella (se comprobó con `auth.users.last_sign_in_at`: todos con ingreso
-- reciente). Si alguna vez agregas un vendedor, revísalo de nuevo con la
-- consulta del final antes de tocar nada.
--
-- ⚠️ ORDEN OBLIGATORIO
-- 1. PRIMERO subir el `index.html` de la etapa 4. Sin él, cerrar la
--    lectura deja a TODOS afuera: la app vieja pide los datos antes de
--    iniciar sesión, y sin datos no puede ni reconocer quién entra.
-- 2. Comprobar que entras con la app nueva (tú y algún vendedor).
-- 3. Recién entonces correr los bloques de acá, de a uno.
--
-- CÓMO DESHACER TODO, RÁPIDO (si algo sale mal a las 10 de la mañana)
-- Está al final del archivo, en un solo bloque para copiar y pegar.
-- Deshacer el SQL basta: la app de la etapa 4 sigue funcionando con los
-- permisos abiertos. Al revés no: la app VIEJA no funciona con los
-- permisos cerrados. Por eso siempre se deshace el SQL primero.
-- =====================================================================


-- =====================================================================
-- BLOQUE 5 — Cerrar la LECTURA de las cuatro tablas de la etapa 3
-- =====================================================================

drop policy if exists vendedores_leer_todos on public.vendedores;
create policy vendedores_leer_autenticados on public.vendedores
  for select using (auth.uid() is not null);

drop policy if exists sorteos_leer_todos on public.sorteos;
create policy sorteos_leer_autenticados on public.sorteos
  for select using (auth.uid() is not null);

drop policy if exists resultados_leer_todos on public.resultados;
create policy resultados_leer_autenticados on public.resultados
  for select using (auth.uid() is not null);

drop policy if exists app_config_leer_todos on public.app_config;
create policy app_config_leer_autenticados on public.app_config
  for select using (auth.uid() is not null);

revoke all on public.vendedores from anon;
revoke all on public.sorteos     from anon;
revoke all on public.resultados  from anon;
revoke all on public.app_config  from anon;

-- PRUEBA DEL BLOQUE 5 (en la app):
--   1. Cierra sesión y vuelve a entrar como admin. Debe entrar normal.
--   2. Administración → Seguridad → "Probar permisos": los 5 en verde.
--   3. Un vendedor debe poder cerrar sesión, entrar de nuevo y ver todo.
--   4. La pantalla de login NO debe mostrar ningún error raro antes de
--      escribir nada (ya no pide datos hasta que alguien entra).


-- =====================================================================
-- BLOQUE 6 — La ruta de venta: `ventas` y `folio_counter`
-- Es la más delicada de todas: si esto queda mal, nadie puede anotar.
-- Se respeta exactamente lo que hace la app, ni un permiso de más:
-- `ventas` no lleva DELETE (los tickets se anulan, nunca se borran; eso
-- ya venía del Camino 2).
-- =====================================================================

do $$
declare
  t record;
  c text;
begin
  for t in select * from (values
      ('ventas',        array['select','insert','update']),
      ('folio_counter', array['select','update'])
    ) as x(tabla, comandos)
  loop
    if to_regclass('public.'||t.tabla) is null then
      raise notice 'La tabla % no existe: se salta.', t.tabla;
      continue;
    end if;
    execute format('alter table public.%I enable row level security', t.tabla);
    -- Fuera las políticas viejas: si quedara una sola con `using (true)`,
    -- seguiría dejando pasar a cualquiera.
    execute (
      select coalesce(string_agg(format('drop policy %I on public.%I;', policyname, t.tabla), ' '), 'select 1')
        from pg_policies where schemaname='public' and tablename=t.tabla
    );
    foreach c in array t.comandos loop
      if c = 'insert' then
        execute format('create policy %I on public.%I for insert with check (auth.uid() is not null)',
                       t.tabla||'_insertar', t.tabla);
      elsif c = 'update' then
        execute format('create policy %I on public.%I for update using (auth.uid() is not null) with check (auth.uid() is not null)',
                       t.tabla||'_actualizar', t.tabla);
      elsif c = 'delete' then
        execute format('create policy %I on public.%I for delete using (auth.uid() is not null)',
                       t.tabla||'_borrar', t.tabla);
      else
        execute format('create policy %I on public.%I for select using (auth.uid() is not null)',
                       t.tabla||'_leer', t.tabla);
      end if;
    end loop;
    execute format('revoke all on public.%I from anon', t.tabla);
  end loop;
end $$;

-- PRUEBA DEL BLOQUE 6 (la más importante de toda la etapa):
--   1. TÚ anota un ticket de prueba y anúlalo. Debe salir el comprobante
--      y el folio debe avanzar.
--   2. Un VENDEDOR (o tú entrando con la cuenta de uno) anota un ticket.
--      Si esto falla, deshaz este bloque de inmediato — sin esto no hay
--      negocio.
--   3. Revisa el Historial: el ticket aparece, y el ↻ lo sigue trayendo.


-- =====================================================================
-- BLOQUE 7 — El resto de las tablas
-- =====================================================================

do $$
declare
  t record;
  c text;
begin
  for t in select * from (values
      ('liquidaciones',     array['select','insert','update']),
      ('deudas_equipo',     array['select','insert','update','delete']),
      ('asistencia_equipo', array['select','insert','delete']),
      ('coberturas',        array['select','insert','delete']),
      ('registro_cambios',  array['select','insert']),
      ('push_subscriptions',array['select','insert','update'])
    ) as x(tabla, comandos)
  loop
    if to_regclass('public.'||t.tabla) is null then
      raise notice 'La tabla % no existe: se salta.', t.tabla;
      continue;
    end if;
    execute format('alter table public.%I enable row level security', t.tabla);
    execute (
      select coalesce(string_agg(format('drop policy %I on public.%I;', policyname, t.tabla), ' '), 'select 1')
        from pg_policies where schemaname='public' and tablename=t.tabla
    );
    foreach c in array t.comandos loop
      if c = 'insert' then
        execute format('create policy %I on public.%I for insert with check (auth.uid() is not null)',
                       t.tabla||'_insertar', t.tabla);
      elsif c = 'update' then
        execute format('create policy %I on public.%I for update using (auth.uid() is not null) with check (auth.uid() is not null)',
                       t.tabla||'_actualizar', t.tabla);
      elsif c = 'delete' then
        execute format('create policy %I on public.%I for delete using (auth.uid() is not null)',
                       t.tabla||'_borrar', t.tabla);
      else
        execute format('create policy %I on public.%I for select using (auth.uid() is not null)',
                       t.tabla||'_leer', t.tabla);
      end if;
    end loop;
    execute format('revoke all on public.%I from anon', t.tabla);
  end loop;
end $$;

-- PRUEBA DEL BLOQUE 7:
--   1. Guarda un resultado (el mismo que ya estaba, con los mismos
--      números) y revisa que las filas automáticas de Vendedores
--      Independientes se sigan generando.
--   2. Entra a Cuentas de vendedores y agrega y borra un ajuste de prueba.
--   3. Control de equipo: marca un día trabajado de prueba y bórralo.
--   4. Revisa que el Registro de cambios siga anotando lo que haces.


-- =====================================================================
-- BLOQUE 8 — Limpieza: ya no hace falta la muleta del login viejo
-- Correr solo cuando los bloques 5, 6 y 7 estén probados y en pie.
-- =====================================================================

drop function if exists public.migrar_password_legacy(text, text, text);


-- =====================================================================
-- REVISIÓN FINAL
-- =====================================================================
-- ¿Le queda algún permiso al público (rol anon)? Lo correcto es que esta
-- consulta devuelva CERO filas:
--
-- select table_name, privilege_type
--   from information_schema.role_table_grants
--  where grantee = 'anon' and table_schema = 'public'
--    and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')
--  order by table_name;
--
-- ¿Quedó alguna tabla con RLS apagado o sin políticas?
--
-- select c.relname,
--        c.relrowsecurity as rls_encendido,
--        (select count(*) from pg_policies p
--          where p.schemaname='public' and p.tablename=c.relname) as politicas
--   from pg_class c
--  where c.relnamespace = 'public'::regnamespace and c.relkind='r'
--  order by c.relname;
--
-- Antes de agregar un vendedor nuevo, comprueba siempre que tenga cuenta
-- real y que YA haya entrado con ella:
--
-- select v.username, (u.email is not null) as tiene_cuenta, u.last_sign_in_at
--   from public.vendedores v
--   left join auth.users u on lower(u.email) = lower(v.username) || '@lotc4pa.app'
--  order by u.last_sign_in_at nulls first;


-- =====================================================================
-- DESHACER TODA LA ETAPA 4 (copiar y pegar completo, en una sola corrida)
-- Deja la base como estaba al terminar la etapa 3: se puede volver a
-- leer sin iniciar sesión y las tablas de venta vuelven a estar abiertas.
-- La app de la etapa 4 sigue funcionando igual después de esto.
-- =====================================================================
-- do $$
-- declare t text;
-- begin
--   for t in select unnest(array['ventas','folio_counter','liquidaciones','deudas_equipo',
--                                'asistencia_equipo','coberturas','registro_cambios','push_subscriptions'])
--   loop
--     if to_regclass('public.'||t) is null then continue; end if;
--     execute (select coalesce(string_agg(format('drop policy %I on public.%I;', policyname, t), ' '), 'select 1')
--                from pg_policies where schemaname='public' and tablename=t);
--     execute format('create policy %I on public.%I for all using (true) with check (true)', t||'_abierto', t);
--     execute format('grant select, insert, update, delete on public.%I to anon', t);
--   end loop;
-- end $$;
--
-- drop policy if exists vendedores_leer_autenticados on public.vendedores;
-- drop policy if exists sorteos_leer_autenticados    on public.sorteos;
-- drop policy if exists resultados_leer_autenticados on public.resultados;
-- drop policy if exists app_config_leer_autenticados on public.app_config;
-- create policy vendedores_leer_todos on public.vendedores for select using (true);
-- create policy sorteos_leer_todos    on public.sorteos    for select using (true);
-- create policy resultados_leer_todos on public.resultados for select using (true);
-- create policy app_config_leer_todos on public.app_config for select using (true);
-- grant select on public.vendedores, public.sorteos, public.resultados, public.app_config to anon;
