-- {"query": "127.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 3111} 
with
-- base posts separated into questions and answers, with some computed flags
base_posts as (
  select
    p.*,
    case when p.PostTypeId = 1 then 'question'
         when p.PostTypeId = 2 then 'answer'
         else 'other' end as post_kind,
    -- normalized tag list (nullable for non-questions)
    case when p.PostTypeId = 1 and p.Tags is not null
         then string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
         else null end as tag_array
  from Posts p
),

-- explode tags for questions for tag-level aggregations
exploded_tags as (
  select
    bp.Id as QuestionId,
    bp.Title,
    trim(tg) as Tag,
    bp.OwnerUserId,
    bp.CreationDate,
    bp.Score,
    bp.ViewCount,
    bp.AnswerCount,
    bp.FavoriteCount
  from base_posts bp
  cross join lateral (
    select unnest(bp.tag_array) as tg
  ) x
  where bp.post_kind = 'question' and bp.tag_array is not null
),

-- aggregate tag statistics with window functions and complex expressions
tag_stats as (
  select
    Tag,
    count(*) filter (where CreationDate >= now() - interval '365 days') as q_count_last_year,
    count(*) as q_count_total,
    avg(nullif(Score,0)) filter (where Score <> 0) as avg_score_nonzero,
    coalesce(median_score,0) as median_score, -- placeholder; computed in next step via window
    max(Score) as max_score,
    sum(COALESCE(ViewCount,0)) as total_views,
    sum(COALESCE(FavoriteCount,0)) as total_favorites,
    -- top question per tag by score, with tie-breaker by viewcount
    max( (Score::bigint << 32) + COALESCE(ViewCount,0) ) as packed_score_view
  from exploded_tags
  group by Tag
),

-- compute median score per tag via windowing (two-step)
tag_scores_expanded as (
  select
    Tag,
    Score,
    row_number() over (partition by Tag order by Score asc, QuestionId) as rn_asc,
    row_number() over (partition by Tag order by Score desc, QuestionId) as rn_desc,
    count(*) over (partition by Tag) as cnt
  from exploded_tags
),

tag_median as (
  select distinct
    Tag,
    case
      when cnt % 2 = 1 then -- odd: take middle
        max(case when rn_asc = (cnt+1)/2 then Score end) over (partition by Tag)
      else -- even: average two middle values
        (max(case when rn_asc = cnt/2 then Score end) over (partition by Tag) +
         max(case when rn_asc = cnt/2 + 1 then Score end) over (partition by Tag))::numeric / 2
    end as median_score
  from tag_scores_expanded
),

-- merge stats with medians
tag_analytics as (
  select
    ts.Tag,
    ts.q_count_total,
    ts.q_count_last_year,
    ts.avg_score_nonzero,
    tm.median_score,
    ts.max_score,
    ts.total_views,
    ts.total_favorites,
    ts.packed_score_view
  from tag_stats ts
  left join tag_median tm using (Tag)
),

-- user-level aggregates including correlated subqueries and NULL logic
user_activity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(u.Views,0) as Views,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    -- number of questions and answers (outer join + filter)
    (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as num_questions,
    (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as num_answers,
    -- last activity across posts and comments via greatest / correlated subqueries
    greatest(
      u.LastAccessDate,
      coalesce((select max(LastActivityDate) from Posts p where p.OwnerUserId = u.Id), '1970-01-01'::timestamp),
      coalesce((select max(CreationDate) from Comments c where c.UserId = u.Id), '1970-01-01'::timestamp)
    ) as last_content_activity,
    -- ratio expression with NULL-safe math
    case when (select count(*) from Posts p where p.OwnerUserId = u.Id) = 0 then null
         else round( (select sum(coalesce(Score,0)) from Posts p where p.OwnerUserId = u.Id)::numeric /
                     greatest(1, (select count(*) from Posts p where p.OwnerUserId = u.Id)), 3)
    end as avg_score_per_post,
    -- whether user holds at least one gold badge (class = 1)
    exists (select 1 from Badges b where b.UserId = u.Id and b.Class = 1) as has_gold
  from Users u
),

-- answer-level enriched info including correlated subqueries to parent question and accepted answer logic
answers_enriched as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate as AnswerDate,
    a.Score as AnswerScore,
    q.Title as QuestionTitle,
    q.Tags as QuestionTags,
    q.OwnerUserId as QuestionOwner,
    -- is this answer the accepted one (join to question AcceptedAnswerId)
    case when q.AcceptedAnswerId = a.Id then true else false end as is_accepted,
    -- count of comments on the answer (correlated)
    (select count(*) from Comments c where c.PostId = a.Id) as comment_count,
    -- age in days between question and answer
    extract(epoch from (a.CreationDate - q.CreationDate))/86400.0 as answer_delay_days,
    -- indicator if answerer is same as question owner
    case when a.OwnerUserId is null or q.OwnerUserId is null then null
         when a.OwnerUserId = q.OwnerUserId then true else false end as self_answer
  from Posts a
  left join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
),

-- compute per-question multi-metrics joining answers, comments, votes using outer joins and set operators
question_overview as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.Score as QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    -- number of distinct answerers
    (select count(distinct OwnerUserId) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2 and a.OwnerUserId is not null) as distinct_answerers,
    -- top answer score and average answer score; using left join to answers_enriched
    max(ae.AnswerScore) as top_answer_score,
    avg(ae.AnswerScore) as avg_answer_score,
    -- proportion of answers that are accepted or from OP (complex expression)
    sum(case when ae.is_accepted then 1 else 0 end)::numeric / nullif(greatest(1, count(ae.AnswerId)),1) as accepted_ratio,
    sum(case when ae.self_answer then 1 else 0 end)::numeric / nullif(greatest(1, count(ae.AnswerId)),1) as self_answer_ratio,
    -- flags by correlated subqueries: has bounty? has recent edit? closed within 30 days?
    exists (select 1 from Votes v where v.PostId = q.Id and v.VoteTypeId = 8) as has_bounty,
    exists (select 1 from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId in (4,5,6) and ph.CreationDate > q.CreationDate + interval '30 days') as edited_after_30d,
    (select min(CreationDate) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10) as first_close_date,
    -- most common tag for this question (simple parse pick first tag lexically)
    (select min(tg) from unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) tg) as canonical_tag
  from Posts q
  left join answers_enriched ae on ae.QuestionId = q.Id
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Tags
),

