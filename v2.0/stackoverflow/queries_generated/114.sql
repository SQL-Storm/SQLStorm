-- {"query": "114.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3276} 
with
-- recent active users with rank buckets
recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    width_bucket(u.reputation, 0, 100000, 10) as rep_bucket,
    row_number() over (order by u.lastaccessdate desc, u.id) as rn_access
  from users u
  where u.lastaccessdate >= (select max(p.creationdate) from posts p where p.creationdate is not null) - interval '365 days'
),
-- questions with rich aggregates
q as (
  select
    p.id as question_id,
    p.owneruserid as asker_id,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    coalesce(p.answercount, 0) as answercount,
    regexp_replace(coalesce(p.title, ''), '\s+', ' ', 'g') as title_clean,
    string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
),
-- answers joined to questions
a as (
  select
    pa.id as answer_id,
    pa.parentid as question_id,
    pa.owneruserid as answerer_id,
    pa.creationdate as a_created,
    pa.score as a_score,
    dense_rank() over (partition by pa.parentid order by pa.score desc nulls last, pa.creationdate asc nulls last, pa.id) as rank_in_q
  from posts pa
  where pa.posttypeid = 2
),
-- comment densities on questions and answers
comment_stats as (
  select
    p.id as post_id,
    count(c.id) as comment_count,
    coalesce(avg(nullif(c.score, 0)), 0) as avg_nonzero_comment_score,
    max(c.creationdate) as last_comment_at
  from posts p
  left join comments c on c.postid = p.id
  group by p.id
),
-- vote breakdown per post
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
-- duplicate relationships
dupes as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id,
    pl.creationdate as link_created
  from postlinks pl
  where pl.linktypeid = 3
),
-- questions closed reasons (latest close event)
close_events as (
  select
    ph.postid as question_id,
    cast(nullif(ph.comment, '') as int) as close_reason_id,
    row_number() over (partition by ph.postid order by ph.creationdate desc, ph.id desc) as rn_close,
    ph.creationdate as closed_at
  from posthistory ph
  where ph.posthistorytypeid = 10
),
-- tag dimension expanded from questions
question_tags as (
  select
    q.question_id,
    lower(trim(t)) as tagname
  from q
  cross join lateral unnest(q.tag_arr) as t
),
-- join to tag counts for popularity metrics
tag_pop as (
  select
    qt.question_id,
    avg(coalesce(tags.count, 0)) as avg_tag_popularity,
    sum(case when coalesce(tags.count, 0) = 0 then 1 else 0 end) as zero_count_tags,
    count(*) as tag_count
  from question_tags qt
  left join tags on tags.tagname = qt.tagname
  group by qt.question_id
),
-- accepted answer quality vs best-scored answer
accepted_vs_best as (
  select
    q.question_id,
    q.acceptedanswerid,
    max(a.a_score) filter (where a.rank_in_q = 1) as best_answer_score,
    max(case when a.answer_id = q.acceptedanswerid then a.a_score end) as accepted_answer_score,
    min(a.a_created) as first_answer_at
  from q
  left join a on a.question_id = q.question_id
  group by q.question_id, q.acceptedanswerid
),
-- badge counts for askers and answerers
user_badges as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
-- rolling activity per question (window across time)
question_activity as (
  select
    q.question_id,
    q.q_created,
    q.q_score,
    count(a.answer_id) as answers_total,
    count(a.answer_id) filter (where a.a_created <= q.q_created + interval '7 days') as answers_in_7d,
    count(a.answer_id) filter (where a.a_created <= q.q_created + interval '30 days') as answers_in_30d
  from q
  left join a on a.question_id = q.question_id
  group by q.question_id, q.q_created, q.q_score
),
-- quality score per question using various features
quality_features as (
  select
    q.question_id,
    q.asker_id,
    q.q_created,
    q.q_score,
    q.viewcount,
    q.title_clean,
    tag_pop.avg_tag_popularity,
    tag_pop.tag_count,
    coalesce(vq.upvotes, 0) as q_up,
    coalesce(vq.downvotes, 0) as q_down,
    coalesce(vq.favorites, 0) as q_fav,
    coalesce(vq.total_votes, 0) as q_votes,
    coalesce(cs_q.comment_count, 0) as q_comments,
    coalesce(cs_q.avg_nonzero_comment_score, 0) as q_avg_cscore,
    coalesce(ce.close_reason_id, -1) as close_reason_id,
    ce.closed_at,
    avb.best_answer_score,
    avb.accepted_answer_score,
    (case
      when avb.accepted_answer_score is null then null
      when avb.best_answer_score is null then null
      else avb.accepted_answer_score - avb.best_answer_score
    end) as accepted_vs_best_delta,
    qa.answers_total,
    qa.answers_in_7d,
    qa.answers_in_30d,
    extract(epoch from (coalesce(avb.first_answer_at, q.q_created) - q.q_created)) / 3600.0 as hours_to_first_answer
  from q
  left join tag_pop on tag_pop.question_id = q.question_id
  left join vote_agg vq on vq.postid = q.question_id
  left join comment_stats cs_q on cs_q.post_id = q.question_id
  left join close_events ce on ce.question_id = q.question_id and ce.rn_close = 1
  left join accepted_vs_best avb on avb.question_id = q.question_id
  left join question_activity qa on qa.question_id = q.question_id
),
-- user profile enrichment
asker_profile as (
  select
    u.id as user_id,
    u.displayname as user_display,
    u.reputation,
    u.creationdate as user_created,
    u.location,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ru.rep_bucket,
    rank() over (order by u.reputation desc, u.id) as rep_rank_global
  from users u
  left join user_badges ub on ub.userid = u.id
  left join recent_users ru on ru.id = u.id
),
-- per-question difficulty score (arbitrary expression for benchmarking)
difficulty as (
  select
    qf.question_id,
    (
      0.5 * ln(1 + greatest(qf.viewcount, 0)) +
      1.2 * coalesce(qf.q_down, 0) -
      0.8 * coalesce(qf.q_up, 0) +
      2.0 * coalesce(nullif(qf.answers_in_7d, 0), 0) +
      case when qf.close_reason_id in (101,102,103,104,105) then 5 else 0 end +
      case when qf.accepted_vs_best_delta is not null and qf.accepted_vs_best_delta < 0 then 3 else 0 end +
      coalesce(10.0 / nullif(qf.tag_count, 0), 10) -
      coalesce(ln(nullif(qf.avg_tag_popularity, 0)), -2)
    ) as difficulty_score
  from quality_features qf
),
-- correlated subquery to get most-linked related question per question
most_linked as (
  select
    q.question_id,
    (
      select pl.relatedpostid
      from postlinks pl
      where pl.postid = q.question_id and pl.linktypeid = 1
      group by pl.relatedpostid
      order by count(*) desc, min(pl.creationdate) asc
      limit 1
    ) as top_related_id
  from q
),
-- compile answerer stats for the top answer per question
top_answerer as (
  select
    a.question_id,
    a.answer_id,
    a.answerer_id,
    a.a_score,
    a.a_created,
    row_number() over (partition by a.question_id order by a.a_score desc nulls last, a.a_created asc, a.answer_id) as rn
  from a
),
answerer_profile as (
  select
    ta.question_id,
    u.id as answerer_id,
    u.displayname as answerer_display,
    u.reputation as answerer_rep,
    ub.total_badges as answerer_badges,
    ru.rep_bucket as answerer_rep_bucket
  from top_answerer ta
  join users u on u.id = ta.answerer_id
  left join user_badges ub on ub.userid = u.id
  left join recent_users ru on ru.id = u.id
  where ta.rn = 1
)
select
  qf.question_id,
  qf.title_clean as question_title,
  left(coalesce(qf.title_clean, ''), 120) || case when length(coalesce(qf.title_clean, '')) > 120 then '…' else '' end as title_snippet,
  ap.user_id as asker_id,
  coalesce(ap.user_display, '[unknown]') as asker_display,
  ap.reputation as asker_rep,
  ap.total_badges as asker_badges,
  ap.rep_rank_global,
  qf.q_created,
  qf.q_score,
  qf.viewcount,
  qf.q_votes,
  qf.q_up,
  qf.q_down,
  qf.q_fav,
  qf.q_comments,
  qf.q_avg_cscore,
  qf.tag_count,
  round(coalesce(qf.avg_tag_popularity, 0)::numeric, 2) as avg_tag_popularity,
  qf.answers_total,
  qf.answers_in_7d,
  qf.answers_in_30d,
  qf.accepted_answer_score,
  qf.best_answer_score,
  qf.accepted_vs_best_delta,
  qf.hours_to_first_answer,
  qf.close_reason_id,
  qf.closed_at,
  d.difficulty_score,
  ml.top_related_id,
  coalesce(vbest.upvotes, 0) as best_answer_upvotes,
  coalesce(vbest.downvotes, 0) as best_answer_downvotes,
  coalesce(cs_best.comment_count, 0) as best_answer_comments,
  ap.location,
  ap.user_created,
  ap.gold_badges,
  ap.silver_badges,
  ap.bronze_badges,
  ap.rep_bucket as asker_rep_bucket,
  coalesce(an.answerer_id, -1) as top_answerer_id,
  coalesce(an.answerer_display, '[unknown]') as top_answerer_display,
  an.answerer_rep,
  an.answerer_badges,
  an.answerer_rep_bucket
