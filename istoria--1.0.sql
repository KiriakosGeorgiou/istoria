\echo Use "CREATE EXTENSION pair" to load this file. \quit
drop table if exists history_timelines cascade;
create table history_timelines (
    timeline_id bigserial constraint history_timelines_pk primary key,
    session_id bigint not null,
    parent_action_id bigint
);

grant select on history_timelines to public;

drop table if exists history_actions cascade;
create table history_actions (
    action_id bigserial constraint history_actions_pk PRIMARY KEY,
    timeline_id bigint not null,
    action char(1) not null,
    old jsonb,
    new jsonb
);
create index history_actions_timeline_id_idx on history_actions(timeline_id);

grant select on history_actions to public;

drop table if exists history_sessions cascade;
create table history_sessions (
    session_id bigserial constraint history_sessions_pk primary key,
    table_name text not null,
    session jsonb,
    active_action_id bigint
);

grant select on history_sessions to public;

alter table history_sessions add constraint history_sessions_fk1
    foreign key (active_action_id) references history_actions (action_id);

alter table history_timelines add constraint history_timelines_fk1
    foreign key (session_id) references history_sessions (session_id);

alter table history_timelines add constraint history_timelines_fk2
    foreign key (parent_action_id) references history_actions (action_id);

alter table history_actions add constraint history_actions_fk1
    foreign key (timeline_id) references history_timelines (timeline_id);
/*
 * Caller: history_session_actions()	    
 *
 * Use Case: This is used for the ordering of actions in
 *   history_session_actions().     
 *
 * Description: For an action on a root timeline it returns an empty array.
 *   For a p_action that's not on a root timeline, it returns an array with
 *   the action ids of the parent action of each timeline starting from the
 *   root timeline and ending at the timeline of p_action.  So if p_action
 *   11 belongs to timeline 5 that has a parent action of 8, which is on
 *   timeline 4 that has a parent action of 3 which is on timeline 1 with no
 *   parent, then this function will return the array {3,8}.
 */

create or replace function history_action_ancestors(
    p_action bigint
)
returns bigint[]
as $$ 
declare
    l_ancestors bigint[] = ARRAY[]::bigint[]; -- empty array
    l_parent bigint;
begin
    l_parent := history_action_timeline_parent(p_action);
    loop
        if l_parent is null
        then
            return l_ancestors;
        else
            l_ancestors := l_parent || l_ancestors;
            l_parent := history_action_timeline_parent(l_parent);
        end if;
    end loop;
end;
$$ language plpgsql;
/*
 * Caller: history_session_redo()  
 *
 * Use Case: To determine the p_action 's first descendant (child) action
 *   that is in the same timeline as p_action.	
 *
 * Description: If p_action has no descendant, then p_action is returned.
 */

