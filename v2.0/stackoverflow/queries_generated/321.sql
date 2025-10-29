-- {"query": "321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2355} 
with
-- recent questions and their tags exploded
recent_questions as (
  select
    p.id as question_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneryserid as owner_user_id,
    lower(trim(t)) as tag
  from posts p
  left join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
      then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t on true
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
-- engagement metrics per question
engagement as (
  select
    q.question_id,
    count(distinct a.id) filter (where a.posttypeid = 2) as answer_count,
    count(distinct c.id) as comment_count,
    sum(v_bounty.bountyamount) as bounty_total,
    sum(case when v_vote.votetypeid = 2 then 1 when v_vote.votetypeid = 3 then -1 else 0 end) as net_votes
  from recent_questions q
  left join posts a on a.parentid = q.question_id and a.posttypeid = 2
  left join comments c on c.postid in (q.question_id, a.id)
  left join votes v_bounty on v_bounty.postid in (q.question_id, a.id) and v_bounty.votetypeid in (8,9)
  left join votes v_vote on v_vote.postid in (q.question_id, a.id) and v_vote.votetypeid in (2,3)
  group by q.question_id
),
-- closure and migration signals
moderation_signals as (
  select
    ph.postid as question_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,35)) as last_closed_or_migrated,
    bool_or(ph.posthistorytypeid in (11,13)) as had_reopen_or_undelete,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_events,
    count(*) filter (where ph.posthistorytypeid in (35,36,17)) as migration_events
  from posthistory ph
  join posts p on p.id = ph.postid and p.posttypeid = 1
  group by ph.postid
),
-- tag popularity snapshot
tag_popularity as (
  select
    lower(t.tagname) as tag,
    t.count as tag_count,
    row_number() over (order by t.count desc, t.tagname) as tag_rank
  from tags t
),
-- compute user activity and standing
user_profile as (
  select
    u.id as user_id,
    u.reputation,
    coalesce(u.upvotes,0) - coalesce(u.downvotes,0) as vote_delta,
    date_part('day', now() - u.creationdate) as account_age_days,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.upvotes, u.downvotes, u.creationdate
),
-- link graph features (duplicates and related)
link_graph as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_date
  from postlinks pl
  group by pl.postid
),
-- aggregate per-question by tag and user
question_rollup as (
  select
    q.question_id,
    min(q.creationdate) as creationdate,
    max(q.score) as score,
    max(q.viewcount) as viewcount,
    max(q.owner_user_id) as owner_user_id,
    array_agg(distinct q.tag) filter (where q.tag is not null) as tags,
    count(distinct q.tag) as tag_count
  from recent_questions q
  group by q.question_id
),
-- join all features
features as (
  select
    qr.question_id,
    qr.creationdate,
    qr.score,
    qr.viewcount,
    qr.owner_user_id,
    qr.tags,
    qr.tag_count,
    coalesce(e.answer_count,0) as answer_count,
    coalesce(e.comment_count,0) as comment_count,
    coalesce(e.bounty_total,0) as bounty_total,
    coalesce(e.net_votes,0) as net_votes,
    ms.last_closed_or_migrated,
    coalesce(ms.had_reopen_or_undelete,false) as had_reopen_or_undelete,
    coalesce(ms.close_events,0) as close_events,
    coalesce(ms.migration_events,0) as migration_events,
    coalesce(lg.duplicate_links,0) as duplicate_links,
    coalesce(lg.related_links,0) as related_links,
    lg.last_link_date,
    up.reputation,
    up.vote_delta,
    up.account_age_days,
    up.gold_badges,
    up.silver_badges,
    up.bronze_badges,
    up.total_badges
  from question_rollup qr
  left join engagement e on e.question_id = qr.question_id
  left join moderation_signals ms on ms.question_id = qr.question_id
  left join link_graph lg on lg.question_id = qr.question_id
  left join users u on u.id = qr.owner_user_id
  left join user_profile up on up.user_id = qr.owner_user_id
),
-- per-tag aggregates over selected questions
tag_agg as (
  select
    lower(t) as tag,
    count(distinct f.question_id) as q_count,
    sum(f.viewcount) as total_views,
    avg(nullif(f.score,0)) as avg_score_nonzero,
    percentile_cont(0.5) within group (order by f.viewcount) as p50_views
  from features f
  left join lateral unnest(coalesce(f.tags, array[]::varchar[])) t on true
  group by lower(t)
),
-- combine tags with global popularity snapshot
tag_enriched as (
  select
    ta.tag,
    coalesce(tp.tag_count, 0) as global_tag_count,
    ta.q_count,
    ta.total_views,
    ta.avg_score_nonzero,
    ta.p50_views,
    dense_rank() over (order by coalesce(tp.tag_count,0) desc, ta.q_count desc, ta.total_views desc) as tag_priority
  from tag_agg ta
  full outer join tag_popularity tp on tp.tag = ta.tag
),
-- windowed ranks and anomaly signals
scored as (
  select
    f.*,
    coalesce(te.tag_priority, 999999) as tag_priority,
    -- compute a complexity score mixing multiple signals
    (
      coalesce(log(greatest(f.viewcount,1)),0)
      + 0.5 * coalesce(f.answer_count,0)
      + 0.2 * coalesce(f.comment_count,0)
      + case when f.bounty_total > 0 then 1 else 0 end
      + 0.3 * coalesce(f.duplicate_links,0)
      - 0.4 * coalesce(f.close_events,0)
      + 0.1 * coalesce(f.total_badges,0)
      + case when f.last_closed_or_migrated is not null then -0.5 else 0 end
    ) as complexity_score,
    row_number() over (order by f.viewcount desc nulls last) as rn_views_desc,
    row_number() over (order by f.creationdate asc nulls last) as rn_oldest_first,
    avg(f.score) over (partition by f.owner_user_id) as owner_avg_score,
    sum(f.viewcount) over (partition by f.owner_user_id) as owner_total_views,
    count(*) over (partition by f.owner_user_id) as owner_question_count,
    lag(f.viewcount) over (order by f.creationdate) as prev_viewcount_by_time,
    lead(f.viewcount) over (order by f.creationdate) as next_viewcount_by_time
  from features f
  left join lateral (
    select min(tag_priority) as tag_priority
    from tag_enriched te
    where te.tag = any(coalesce(f.tags, array[]::varchar[]))
  ) te on true
)
select
  s.question_id,
  s.creationdate,
  s.viewcount,
  s.score,
  s.answer_count,
  s.comment_count,
  s.net_votes,
  s.bounty_total,
  s.duplicate_links,
  s.related_links,
  s.close_events,
  s.migration_events,
  s.last_closed_or_migrated,
  s.had_reopen_or_undelete,
  s.tags,
  s.tag_count,
  s.owner_user_id,
  s.reputation,
  s.vote_delta,
  s.account_age_days,
  s.gold_badges,
  s.silver_badges,
  s.bronze_badges,
  s.total_badges,
  s.owner_avg_score,
  s.owner_total_views,
  s.owner_question_count,
  s.prev_viewcount_by_time,
  s.next_viewcount_by_time,
  s.tag_priority,
  s.complexity_score,
  -- derived label: "hotness" bucket with null/edge handling
  case
    when s.viewcount is null then 'unknown'
    when s.viewcount >= 100000 then 'blazing'
    when s.viewcount >= 25000 then 'hot'
    when s.viewcount >= 5000 then 'warm'
    when s.viewcount >= 1000 then 'tepid'
    else 'cold'
  end as hotness_bucket
from scored s
where
  -- complex predicate combining multiple metrics and null-safe logic
  (
    coalesce(s.viewcount, 0) > 500
    and (s.answer_count >= 1 or s.comment_count >= 3)
    and (s.close_events = 0 or s.had_reopen_or_undelete is true)
  )
  or (
    s.bounty_total > 0
    and s.score >= coalesce(s.owner_avg_score, 0)
  )
  or (
    s.tag_priority <= 100
    and s.complexity_score > 2
  )
order by
  s.complexity_score desc nulls last,
  s.viewcount desc nulls last,
  s.creationdate desc
limit 500;