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
