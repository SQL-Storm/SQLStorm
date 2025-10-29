-- {"query": "531.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2910} 
with
-- Active users with rank by reputation and activity recency
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
    case when position('.' in coalesce(u.websiteurl, '')) > 0 then 1 else 0 end as has_website,
    row_number() over (order by u.reputation desc, u.lastaccessdate desc, u.id) as rn_rep_recent,
    dense_rank() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc) as dr_loc_rep
  from users u
  where u.reputation > 0
),
-- Questions with tag array and edit/close info
questions as (
  select
    p.id as qid,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_arr,
    p.answercount,
    p.closeddate,
    p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
-- Answers table augmented
answers as (
  select
    a.id as aid,
    a.parentid as qid,
    a.owneruserid as answerer_id,
    a.score as a_score,
    a.creationdate as a_created
  from posts a
  where a.posttypeid = 2
),
-- Votes aggregated by post and type with window stats
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    max(v.creationdate) as last_vote_ts,
    stddev_pop(extract(epoch from v.creationdate)) over (partition by v.postid) as vote_time_jitter
  from votes v
  group by v.postid
),
-- Comment activity per question within 7 days of question creation
early_commenters as (
  select
    c.postid as qid,
    count(*) filter (where c.creationdate <= (q.creationdate + interval '7 days')) as early_comments,
    count(*) as total_comments,
    max(c.creationdate) as last_comment_ts
  from comments c
  join questions q on q.qid = c.postid
  group by c.postid
),
-- PostHistory-derived closes, edits, migrations, protected
q_history as (
  select
    ph.postid as qid,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as first_close_ts,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_votes_events,
    count(*) filter (where ph.posthistorytypeid in (5,6,4)) as edits,
    count(*) filter (where ph.posthistorytypeid in (35,36,17)) as migrations,
    count(*) filter (where ph.posthistorytypeid in (19)) as protected_events
  from posthistory ph
  group by ph.postid
),
-- Duplicate link relationships and general links
q_links as (
  select
    pl.postid as qid,
    count(*) filter (where pl.linktypeid = 3) as dup_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_ts
  from postlinks pl
  group by pl.postid
),
-- Tag popularity snapshot
tag_pop as (
  select
    t.tagname,
    t.count as tag_count,
    ntile(10) over (order by t.count desc nulls last) as tag_decile
  from tags t
),
-- Expand question tags and join popularity
q_tag_expanded as (
  select
    q.qid,
    lower(trim(t)) as tagname
  from questions q
  cross join lateral unnest(coalesce(q.tag_arr, array[]::varchar[])) as t
),
q_with_tag_stats as (
  select
    e.qid,
    count(*) as tag_cnt,
    sum(tp.tag_count) as sum_tag_popularity,
    avg(tp.tag_count::numeric) as avg_tag_popularity,
    max(tp.tag_decile) as worst_tag_decile,
    min(tp.tag_decile) as best_tag_decile
  from q_tag_expanded e
  left join tag_pop tp on tp.tagname = e.tagname
  group by e.qid
),
-- Per-question answer stats
answer_stats as (
  select
    a.qid,
    count(*) as answers_total,
    count(*) filter (where a.a_score > 0) as answers_positive,
    max(a.a_score) as max_answer_score,
    min(a.a_score) as min_answer_score,
    avg(a.a_score::numeric) as avg_answer_score,
    max(a.a_created) as last_answer_ts,
    count(distinct a.answerer_id) as distinct_answerers
  from answers a
  group by a.qid
),
-- Identify best answer by score then earliest
best_answer as (
  select distinct on (a.qid)
    a.qid,
    a.aid as best_aid,
    a.answerer_id as best_answerer_id,
    a.a_score as best_a_score,
    a.a_created as best_a_created
  from answers a
  order by a.qid, a.a_score desc nulls last, a.a_created asc, a.aid
),
-- User-level activity snapshots
user_post_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_posted,
    count(*) filter (where p.posttypeid = 2) as a_posted,
    sum(coalesce(p.score,0)) as sum_post_scores,
    max(p.lastactivitydate) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
