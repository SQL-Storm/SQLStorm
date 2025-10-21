-- {"query": "38075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 3270} 
with recent_questions as (
  select
    p.id as question_id,
    p.creationdate as question_created,
    p.title,
    p.tags,
    p.viewcount,
    p.score as question_score,
    p.owneruserid as asker_id
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_created
  from posts a
  where a.posttypeid = 2
),
first_answer as (
  select distinct on (a.question_id)
    a.question_id,
    a.answer_id as first_answer_id,
    a.answerer_id as first_answerer_id,
    a.answer_created as first_answer_created,
    extract(epoch from (a.answer_created - rq.question_created)) / 60.0 as minutes_to_first_answer
  from answers a
  join recent_questions rq on rq.question_id = a.question_id
  order by a.question_id, a.answer_created asc, a.answer_id asc
),
accepted_answer as (
  select
    q.id as question_id,
  q.acceptedanswerid as accepted_answer_id
  from posts q
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
),
answer_stats as (
  select
    rq.question_id,
    count(a.answer_id) as total_answers,
    avg(a.answer_score) as avg_answer_score,
    max(a.answer_score) as max_answer_score,
    sum(case when a.answer_score >= 1 then 1 else 0 end) as upvoted_answers
  from recent_questions rq
  left join answers a on a.question_id = rq.question_id
  group by rq.question_id
),
comment_activity as (
  select
    p.id as post_id,
    count(c.id) as comment_count,
    sum(c.score) as comment_score_sum,
    max(c.creationdate) as last_comment_date
  from posts p
  left join comments c on c.postid = p.id
  group by p.id
),
tag_expansion as (
  select
    rq.question_id,
    unnest(string_to_array(substring(rq.tags, 2, length(rq.tags)-2), '><')) as tag
  from recent_questions rq
  where rq.tags is not null and rq.tags <> ''
),
tag_quality as (
  select
    te.question_id,
    avg(t.count) as avg_tag_popularity,
    max(t.count) as max_tag_popularity,
    sum(case when t.ismoderaTORonly then 1 else 0 end) as moderator_only_tag_count
  from tag_expansion te
  left join tags t on lower(t.tagname) = lower(te.tag)
  group by te.question_id
),
asker_profile as (
  select
    u.id as user_id,
    u.reputation,
    u.upvotes,
    u.downvotes,
    u.views as profile_views,
    date_part('day', now() - u.creationdate) as account_age_days,
    coalesce(b.badge_gold,0) as badge_gold,
    coalesce(b.badge_silver,0) as badge_silver,
    coalesce(b.badge_bronze,0) as badge_bronze
  from users u
  left join (
    select
      userId,
      sum(case when class = 1 then 1 else 0 end) as badge_gold,
      sum(case when class = 2 then 1 else 0 end) as badge_silver,
      sum(case when class = 3 then 1 else 0 end) as badge_bronze
    from badges
    group by userid
  ) b on b.userid = u.id
),
question_votes as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.postid
),
close_events as (
  select
    ph.postid as question_id,
    min(ph.creationdate) as first_close_date,
    count(*) filter (where ph.posthistorytypeid = 10) as close_vote_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
duplicates as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as linked_links
  from postlinks pl
  group by pl.postid
),
answerer_diversity as (
  select
    a.question_id,
    count(distinct a.answerer_id) filter (where a.answerer_id is not null) as distinct_answerers
  from answers a
  group by a.question_id
),
time_buckets as (
  select
    rq.question_id,
    date_trunc('day', rq.question_created) as day_bucket,
    date_trunc('hour', rq.question_created) as hour_bucket,
    extract(isodow from rq.question_created) as dow
  from recent_questions rq
),
question_enriched as (
  select
    rq.question_id,
    rq.title,
    rq.tags,
    rq.viewcount,
    rq.question_score,
    rq.asker_id,
    ab.upvotes as q_upvotes,
    ab.downvotes as q_downvotes,
    ab.favorites as q_favorites,
    ab.bounty_total,
    fs.first_answer_id,
    fs.first_answerer_id,
    fs.first_answer_created,
    fs.minutes_to_first_answer,
    aa.accepted_answer_id,
    ast.total_answers,
    ast.avg_answer_score,
    ast.max_answer_score,
    ast.upvoted_answers,
    ca.comment_count as q_comment_count,
    ca.comment_score_sum as q_comment_score_sum,
    ca.last_comment_date as q_last_comment_date,
    tq.avg_tag_popularity,
    tq.max_tag_popularity,
    tq.moderator_only_tag_count,
    ap.reputation as asker_reputation,
    ap.upvotes as asker_upvotes,
    ap.downvotes as asker_downvotes,
    ap.profile_views as asker_profile_views,
    ap.account_age_days as asker_account_age_days,
    ap.badge_gold,
    ap.badge_silver,
    ap.badge_bronze,
    ce.first_close_date,
    ce.close_vote_events,
    ce.reopen_events,
    du.duplicate_links,
    du.linked_links,
    ad.distinct_answerers,
    tb.day_bucket,
    tb.hour_bucket,
    tb.dow
  from recent_questions rq
  left join question_votes ab on ab.question_id = rq.question_id
  left join first_answer fs on fs.question_id = rq.question_id
  left join accepted_answer aa on aa.question_id = rq.question_id
  left join answer_stats ast on ast.question_id = rq.question_id
  left join comment_activity ca on ca.post_id = rq.question_id
  left join tag_quality tq on tq.question_id = rq.question_id
  left join asker_profile ap on ap.user_id = rq.asker_id
  left join close_events ce on ce.question_id = rq.question_id
  left join duplicates du on du.question_id = rq.question_id
  left join answerer_diversity ad on ad.question_id = rq.question_id
  left join time_buckets tb on tb.question_id = rq.question_id
),
answer_enriched as (
  select
    a.answer_id,
    a.question_id,
    a.answerer_id,
    a.answer_score,
    a.answer_created,
    ca.comment_count as a_comment_count,
    ca.comment_score_sum as a_comment_score_sum,
    ca.last_comment_date as a_last_comment_date
  from answers a
  left join comment_activity ca on ca.post_id = a.answer_id
),
per_tag_rollup as (
  select
    te.tag,
    count(distinct qe.question_id) as questions,
    avg(qe.minutes_to_first_answer) filter (where qe.minutes_to_first_answer is not null) as avg_minutes_to_first_answer,
    percentile_cont(0.5) within group (order by qe.minutes_to_first_answer) as p50_minutes_to_first_answer,
    percentile_cont(0.9) within group (order by qe.minutes_to_first_answer) as p90_minutes_to_first_answer,
    avg(qe.total_answers) as avg_answers_per_question,
    avg(qe.question_score) as avg_question_score,
    avg(qe.q_upvotes - qe.q_downvotes) as avg_net_votes,
    avg(qe.viewcount) as avg_views,
    sum(qe.bounty_total) as total_bounty,
    sum(qe.close_vote_events) as close_events,
    sum(qe.reopen_events) as reopen_events
  from question_enriched qe
  join tag_expansion te on te.question_id = qe.question_id
  group by te.tag
),
hourly_rollup as (
  select
    qe.hour_bucket,
    count(*) as questions,
    avg(qe.minutes_to_first_answer) as avg_minutes_to_first_answer,
    avg(qe.total_answers) as avg_answers_per_question,
    sum(qe.q_favorites) as favorites,
    sum(qe.duplicate_links) as duplicate_links,
    sum(qe.close_vote_events) as close_events
  from question_enriched qe
  group by qe.hour_bucket
),
rankings as (
  select
    qe.*,
    rank() over (order by qe.minutes_to_first_answer) as r_fastest_answered,
    rank() over (order by qe.total_answers desc) as r_most_answers,
    rank() over (order by qe.viewcount desc) as r_most_viewed,
    rank() over (order by qe.q_upvotes - qe.q_downvotes desc) as r_highest_net_votes,
    dense_rank() over (partition by qe.dow order by qe.minutes_to_first_answer) as r_fastest_by_dow
  from question_enriched qe
)
select
  'questions' as section,
  r.question_id,
  r.title,
  r.tags,
  r.viewcount,
  r.question_score,
  r.q_upvotes,
  r.q_downvotes,
  r.q_favorites,
  r.bounty_total,
  r.first_answer_id,
  r.first_answerer_id,
  r.first_answer_created,
  r.minutes_to_first_answer,
  r.accepted_answer_id,
  r.total_answers,
  r.avg_answer_score,
  r.max_answer_score,
  r.upvoted_answers,
  r.q_comment_count,
  r.q_comment_score_sum,
  r.q_last_comment_date,
  r.avg_tag_popularity,
  r.max_tag_popularity,
  r.moderator_only_tag_count,
  r.asker_id,
  r.asker_reputation,
  r.asker_upvotes,
  r.asker_downvotes,
  r.asker_profile_views,
  r.asker_account_age_days,
  r.badge_gold,
  r.badge_silver,
  r.badge_bronze,
  r.first_close_date,
  r.close_vote_events,
  r.reopen_events,
  r.duplicate_links,
  r.linked_links,
  r.distinct_answerers,
  r.day_bucket,
  r.hour_bucket,
  r.dow,
  r.r_fastest_answered,
  r.r_most_answers,
  r.r_most_viewed,
  r.r_highest_net_votes,
  r.r_fastest_by_dow,
  null::text as rollup_key,
  null::timestamp as rollup_time,
  null::int as rollup_value1,
  null::numeric as rollup_value2
