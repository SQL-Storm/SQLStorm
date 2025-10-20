-- {"query": "38026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2201} 
with recent_users as (
  select u.id as user_id, u.displayname, u.reputation, u.creationdate
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
active_questions as (
  select p.id as question_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.owneruserid,
         p.tags,
         p.answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answer_user_id,
         a.score as answer_score,
         a.creationdate as answer_creationdate
  from posts a
  where a.posttypeid = 2
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
         count(*) as total_votes
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '730 days' from votes)
  group by v.postid
),
comment_agg as (
  select c.postid,
         count(*) as comment_count,
         sum(c.score) as comment_score_sum,
         avg(c.score) as comment_score_avg,
         max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= (select max(creationdate) - interval '730 days' from comments)
  group by c.postid
),
tag_expansion as (
  select q.question_id,
         unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from active_questions q
  where q.tags is not null and q.tags like '<%>'
),
top_tags as (
  select te.tagname,
         count(distinct te.question_id) as q_count
  from tag_expansion te
  group by te.tagname
  having count(distinct te.question_id) >= 50
),
question_quality as (
  select q.question_id,
         q.creationdate,
         q.score as q_score,
         q.viewcount,
         q.owneruserid,
         q.answercount,
         coalesce(va.upvotes,0) as q_up,
         coalesce(va.downvotes,0) as q_down,
         coalesce(va.favorites,0) as q_fav,
         coalesce(va.total_votes,0) as q_votes,
         coalesce(ca.comment_count,0) as q_comments,
         coalesce(ca.comment_score_sum,0) as q_comment_score_sum,
         coalesce(ca.comment_score_avg,0.0) as q_comment_score_avg,
         coalesce(va.bounty_started,0) as bounty_started,
         coalesce(va.bounty_awarded,0) as bounty_awarded
  from active_questions q
  left join votes_agg va on va.postid = q.question_id
  left join comment_agg ca on ca.postid = q.question_id
),
answerers as (
  select a.question_id,
         a.answer_id,
         a.answer_user_id,
         a.answer_score,
         a.answer_creationdate,
         ru.reputation as answerer_rep,
         ru.creationdate as answerer_creation
  from answers a
  left join recent_users ru on ru.user_id = a.answer_user_id
),
accepted_map as (
  select p.id as question_id, p.acceptedanswerid
  from posts p
  where p.posttypeid = 1 and p.acceptedanswerid is not null
),
answer_stats as (
  select a.question_id,
         count(*) as answers_total,
         sum(case when a.answer_score > 0 then 1 else 0 end) as answers_positive,
         sum(case when a.answer_score < 0 then 1 else 0 end) as answers_negative,
         max(a.answer_score) as best_answer_score,
         min(a.answer_creationdate) as first_answer_time,
         avg(a.answerer_rep) filter (where a.answerer_rep is not null) as avg_answerer_rep_last_year
  from answerers a
  group by a.question_id
),
accepted_stats as (
  select am.question_id,
         a.answer_id as accepted_answer_id,
         a.answer_score as accepted_answer_score,
         a.answer_creationdate as accepted_answer_time
  from accepted_map am
  join answers a on a.id = am.acceptedanswerid
),
hot_network_events as (
  select ph.postid as question_id,
         min(ph.creationdate) as first_hot_time,
         count(*) as hot_events
  from posthistory ph
  where ph.posthistorytypeid in (52,53)
  group by ph.postid
),
closures as (
  select ph.postid as question_id,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as close_time,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopen_time,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
dup_links as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         count(*) filter (where pl.linktypeid = 1) as linked_links
  from postlinks pl
  group by pl.postid
),
tagged_questions as (
  select qq.*, te.tagname
  from question_quality qq
  join tag_expansion te on te.question_id = qq.question_id
  join top_tags tt on tt.tagname = te.tagname
),
scored as (
  select tq.question_id,
         tq.tagname,
         tq.q_score,
         tq.viewcount,
         tq.answercount,
         tq.q_up,
         tq.q_down,
         tq.q_fav,
         tq.q_votes,
         tq.q_comments,
         tq.q_comment_score_sum,
         tq.q_comment_score_avg,
         tq.bounty_started,
         tq.bounty_awarded,
         coalesce(as2.answers_total,0) as answers_total,
         coalesce(as2.answers_positive,0) as answers_positive,
         coalesce(as2.answers_negative,0) as answers_negative,
         coalesce(as2.best_answer_score,0) as best_answer_score,
         as2.first_answer_time,
         as2.avg_answerer_rep_last_year,
         ac.accepted_answer_id,
         ac.accepted_answer_score,
         ac.accepted_answer_time,
         he.first_hot_time,
         he.hot_events,
         cl.close_time,
         cl.reopen_time,
         cl.close_events,
         cl.reopen_events,
         dl.duplicate_links,
         dl.linked_links,
         extract(epoch from (coalesce(as2.first_answer_time, tq.creationdate) - tq.creationdate)) as secs_to_first_answer,
         extract(epoch from (coalesce(ac.accepted_answer_time, tq.creationdate) - tq.creationdate)) as secs_to_accept,
         case
           when tq.q_votes > 0 then (tq.q_up::numeric - tq.q_down::numeric) / tq.q_votes::numeric
           else null
         end as vote_ratio,
         case
           when tq.viewcount > 0 then (tq.q_fav::numeric / tq.viewcount::numeric)
           else 0
         end as fav_per_view,
         (coalesce(as2.answers_positive,0) - coalesce(as2.answers_negative,0)) as net_positive_answers
  from tagged_questions tq
  left join answer_stats as2 on as2.question_id = tq.question_id
  left join accepted_stats ac on ac.question_id = tq.question_id
  left join hot_network_events he on he.question_id = tq.question_id
  left join closures cl on cl.question_id = tq.question_id
  left join dup_links dl on dl.question_id = tq.question_id
),
ranked as (
  select s.*,
         row_number() over (partition by s.tagname order by
           coalesce(s.vote_ratio,0) desc,
           s.q_score desc,
           s.viewcount desc,
           s.answers_total desc,
           s.q_comments asc
         ) as tag_rank,
         percentile_cont(0.9) within group (order by s.viewcount) over (partition by s.tagname) as p90_views_in_tag
  from scored s
)
select
  r.tagname,
  r.question_id,
  r.q_score,
  r.viewcount,
  r.answercount,
  r.q_up,
  r.q_down,
  r.q_fav,
  r.q_votes,
  r.vote_ratio,
  r.fav_per_view,
  r.q_comments,
  r.q_comment_score_sum,
  r.q_comment_score_avg,
  r.answers_total,
  r.answers_positive,
  r.answers_negative,
  r.best_answer_score,
  r.net_positive_answers,
  r.accepted_answer_id,
  r.accepted_answer_score,
  r.secs_to_first_answer,
  r.secs_to_accept,
  r.first_hot_time,
  r.hot_events,
  r.close_time,
  r.reopen_time,
  r.close_events,
  r.reopen_events,
  r.duplicate_links,
  r.linked_links,
  r.p90_views_in_tag,
  dense_rank() over (order by r.viewcount desc) as global_view_rank,
  dense_rank() over (order by r.q_score desc) as global_score_rank
from ranked r
where r.tag_rank <= 20
order by r.tagname, r.tag_rank;