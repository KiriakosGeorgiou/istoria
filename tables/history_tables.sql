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
