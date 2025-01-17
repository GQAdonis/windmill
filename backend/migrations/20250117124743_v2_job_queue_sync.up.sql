-- Add up migration script here

-- v2 -> v1
-- This trigger will be removed once all server(s)/worker(s) are updated to use `v2_*` tables
CREATE OR REPLACE FUNCTION v2_job_queue_before_insert() RETURNS TRIGGER AS $$
DECLARE job v2_job;
BEGIN
    job := (SELECT * FROM v2_job WHERE id = NEW.id);
    NEW.__created_by := job.created_by;
    NEW.__permissioned_as := job.permissioned_as;
    NEW.__email := job.permissioned_as_email;
    NEW.__job_kind := job.kind;
    NEW.__script_hash := job.runnable_id;
    NEW.__script_path := job.runnable_path;
    NEW.__parent_job := job.parent_job;
    NEW.__language := job.script_lang;
    NEW.__flow_step_id := job.flow_step_id;
    NEW.__root_job := job.flow_root_job;
    NEW.__schedule_path := job.schedule_path;
    NEW.__same_worker := job.same_worker;
    NEW.__visible_to_owner := job.visible_to_owner;
    NEW.__concurrent_limit := job.concurrent_limit;
    NEW.__concurrency_time_window_s := job.concurrency_time_window_s;
    NEW.__cache_ttl := job.cache_ttl;
    NEW.__timeout := job.timeout;
    NEW.__args := job.args;
    NEW.__pre_run_error := job.pre_run_error;
    NEW.__raw_code := job.raw_code;
    NEW.__raw_lock := job.raw_lock;
    NEW.__raw_flow := job.raw_flow;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER v2_job_queue_before_insert_trigger
    BEFORE INSERT ON v2_job_queue
    FOR EACH ROW
    WHEN (pg_trigger_depth() < 1 AND NEW.__created_by IS NULL) -- Prevent infinite loop v1 <-> v2
EXECUTE FUNCTION v2_job_queue_before_insert();

-- v1 -> v2
-- On every insert to `v2_job_queue`, insert to `v2_job`, `v2_job_runtime` and `v2_job_flow_runtime` as well
-- This trigger will be removed once all server(s)/worker(s) are updated to use `v2_*` tables
CREATE OR REPLACE FUNCTION v2_job_queue_after_insert() RETURNS TRIGGER AS $$ BEGIN
    INSERT INTO v2_job (
        id, workspace_id, created_at, created_by, permissioned_as, permissioned_as_email,
        kind, runnable_id, runnable_path, parent_job,
        script_lang,
        flow_step, flow_step_id, flow_root_job,
        schedule_path,
        tag, same_worker, visible_to_owner, concurrent_limit, concurrency_time_window_s, cache_ttl, timeout, priority,
        args, pre_run_error,
        raw_code, raw_lock, raw_flow
    ) VALUES (
        NEW.id, NEW.workspace_id, NEW.created_at, NEW.__created_by, NEW.__permissioned_as, NEW.__email,
        NEW.__job_kind, NEW.__script_hash, NEW.__script_path, NEW.__parent_job,
        NEW.__language,
        NULL, NEW.__flow_step_id, NEW.__root_job,
        NEW.__schedule_path,
        NEW.tag, NEW.__same_worker, NEW.__visible_to_owner, NEW.__concurrent_limit, NEW.__concurrency_time_window_s,
        NEW.__cache_ttl, NEW.__timeout, NEW.priority,
        NEW.__args, NEW.__pre_run_error,
        NEW.__raw_code, NEW.__raw_lock, NEW.__raw_flow
    ) ON CONFLICT (id) DO UPDATE SET
        workspace_id = EXCLUDED.workspace_id,
        created_at = EXCLUDED.created_at,
        created_by = EXCLUDED.created_by,
        permissioned_as = EXCLUDED.permissioned_as,
        permissioned_as_email = EXCLUDED.permissioned_as_email,
        kind = EXCLUDED.kind,
        runnable_id = EXCLUDED.runnable_id,
        runnable_path = EXCLUDED.runnable_path,
        parent_job = EXCLUDED.parent_job,
        script_lang = EXCLUDED.script_lang,
        flow_step = EXCLUDED.flow_step,
        flow_step_id = EXCLUDED.flow_step_id,
        flow_root_job = EXCLUDED.flow_root_job,
        schedule_path = EXCLUDED.schedule_path,
        tag = EXCLUDED.tag,
        same_worker = EXCLUDED.same_worker,
        visible_to_owner = EXCLUDED.visible_to_owner,
        concurrent_limit = EXCLUDED.concurrent_limit,
        concurrency_time_window_s = EXCLUDED.concurrency_time_window_s,
        cache_ttl = EXCLUDED.cache_ttl,
        timeout = EXCLUDED.timeout,
        priority = EXCLUDED.priority,
        args = EXCLUDED.args,
        pre_run_error = EXCLUDED.pre_run_error,
        raw_code = COALESCE(v2_job.raw_code, EXCLUDED.raw_code),
        raw_lock = COALESCE(v2_job.raw_lock, EXCLUDED.raw_lock),
        raw_flow = COALESCE(v2_job.raw_flow, EXCLUDED.raw_flow)
    ;
    INSERT INTO v2_job_runtime (id, ping, memory_peak)
    VALUES (NEW.id, NEW.__last_ping, NEW.__mem_peak)
    ON CONFLICT (id) DO UPDATE SET
        ping = COALESCE(v2_job_runtime.ping, EXCLUDED.ping),
        memory_peak = COALESCE(v2_job_runtime.memory_peak, EXCLUDED.memory_peak)
    ;
    IF NEW.__flow_status IS NOT NULL OR NEW.__leaf_jobs IS NOT NULL THEN
        INSERT INTO v2_job_flow_runtime (id, flow_status, leaf_jobs)
        VALUES (NEW.id, NEW.__flow_status, NEW.__leaf_jobs)
        ON CONFLICT (id) DO UPDATE SET
            flow_status = COALESCE(v2_job_flow_runtime.flow_status, EXCLUDED.flow_status),
            leaf_jobs = COALESCE(v2_job_flow_runtime.leaf_jobs, EXCLUDED.leaf_jobs)
        ;
    END IF;
    IF NEW.__logs IS NOT NULL THEN
        INSERT INTO job_logs (job_id, workspace_id, logs)
        VALUES (NEW.id, NEW.workspace_id, NEW.__logs)
        ON CONFLICT (job_id) DO UPDATE SET
            logs = CONCAT(job_logs.logs, EXCLUDED.logs)
        ;
        NEW.__logs := NULL;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER v2_job_queue_after_insert_trigger
    AFTER INSERT ON v2_job_queue
    FOR EACH ROW
    WHEN (pg_trigger_depth() < 1 AND NEW.__created_by IS NOT NULL) -- Prevent infinite loop v1 <-> v2
