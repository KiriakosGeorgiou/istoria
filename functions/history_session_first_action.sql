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
