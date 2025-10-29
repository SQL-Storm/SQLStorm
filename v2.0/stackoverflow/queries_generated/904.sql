-- {"query": "904.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3629} 
with
-- Active users with basic stats
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    date_trunc('month', u.creationdate) as user_cohort_month,
    u.upvotes,
    u.downvotes,
    u.views,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges,
    count(distinct case when b.tagbased = 1 then b.name end) as distinct_tag_badges
  from users u
  left join badges b on b.userid = u.id
  group by u.id
),
-- Questions and Answers with normalized tag arrays
posts_norm as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.lastactivitydate,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2, 0)), '><') as tag_arr
  from posts p
),
-- Recent activity window: last 365 days from max post date
bounds as (
  select
    (max(p.creationdate) - interval '365 days') as start_ts,
    max(p.creationdate) as end_ts
  from posts p
),
-- Filter to recent questions and answers
recent_posts as (
  select pn.*
  from posts_norm pn
  cross join bounds b
  where pn.creationdate >= b.start_ts
),
-- Map questions to their accepted answers (if any)
accepted_answers as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as question_created,
    q.score as question_score,
    q.viewcount as question_views,
    q.title as question_title,
    q.tag_arr as question_tags,
    a.id as accepted_answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as answer_created,
    a.score as answer_score
  from recent_posts q
  left join posts_norm a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
),
-- Compute first answer time and answer counts per question
answer_stats as (
  select
    q.id as question_id,
    min(a.creationdate) as first_answer_time,
    count(*) as total_answers,
    count(*) filter (where a.score > 0) as positive_answers
  from posts_norm q
  left join posts_norm a
    on a.parentid = q.id
    and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),
