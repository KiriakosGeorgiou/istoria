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
