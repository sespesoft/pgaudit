CREATE OR REPLACE FUNCTION pgaudit.bind(session_id name) RETURNS INTEGER
LANGUAGE plpgsql AS $tracking_session$
BEGIN
    PERFORM relname
    FROM pg_class
    WHERE relname = 'tbl_session'
    AND CASE WHEN has_schema_privilege(relnamespace, 'USAGE')
        THEN pg_table_is_visible(oid) ELSE false END;
    IF not FOUND THEN
        CREATE TEMPORARY TABLE tbl_session (name TEXT, value TEXT);
    ELSE
        DELETE FROM tbl_session WHERE name = 'session_id';
    END IF;
    INSERT INTO tbl_session VALUES ('session_id', session_id);
    RETURN 1;
END
$tracking_session$;

CREATE OR REPLACE FUNCTION pgaudit.trail(session_id name) RETURNS INTEGER
LANGUAGE plpgsql AS $alias_bind$
BEGIN
    RETURN pgaudit.bind(session_id);
END
$alias_bind$;