-- Votes aggregated per post with windowed rates
vote_agg as (
  select
    v.postid,
    sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes,
    sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes,
    sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites,
    sum(case when vt.name in ('BountyStart','BountyClose') then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as vote_events,
    -- rolling 30-day vote count per post for volatility
    count(*) filter (where v.creationdate >= (select max(v2.creationdate) from votes v2) - interval '30 days') as votes_last_30d
  from votes v
  join votetypes vt on vt.id = v.votetypeid
  group by v.postid
),
-- Post history signals like closes/reopens/protections
history_flags as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
    max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
    max(case when ph.posthistorytypeid = 19 then 1 else 0 end) as was_protected,
    max(case when ph.posthistorytypeid in (35,36) then 1 else 0 end) as was_migrated,
    max(case when ph.posthistorytypeid = 50 then 1 else 0 end) as community_bump,
    max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as became_hot,
    max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events
  from posthistory ph
  group by ph.postid
),
-- Link graph to count duplicates and related links
link_agg as (
  select
    pl.postid,
    sum(case when lt.name = 'Duplicate' then 1 else 0 end) as duplicate_links,
    sum(case when lt.name = 'Linked' then 1 else 0 end) as related_links
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid
  group by pl.postid
),
-- Tag popularity snapshot
tag_popularity as (
  select
    lower(t.tagname) as tagname,
    t.count as tag_global_count
  from tags t
),
-- Explode question tags and enrich with tag popularity
question_tags as (
  select
    q.id as question_id,
    lower(trim(tg)) as tagname
  from posts_norm q
  cross join lateral unnest(q.tag_arr) as tg
  where q.posttypeid = 1
),
question_tag_stats as (
  select
    qt.question_id,
    avg(tp.tag_global_count::numeric) as avg_tag_popularity,
    min(tp.tag_global_count) as min_tag_popularity,
    max(tp.tag_global_count) as max_tag_popularity,
    count(*) as tag_count
  from question_tags qt
  left join tag_popularity tp on tp.tagname = qt.tagname
  group by qt.question_id
),
-- Build user activity cohorts for recent year
user_activity as (
  select
    au.user_id,
    date_trunc('month', p.creationdate) as activity_month,
    count(*) filter (where p.posttypeid = 1) as questions_asked,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
    sum(coalesce(p.score,0)) as net_post_score
  from active_users au
  left join posts_norm p on p.owneruserid = au.user_id
  cross join bounds b
  where p.creationdate >= b.start_ts
  group by au.user_id, date_trunc('month', p.creationdate)
),
-- Rank users by recent contribution using a composite score
user_rank as (
  select
    ua.user_id,
    sum(ua.answers_posted * 2 + ua.questions_asked * 1 + ua.net_post_score * 0.5 + coalesce(ua.question_views,0) * 0.001) as contrib_score,
    rank() over (order by sum(ua.answers_posted * 2 + ua.questions_asked * 1 + ua.net_post_score * 0.5 + coalesce(ua.question_views,0) * 0.001) desc) as contrib_rank
  from user_activity ua
  group by ua.user_id
),
-- Compute response time in hours and quality metrics for accepted answers
qa_quality as (
  select
    aa.question_id,
    aa.asker_id,
    aa.answerer_id,
    extract(epoch from (aa.answer_created - aa.question_created))/3600.0 as accepted_answer_hours,
    case
      when aa.answer_score is null then 0
      when aa.answer_score >= 5 then 3
      when aa.answer_score >= 1 then 2
      when aa.answer_score >= 0 then 1
      else 0
    end as accepted_answer_quality_bucket
  from accepted_answers aa
),
-- Per-question comprehensive metrics
question_metrics as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.commentcount,
    q.favoritecount,
    q.closeddate,
    va.upvotes,
    va.downvotes,
    va.favorites,
    va.bounty_total,
    va.vote_events,
    va.votes_last_30d,
    hf.was_closed,
    hf.was_reopened,
    hf.was_protected,
    hf.was_migrated,
    hf.community_bump,
    hf.became_hot,
    hf.removed_hot,
    hf.edit_events,
    la.duplicate_links,
    la.related_links,
    qts.avg_tag_popularity,
    qts.min_tag_popularity,
    qts.max_tag_popularity,
    qts.tag_count,
    ans.first_answer_time,
    ans.total_answers,
    ans.positive_answers
  from posts_norm q
  left join vote_agg va on va.postid = q.id
  left join history_flags hf on hf.postid = q.id
  left join link_agg la on la.postid = q.id
  left join question_tag_stats qts on qts.question_id = q.id
  left join answer_stats ans on ans.question_id = q.id
  where q.posttypeid = 1
),
-- Compute engagement scores combining multiple signals
engagement_scored as (
  select
    qm.question_id,
    qm.asker_id,
    coalesce(qm.viewcount,0) as views,
    coalesce(qm.score,0) as post_score,
    coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) as net_votes,
    coalesce(qm.favorites,0) as favorites,
    coalesce(qm.bounty_total,0) as bounty,
    coalesce(qm.total_answers,0) as answers_total,
    coalesce(qm.positive_answers,0) as answers_positive,
    coalesce(qm.votes_last_30d,0) as votes_last_30d,
    coalesce(qm.edit_events,0) as edit_events,
    coalesce(qm.duplicate_links,0) as dup_links,
    coalesce(qm.related_links,0) as rel_links,
    coalesce(qm.avg_tag_popularity,0) as avg_tag_popularity,
    case when qm.closeddate is not null or qm.was_closed = 1 then 1 else 0 end as is_closed,
    -- composite engagement score
    least(1000,
      (coalesce(qm.viewcount,0) * 0.01)
      + (greatest(coalesce(qm.score,0),0) * 5)
      + (coalesce(qm.favorites,0) * 3)
      + (coalesce(qm.bounty_total,0) * 0.1)
      + (coalesce(qm.total_answers,0) * 4)
      + (coalesce(qm.related_links,0) * 1.5)
      + (coalesce(qm.duplicate_links,0) * -2)
      + (coalesce(qm.edit_events,0) * 0.5)
      + (coalesce(qm.votes_last_30d,0) * 1.2)
    ) as engagement_score
  from question_metrics qm
),
-- Correlated subquery for most active commenter per question
top_commenter as (
  select
    c.postid as question_id,
    (select c2.userid
     from comments c2
     where c2.postid = c.postid
     group by c2.userid
     order by count(*) desc nulls last, max(c2.score) desc nulls last, min(c2.creationdate) asc
     limit 1) as top_commenter_userid
  from comments c
  group by c.postid
),
-- Normalize user fields for final join and compute anomalies
user_enriched as (
  select
    au.user_id,
    au.displayname,
    au.reputation,
    au.location,
    au.websiteurl,
    au.upvotes,
    au.downvotes,
    au.views,
    au.gold_badges,
    au.silver_badges,
    au.bronze_badges,
    au.distinct_tag_badges,
    ur.contrib_score,
    ur.contrib_rank,
    case
      when au.reputation = 0 and (au.upvotes + au.downvotes) > 50 then 'vote-heavy-low-rep'
      when au.reputation > 100000 then 'legend'
      when au.reputation between 10000 and 100000 then 'veteran'
      when au.reputation between 1000 and 9999 then 'regular'
      when au.reputation between 1 and 999 then 'newbie'
      else 'unknown'
    end as user_segment
  from active_users au
  left join user_rank ur on ur.user_id = au.user_id
),
-- Final ranking of questions with window functions and null logic
ranked_questions as (
  select
    es.question_id,
    es.asker_id,
    es.engagement_score,
    es.views,
    es.post_score,
    es.net_votes,
    es.favorites,
    es.bounty,
    es.answers_total,
    es.answers_positive,
    es.votes_last_30d,
    es.edit_events,
    es.dup_links,
    es.rel_links,
    es.avg_tag_popularity,
    es.is_closed,
    qc.accepted_answer_hours,
    qc.accepted_answer_quality_bucket,
    row_number() over (order by es.engagement_score desc, es.views desc, es.post_score desc, es.net_votes desc) as rownum,
    dense_rank() over (order by es.engagement_score desc) as engagement_dr,
    ntile(10) over (order by es.engagement_score desc) as engagement_decile
  from engagement_scored es
  left join qa_quality qc on qc.question_id = es.question_id
)
select
  rq.rownum,
  rq.engagement_dr,
  rq.engagement_decile,
  rq.question_id,
  q.title,
  q.creationdate as question_created,
  q.viewcount,
  q.score as question_score,
  q.answercount,
  q.commentcount,
  q.favoritecount,
  q.closeddate,
  rq.engagement_score,
  rq.accepted_answer_hours,
  rq.accepted_answer_quality_bucket,
  rq.answers_total,
  rq.answers_positive,
  rq.net_votes,
  rq.votes_last_30d,
  rq.edit_events,
  rq.dup_links,
  rq.rel_links,
  rq.avg_tag_popularity,
  rq.is_closed,
  ue.user_id as asker_id,
  coalesce(ue.displayname, q.ownerdisplayname, 'anonymous') as asker_displayname,
  ue.user_segment,
  ue.reputation,
  ue.gold_badges,
  ue.silver_badges,
  ue.bronze_badges,
  ue.contrib_score,
  ue.contrib_rank,
  tc.top_commenter_userid,
  coalesce(au.displayname, 'n/a') as top_commenter_displayname,
  -- string expressions and NULL logic for a compact summary
  trim(both ' ' from
    coalesce(q.title, '')
    || case when q.tags is not null then ' [' || regexp_replace(q.tags, '[<>]', '', 'g') || ']' else '' end
  ) as question_summary
from ranked_questions rq
join posts_norm q on q.id = rq.question_id
left join user_enriched ue on ue.user_id = rq.asker_id
left join top_commenter tc on tc.question_id = rq.question_id
left join users au on au.id = tc.top_commenter_userid
where
  -- complex predicate combining multiple signals
  (
    (rq.engagement_decile <= 3 and rq.accepted_answer_hours is not null)
    or (rq.engagement_score >= 200 and rq.answers_total >= 1)
    or (rq.is_closed = 0 and rq.avg_tag_popularity > 0 and rq.votes_last_30d >= 5)
  )
  and coalesce(q.viewcount,0) >= 10
  and (q.closeddate is null or q.closeddate > q.creationdate)
  and (ue.user_segment is distinct from 'unknown' or ue.contrib_rank <= 100)
order by rq.engagement_score desc, rq.rownum
limit 500;