from rankings r
where r.total_answers is not null
union all
select
  'answers' as section,
  ae.answer_id as id,
  null,
  null,
  null,
  ae.answer_score,
  null,
  null,
  null,
  null,
  ae.answer_id,
  ae.answerer_id,
  ae.answer_created,
  null,
  null,
  null,
  null,
  ae.a_comment_count,
  ae.a_comment_score_sum,
  ae.a_last_comment_date,
  null,
  null,
  null,
  ae.answerer_id,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null::text,
  null::timestamp,
  null::int,
  null::numeric
from answer_enriched ae
where ae.answer_created >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
union all
select
  'per_tag_rollup' as section,
  null,
  null,
  t.tag,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  t.avg_minutes_to_first_answer,
  null,
  t.avg_answers_per_question,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  t.tag as rollup_key,
  null::timestamp,
  t.questions as rollup_value1,
  t.p90_minutes_to_first_answer as rollup_value2
from per_tag_rollup t
union all
select
  'hourly_rollup' as section,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  h.avg_minutes_to_first_answer,
  null,
  h.avg_answers_per_question,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  h.hour_bucket as rollup_key,
  h.hour_bucket as rollup_time,
  h.questions as rollup_value1,
  h.favoriteS as rollup_value2
from hourly_rollup h
order by section, coalesce(minutes_to_first_answer, 1e18) asc, coalesce(viewcount, 0) desc, coalesce(total_answers, 0) desc
limit 1000;