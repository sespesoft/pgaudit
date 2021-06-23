CREATE OR REPLACE FUNCTION pgaudit.split(format TEXT) RETURNS VARCHAR
LANGUAGE plpgsql AS $split_log_by_date$
DECLARE
    table_name VARCHAR;
    now TIMESTAMP;
    query TEXT;
BEGIN
    now := CURRENT_TIMESTAMP;
    table_name := 'pgaudit.log_' || TO_CHAR(now, format);
    query := $SQL$
        CREATE TABLE TG_TABLE_NAME (
            id            INTEGER PRIMARY KEY,
            table_name    VARCHAR(250),
            register_date TIMESTAMP WITH TIME ZONE NOT NULL,
            user_db       TEXT NOT NULL,
            session_id        TEXT,
            command       CHAR(1) NOT NULL,
            old           JSON,
            new           JSON
        );
        INSERT INTO TG_TABLE_NAME(id, table_name, register_date, user_db, session_id, command, old, new)
        SELECT id, table_name, register_date, user_db, session_id, command, old, new FROM pgaudit.log
        WHERE register_date < 'TG_NOW';
        DELETE FROM pgaudit.log WHERE register_date < 'TG_NOW';
    $SQL$;
    query := REPLACE(query, 'TG_TABLE_NAME', table_name);
    query := REPLACE(query, 'TG_NOW', now::text);
    EXECUTE query;
    RETURN table_name || ' created';
END
$split_log_by_date$;

CREATE OR REPLACE FUNCTION pgaudit.split() RETURNS VARCHAR
LANGUAGE plpgsql AS $split_default_log_by_date$
BEGIN
    RETURN pgaudit.split('YYYY_MM_DD_HH24MISSMS');
END
$split_default_log_by_date$;