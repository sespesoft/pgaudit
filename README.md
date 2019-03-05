pgAudit
=======
Sistema base de auditoria para tablas postgreSQL. [Marco referencial](http://www.juanluramirez.com/auditoria-bases-datos/).

Instalación
-----------
Se debe ejecutar el script **pgaudit.sql** dentro de la base de datos a auditar, este proceso generara el esquema pgaudit, la tabla config, las funciones table y trail.

Configuración
-------------
Con solo ejecutar el archivo pgaudit.sql se crea toda la estructura que da soporte al sistema de auditoria, pero no funcionara hasta que se configuren las acciones a auditar; para esto se creo el archivo **config.sql** en él se encuentran los inserts necesarios para alimentar la tabla config del esquema pgaudit.

| key | value | state |
|-----|-------|-------|
| I | INSERT | 1 |
| U | UPDATE | 1 |
| D | DELETE | 1 |

Si el sistema es ejecutado sin una configuración establecida no ingresara datos a las tablas auditadas, de igual manera es posible desactivar la auditoria de un comando cambiando el estado a 0.

Uso
---
Para auditar una tabla se hace uso de la función `pgaudit.table(schema, table)` o `pgaudit.table(table)`, en este último caso se fijara la tabla al esquema público de la base de datos, de cualquier forma se creará la tabla de auditoria *pgaudit.schema$table*.

| Campo | Descripción |
|-------|-------------|
| id | Identificador único de la tabla |
| register_date | Fecha enn la que ocurrio el evento |
| user_db | Usuario de la base de datos que modifico el registro |
| log_id | Identificador del acceso de usuario en el sistema |
| command | Operación realizada sobre el registro según la configuración del sistema (INSERT, UPDATE, DELETE) |
| old | Registro anterior a la modificación realizada, si la modificación fue de tipo *INSERT* este registro se encuentra vacío |
| new | Registro posterior a la modificación realizada, si la modificación fue de tipo *DELETE* este registro se encuentra vacío |

Al realizar una operación DML(Excepto SELECT) sobre una tabla auditada el sistema registra automáticamente en la tabla de auditoria los campos: *id*, *register_date*, *user_db*, *command*, *old* y *new*. Si se desea realizar auditoria directa sobre la aplicación se debe hacer uso del campo *log_id*, este campo hace referencia a la tabla que mantiene la información de ingreso del usuario al sistema o al mismo usuario que ingreso a la aplicación, el registro de esta información se debe realizar implementando la función `pgaudit.trail(idLog)` dentro de la aplicación.

```php
<?php
$db = new PDO("pgsql:dbname=$dbname;host=$host", $dbuser, $dbpass);
$db->exec("SELECT pgaudit.trail('$log')");
```

Se debe tener especial cuidado de ejecutar correctamente esta función, en ocaciones se puede perder la referencia al log ya que la conexión se cierra y con ella la tabla temporal que mantiene el dato en sesión para ser consumido por el trigger.

Las operaciones soportadas por pgAudit son: INSERT, UPDATE y DELETE, cada una de estas operaciones crea un registro en la tabla de auditoria.

Un registro se puede recuperar fácilmente desde la tabla de auditoria con tan solo usar los campos *old* y *new*, estos almacenan el registro que tenia la tabla antes y después de realizar la operación DML.

```sql
INSERT INTO public.usuario
SELECT (old).id, (old).nombre, (old).email, (old).password
FROM pgaudit.public$usuario
WHERE id = 1;
```

El manejo de registros como tipo de dato es tan versátil y poderoso que no solo puede restablecer una tabla del sistema, si no que puede realizar cualquier otro tipo de operación como consultas.

```sql
SELECT (new).id
FROM pgaudit.public$usuario
WHERE (new).nombre = 'admin';
```
