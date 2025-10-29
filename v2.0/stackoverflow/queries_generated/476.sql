-- {"query": "476.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2752} 
with
-- Parameterizable date range and tag filter
params as (
  select
    date_trunc('month', coalesce((select max(CreationDate) from Posts), now())) - interval '24 months' as start_dt,
    date_trunc('month', coalesce((select max(CreationDate) from Posts), now())) + interval '1 month' as end_dt,
    '{python,java,javascript,c#,c++}'::varchar as tag_whitelist
),
-- Expand question tags into rows and filter to a whitelist for benchmarking
q as (
  select
    p.Id as PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.CreationDate,
    p.ClosedDate,
    p.Tags,
    unnest(string_to_array(nullif(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), ''><''))) as TagItem
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
  join params prm on p.CreationDate >= prm.start_dt and p.CreationDate < prm.end_dt
),
-- Normalize tags and keep only whitelisted ones; also attach tag metadata
q_tags as (
  select
    q.*,
    lower(q.TagItem) as tag_lower
  from q
  where q.TagItem is not null
),
whitelist as (
  select lower(regexp_replace(t, '^\s*|\s*$', '')) as tag_lower
  from params, unnest(string_to_array(tag_whitelist, ',')) t
),
q_whitelist as (
  select qt.*
  from q_tags qt
  join whitelist w on w.tag_lower = qt.tag_lower
),
-- Votes aggregation per post with windowed distributions
votes_agg as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as upvotes,
    count(*) filter (where v.VoteTypeId = 3) as downvotes,
    count(*) filter (where v.VoteTypeId = 12) as spam_flags,
    count(*) filter (where v.VoteTypeId = 10) as deletions,
    max(v.CreationDate) as last_vote_at
  from Votes v
  join q on q.PostId = v.PostId
  group by v.PostId
),
-- Comment stats with correlated subquery for longest comment per post
comment_agg as (
  select
    c.PostId,
    count(*) as comment_count,
    coalesce(sum(greatest(c.Score,0)),0) as nonneg_comment_score,
    max(c.CreationDate) as last_comment_at,
    (
      select c2.Text
      from Comments c2
      where c2.PostId = c.PostId
      order by length(c2.Text) desc nulls last, c2.Score desc nulls last, c2.Id
      limit 1
    ) as longest_comment_text
  from Comments c
  where exists (select 1 from q where q.PostId = c.PostId)
  group by c.PostId
),
-- Answers per question with acceptance flag and recency signals
answers as (
  select
    a.ParentId as QuestionId,
    count(*) as answer_count_all,
    max(a.Score) as max_answer_score,
    count(*) filter (where a.CreationDate >= now() - interval '90 days') as recent_answers,
    bool_or(a.Id = q.AcceptedAnswerId) as has_accepted
  from Posts a
  join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
  join Posts q on q.Id = a.ParentId
  group by a.ParentId
),
-- Post history signals (closures, protections, migrations, edits)
history_flags as (
  select
    ph.PostId,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,35,36)) as first_mod_action_at,
    count(*) filter (where ph.PostHistoryTypeId in (10)) as close_votes_events,
    count(*) filter (where ph.PostHistoryTypeId in (11)) as reopen_events,
    count(*) filter (where ph.PostHistoryTypeId in (19)) as protected_events,
    count(*) filter (where ph.PostHistoryTypeId in (24)) as suggested_edits_applied,
    count(*) filter (where ph.PostHistoryTypeId in (5,8)) as body_edits
  from PostHistory ph
  where exists (select 1 from q where q.PostId = ph.PostId)
  group by ph.PostId
),
-- User reputation and badge signals for owners
owner_profile as (
  select
    u.Id as UserId,
    u.Reputation,
    extract(year from age(now(), u.CreationDate))::int as account_age_years,
    coalesce(u.Location, '') as location,
    greatest(u.UpVotes - coalesce(u.DownVotes,0), 0) as net_votes,
    sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes
),
-- Monthly rollups per tag with window ranking and medians
per_tag_month as (
  select
    date_trunc('month', q.CreationDate)::date as month,
    q.tag_lower,
    count(distinct q.PostId) as questions,
    avg(q.Score) as avg_score,
    percentile_cont(0.5) within group (order by q.ViewCount) as median_views,
    sum(coalesce(v.upvotes,0)) as sum_upvotes,
    sum(coalesce(v.downvotes,0)) as sum_downvotes,
    sum(coalesce(c.comment_count,0)) as sum_comments
  from q_whitelist q
  left join votes_agg v on v.PostId = q.PostId
  left join comment_agg c on c.PostId = q.PostId
  group by 1,2
),
-- Rank tags by month by multiple criteria
tag_month_rank as (
  select
    ptm.*,
    row_number() over (partition by month order by questions desc, avg_score desc nulls last, sum_upvotes desc nulls last) as rnk_by_questions,
    dense_rank() over (partition by month order by sum_upvotes - sum_downvotes desc nulls last) as rnk_by_net_votes
  from per_tag_month ptm
),
-- Identify "hot" questions per tag and month using combined signals
question_signals as (
  select
    q.PostId,
    q.tag_lower,
    date_trunc('month', q.CreationDate)::date as month,
    q.Score,
    q.ViewCount,
    q.FavoriteCount,
    q.AnswerCount,
    coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
    coalesce(v.spam_flags,0) as spam_flags,
    coalesce(c.comment_count,0) as comment_count,
    coalesce(a.has_accepted, false) as has_accepted,
    coalesce(a.max_answer_score,0) as max_answer_score,
    coalesce(h.body_edits,0) as body_edits,
    case when q.ClosedDate is not null then 1 else 0 end as is_closed
  from q_whitelist q
  left join votes_agg v on v.PostId = q.PostId
  left join comment_agg c on c.PostId = q.PostId
  left join answers a on a.QuestionId = q.PostId
  left join history_flags h on h.PostId = q.PostId
),
scored as (
  select
    qs.*,
    -- Composite score with mixed signals and null-safe handling
    (
      0.40 * coalesce(qs.Score,0) +
      0.25 * ln(greatest(qs.ViewCount,1)) +
      0.15 * coalesce(qs.net_votes,0) +
      0.10 * coalesce(qs.comment_count,0) +
      0.07 * coalesce(qs.max_answer_score,0) +
      0.03 * (case when qs.has_accepted then 5 else 0 end) -
      0.20 * coalesce(qs.spam_flags,0) -
      0.30 * coalesce(qs.is_closed,0) +
      0.05 * coalesce(qs.body_edits,0)
    ) as hotness_score
  from question_signals qs
),
-- Rank per tag/month and overall; include percentiles
ranked as (
  select
    s.*,
    row_number() over (partition by s.tag_lower, s.month order by s.hotness_score desc nulls last, s.PostId) as rn_in_tag_month,
    ntile(100) over (partition by s.tag_lower, s.month order by s.hotness_score desc nulls last) as percentile_in_tag_month,
    rank() over (partition by s.month order by s.hotness_score desc nulls last) as month_rank
  from scored s
),
-- Bring in owner info with outer join and null semantics; build a display label
with_owner as (
  select
    r.*,
    u.UserId,
    u.Reputation,
    u.account_age_years,
    u.net_votes as owner_net_votes,
    coalesce(u.gold_badges,0) as gold_badges,
    coalesce(u.silver_badges,0) as silver_badges,
    coalesce(u.bronze_badges,0) as bronze_badges,
    case
      when u.UserId is null then '[deleted]'
      when coalesce(u.location,'') = '' then coalesce((select DisplayName from Posts p where p.Id = r.PostId and p.OwnerDisplayName is not null limit 1), 'user')
      else u.location
    end as owner_label
  from ranked r
  left join Posts p on p.Id = r.PostId
  left join owner_profile u on u.UserId = p.OwnerUserId
),
-- Select top N per tag/month and union with month leaders
topn as (
  select * from with_owner where rn_in_tag_month <= 10
  union all
  select wo.*
  from with_owner wo
  join (
    select month, tag_lower, min(rnk_by_questions) as best_rnk
    from tag_month_rank
    group by 1,2
    having min(rnk_by_questions) = 1
  ) leaders on leaders.month = wo.month and leaders.tag_lower = wo.tag_lower
),
-- Deduplicate in case of overlap
dedup as (
  select distinct on (PostId, tag_lower, month) *
  from topn
  order by PostId, tag_lower, month
)
select
  d.month,
  d.tag_lower as tag,
  d.PostId,
  coalesce(p.Title, concat('[wiki/', d.tag_lower, ']')) as title_or_tag,
  round(d.hotness_score::numeric, 3) as hotness,
  d.Score,
  d.ViewCount,
  d.FavoriteCount,
  d.AnswerCount,
  d.net_votes,
  d.comment_count,
  d.max_answer_score,
  d.has_accepted,
  d.is_closed = 1 as is_closed_bool,
  d.percentile_in_tag_month,
  d.month_rank,
  d.rn_in_tag_month,
  d.UserId as owner_id,
  d.Reputation as owner_rep,
  d.owner_net_votes,
  d.gold_badges,
  d.silver_badges,
  d.bronze_badges,
  d.owner_label,
  -- string expressions and null logic to create a compact summary
  regexp_replace(
    coalesce(p.Tags,''),
    '(^<|>$)',
    '',
    'g'
  ) as raw_tags,
  coalesce(c.longest_comment_text, '') as longest_comment_excerpt,
  -- time since last engagement across votes/comments
  greatest(
    coalesce(current_timestamp - v.last_vote_at, interval '0'),
    coalesce(current_timestamp - c.last_comment_at, interval '0')
  ) as since_last_engagement
from dedup d
left join Posts p on p.Id = d.PostId
left join votes_agg v on v.PostId = d.PostId
left join comment_agg c on c.PostId = d.PostId
order by d.month desc, d.tag_lower asc, d.hotness_score desc, d.PostId
limit 500;