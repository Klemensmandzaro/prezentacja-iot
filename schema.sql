-- IoT Challenge – wklej całość w Supabase: SQL Editor -> New query -> Run
create table game(id int primary key default 1 check(id=1), state text not null default 'lobby', current_q int not null default 0, q_started_at timestamptz);
insert into game(id) values(1);
create table host_secret(pin text not null);
insert into host_secret values('0712');
create table questions(id int primary key, mission text, prompt text, options jsonb, points int default 1000, seconds int default 20);
create table answer_keys(q int primary key references questions(id), correct int not null);
create table players(id uuid primary key default gen_random_uuid(), nick text unique not null check(char_length(nick) between 2 and 20), score int not null default 0, created_at timestamptz default now());
create table answers(player_id uuid references players(id) on delete cascade, q int, choice int, points int default 0, primary key(player_id,q));

alter table game enable row level security; alter table questions enable row level security;
alter table host_secret enable row level security; alter table answer_keys enable row level security;
alter table players enable row level security; alter table answers enable row level security;
create policy "read game" on game for select to anon using(true);
create policy "read questions" on questions for select to anon using(true);

create view leaderboard as select nick, score from players order by score desc, created_at;
grant select on leaderboard to anon;

create function join_game(p_nick text) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin insert into players(nick) values(trim(p_nick)) returning id into v; return v; end $$;

create function submit_answer(p_player uuid,p_q int,p_choice int) returns void language plpgsql security definer set search_path=public as $$
declare g game; qq questions; el numeric; pts int:=0;
begin
  select * into g from game; select * into qq from questions where id=p_q;
  if g.state<>'question' or g.current_q<>p_q then return; end if;
  el:=extract(epoch from now()-g.q_started_at);
  if el>qq.seconds+2 then return; end if;
  if p_choice=(select correct from answer_keys where q=p_q) then pts:=round(qq.points*(0.5+0.5*greatest(0,1-el/qq.seconds))); end if;
  insert into answers values(p_player,p_q,p_choice,pts) on conflict do nothing;
  if found then update players set score=score+pts where id=p_player; end if;
end $$;

create function get_correct(p_q int) returns int language sql security definer set search_path=public as
$$ select correct from answer_keys where q=p_q and exists(select 1 from game where state in('results','final') and current_q>=p_q) $$;
create function get_my_result(p_player uuid,p_q int) returns json language sql security definer set search_path=public as
$$ select coalesce((select json_build_object('choice',choice,'points',points) from answers where player_id=p_player and q=p_q),'{}'::json) $$;
create function answer_count(p_q int) returns int language sql security definer set search_path=public as
$$ select count(*)::int from answers where q=p_q $$;

create function host_set(p_pin text,p_state text,p_q int) returns void language plpgsql security definer set search_path=public as $$
begin
  if p_pin is distinct from (select pin from host_secret limit 1) then raise exception 'bad pin'; end if;
  update game set state=p_state, current_q=p_q, q_started_at=case when p_state='question' then now() else q_started_at end;
end $$;
create function host_reset(p_pin text) returns void language plpgsql security definer set search_path=public as $$
begin
  if p_pin is distinct from (select pin from host_secret limit 1) then raise exception 'bad pin'; end if;
  delete from players; update game set state='lobby',current_q=0,q_started_at=null;
end $$;
revoke execute on all functions in schema public from public;
grant execute on function join_game,submit_answer,get_correct,get_my_result,answer_count,host_set,host_reset to anon;

alter publication supabase_realtime add table game;

insert into questions(id,mission,prompt,options) values
(1,'Misja 1: Skróty','Co oznacza skrót IoT?','["Internet of Things","Input of Time","Integrated Online Tools","Internal Optical Transfer"]'),
(2,'Misja 2: Komunikacja','Który protokół to lekki system publish/subscribe dla IoT?','["HTTP 1.0","MQTT","FTP","SMTP"]'),
(3,'Misja 3: Sprzęt','Co ma wbudowane typowy układ ESP32?','["Wi-Fi i Bluetooth","Tylko Ethernet","GPS i LTE","Tylko USB"]'),
(4,'Misja 4: Czujniki','Co mierzy czujnik DHT22?','["Ciśnienie","Temperaturę i wilgotność","Natężenie światła","Ruch"]'),
(5,'Misja 5: Elektronika','Do czego służy rezystor pull-up?','["Zwiększa napięcie zasilania","Utrzymuje stan wysoki na wejściu, gdy nic nie jest podłączone","Chłodzi układ","Wzmacnia Wi-Fi"]'),
(6,'Misja 6: Zasięg','Która sieć LPWAN ma duży zasięg i niski pobór energii?','["LoRaWAN","HDMI","NFC","PCIe"]'),
(7,'Misja 7: Platformy','Czym jest Raspberry Pi?','["Mikrokontrolerem bez systemu","Komputerem jednopłytkowym z Linuksem","Czujnikiem","Protokołem sieciowym"]'),
(8,'Misja 8: Zasilanie','Jakie jest napięcie logiczne ESP32?','["5 V","3,3 V","12 V","230 V"]');
insert into answer_keys values(1,0),(2,1),(3,0),(4,1),(5,1),(6,0),(7,1),(8,1);
