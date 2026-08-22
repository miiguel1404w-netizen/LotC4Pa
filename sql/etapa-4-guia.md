# Etapa 4 del Camino 1 — guía paso a paso

Esta es **la etapa de riesgo**: apaga el login viejo y cierra la lectura de
todas las tablas. Después de aplicarla, la llave pública que está a la vista
en el código **no sirve para nada** sin haber iniciado sesión.

El modo de fallar de esta etapa es "un vendedor no puede entrar a vender", así
que se hace con cuidado y con la marcha atrás preparada.

---

## Requisito (se comprobó el 22/08/2026)

**Todos** los vendedores tienen que tener cuenta real **y ya haber entrado con
ella**. No basta con que la cuenta exista: si la contraseña de la cuenta no es
la que el vendedor escribe, hoy entra igual por el login viejo sin que nadie se
entere, y al apagarlo se queda afuera.

Se comprueba así:

```sql
select v.username, (u.email is not null) as tiene_cuenta, u.last_sign_in_at
  from public.vendedores v
  left join auth.users u on lower(u.email) = lower(v.username) || '@lotc4pa.app'
 order by u.last_sign_in_at nulls first;
```

`last_sign_in_at` vacío = esa persona **nunca** ha entrado con su cuenta real.
Hay que resolverlo antes de seguir.

## Orden

1. **Primero el `index.html`** de la etapa 4. Sin él, cerrar la lectura deja a
   todos afuera: la app vieja pide los datos *antes* de iniciar sesión y, sin
   datos, no puede ni reconocer quién está entrando.
2. Comprobar que se entra bien con la app nueva (tú y un vendedor).
3. Después el SQL, bloque por bloque: **5** (cerrar lectura), **6** (ruta de
   venta), **7** (resto de tablas), **8** (limpieza). Probar entre uno y otro.

## Marcha atrás

Está al final de `sql/etapa-4-rls.sql`, en un solo bloque para copiar y pegar.
Deja la base como al terminar la etapa 3.

**Deshacer el SQL alcanza**: la app de la etapa 4 sigue funcionando con los
permisos abiertos. Al revés no funciona — la app vieja no sirve con los
permisos cerrados. Por eso, si algo falla, **siempre se deshace el SQL
primero** y recién después, si hace falta, se revierte la app.

---

## ⚠️ Lo que cambia para siempre en el día a día

### Agregar un vendedor son DOS pasos ahora

1. En la app: Administración → Agregar vendedor (como siempre).
2. En Supabase: **Authentication → Add user**, con el correo
   `suusuario@lotc4pa.app`, la contraseña que le vas a dar, y marcando
   **Auto Confirm User**.

Si te saltas el paso 2, ese vendedor **no puede entrar**. La contraseña que se
escribe en el formulario de la app ya no controla el acceso (queda guardada,
pero no se usa para entrar).

### Cambiar una contraseña se hace en Supabase

Tanto la del admin como la de cualquier vendedor: **Supabase → Authentication**,
buscar la cuenta, cambiarla ahí. El formulario de Administración → Seguridad ya
no controla el acceso.

### Si alguien no puede entrar

1. ¿Tiene cuenta? Míralo con la consulta de arriba.
2. ¿Está escribiendo bien el usuario? Da igual mayúsculas o minúsculas, y
   también sirve escribir el correo completo.
3. Si hace falta, cámbiale la contraseña desde Supabase → Authentication y
   dásela de nuevo. Con eso entra al instante, sin tocar código ni SQL.