-- Derived signals per question combining everything
question_metric as (
  select
    q.qid,
    q.creationdate,
    q.owneruserid as asker_id,
    q.score as q_score,
    q.viewcount,
    coalesce(q.answercount, 0) as answercount,
    q.closeddate,
    q.acceptedanswerid,
    coalesce(va.upvotes,0) as q_upvotes,
    coalesce(va.downvotes,0) as q_downvotes,
    coalesce(va.favorites,0) as q_favorites,
    va.vote_time_jitter,
    ec.early_comments,
    ec.total_comments,
    qh.first_close_ts,
    qh.close_votes_events,
    qh.edits,
    qh.migrations,
    qh.protected_events,
    ql.dup_links,
    ql.related_links,
    coalesce(qts.tag_cnt,0) as tag_cnt,
    coalesce(qts.sum_tag_popularity,0) as sum_tag_popularity,
    coalesce(qts.avg_tag_popularity,0) as avg_tag_popularity,
    qts.worst_tag_decile,
    qts.best_tag_decile,
    coalesce(ast.answers_total,0) as answers_total,
    coalesce(ast.answers_positive,0) as answers_positive,
    ast.max_answer_score,
    ast.min_answer_score,
    ast.avg_answer_score,
    ast.last_answer_ts,
    ast.distinct_answerers,
    ba.best_aid,
    ba.best_answerer_id,
    ba.best_a_score,
    ba.best_a_created
  from questions q
  left join vote_agg va on va.postid = q.qid
  left join early_commenters ec on ec.qid = q.qid
  left join q_history qh on qh.qid = q.qid
  left join q_links ql on ql.qid = q.qid
  left join q_with_tag_stats qts on qts.qid = q.qid
  left join answer_stats ast on ast.qid = q.qid
  left join best_answer ba on ba.qid = q.qid
),
-- Rank questions by multiple composite metrics
ranked_questions as (
  select
    qm.*,
    -- composite score mixing signals; avoid division by zero with nullif
    (
      coalesce(qm.q_score,0)*2
      + coalesce(qm.q_upvotes,0)
      - coalesce(qm.q_downvotes,0)*2
      + least(coalesce(qm.viewcount,0)/100, 100)
      + coalesce(qm.answers_positive,0)*3
      + case when qm.acceptedanswerid is not null then 15 else 0 end
      + case when qm.closeddate is not null then -20 else 0 end
      + coalesce(qm.q_favorites,0)*2
    )::numeric as composite_signal,
    -- freshness decay example
    extract(epoch from (now() - qm.creationdate))/86400.0 as age_days,
    (coalesce(qm.answers_total,0)::numeric / nullif(qm.tag_cnt,0)) as answers_per_tag,
    row_number() over (
      order by
        (coalesce(qm.q_upvotes,0) - coalesce(qm.q_downvotes,0)) desc,
        coalesce(qm.viewcount,0) desc,
        qm.creationdate desc
    ) as rn_popularity,
    percentile_cont(0.5) within group (order by coalesce(qm.viewcount,0)) over () as median_views_global
  from question_metric qm
),
-- Join asker and best-answerer user slices for extra dims
user_dims as (
  select
    au.user_id,
    au.displayname,
    au.reputation,
    au.norm_location,
    au.has_website,
    upa.q_posted,
    upa.a_posted,
    upa.sum_post_scores
  from active_users au
  left join user_post_activity upa on upa.user_id = au.user_id
)
select
  rq.qid,
  rq.creationdate as question_created,
  rq.q_score,
  rq.viewcount,
  rq.answercount,
  rq.q_upvotes,
  rq.q_downvotes,
  rq.q_favorites,
  rq.early_comments,
  rq.total_comments,
  rq.edits,
  rq.dup_links,
  rq.related_links,
  rq.tag_cnt,
  rq.sum_tag_popularity,
  rq.avg_tag_popularity,
  rq.answers_total,
  rq.answers_positive,
  rq.max_answer_score,
  rq.min_answer_score,
  rq.avg_answer_score,
  rq.distinct_answerers,
  rq.best_aid,
  rq.best_answerer_id,
  rq.best_a_score,
  rq.best_a_created,
  rq.acceptedanswerid,
  rq.closeddate,
  rq.first_close_ts,
  rq.close_votes_events,
  rq.migrations,
  rq.protected_events,
  rq.vote_time_jitter,
  rq.composite_signal,
  rq.age_days,
  rq.answers_per_tag,
  rq.rn_popularity,
  rq.median_views_global,
  -- Asker dims
  ask.displayname as asker_displayname,
  ask.reputation as asker_reputation,
  ask.norm_location as asker_location,
  ask.has_website as asker_has_website,
  ask.q_posted as asker_q_posted,
  ask.a_posted as asker_a_posted,
  ask.sum_post_scores as asker_sum_post_scores,
  -- Best answerer dims
  ans.displayname as best_answerer_displayname,
  ans.reputation as best_answerer_reputation,
  ans.norm_location as best_answerer_location,
  ans.has_website as best_answerer_has_website
from ranked_questions rq
left join user_dims ask on ask.user_id = rq.asker_id
left join user_dims ans on ans.user_id = rq.best_answerer_id
where
  -- complex predicate combining many signals
  (
    (rq.composite_signal > 50 and rq.age_days < 365)
    or (rq.answers_total >= 5 and coalesce(rq.avg_answer_score,0) > 1)
    or (rq.q_favorites >= 10 and rq.viewcount >= 1000)
    or (rq.closeddate is null and rq.rn_popularity <= 1000)
  )
  and coalesce(rq.tag_cnt,0) between 1 and 5
  and (rq.best_a_score is null or rq.best_a_score >= 0)
  and not (rq.q_downvotes > rq.q_upvotes and rq.viewcount < 50)
  and (
    rq.sum_tag_popularity is null
    or rq.sum_tag_popularity > 0
  )
order by
  rq.composite_signal desc nulls last,
  rq.rn_popularity asc,
  rq.viewcount desc,
  rq.qid
limit 500;