EXECUTE FUNCTION v2_job_queue_after_insert();

-- On every update to `v2_job_queue`, update `v2_job`, `v2_job_runtime` and `v2_job_flow_runtime` as well
-- This trigger will be removed once all server(s)/worker(s) are updated to use `v2_*` tables
CREATE OR REPLACE FUNCTION v2_job_queue_before_update() RETURNS TRIGGER AS $$ BEGIN
    -- `v2_job`: Only `args` are updated
    IF NEW.__args::text IS DISTINCT FROM OLD.__args::text THEN
        UPDATE v2_job
        SET args = NEW.__args
        WHERE id = NEW.id;
    END IF;
    -- `v2_job_runtime`:
    IF NEW.__last_ping IS DISTINCT FROM OLD.__last_ping OR NEW.__mem_peak IS DISTINCT FROM OLD.__mem_peak THEN
        INSERT INTO v2_job_runtime (id, ping, memory_peak)
        VALUES (NEW.id, NEW.__last_ping, NEW.__mem_peak)
        ON CONFLICT (id) DO UPDATE SET
            ping = EXCLUDED.ping,
            memory_peak = EXCLUDED.memory_peak
        ;
    END IF;
    -- `v2_job_flow_runtime`:
    IF NEW.__flow_status::text IS DISTINCT FROM OLD.__flow_status::text OR
       NEW.__leaf_jobs::text IS DISTINCT FROM OLD.__leaf_jobs::text THEN
        INSERT INTO v2_job_flow_runtime (id, flow_status, leaf_jobs)
        VALUES (NEW.id, NEW.__flow_status, NEW.__leaf_jobs)
        ON CONFLICT (id) DO UPDATE SET
            flow_status = EXCLUDED.flow_status,
            leaf_jobs = EXCLUDED.leaf_jobs
        ;
    END IF;
    -- `job_logs`:
    IF NEW.__logs IS DISTINCT FROM OLD.__logs THEN
        INSERT INTO job_logs (job_id, workspace_id, logs)
        VALUES (NEW.id, NEW.workspace_id, NEW.__logs)
        ON CONFLICT (job_id) DO UPDATE SET
            logs = CONCAT(job_logs.logs, EXCLUDED.logs)
        ;
        NEW.__logs := NULL;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER v2_job_queue_before_update_trigger
    BEFORE UPDATE ON v2_job_queue
    FOR EACH ROW
    WHEN (pg_trigger_depth() < 1) -- Prevent infinite loop v1 <-> v2
EXECUTE FUNCTION v2_job_queue_before_update();