-- a combined heavy-weight result set merging tag analytics, question overview and user activity,
-- demonstrating outer joins, null-handling, set operations and window ranking
combined as (
  select
    qo.QuestionId,
    qo.Title,
    qo.CreationDate,
    u.UserId as QuestionOwnerId,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    qo.QuestionScore,
    qo.ViewCount,
    qo.AnswerCount,
    qo.FavoriteCount,
    qo.distinct_answerers,
    qo.top_answer_score,
    qo.avg_answer_score,
    qo.accepted_ratio,
    qo.self_answer_ratio,
    qo.has_bounty,
    qo.edited_after_30d,
    qo.first_close_date,
    qo.canonical_tag,
    ta.q_count_total as tag_q_total,
    ta.q_count_last_year as tag_q_last_year,
    ta.avg_score_nonzero as tag_avg_score_nonzero,
    ta.median_score as tag_median_score,
    ta.total_views as tag_total_views,
    -- derive a composite "hotness" score combining many signals (complicated expression)
    (
      coalesce(qo.QuestionScore,0) * 1.5
      + ln(1 + greatest(qo.ViewCount,0)) * 2
      + coalesce(qo.avg_answer_score,0) * 1.2
      + coalesce(ta.q_count_last_year,0) * 0.05
      + case when qo.has_bounty then 10 else 0 end
      - coalesce((extract(epoch from now() - qo.CreationDate)/86400.0)::numeric,0) * 0.02
    ) as hotness_score
  from question_overview qo
  left join Users u on u.Id = qo.OwnerUserId
  left join tag_analytics ta on ta.Tag = qo.canonical_tag
),

-- rank combined results and produce top N; also perform an UNION ALL with "cold" questions to exercise set operators
ranked as (
  select
    c.*,
    row_number() over (order by hotness_score desc nulls last) as hot_rank,
    percent_rank() over (order by hotness_score desc nulls last) as hot_percentile
  from combined c
),

cold_set as (
  select
    c.*,
    null as hot_rank,
    null as hot_percentile
  from combined c
  where c.AnswerCount = 0 and c.ViewCount < 50
  order by c.CreationDate desc
  limit 50
)

-- final output: take top 100 hot questions, union with a sample of cold questions, include complex ordering and filters
select
  r.hot_rank,
  r.hot_percentile,
  r.QuestionId,
  left(r.Title, 200) as short_title,
  r.CreationDate,
  r.QuestionOwnerId,
  r.QuestionOwner,
  r.OwnerReputation,
  r.QuestionScore,
  r.ViewCount,
  r.AnswerCount,
  r.FavoriteCount,
  round(r.hotness_score::numeric,3) as hotness_score,
  r.canonical_tag,
  r.tag_q_total,
  r.tag_q_last_year,
  r.tag_avg_score_nonzero,
  r.tag_median_score,
  r.tag_total_views,
  r.distinct_answerers,
  r.top_answer_score,
  round(coalesce(r.avg_answer_score,0)::numeric,3) as avg_answer_score,
  r.accepted_ratio,
  r.self_answer_ratio,
  r.has_bounty,
  r.edited_after_30d,
  r.first_close_date
from ranked r
where r.hot_rank <= 100

union all

select
  cs.hot_rank,
  cs.hot_percentile,
  cs.QuestionId,
  left(cs.Title,200),
  cs.CreationDate,
  cs.QuestionOwnerId,
  cs.QuestionOwner,
  cs.OwnerReputation,
  cs.QuestionScore,
  cs.ViewCount,
  cs.AnswerCount,
  cs.FavoriteCount,
  round(cs.hotness_score::numeric,3),
  cs.canonical_tag,
  cs.tag_q_total,
  cs.tag_q_last_year,
  cs.tag_avg_score_nonzero,
  cs.tag_median_score,
  cs.tag_total_views,
  cs.distinct_answerers,
  cs.top_answer_score,
  round(coalesce(cs.avg_answer_score,0)::numeric,3),
  cs.accepted_ratio,
  cs.self_answer_ratio,
  cs.has_bounty,
  cs.edited_after_30d,
  cs.first_close_date
from cold_set cs

order by
  -- sort hot questions first by rank (nulls last), then cold set by CreationDate desc (these have null rank)
  case when hot_rank is not null then 0 else 1 end,
  hot_rank nulls last,
  CreationDate desc
;