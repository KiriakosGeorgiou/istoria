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