from quality_features qf
left join difficulty d on d.question_id = qf.question_id
left join most_linked ml on ml.question_id = qf.question_id
left join accepted_vs_best avb on avb.question_id = qf.question_id
left join vote_agg vbest on vbest.postid = (
  select a2.answer_id
  from a a2
  where a2.question_id = qf.question_id
  order by a2.score desc nulls last, a2.a_created asc, a2.answer_id
  limit 1
)
left join comment_stats cs_best on cs_best.post_id = (
  select a3.answer_id
  from a a3
  where a3.question_id = qf.question_id
  order by a3.score desc nulls last, a3.a_created asc, a3.answer_id
  limit 1
)
left join asker_profile ap on ap.user_id = qf.asker_id
left join answerer_profile an on an.question_id = qf.question_id
where
  -- complicated predicate using null logic and string search
  (
    qf.accepted_vs_best_delta is null
    or qf.accepted_vs_best_delta < 0
    or (qf.accepted_vs_best_delta between 0 and 2 and qf.q_comments >= 3)
  )
  and (
    qf.title_clean ilike any (array['%performance%', '%join%', '%index%'])
    or exists (
      select 1 from question_tags qt
      where qt.question_id = qf.question_id
        and qt.tagname in ('sql', 'postgresql', 'mysql', 'tsql')
    )
  )
  and (
    qf.close_reason_id not in (101,102,103,104,105)
    or qf.close_reason_id is null
  )
  and coalesce(qf.viewcount, 0) >= 0
order by
  d.difficulty_score desc nulls last,
  qf.q_votes desc nulls last,
  qf.viewcount desc nulls last,
  qf.q_created desc
limit 500;