create or replace function history_action_child(
    p_action bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
    l_child bigint;
begin
    if p_action is null
    then
        return null;
    end if;

    l_timeline := history_action_timeline(p_action);

    select min(action_id) into l_child
    from history_actions
    where action_id > p_action and timeline_id = l_timeline;

    return case when l_child is null then p_action else l_child end;
end;
$$ language plpgsql;
/*
 * Caller: history_session_undo(), history_walk()  
 *
 * Use Case: To determine an action's parent action.			     
 *
 * Description: This function returns the parent action of p_action, or null
 *   if there is no parent, which is the case for the first action in a root
 *   timeline.  Note that a session can have more than one root timeline.
 */

create or replace function history_action_parent(
    p_action bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
    l_parent bigint;
begin
    if p_action is null
    then
        return null;
    end if;

    l_timeline := history_action_timeline(p_action);

    select max(action_id) into l_parent
    from history_actions
    where action_id < p_action and timeline_id = l_timeline;

    if l_parent is null
    then
        select parent_action_id into l_parent
        from history_timelines
        where timeline_id = l_timeline;
    end if;

    return l_parent;
end;
$$ language plpgsql;
/*
 * Caller: history_walk(), history_sessions_trigger_func()
 *
 * Use Case: To determine p_action 's session id.
 *
 * Description: Returns p_action 's session id, possibly null if an invalid
 *   or null p_action is passed.
 */

create or replace function history_action_session(
    p_action bigint
)
returns bigint
as $$ 
begin
    return (
        select t.session_id
        from history_actions a join history_timelines t using(timeline_id)
        where a.action_id = p_action
    );
end;
$$ language plpgsql;
/*
 * Caller: history_action_child(), history_action_parent()  
 *
 * Use Case: To determine the timeline of the action.  
 *
 * Description: p_action can not be null, it must be a valid action in
 *   history_actions otherwise this function will throw an error.
 */

create or replace function history_action_timeline(
    p_action bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
begin
    select timeline_id into strict l_timeline
    from history_actions
    where action_id = p_action;

    return l_timeline;
end;
$$ language plpgsql;
/*
 * Caller: history_action_ancestors()
 *
 * Use Case: To determine the parent action of the timeline of p_action.  
 *
 * Description: It returns null for root timelines.
 */

create or replace function history_action_timeline_parent(
    p_action bigint
)
returns bigint
as $$ 
begin
    return (
        select t.parent_action_id
        from history_actions a join history_timelines t using (timeline_id)
        where a.action_id = p_action
    );
end;
$$ language plpgsql;
/*
 * Caller: history_replay() 
 *
 * Use Case: Deletes the record represented by p_jsonb from table p_table. 
 *
 * Description: The function identifies the primary key(s) in table p_table,
 *   and then uses the record information represented by p_jsonb to delete
 *   the record by the primary key(s).
 */

create or replace function history_delete(
    p_table text, p_jsonb jsonb
)
returns void
as $$ 
declare
    l_where_clause text;
begin
    -- find the PKs of p_table and build join clause for the delete
    execute
        format(
            $FMT$
            with
                tmp_pk as (
                    select a.attname as id
                    from pg_index i
                    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
                    where i.indrelid = %L::regclass
                    and i.indisprimary
                )
                select string_agg('%I.' || quote_ident(id) || '=tmp_del.' || quote_ident(id), ' and ')
                from tmp_pk
            $FMT$,
            p_table,
            p_table
        )
        into strict l_where_clause;

    execute
        format(
            $FMT$
            with
                tmp_del as ( -- helper to make the delete via a join easy
                    select * from jsonb_populate_record(null::%I, $1)
                )
                delete from %I using tmp_del
                where %s
            $FMT$,
            p_table,
            p_table, l_where_clause
        )
        using p_jsonb;
end;
$$ language plpgsql;
/*
 * Caller: history_replay() 
 *
 * Use Case: Inserts the record represented by p_jsonb to table p_table. 
 *
 * Description: This is how insert actions are replayed back into the
 *   session table.
 */

create or replace function history_insert(
    p_table text, p_jsonb jsonb
)
returns void
as $$ 
begin

    execute format('insert into %I select * from jsonb_populate_record(null::%I, $1)', p_table, p_table)
    using p_jsonb;

end;
$$ language plpgsql;
/*
 * Caller: history_sessions_trigger_func()    
 *
 * Use Case: This function replays a sequence of actions.    
 *
 * Description: A negative action is considered UNDO, a positive action is
 *   considered REDO.  For insert (I) actions UNDO means doing a delete. For
 *   delete (D) actions UNDO means doing an insert.  For update (U) actions
 *   UNDO means doing a delete on the new record followed by an insert of
 *   the old record. REDO performs the opposite operations of UNDO.
 */

create or replace function history_replay(
    p_actions bigint[]
)
returns void
as $$ 
declare
    x record;
begin
    for x in 
        select
            s.table_name,
            u.ra,
            a.action_id,
            a.action,
            a.old,
            a.new
        from
            unnest(p_actions) with ordinality u(ra, n)
            join history_actions a on a.action_id = (@ ra)
            join history_timelines t on t.timeline_id = a.timeline_id
            join history_sessions s on s.session_id = t.session_id
        order by n
    loop
        if x.ra < 0
        then -- UNDO
            case x.action
                when 'I' then
                    perform history_delete(x.table_name, x.new);
                when 'U' then
                    perform history_delete(x.table_name, x.new);
                    perform history_insert(x.table_name, x.old);
                when 'D' then
                    perform history_insert(x.table_name, x.old);
                    -- we only handle I, U, D
            end case;
        else -- REDO
            case x.action
                when 'I' then
                    perform history_insert(x.table_name, x.new);
                when 'U' then
                    perform history_delete(x.table_name, x.old);
                    perform history_insert(x.table_name, x.new);
                when 'D' then
                    perform history_delete(x.table_name, x.old);
                    -- we only handle I, U, D
            end case;
        end if;
    end loop;
end;
$$ language plpgsql;
/*
 * Caller: history_walk()  
 *
 * Use Case: Reverse and negate the array passed, and return it.  
 *
 * Description: history_walk(A, B) returns an array of actions that can be
 *   applied to the session table to transform it from its state when A was
 *   the active action to its state when B was the active action. 
 *   history_reverse() makes it possible to implement history_walk(A, B) as
 *   history_reverse(history_walk(B, A)).
 */

create or replace function history_reverse(bigint[])
returns bigint[]
as $$
    select ARRAY(
        select - $1[i]
        from generate_subscripts($1,1) as s(i)
        order by i desc
    );
$$ language 'sql' strict immutable;
/*
 * Caller: GUI				    
 *
 * Use Case: To get the actions in timeline order, considering timeline
 *   ancestry. This ordering makes sense for displaying the action tree in a
 *   GUI.					   
 *
 * Description: parent_action_id points to the timeline's parent action and
 *   is provided as a means to properly populate a GUI widget such as a
 *   tree.  A json object can easily be built from the results of this
 *   function and can be used to populate such GUI widget. 'indent' is a
 *   number the GUI might use to calculate how much to indent or in which
 *   column to show actions, thus graphically relating actions to timelines.
 *   'active' indicates if it's the active action of the session.
 *   'timeline_root' is the timeline_id of the root timeline the action
 *   belongs to. 'timeline_root' can be useful for separating actions in
 *   groups by their root timeline. 'ancestors' contains the timeline parent
 *   action ancestry, for more info see history_action_ancestors().
 */

create or replace function history_session_actions(
    p_session bigint
)
returns table (
    action_id bigint,
    ancestors bigint[],
    indent int,
    parent_action_id bigint,
    active boolean,
    timeline_id bigint,
    timeline_root bigint,
    action char(1),
    old jsonb,
    new jsonb
)
as $$ 
begin
    return query
        select
            a.action_id,
            history_action_ancestors(a.action_id),
            coalesce(array_length(history_action_ancestors(a.action_id), 1), 0),
            t.parent_action_id,

            /*
                If s.active_action_id is null, the comparison will always evaluate to null,
                and we want to return false since no action will be active.
            */
            coalesce(a.action_id = s.active_action_id, false), 
            a.timeline_id,
            history_timeline_root(a.timeline_id),
            a.action,
            a.old,
            a.new
        from
            history_actions a
            join history_timelines t on t.timeline_id = a.timeline_id
            join history_sessions s on s.session_id = t.session_id
        where
            s.session_id = p_session
        order by
            -- ancestors + action_id gets the correct order
            history_action_ancestors(a.action_id) || a.action_id;
end;
$$ language plpgsql;

grant execute on function history_session_actions(bigint) to public;
/*
 * Caller: history_session_redo(), history_walk()     
 *
 * Use Case: To determine the first action of session p_session.     
 *
 * Description: It returns either the first action of session p_session or
 *   null if session p_session does not have any actions yet.  Note that
 *   'first' means that in the case when a session has multiple root
 *   timelines, it returns the first action of the session's oldest root
 *   timeline.
 */

create or replace function history_session_first_action(
    p_session bigint
)
returns bigint
as $$ 
begin
    return (
        select min(a.action_id)
        from history_actions a join history_timelines t using (timeline_id)
        where t.session_id = p_session
    );
end;
$$ language plpgsql;
/*
 * Caller: Application. 
 *
 * Use Case: To advance the active action of session p_session to the first
 *   descendant action (child) of the active action, in the same timeline. 
 *
 * Description: If the active action of session p_session is null, then the
 *   active action of session p_session is set to the first action of
 *   session p_session.
 */

create or replace function history_session_redo(
    p_session bigint
)
returns bigint
as $$ 
declare
    l_active_action_id bigint;
begin
    update history_sessions
    set active_action_id =
        case when active_action_id is null
            then history_session_first_action(p_session)
            else history_action_child(active_action_id)
        end
    where session_id = p_session
    returning active_action_id into l_active_action_id;

    return l_active_action_id;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_redo(bigint) to public;
/*
 * Caller: history_trigger_func(), GUI	    
 *
 * Use Case: To set a session's active action.	    
 *
 * Description: It's just a simple update, but under the hood the update
 *   trigger on history_sessions will a) not allow the update if p_action
 *   belongs to another session b) replay the history, undoing and redoing
 *   actions, so the underlying session table goes back to the same state as
 *   it was just after p_action first occured.	It returns the session's
 *   active action after it is set.
 */

create or replace function history_session_set_active_action(
    p_session bigint, p_action bigint
)
returns bigint
as $$ 
declare
    l_active_action_id bigint;
begin
    update history_sessions
    set active_action_id = p_action
    where session_id = p_session
    returning active_action_id into l_active_action_id;

    return l_active_action_id;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_set_active_action(bigint, bigint) to public;
/*
 * Caller: Application. 
 *
 * Use Case: To reset the active action of session p_session to the parent
 *   of the active action, and return that parent action id. 
 *
 * Description: If the active action of session p_session has no parent,
 *   which is the case for the first action in the root timeline, then the
 *   function sets the active action to null and returns null.	This in
 *   effect means that all actions for session p_session have been undone,
 *   and there is nothing more to be undone.
 */

create or replace function history_session_undo(
    p_session bigint
)
returns bigint
as $$ 
declare
    l_active_action bigint;
begin
    update history_sessions
    set active_action_id = history_action_parent(active_action_id)
    where session_id = p_session
    returning active_action_id into l_active_action;

    return l_active_action;
end;
$$ language plpgsql
security definer;

grant execute on function history_session_undo(bigint) to public;
/*
 * Caller: history_session_actions() 
 *
 * Use Case: To determine the root timeline of a timeline. 
 *
 * Description: It walks history_timelines backwards starting at the passed
 *   timeline, until it finds a timeline with no parent action (root
 *   timeline), and it returns it.
 */

create or replace function history_timeline_root(
    p_timeline bigint
)
returns bigint
as $$ 
declare
    l_timeline bigint;
    l_parent_action_id bigint;
begin
    l_timeline := p_timeline;
    loop
        select parent_action_id into l_parent_action_id
        from history_timelines
        where timeline_id = l_timeline;

        if l_parent_action_id is null
        then
            return l_timeline;
        else
            l_timeline := history_action_timeline(l_parent_action_id);
        end if;
    end loop;
end;
$$ language plpgsql;
/*
 * Caller: history_sessions_trigger_func()   
 *
 * Use Case: To determine the sequence of actions that should be replayed in
 *   order to transform the session table from its state when p_from_action
 *   was the active action to its state when p_to_action was the active
 *   action.  
 *
 * Description: A negative action means undo it, a positive action means
 *   redo it.  This function is recursive, but it avoids deep recursion.
 */

create or replace function history_walk(
    p_from_action bigint, p_to_action bigint
)
returns bigint[]
as $$ 
declare
    l_first_action_in_session bigint;
    l_from_session bigint;
    l_to_session bigint;
    l_actions bigint[] = ARRAY[]::bigint[]; -- empty array
begin
    if p_from_action is null and p_to_action is null
    then -- noop
        return l_actions;
    end if;

    l_from_session := history_action_session(p_from_action);
    l_to_session := history_action_session(p_to_action);

    if p_to_action is null
    then
        l_first_action_in_session := history_session_first_action(l_from_session);
        return history_walk(p_from_action, l_first_action_in_session) || -l_first_action_in_session;
    end if;

    if p_from_action is null
    then
        l_first_action_in_session := history_session_first_action(l_to_session);
        return l_first_action_in_session || history_walk(l_first_action_in_session, p_to_action);
    end if;

    if l_from_session <> l_to_session
    then
        raise exception 'p_from_action session = %, p_to_action session = %', l_from_session, l_to_session
            using hint = 'the actions can not be from different sessions';
    end if;

    if p_from_action = p_to_action
    then -- base case, noop
        return l_actions;
    end if;

    while p_from_action > p_to_action
    loop
        l_actions = l_actions || -p_from_action;
        p_from_action := history_action_parent(p_from_action);
    end loop;

    /*
        We have no way of walking the action histories when p_from_action < p_to_action
        but we can walk backwards and then reverse the order and negate the actions.
    */
    return l_actions || history_reverse(history_walk(p_to_action, p_from_action));
end;
$$ language plpgsql;
/*
 * Caller: The update trigger on history_sessions.active_action_id.  
 *
 * Use Case: To replay the action history to keep the session base table
 *   consistent with the update of history_sessions.active_action_id.  
 *
 * Description: Note that this function is, be design, only called when the
 *   update to history_sessions.active_action_id happens outside a
 *   trigger.  The update of history_sessions.active_action_id
 *   within history_trigger_func() does not cause this trigger function to
 *   execute.
 */

create or replace function history_sessions_trigger_func() returns trigger
as $$ 
declare
    new_session bigint;
begin 

    /*
        CROSS CHECK - useful because history_walk() will gladly walk from
        a null to any to_action and assume you meant to start from the
        first action of to_action's session.  Without this check one could
        set the active_action_id of a session to null, and then update it
        to an action in another session.
    */
    new_session := history_action_session(new.active_action_id);
    if (new_session is not null) and (new_session <> old.session_id)
    then
        raise exception 'the new active_history_action_id is from session %', new_session
        using hint = 'the actions can not be from different sessions';
    end if;

    perform history_replay(history_walk(old.active_action_id, new.active_action_id));
    return null;
end;
$$ language plpgsql;

drop trigger if exists history_sessions_tr on history_sessions;
create trigger history_sessions_tr after update of active_action_id on history_sessions
for each row
    when (pg_trigger_depth() < 1)
    execute procedure history_sessions_trigger_func();
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
