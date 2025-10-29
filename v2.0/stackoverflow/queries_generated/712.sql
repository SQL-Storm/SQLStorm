-- {"query": "712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3549} 
with
-- Active users with basic stats
u as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    date_trunc('month', u.creationdate) as join_month,
    extract(epoch from (u.lastaccessdate - u.creationdate)) / 86400.0 as lifetime_days
  from users u
),
-- Classify posts and derive tag array safely
p as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.acceptedanswerid,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer,
    case
      when p.tags is null then array[]::varchar[]
      when length(p.tags) <= 2 then array[]::varchar[]
      else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
    end as tag_arr
  from posts p
),
-- Derive per-user question/answer aggregates with window ranks
user_post_aggs as (
  select
    u.id as user_id,
    count(*) filter (where p.is_question=1) as q_count,
    count(*) filter (where p.is_answer=1) as a_count,
    sum(p.score) filter (where p.is_question=1) as q_score_sum,
    sum(p.score) filter (where p.is_answer=1) as a_score_sum,
    avg(nullif(p.score,0)) filter (where p.is_question=1) as q_avg_score_nonzero,
    max(p.viewcount) filter (where p.is_question=1) as q_best_views,
    min(p.creationdate) as first_post_at,
    max(p.lastactivitydate) as last_activity_at,
    count(*) filter (where p.closeddate is not null) as closed_posts,
    sum(case when p.is_question=1 and p.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
    rank() over (order by count(*) filter (where p.is_question=1) desc nulls last) as r_q_count,
    rank() over (order by sum(p.score) filter (where p.is_answer=1) desc nulls last) as r_a_score
  from u
  left join p on p.owneruserid = u.id
  group by u.id
),
-- Votes per user per type in a rolling window
user_vote_30d as (
  select
    v.userid,
    v.votetypeid,
    count(*) as votes_30d
  from votes v
  where v.creationdate >= (select max(creationdate) from posts) - interval '30 days'
  group by v.userid, v.votetypeid
),
-- Extract duplicates and linked relationships around a user
link_context as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
  from postlinks pl
),
-- Badges summary with class pivot-like aggregates
badge_aggs as (
  select
    b.userid,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
-- Compute tag affinity per user: top tag by frequency in questions
user_tag_affinity as (
  select
    p.owneruserid as user_id,
    t as tagname,
    count(*) as uses,
    row_number() over (partition by p.owneruserid order by count(*) desc, t) as rn
  from p
  cross join unnest(p.tag_arr) as t
  where p.is_question = 1 and p.owneruserid is not null
  group by p.owneruserid, t
),
-- Recent comment activity and sentiment-ish proxy via score thresholds
recent_comments as (
  select
    c.userid,
    count(*) as comments_30d,
    sum(case when c.score >= 5 then 1 else 0 end) as high_score_comments_30d,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.creationdate >= (select max(creationdate) from comments) - interval '30 days'
  group by c.userid
),
-- Post history closures and reopen counts per user
history_flags as (
  select
    ph.userid,
    count(*) filter (where ph.posthistorytypeid = 10) as closures,
    count(*) filter (where ph.posthistorytypeid = 11) as reopens,
    count(*) filter (where ph.posthistorytypeid in (12,13)) as deletions_changes,
    count(*) filter (where ph.posthistorytypeid = 50) as community_bumps
  from posthistory ph
  group by ph.userid
),
-- Per-user time-to-first-accepted-answer on their questions
q_time_to_accept as (
  select
    q.owneruserid as user_id,
    percentile_cont(0.5) within group (order by extract(epoch from (a.creationdate - q.creationdate))/3600.0) as median_hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1 and q.acceptedanswerid is not null and q.owneruserid is not null
  group by q.owneruserid
),
-- Compute activity deciles for users by reputation and post counts
user_quantiles as (
  select
    u.id as user_id,
    ntile(10) over (order by u.reputation desc) as rep_decile,
    ntile(10) over (order by coalesce(upa.q_count,0)+coalesce(upa.a_count,0) desc) as postcount_decile
  from u
  left join user_post_aggs upa on upa.user_id = u.id
),
-- A set operator example: union distinct of users with either gold badges or top 5% postcount
noteworthy_users as (
  select userid as user_id
  from badge_aggs
  where gold_badges > 0
  union
  select uq.user_id
  from user_quantiles uq
  where uq.postcount_decile <= 1
),
-- Correlated subquery: find user’s most-viewed question title
user_top_question as (
  select
    q.owneruserid as user_id,
    q.id as post_id,
    q.title,
    q.viewcount,
    rank() over (partition by q.owneruserid order by q.viewcount desc nulls last, q.id) as r
  from posts q
  where q.posttypeid = 1 and q.owneruserid is not null and q.viewcount is not null
),
-- Outer join combined feature set
features as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location_norm,
    u.join_month,
    u.lifetime_days,
    coalesce(upa.q_count,0) as q_count,
    coalesce(upa.a_count,0) as a_count,
    coalesce(upa.q_score_sum,0) as q_score_sum,
    coalesce(upa.a_score_sum,0) as a_score_sum,
    coalesce(upa.q_avg_score_nonzero, 0) as q_avg_score_nonzero,
    coalesce(upa.q_best_views, 0) as q_best_views,
    upa.first_post_at,
    upa.last_activity_at,
    coalesce(upa.closed_posts,0) as closed_posts,
    coalesce(upa.accepted_questions,0) as accepted_questions,
    coalesce(ba.badge_count,0) as badge_count,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.tag_badges,0) as tag_badges,
    ba.first_badge_at,
    ba.last_badge_at,
    coalesce(rc.comments_30d,0) as comments_30d,
    coalesce(rc.high_score_comments_30d,0) as high_score_comments_30d,
    rc.last_comment_at,
    coalesce(hf.closures,0) as closures,
    coalesce(hf.reopens,0) as reopens,
    coalesce(hf.deletions_changes,0) as deletions_changes,
    coalesce(hf.community_bumps,0) as community_bumps,
    coalesce(uq.rep_decile,10) as rep_decile,
    coalesce(uq.postcount_decile,10) as postcount_decile,
    coalesce(qta.median_hours_to_accept, null) as median_hours_to_accept,
    coalesce(uv2.votes_30d,0) as upvotes_30d,
    coalesce(uv3.votes_30d,0) as downvotes_30d,
    coalesce(uv5.votes_30d,0) as favorites_30d,
    coalesce(uv8.votes_30d,0) as bounty_start_30d,
    nt.tagname as top_tag,
    utq.title as top_question_title,
    utq.viewcount as top_question_views,
    case
      when coalesce(upa.q_count,0)+coalesce(upa.a_count,0) = 0 then null
      else round((coalesce(upa.q_score_sum,0)+coalesce(upa.a_score_sum,0))::numeric / nullif(coalesce(upa.q_count,0)+coalesce(upa.a_count,0),0), 2)
    end as avg_score_per_post,
    case
      when coalesce(upa.q_count,0) = 0 then 0.0
      else round(100.0 * coalesce(upa.accepted_questions,0)::numeric / nullif(upa.q_count,0), 2)
    end as q_accept_rate_pct,
    case
      when u.lifetime_days <= 0 then null
      else round((coalesce(upa.q_count,0)+coalesce(upa.a_count,0)) / nullif(u.lifetime_days,0), 3)
    end as posts_per_day,
    case
      when u.reputation < 100 then 'newbie'
      when u.reputation < 1000 then 'intermediate'
      when u.reputation < 10000 then 'advanced'
      else 'elite'
    end as rep_bucket
  from u
  left join user_post_aggs upa on upa.user_id = u.id
  left join badge_aggs ba on ba.userid = u.id
  left join recent_comments rc on rc.userid = u.id
  left join history_flags hf on hf.userid = u.id
  left join q_time_to_accept qta on qta.user_id = u.id
  left join user_quantiles uq on uq.user_id = u.id
  left join user_vote_30d uv2 on uv2.userid = u.id and uv2.votetypeid = 2
  left join user_vote_30d uv3 on uv3.userid = u.id and uv3.votetypeid = 3
  left join user_vote_30d uv5 on uv5.userid = u.id and uv5.votetypeid = 5
  left join user_vote_30d uv8 on uv8.userid = u.id and uv8.votetypeid = 8
  left join user_tag_affinity nt on nt.user_id = u.id and nt.rn = 1
  left join user_top_question utq on utq.user_id = u.id and utq.r = 1
),
-- Derive duplicate involvement using correlated existence checks
dup_involvement as (
  select
    u.id as user_id,
    count(*) filter (where exists (
      select 1
      from link_context lc
      join posts p1 on p1.id = lc.postid
      where lc.is_duplicate = 1 and p1.owneruserid = u.id
    )) as has_duplicates,
    count(*) filter (where exists (
      select 1
      from link_context lc
      join posts p2 on p2.id = lc.relatedpostid
      where lc.is_duplicate = 1 and p2.owneruserid = u.id
    )) as has_been_marked_as_original
  from users u
  group by u.id
),
-- Construct a synthetic KPI for ranking
scored as (
  select
    f.*,
    coalesce(0.4 * least(greatest((f.q_count + f.a_count)::numeric,0), 100)
           + 0.3 * least(greatest((f.q_score_sum + f.a_score_sum)::numeric,0), 1000)/10.0
           + 0.2 * coalesce(f.badge_count,0)
           + 0.1 * coalesce(f.top_question_views,0)::numeric / 1000.0
           - 0.15 * coalesce(f.closed_posts,0)
           - 0.1 * coalesce(f.deletions_changes,0)
           + case when f.gold_badges > 0 then 5 else 0 end
           + case when f.rep_bucket = 'elite' then 10 when f.rep_bucket='advanced' then 5 else 0 end, 0) as perf_score
  from features f
),
-- Windowed ranks and percentiles
ranked as (
  select
    s.*,
    dense_rank() over (order by s.perf_score desc nulls last) as rk_overall,
    percentile_disc(0.9) within group (order by s.perf_score) over () as p90_perf,
    avg(s.perf_score) over () as avg_perf
  from scored s
)
select
  r.user_id,
  r.displayname,
  r.location_norm,
  r.rep_bucket,
  r.reputation,
  r.q_count, r.a_count,
  r.q_score_sum, r.a_score_sum,
  r.avg_score_per_post,
  r.q_accept_rate_pct,
  r.posts_per_day,
  r.gold_badges, r.silver_badges, r.bronze_badges,
  r.top_tag,
  coalesce(r.top_question_title, '[none]') as top_question_title,
  r.top_question_views,
  r.comments_30d, r.high_score_comments_30d,
  r.closures, r.reopens, r.deletions_changes,
  r.upvotes_30d, r.downvotes_30d, r.favorites_30d, r.bounty_start_30d,
  r.median_hours_to_accept,
  r.rep_decile, r.postcount_decile,
  round(r.perf_score::numeric, 2) as perf_score,
  r.rk_overall,
  case when r.perf_score >= r.p90_perf then 'P90+' else 'Below P90' end as perf_band,
  r.avg_perf
from ranked r
where
  -- Complicated predicate mixing null logic, text ops, and math
  (
    (r.q_count + r.a_count >= 5 and coalesce(r.avg_score_per_post, 0) >= 0)
    or (r.gold_badges > 0 and r.perf_score is not null)
    or (r.top_tag is not null and r.top_tag ilike any (array['%sql%','%java%','%python%','%c%']))
  )
  and coalesce(r.location_norm, '') not ilike any (array['%test%','%bot%'])
  and (r.last_activity_at is null or r.last_activity_at <= now() or r.last_activity_at > r.first_post_at)
order by r.perf_score desc nulls last, r.reputation desc, r.user_id
limit 200;