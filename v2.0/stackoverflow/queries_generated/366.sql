-- {"query": "366.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3374} 
with
-- Normalize tag arrays from bracketed string and filter to programming-related tags
q as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.OwnerUserId,
    p.Score as QuestionScore,
    p.ViewCount,
    p.AcceptedAnswerId,
    coalesce(string_to_array(nullif(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), ''), '><'), array[]::varchar[]) as tag_arr
  from Posts p
  where p.PostTypeId = 1
),
-- Expand tags to one-per-row
qt as (
  select
    q.QuestionId,
    lower(trim(t)) as tag
  from q
  left join lateral unnest(q.tag_arr) as t on true
),
-- Derive question-level tag stats
q_tag_agg as (
  select
    QuestionId,
    count(*) filter (where tag is not null and tag <> '') as tag_count,
    max(tag) filter (where tag like 'sql%') as has_sql_like,
    sum(case when tag in ('sql','postgresql','mysql','tsql','oracle','sqlite') then 1 else 0 end) as db_tag_hits
  from qt
  group by QuestionId
),
-- Recent activity on questions (edits, closures, migrations)
q_recent_hist as (
  select
    ph.PostId as QuestionId,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,10,11,12,13,35,36)) as last_major_event,
    count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13)) as mod_action_count,
    bool_or(ph.PostHistoryTypeId = 10) as was_closed,
    max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as closed_at
  from PostHistory ph
  join Posts pq on pq.Id = ph.PostId and pq.PostTypeId = 1
  group by ph.PostId
),
-- Accepted answer stats and fallback to top-scored answer if no accepted
answers as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerUserId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreated,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score
  from Posts a
  where a.PostTypeId = 2
),
best_answer as (
  select
    q.QuestionId,
    coalesce(q.AcceptedAnswerId, a_by_score.AnswerId) as BestAnswerId,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as IsAcceptedPresent,
    coalesce(a_acc.AnswerUserId, a_by_score.AnswerUserId) as BestAnswerUserId,
    coalesce(a_acc.AnswerScore, a_by_score.AnswerScore) as BestAnswerScore,
    coalesce(a_acc.AnswerCreated, a_by_score.AnswerCreated) as BestAnswerCreated
  from q
  left join answers a_acc on a_acc.AnswerId = q.AcceptedAnswerId
  left join answers a_by_score on a_by_score.QuestionId = q.QuestionId and a_by_score.rn_by_score = 1
),
-- Votes aggregation with window function over time buckets
vote_buckets as (
  select
    v.PostId,
    date_trunc('month', v.CreationDate) as month_bucket,
    count(*) filter (where v.VoteTypeId = 2) as upvotes,
    count(*) filter (where v.VoteTypeId = 3) as downvotes,
    count(*) filter (where v.VoteTypeId = 5) as favorites
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId, date_trunc('month', v.CreationDate)
),
vote_trends as (
  select
    PostId as QuestionId,
    month_bucket,
    upvotes,
    downvotes,
    favorites,
    sum(upvotes - downvotes) over (partition by PostId order by month_bucket rows between unbounded preceding and current row) as cum_net_votes,
    lag(upvotes) over (partition by PostId order by month_bucket) as prev_upvotes
  from vote_buckets
),
-- Comment sentiment proxy: length and score mix
comment_stats as (
  select
    c.PostId as QuestionId,
    count(*) as comment_count,
    coalesce(sum(greatest(c.Score,0)),0) as comment_score_pos,
    avg(nullif(length(c.Text),0)) as avg_comment_len,
    max(c.CreationDate) as last_comment_at
  from Comments c
  join Posts p on p.Id = c.PostId and p.PostTypeId = 1
  group by c.PostId
),
-- User quality metrics
user_feats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    coalesce(u.Location,'') as Location,
    case when u.WebsiteUrl is not null and length(u.WebsiteUrl) > 0 then 1 else 0 end as HasWebsite,
    ntile(10) over (order by Reputation desc) as rep_decile
  from Users u
),
-- Badge counts per user with pivot-like aggregates
badge_counts as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
    count(*) filter (where b.TagBased = 1) as tag_badges,
    count(*) filter (where b.TagBased = 0) as named_badges,
    max(b.Date) as last_badge_at
  from Badges b
  group by b.UserId
),
-- Duplicate linkage and cross-links
link_info as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as dup_links,
    count(*) filter (where pl.LinkTypeId = 1) as linked_links,
    max(pl.CreationDate) as last_link_at,
    count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as distinct_dups
  from PostLinks pl
  group by pl.PostId
),
-- Combine question-level metrics
q_base as (
  select
    q.QuestionId,
    q.CreationDate,
    q.OwnerUserId,
    q.QuestionScore,
    q.ViewCount,
    b.IsAcceptedPresent,
    b.BestAnswerId,
    b.BestAnswerUserId,
    b.BestAnswerScore,
    b.BestAnswerCreated,
    qa.tag_count,
    qa.has_sql_like,
    qa.db_tag_hits,
    rh.last_major_event,
    rh.mod_action_count,
    rh.was_closed,
    rh.closed_at,
    li.dup_links,
    li.linked_links,
    li.last_link_at,
    li.distinct_dups,
    cs.comment_count,
    cs.comment_score_pos,
    cs.avg_comment_len,
    cs.last_comment_at
  from q
  left join best_answer b on b.QuestionId = q.QuestionId
  left join q_tag_agg qa on qa.QuestionId = q.QuestionId
  left join q_recent_hist rh on rh.QuestionId = q.QuestionId
  left join link_info li on li.QuestionId = q.QuestionId
  left join comment_stats cs on cs.QuestionId = q.QuestionId
),
-- Windowed ranking of questions by multi-factor score
q_rank as (
  select
    qb.*,
    coalesce(qb.QuestionScore,0) +
    coalesce(qb.ViewCount/100,0) +
    coalesce(qb.BestAnswerScore,0) * 2 +
    coalesce(qb.comment_score_pos,0) -
    coalesce(qb.dup_links,0) * 0.5 as composite_score,
    rank() over (order by
      coalesce(qb.QuestionScore, -2147483648) desc,
      coalesce(qb.ViewCount, -2147483648) desc,
      coalesce(qb.BestAnswerScore, -2147483648) desc) as rank_basic,
    dense_rank() over (order by
      coalesce(qb.comment_count,0) + coalesce(qb.dup_links,0) desc) as rank_discussion,
    row_number() over (partition by (qb.was_closed is true) order by qb.CreationDate desc) as rn_recent_by_closed
  from q_base qb
),
-- Correlated subquery: detect presence of highly upvoted comments by others
q_flags as (
  select
    qb.QuestionId,
    exists (
      select 1
      from Comments c
      where c.PostId = qb.QuestionId
        and c.Score >= 5
        and (c.UserId is distinct from qb.OwnerUserId)
      limit 1
    ) as has_popular_external_comment,
    exists (
      select 1
      from Votes v
      where v.PostId = qb.QuestionId and v.VoteTypeId = 12
    ) as has_spam_flags
  from q_base qb
),
-- Build final enriched dataset with user and answerer features
enriched as (
  select
    qr.*,
    uf.Reputation as asker_rep,
    uf.rep_decile as asker_rep_decile,
    bc.gold_badges as asker_gold,
    bc.silver_badges as asker_silver,
    bc.bronze_badges as asker_bronze,
    coalesce(uf.Location,'') as asker_location,
    coalesce(uf.HasWebsite,0) as asker_has_website,
    baf.Reputation as answerer_rep,
    babc.gold_badges as answerer_gold,
    vt.cum_net_votes as latest_cum_net_votes,
    vt.prev_upvotes as prev_month_upvotes,
    qf.has_popular_external_comment,
    qf.has_spam_flags
  from q_rank qr
  left join user_feats uf on uf.UserId = qr.OwnerUserId
  left join badge_counts bc on bc.UserId = qr.OwnerUserId
  left join user_feats baf on baf.UserId = qr.BestAnswerUserId
  left join badge_counts babc on babc.UserId = qr.BestAnswerUserId
  left join lateral (
    select vt1.cum_net_votes, vt1.prev_upvotes
    from vote_trends vt1
    where vt1.QuestionId = qr.QuestionId
    order by vt1.month_bucket desc
    limit 1
  ) vt on true
  left join q_flags qf on qf.QuestionId = qr.QuestionId
),
-- Identify outliers via z-scores (with NULL-safe stats)
stats as (
  select
    avg(coalesce(composite_score,0.0)) as mu_comp,
    stddev_pop(coalesce(composite_score,0.0)) as sd_comp,
    avg(coalesce(ViewCount,0.0)) as mu_views,
    stddev_pop(coalesce(ViewCount,0.0)) as sd_views
  from enriched
),
scored as (
  select
    e.*,
    s.mu_comp, s.sd_comp, s.mu_views, s.sd_views,
    case when s.sd_comp > 0 then (coalesce(e.composite_score,0.0) - s.mu_comp)/s.sd_comp end as z_comp,
    case when s.sd_views > 0 then (coalesce(e.ViewCount,0.0) - s.mu_views)/s.sd_views end as z_views
  from enriched e cross join stats s
),
-- Add complex predicate classifications
classified as (
  select
    s.*,
    case
      when s.was_closed is true and coalesce(s.dup_links,0) >= 1 then 'Closed-Duplicate'
      when s.was_closed is true then 'Closed-Other'
      when s.IsAcceptedPresent = 1 then 'Answered'
      when s.BestAnswerId is not null then 'Answered-By-Score'
      else 'Unanswered'
    end as status_label,
    case
      when coalesce(s.db_tag_hits,0) >= 2 or s.has_sql_like is not null then 'DB-SQL'
      when coalesce(s.tag_count,0) >= 5 then 'Many-Tags'
      when coalesce(s.tag_count,0) = 0 then 'No-Tags'
      else 'General'
    end as topic_bucket
  from scored s
),
-- Build a synthetic "stress set" with UNION/INTERSECT/EXCEPT to exercise set operators
stress_set as (
  (
    select QuestionId from classified where status_label like 'Closed%' and coalesce(ViewCount,0) > 1000
    union
    select QuestionId from classified where topic_bucket = 'DB-SQL' and coalesce(asker_rep,0) > 10000
  )
  intersect
  (
    select QuestionId from classified where coalesce(BestAnswerScore,0) >= 1
    except
    select QuestionId from classified where has_spam_flags
  )
)
select
  c.QuestionId,
  c.CreationDate,
  c.status_label,
  c.topic_bucket,
  c.rank_basic,
  c.rank_discussion,
  c.rn_recent_by_closed,
  round(c.composite_score::numeric, 2) as composite_score,
  round(coalesce(c.z_comp,0)::numeric, 3) as z_comp,
  c.ViewCount,
  c.QuestionScore,
  c.BestAnswerScore,
  c.asker_rep,
  c.answerer_rep,
  c.asker_gold,
  c.asker_silver,
  c.asker_bronze,
  c.db_tag_hits,
  c.tag_count,
  c.dup_links,
  c.linked_links,
  c.comment_count,
  c.latest_cum_net_votes,
  c.prev_month_upvotes,
  c.was_closed,
  c.closed_at,
  c.last_major_event,
  c.last_link_at,
  c.last_comment_at,
  c.has_popular_external_comment,
  c.has_spam_flags,
  case when c.QuestionId in (select QuestionId from stress_set) then 1 else 0 end as in_stress_set,
  -- String expressions/NULL logic demo
  coalesce(nullif(trim(coalesce(c.asker_location,'')),''),'Unknown') ||
  case when c.asker_has_website = 1 then ' (web)' else '' end as asker_loc_web
from classified c
where
  -- Complicated predicate to exercise planner
  (
    (c.status_label in ('Answered','Answered-By-Score') and coalesce(c.ViewCount,0) > 500)
    or
    (c.status_label like 'Closed%' and (c.z_views is null or c.z_views < 2.5))
    or
    (c.topic_bucket in ('DB-SQL','Many-Tags') and coalesce(c.comment_count,0) >= 3)
  )
  and not (c.has_spam_flags and c.was_closed is true)
  and (c.CreationDate is not null and c.CreationDate > (select min(CreationDate) from Posts where PostTypeId = 1))
order by
  coalesce(c.z_comp, -999) desc nulls last,
  c.rank_basic asc,
  c.QuestionId asc
limit 500;