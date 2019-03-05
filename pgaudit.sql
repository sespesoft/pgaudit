CREATE SCHEMA IF NOT EXISTS pgaudit;

CREATE TABLE IF NOT EXISTS pgaudit.config(
    key char(1) NOT NULL PRIMARY KEY,
    value varchar(20) NOT NULL,
    state bit(1) NOT NULL DEFAULT '1'
);

CREATE OR REPLACE FUNCTION pgaudit.trail(log_id name) RETURNS INTEGER
LANGUAGE plpgsql AS $trail_session$
BEGIN
    PERFORM relname
    FROM pg_class
    WHERE relname = 'tbl_session'
    AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
        THEN pg_table_is_visible(oid) ELSE false END;
    IF not FOUND THEN
        CREATE TEMPORARY TABLE tbl_session (name TEXT, value TEXT);
    ELSE
        DELETE FROM tbl_session WHERE name = 'log_id';
    END IF;
    INSERT INTO tbl_session VALUES ('log_id', log_id);
    RETURN 1;
END
$trail_session$;

CREATE OR REPLACE FUNCTION pgaudit.table(table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $audit_table_whithout_schema$
DECLARE
    result VARCHAR;
BEGIN
    SELECT pgaudit.table('public', table_name) INTO result;
    RETURN result;
END
$audit_table_whithout_schema$;

CREATE OR REPLACE FUNCTION pgaudit.table(schema name, table_name name) RETURNS VARCHAR
LANGUAGE plpgsql AS $audit_table$
DECLARE
    trigger_auditor TEXT;
    table_origin TEXT;
    schema_audit TEXT;
    table_log TEXT;
BEGIN
    table_origin := schema || '.' || table_name;
    schema_audit := 'pgaudit';
    table_log := schema_audit || '.' || schema || '$' || table_name;

    EXECUTE 'CREATE TABLE IF NOT EXISTS ' || table_log || ' (' ||
            'id             SERIAL NOT NULL PRIMARY KEY' ||
            ',register_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT current_timestamp' ||
            ',user_db       TEXT NOT NULL DEFAULT USER'
            ',log_id        TEXT' ||
            ',command       CHAR(1) NOT NULL REFERENCES pgaudit.config(key)' ||
            ',old           ' || table_origin ||
            ',new           ' || table_origin || ')';

    trigger_auditor := $FUNCTION$
        CREATE OR REPLACE FUNCTION TG_TABLE_NAME_audit() RETURNS TRIGGER STRICT LANGUAGE plpgsql
        AS $PROC$
        DECLARE
            log_id TEXT;
            config RECORD;
        BEGIN
            PERFORM relname
            FROM pg_class
            WHERE relname = 'tbl_session'
            AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
                THEN pg_table_is_visible(oid) ELSE false END;
            IF not found THEN
                log_id := NULL;
            ELSE
                log_id := (SELECT value FROM tbl_session WHERE name = 'log_id');
            END IF;

            SELECT * INTO config FROM pgaudit.config WHERE value = TG_OP AND state = '1';
            IF FOUND THEN
                IF TG_OP = 'INSERT' THEN
                    INSERT INTO TG_TABLE_NAME (log_id, command, new) VALUES (log_id, config.key, NEW);
                ELSIF TG_OP = 'DELETE' THEN
                    INSERT INTO TG_TABLE_NAME (log_id, command, old) VALUES (log_id, config.key, OLD);
                ELSIF TG_OP = 'UPDATE' THEN
                    INSERT INTO TG_TABLE_NAME (log_id, command, old, new) VALUES (log_id, config.key, OLD, NEW);
                END IF;
            END IF;
            RETURN NULL;
        END
        $PROC$;
    $FUNCTION$;

    trigger_auditor := replace(trigger_auditor, 'TG_TABLE_NAME', table_log);
    EXECUTE trigger_auditor;

    EXECUTE 'DROP TRIGGER IF EXISTS audit ON ' || table_origin || ';CREATE TRIGGER audit ' ||
        ' AFTER INSERT OR UPDATE OR DELETE ON ' || table_origin ||
        ' FOR EACH ROW EXECUTE PROCEDURE ' || table_log || '_audit();';

    RETURN table_origin || ' table being audited...';
END
$audit_table$;
