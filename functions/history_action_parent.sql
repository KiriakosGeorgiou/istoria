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
