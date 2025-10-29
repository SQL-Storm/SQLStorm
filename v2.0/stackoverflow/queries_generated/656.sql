-- {"query": "656.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3223} 
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
         row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_badge_rollup as (
  select b.userid as user_id,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
q as (
  select p.id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.title,
         p.tags,
         p.closeddate,
         p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
a as (
  select p.id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
question_activity as (
  select q.id as question_id,
         q.user_id as asker_id,
         q.creationdate as q_created,
         q.score as q_score,
         q.viewcount,
         q.answercount,
         q.title,
         q.tags,
         q.closeddate,
         q.acceptedanswerid,
         count(a.id) as answers_total,
         sum(case when a.score > 0 then 1 else 0 end) as answers_pos,
         max(a.score) as max_answer_score,
         min(a.creationdate) filter (where a.id is not null) as first_answer_time,
         max(a.creationdate) filter (where a.id is not null) as last_answer_time
  from q
  left join a on a.question_id = q.id
  group by q.id, q.user_id, q.creationdate, q.score, q.viewcount, q.answercount, q.title, q.tags, q.closeddate, q.acceptedanswerid
),
votes_rollup as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
         min(v.creationdate) as first_vote_time,
         max(v.creationdate) as last_vote_time
  from votes v
  group by v.postid
),
ph_closure as (
  select ph.postid,
         min(ph.creationdate) filter (where ph.posthistorytypeid in (10,35)) as first_close_time,
         max(case when ph.posthistorytypeid in (10,35) then try_cast(ph.comment as int) end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)
  group by ph.postid
),
dupe_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as orig_post_id,
         min(pl.creationdate) as first_dupe_link_time
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
tag_extracted as (
  select qa.question_id,
         unnest(string_to_array(substring(coalesce(qa.tags, ''), 2, greatest(length(coalesce(qa.tags, ''))-2,0)), '><')) as tag
  from question_activity qa
),
tag_top as (
  select question_id,
         array_agg(tag order by tag) as tags_array,
         string_agg(tag, '|') as tags_pipe
  from tag_extracted
  group by question_id
),
user_activity_window as (
  select qa.asker_id as user_id,
         qa.question_id,
         qa.q_created,
         qa.q_score,
         coalesce(vr.upvotes,0) as upvotes,
         coalesce(vr.downvotes,0) as downvotes,
         coalesce(vr.favorites,0) as favorites,
         qa.viewcount,
         qa.answers_total,
         qa.answers_pos,
         qa.max_answer_score,
         qa.first_answer_time,
         qa.last_answer_time,
         ph.first_close_time,
         ph.last_close_reason_id,
         dl.orig_post_id,
         dl.first_dupe_link_time,
         tt.tags_array,
         tt.tags_pipe,
         row_number() over (partition by qa.asker_id order by qa.q_created desc, qa.question_id desc) as rn_recent,
         sum(qa.q_score) over (partition by qa.asker_id) as sum_q_score_user,
         avg(qa.q_score) over (partition by qa.asker_id) as avg_q_score_user,
         count(*) over (partition by qa.asker_id) as cnt_q_user,
         sum(coalesce(vr.upvotes,0)) over (partition by qa.asker_id) as sum_up_user,
         sum(coalesce(vr.downvotes,0)) over (partition by qa.asker_id) as sum_down_user
  from question_activity qa
  left join votes_rollup vr on vr.postid = qa.question_id
  left join ph_closure ph on ph.postid = qa.question_id
  left join dupe_links dl on dl.dup_post_id = qa.question_id
  left join tag_top tt on tt.question_id = qa.question_id
),
qualified_users as (
  select ru.user_id
  from recent_users ru
  left join user_badge_rollup ubr on ubr.user_id = ru.user_id
  where ru.rn <= 2000
    and (coalesce(ubr.gold_badges,0) + coalesce(ubr.silver_badges,0) + coalesce(ubr.bronze_badges,0)) >= 1
),
mix as (
  select ua.user_id,
         ua.question_id,
         ua.q_created,
         ua.q_score,
         ua.upvotes,
         ua.downvotes,
         ua.favorites,
         ua.viewcount,
         ua.answers_total,
         ua.answers_pos,
         ua.max_answer_score,
         ua.first_answer_time,
         ua.last_answer_time,
         ua.first_close_time,
         ua.last_close_reason_id,
         ua.orig_post_id,
         ua.first_dupe_link_time,
         ua.tags_array,
         ua.tags_pipe,
         ua.rn_recent,
         ua.sum_q_score_user,
         ua.avg_q_score_user,
         ua.cnt_q_user
  from user_activity_window ua
  join qualified_users qu on qu.user_id = ua.user_id
),
ranked as (
  select m.*,
         dense_rank() over (order by (m.q_score + coalesce(m.upvotes,0) - coalesce(m.downvotes,0)) desc, m.viewcount desc) as dr_global,
         dense_rank() over (partition by m.user_id order by (m.q_score + coalesce(m.upvotes,0)*0.8 - coalesce(m.downvotes,0)*1.2 + coalesce(m.favorites,0)*0.5) desc, m.viewcount desc) as dr_user,
         case when m.first_close_time is not null then 1 else 0 end as is_closed,
         case when m.orig_post_id is not null then 1 else 0 end as is_duplicate
  from mix m
),
user_summary as (
  select m.user_id,
         count(*) as questions_count,
         sum(case when m.is_closed = 1 then 1 else 0 end) as closed_count,
         sum(case when m.is_duplicate = 1 then 1 else 0 end) as duplicate_count,
         avg(m.q_score) as avg_q_score,
         percentile_cont(0.5) within group (order by m.q_score) as median_q_score,
         max(m.viewcount) as max_views,
         min(m.q_created) as first_question_time,
         max(m.q_created) as last_question_time
  from ranked m
  group by m.user_id
),
final_rows as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate as user_creation,
         ru.location,
         ru.websiteurl_norm,
         coalesce(ubr.total_badges,0) as total_badges,
         coalesce(ubr.gold_badges,0) as gold_badges,
         coalesce(ubr.silver_badges,0) as silver_badges,
         coalesce(ubr.bronze_badges,0) as bronze_badges,
         us.questions_count,
         us.closed_count,
         us.duplicate_count,
         us.avg_q_score,
         us.median_q_score,
         us.max_views,
         us.first_question_time,
         us.last_question_time,
         r.question_id,
         r.q_created,
         r.q_score,
         r.upvotes,
         r.downvotes,
         r.favorites,
         r.viewcount,
         r.answers_total,
         r.answers_pos,
         r.max_answer_score,
         r.first_answer_time,
         r.last_answer_time,
         r.first_close_time,
         r.last_close_reason_id,
         r.orig_post_id,
         r.first_dupe_link_time,
         r.tags_array,
         r.tags_pipe,
         r.dr_global,
         r.dr_user,
         r.is_closed,
         r.is_duplicate,
         case
           when r.tags_pipe is null or r.tags_pipe = '' then 'untagged'
           when position('sql' in lower(r.tags_pipe)) > 0 then 'sqlish'
           when position('python' in lower(r.tags_pipe)) > 0 then 'pythonish'
           else 'other'
         end as tag_bucket,
         case
           when r.first_answer_time is null then null
           else extract(epoch from (r.first_answer_time - r.q_created))::bigint
         end as secs_to_first_answer,
         case
           when r.last_answer_time is null then null
           else extract(epoch from (r.last_answer_time - r.q_created))::bigint
         end as secs_to_last_answer,
         case
           when r.first_close_time is null then null
           else extract(epoch from (r.first_close_time - r.q_created))::bigint
         end as secs_to_close,
         case
           when r.first_dupe_link_time is null then null
           else extract(epoch from (r.first_dupe_link_time - r.q_created))::bigint
         end as secs_to_dupe_link,
         case when r.q_score >= coalesce(us.avg_q_score, 0) then 1 else 0 end as above_user_avg_score
  from recent_users ru
  join qualified_users qu on qu.user_id = ru.user_id
  left join user_badge_rollup ubr on ubr.user_id = ru.user_id
  left join user_summary us on us.user_id = ru.user_id
  left join lateral (
    select r.*
    from ranked r
    where r.user_id = ru.user_id
      and r.rn_recent <= 5
    order by r.rn_recent
    limit 5
  ) r on true
),
with_nulls as (
  select fr.* from final_rows fr
  union all
  select ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.websiteurl_norm,
         coalesce(ubr.total_badges,0), coalesce(ubr.gold_badges,0), coalesce(ubr.silver_badges,0), coalesce(ubr.bronze_badges,0),
         us.questions_count, us.closed_count, us.duplicate_count, us.avg_q_score, us.median_q_score, us.max_views, us.first_question_time, us.last_question_time,
         null, null, null, null, null, null, null, null, null, null, null, null, null,
         null, null, null, null, null, null, null, null, null, null, null
  from recent_users ru
  join qualified_users qu on qu.user_id = ru.user_id
  left join user_badge_rollup ubr on ubr.user_id = ru.user_id
  left join user_summary us on us.user_id = ru.user_id
  where not exists (select 1 from ranked r where r.user_id = ru.user_id)
),
scored as (
  select wn.*,
         coalesce(q_score,0) * 1.0
         + coalesce(upvotes,0) * 0.7
         - coalesce(downvotes,0) * 1.1
         + coalesce(favorites,0) * 0.5
         + least(coalesce(viewcount,0), 10000) / 100.0
         - case when is_closed = 1 then 2 else 0 end
         - case when is_duplicate = 1 then 1 else 0 end
         + case when secs_to_first_answer is not null then greatest(0, 60000 - secs_to_first_answer) / 60000.0 else 0 end
         as perf_score
  from with_nulls wn
)
select *
from scored s
where
  -- complicated predicate mixing nulls, regex-ish, and date windows
  (
    s.tag_bucket in ('sqlish','pythonish')
    or (s.tags_pipe is null and s.questions_count >= 1)
    or (s.tags_pipe like '%|c%|%' escape '|' or s.tags_pipe like '%java%')
  )
  and coalesce(s.reputation, 0) >= 1
  and coalesce(s.total_badges,0) >= 1
  and (
    s.q_created is null
    or s.q_created >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
  )
  and (
    s.location is null
    or length(trim(s.location)) >= 0
  )
  and (
    s.websiteurl_norm is null
    or s.websiteurl_norm ~* '^https?://'
    or s.websiteurl_norm in ('n/a')
  )
order by s.perf_score desc nulls last, s.dr_global nulls last, s.user_id, s.question_id nulls last
limit 500;