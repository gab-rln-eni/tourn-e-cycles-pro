-- Empreinte du schéma public, lecture seule : une ligne par objet (genre, nom, md5 de sa définition et de ses droits).
-- Même requête que l'agent DEVIS (Audits/devis/requete_empreinte_schema.sql), sortie ligne à ligne pour comparaison.
WITH objs AS (
 SELECT 'col' k, table_name||'.'||column_name n, md5(concat_ws('|',data_type,is_nullable,column_default,udt_name)) h FROM information_schema.columns WHERE table_schema='public'
 UNION ALL SELECT 'con', conrelid::regclass::text||'.'||conname, md5(pg_get_constraintdef(oid)) FROM pg_constraint WHERE connamespace='public'::regnamespace
 UNION ALL SELECT 'pol', tablename||'.'||policyname, md5(concat_ws('|',cmd,roles::text,qual,with_check,permissive)) FROM pg_policies WHERE schemaname='public'
 UNION ALL SELECT 'fn', p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)||coalesce(array_to_string(p.proacl,','),'')) FROM pg_proc p WHERE pronamespace='public'::regnamespace
 UNION ALL SELECT 'trg', tgrelid::regclass::text||'.'||tgname, md5(pg_get_triggerdef(t.oid)) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT tgisinternal AND c.relnamespace='public'::regnamespace
 UNION ALL SELECT 'idx', indexrelid::regclass::text, md5(pg_get_indexdef(indexrelid)) FROM pg_index i JOIN pg_class c ON c.oid=i.indrelid WHERE c.relnamespace='public'::regnamespace
 UNION ALL SELECT 'acl', c.relname, md5(coalesce(array_to_string(c.relacl,','),'')||c.relrowsecurity::text||c.relforcerowsecurity::text) FROM pg_class c WHERE relnamespace='public'::regnamespace AND relkind IN ('r','v','m')
 UNION ALL SELECT 'type', t.typname, md5(coalesce((SELECT string_agg(enumlabel,',' ORDER BY enumsortorder) FROM pg_enum e WHERE e.enumtypid=t.oid),'')) FROM pg_type t WHERE typnamespace='public'::regnamespace AND typtype='e'
)
SELECT k||' '||n||' '||h FROM objs ORDER BY k, n;
