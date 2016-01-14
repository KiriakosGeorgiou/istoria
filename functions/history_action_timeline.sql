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
