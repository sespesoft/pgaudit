# pgAudit
Sistema base de auditoria para tablas postgreSQL. [Marco referencial](http://www.juanluramirez.com/auditoria-bases-datos/).

## Migración
Pasar se un sistema de multiples tabla a una centralizada implica un trabajo de migración.

1. Eliminar todas las funciones y triggers de las tablas auditadas.
2. Ejecutar **pgaudit.sql** en la base de datos.
3. Si es necesario ejecutar **bind.sql** y/o **history.sql**
4. Pasar los datos de cada una de las tablas a la tabla log con el siguiente comando.
```sql
INSERT INTO pgaudit.log(audit_object, register_date, user_db, session_id, command, old, new)
SELECT 'schema.table', register_date, user_db, log_id, command, row_to_json(old), row_to_json(new)
FROM pgaudit.schema$table
```
5. Ejecutar `pgaudit.follow(schema, table)` nuevamente sobre las tablas a auditar.
6. Eliminar las tablas de auditoria.

En caso de cambiar hacia una versión con table_name en vez de audit_object, realizar el cambio de `audi_object -> table_name`.

### Cambios de tipos
En últimas versiones se han modificado algunas columnas, por lo cual si se está realizando migraciones desde versiones anteriores a la modificación se debe tener en cuenta que la columna table_name cambio a audit_object; así como el tamaño de las columnas audit_object, session_id y user_db pasaron a 4000, 40 y 63 respectivamente. El siguiente es un ejemplo de migración de estos tipos.

```sql
ALTER TABLE pgaudit.log
ALTER COLUMN table_name SET DATA TYPE VARCHAR(4000),
ALTER COLUMN session_id SET DATA TYPE VARCHAR(40),
ALTER COLUMN user_db SET DATA TYPE VARCHAR(63);
ALTER TABLE pgaudit.log
RENAME COLUMN table_name TO audit_object;
```

Si se está usando histórico se debe volver a ejecutar el anterior SQL cambiando el nombre de la tabla `pgaudit.log -> pgaudit.history`.

Finalmente y aunque no sea necesario se puede optar por eliminar el campo `state` de la tabla config, pues el manejo de si esta configurado o no el registro ahora se debe realizar con hard delete.

## Instalación
Se debe ejecutar el script **pgaudit.sql** dentro de la base de datos a auditar, este proceso generara el esquema pgaudit así como todas las tablas, funciones y triggers para su funcionamiento.

Configuración
-------------
Las configuraciones se manejan desde la tabla **pgaudit.config** la cual tiene la siguiente estructura.

| key | value |
|-----|-------|
| I | INSERT |
| U | UPDATE |
| D | DELETE |
| H | YYYY |

Por defecto la tabla de configuración activa una serie de features que se pueden activar y desactivar según sea el caso como la auditoria general de un comando eliminado o creando el registro.

## Uso
Para seguir una tabla se hace uso de la función `pgaudit.follow(schema, table)` o `pgaudit.follow(table)`, en este último caso se fijara la tabla al esquema público de la base de datos. El sistema de auditoria ya no crea tabla por tabla auditada, cualquier log se registra en la tabla *log* eliminando el uso de tablas con forma *pgaudit.schema$table*.

| Campo | Descripción |
|-------|-------------|
| id | Identificador único de la tabla |
| audit_object | Nombre del objeto de auditoria, en el caso de una tabla sobre la cual se realizó una operación el formato insertado sera *schema.name* |
| Register_date | Fecha en la que se registro el evento |
| user_db | Usuario de la base de datos que modifico el registro |
| session_id | Identificador del acceso de usuario al sistema |
| command | Operación realizada sobre el registro según la configuración del sistema (INSERT, UPDATE, DELETE) |
| old | Registro anterior a la modificación realizada, si la modificación fue de tipo *INSERT* este registro se encuentra vacío |
| new | Registro posterior a la modificación realizada, si la modificación fue de tipo *DELETE* este registro se encuentra vacío |

Al realizar una operación DML sobre una tabla auditada el sistema registra automáticamente en la tabla de auditoria los campos: *id*, *object*, *date*, *user_db*, *command*, *old* y *new*.

Las operaciones soportadas por pgAudit son: INSERT, UPDATE y DELETE, cada una de estas operaciones crea un registro en la tabla de auditoria siempre y cuando se encuentre activa desde la configuración.

Para deja de seguir una tabla en especifico se debe ejecutar la función `pgaudit.unfollow(schema, table)` o `pgaudit.unfollow(table)`.

### Auditorias fuera de DDL
Como se puede observar, el sistema está pensado para realizar auditorias DDL sobre tablas del sistema de manera sencilla y práctica, sin necesidad de invadir el código de la aplicación y garantizando el almacenamiento de cualquier tipo de manipulación de datos, así esta se realice fuera de la aplicación. Pero en ocasiones es necesario realizar auditarías fuera de las tablas o un poco más complejas, como es el caso de las consultas.

Un caso de uso común es saber quién y cuando se descargó un reporte de la aplicación, es aquí cuando se decide cambiar el enfoque del sistema de auditoria y se permite el ingreso manual de información, de esta manera podemos guardar la URL del reporte como objeto de la auditoria y señalar la sesión del usuario en la que se realizó dicho acceso.

```sql
INSERT INTO pgaudit.log(session_id, object, command)
VALUES (159, 'https://sespesoft.com/admin/report/e2040c9e-4f7f-4634-8001-836c46fa89d5', 'Q');
```

Al ser command una columna requerida se debe especificar dentro de la inserción, esto también ayudará a distinguir este tipo de auditoria de las otras.

## Tracking
Si se desea realizar auditoria directa sobre la aplicación se debe hacer uso del campo *session_id*, este campo debe enlazarse a la tabla que mantiene la información de ingreso del usuario al sistema o al mismo usuario que ingreso a la aplicación, el registro de esta información se debe realizar implementando la función `pgaudit.bind(session_id)` **bind.sql** dentro de la aplicación.

```php
<?php
$db = new PDO("pgsql:dbname=$dbname;host=$host", $dbuser, $dbpass);
$db->exec("SELECT pgaudit.trail('{$session}')");
```

Se debe tener especial cuidado de ejecutar correctamente esta función, en ocaciones se puede perder la referencia al log ya que la conexión se cierra y con ella la tabla temporal que mantiene el dato en sesión para ser consumido por el trigger.

## Histórico
**history.sql** se creeo como reemplazo del antiguo **split.sql** la idea ya no es dividir el log en multiples tablas fisicas, si no que haciendo uso de una tabla particionada **pgaudit.history** almacenar toda la información de la tabla principal gracias a la función `pgaudit.vacuum(TIMESTAMP WITH TIME ZONE)` la cual se encarga de crear las particiones dentro de la tabla. Si no se le envía un párametro a la función esta tomara por defecto la fecha actual.

Finalmente se debe configurar la key *H* por defecto con valor *YYYY* lo cual generaria particiones de tipo *log_YYYY*.

| key | value | state |
|-----|-------|-------|
| H | YYYY | 1 |

## Consultas
Un registro se puede recuperar fácilmente desde la tabla de auditoria con tan solo usar los campos *old* y *new*, estos almacenan el registro que tenia la tabla antes y después de realizar la operación DML.

```sql
INSERT INTO public.user
SELECT (old->>'id')::integer, old->>'name', old->>'password'
FROM pgaudit.log
WHERE old->>'nombre' = 'admin' AND command = 'D' AND table_name = 'public.user';
```

El manejo de registros como tipo de dato es tan versátil y poderoso que no solo puede restablecer una tabla del sistema, si no que puede realizar cualquier otro tipo de operación como consultas.

```sql
SELECT new, old
FROM pgaudit.log
WHERE table_name = 'public.user' AND new->>'name' = 'admin';
```
## TODO
* Agregar formato YYYY_MM al sistema de histórico
