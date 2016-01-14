/*
 * Caller: The insert/update/delete trigger on the base table.	
 *
 * Use Case: To track inserts, updates, and deletes on the base table.	
 *
 * Description: This trigger function should be installed on any table you
 *   want to have full history with timelines and undo/redo functionality. A
 *   string that represents a json array defining the session columns must
 *   be passed as an argument to the trigger when it's installed.  If you
 *   don't want session tracking functionality and would rather track the
 *   table as a one big session, just pass any empty json array as: '[]'
 */

create or replace function history_trigger_func() returns trigger
as $$ 
declare
    l_session_id bigint;
    l_active_action_id bigint;
    l_active_timeline_id bigint;
    l_last_action_in_timeline bigint;
    l_action char(1);
    l_session_columns jsonb;
    l_session jsonb;
begin 
    l_action := left(TG_OP, 1);
    l_session_columns := TG_ARGV[0];

    -- force the user to pass a json array when installing this trigger
    if jsonb_typeof(coalesce(l_session_columns, '{}'::jsonb)) <> 'array'
    then
        -- the json paramater should define the session columns as a json array (which can be empty)
        raise exception 'invalid argument to the history_trigger_func() trigger function'
            using hint = 'it should be a json array that defines the session column names';
    end if;

    -- reduce the new (or old) jsonb to just the columns that define a session
    select coalesce(json_object_agg(kv.key, kv.value), '{}'::json)
    into strict l_session
    from
        json_each(row_to_json(case when l_action in ('I', 'U') then new else old end)) kv
        join jsonb_array_elements_text(l_session_columns) k on kv.key = k.value;

    -- is table in history_sessions?
    if not exists (select 1 from history_sessions where table_name = TG_TABLE_NAME and session = l_session)
    then
        insert into history_sessions(table_name, session) values(TG_TABLE_NAME, l_session);
    end if;
    select session_id, active_action_id
    into strict l_session_id, l_active_action_id
    from history_sessions
    where table_name = TG_TABLE_NAME and session = l_session;

    -- is there an active action?
    if l_active_action_id is null
    then -- no active action, root timeline must not exist, create it
        insert into history_timelines(session_id)
        values(l_session_id)
        returning timeline_id into strict l_active_timeline_id;
    else -- get timeline of active action
        select timeline_id
        into strict l_active_timeline_id
        from history_actions
        where action_id = l_active_action_id;
    end if;

    -- get the last action in active timeline
    select max(action_id)
    into l_last_action_in_timeline
    from history_actions
    where timeline_id = l_active_timeline_id;

    -- timeline has no actions, or the active action is the last one in the timeline
    if (l_last_action_in_timeline is null) or (l_last_action_in_timeline = l_active_action_id)
    then
        -- noop, appent to the active timeline
    else
        -- new timeline
        insert into history_timelines(session_id, parent_action_id)
        values(l_session_id, l_active_action_id)
        returning timeline_id into strict l_active_timeline_id;
    end if;

    insert into history_actions(timeline_id, action, old, new)
    values(
        l_active_timeline_id,
        l_action,
        case when l_action in ('U', 'D') then row_to_json(old)::jsonb else null end,
        case when l_action in ('I', 'U') then row_to_json(new)::jsonb else null end
    ) returning action_id into strict l_active_action_id;

    perform history_session_set_active_action(l_session_id, l_active_action_id);

    return null;
end;
$$ language plpgsql
security definer;

grant execute on function history_trigger_func() to public;
