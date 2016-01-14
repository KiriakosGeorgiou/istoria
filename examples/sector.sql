drop table if exists sector cascade;

create table sector (
    id bigserial,
    chart_id bigint not null,
    sector_name text not null,
    sector_geom text not null,
    gui_editor_action text not null
);

alter table sector add constraint sector_pk primary key (id);

drop trigger if exists sector_history_tr on sector;
create trigger sector_history_tr after insert or update or delete on sector
for each row
when (pg_trigger_depth() < 1)
execute procedure history_trigger_func('["chart_id"]');

-------------------------------------------------------------------------------------

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S010', 'polygon(1 2, 3 4, 1 2)', 'add sector');

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S020', 'polygon(9 9, 4 5, 9 9)', 'add sector');

update sector
set
    sector_geom = 'polygon(1 2, 3 4, 4 5, 1 2)',
    gui_editor_action = 'add point'
where id = 1;

update sector
set
    sector_name = 'S011',
    gui_editor_action = 'sector renamed'
where id = 1;

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

update sector
set
    sector_name = 'S012',
    gui_editor_action = 'sector renamed'
where id = 1;

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

select history_session_set_active_action(1, 3);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S100', 'polygon(3 3, 4 5, 9 9, 3 3)', 'add sector');

select history_session_set_active_action(1, 5);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S030', 'polygon(9 9, 4 5, 9 9)', 'add sector');

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

select history_session_set_active_action(1, 6);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S040', 'polygon(9 9, 4 5, 9 9)', 'add sector');

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

select history_session_set_active_action(1, 6);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S050', 'polygon(9 9, 4 6, 9 9)', 'add sector');

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S060', 'polygon(9 9, 4 7, 9 9)', 'add sector');

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);

select history_session_set_active_action(1, 9);

insert into sector (chart_id, sector_name, sector_geom, gui_editor_action)
values(1, 'S070', 'polygon(9 9, 5 6, 9 9)', 'add sector');

select
    action_id, ancestors, indent, parent_action_id, active,
    timeline_id, timeline_root, action, new->'sector_name', new->'gui_editor_action'
from history_session_actions(1);
