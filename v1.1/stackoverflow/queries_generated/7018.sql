-- {"query": "7018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2309} 
with
-- active questions in the last 2 years with parsed tags expanded
Questions as (
  select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(p.ViewCount,0) as ViewCount,
    coalesce(p.AnswerCount,0) as AnswerCount,
    coalesce(p.FavoriteCount,0) as FavoriteCount,
    p.Tags,
    -- normalized tag array: trim < and > and split into rows (Postgres-style)
    regexp_split_to_table(coalesce(substring(p.Tags from 2 for char_length(p.Tags)-2),''), '><') as Tag
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),
-- answers with some computed metrics and parent's question info
Answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    a.CommentCount,
    a.Body,
    -- length heuristics and code-block detection
    char_length(coalesce(a.Body,'')) as BodyLen,
    (coalesce(char_length(a.Body),0) - char_length(replace(coalesce(a.Body,''), '<code>',''))) / nullif(char_length('<code>'),0) as CodeBlockCount,
    case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
  from Posts a
  left join Posts q on a.ParentId = q.Id
  where a.PostTypeId = 2
    and a.CreationDate >= now() - interval '3 years'
),
-- user aggregates: reputation, badge counts and recent activity window
UserAgg as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(u.Views,0) as ProfileViews,
    coalesce(sum(case when b.Class=1 then 1 else 0 end),0) over (partition by u.Id) as GoldBadges,
    coalesce(sum(case when b.Class=2 then 1 else 0 end),0) over (partition by u.Id) as SilverBadges,
    coalesce(sum(case when b.Class=3 then 1 else 0 end),0) over (partition by u.Id) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  where u.CreationDate <= now()
),
-- recent votes per post type aggregated with correlated subquery and windowed deltas
PostVotes as (
  select
    p.Id as PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    max(v.CreationDate) as LastVoteDate,
    -- freshness score: more recent votes weight more (simple inverse days)
    sum(case when v.CreationDate is not null then 1.0 / nullif(extract(epoch from (now()-v.CreationDate))/86400.0,0) else 0 end) as VoteFreshness
  from Posts p
  left join Votes v on v.PostId = p.Id
  group by p.Id
),
-- compute neighbor statistics for questions via window functions and lateral joins
QuestionStats as (
  select
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    q.Tag,
    -- tag popularity: how many questions share this tag in the two-year window
    count(*) over (partition by q.Tag) as TagPopularity,
    -- rank questions within tag by score, views, and recency
    row_number() over (partition by q.Tag order by q.Score desc, q.ViewCount desc, q.CreationDate desc) as TagRank,
    -- windowed aggregates per tag
    avg(q.Score) over (partition by q.Tag) as AvgScoreByTag,
    pct_rank() over (partition by q.Tag order by q.ViewCount) as ViewPctByTag
  from Questions q
),
-- combine question stats with best answer summaries and vote data, demonstrating correlated subqueries and outer joins
QuestionDetail as (
  select
    qs.*,
    ua.DisplayName as OwnerName,
    ua.Reputation as OwnerReputation,
    coalesce(pv.UpVotes,0) as PostUpVotes,
    coalesce(pv.DownVotes,0) as PostDownVotes,
    coalesce(pv.Favorites,0) as PostFavorites,
    coalesce(pv.VoteFreshness,0) as PostVoteFreshness,
    -- best answer aggregated: highest score, prefer accepted, tie-breaker by recency
    ba.BestAnswerId,
    ba.BestAnswerScore,
    ba.BestAnswerIsAccepted,
    ba.AnswerCountRecent,
    -- computed composite popularity metric combining score, views, favs, and freshness
    (qs.Score * 2.0 + ln(nullif(qs.ViewCount,0) + 1) + coalesce(pv.Favorites,0) * 3 + coalesce(pv.VoteFreshness,0)) as CompositePopularity
  from QuestionStats qs
  left join UserAgg ua on ua.UserId = qs.OwnerUserId
  left join PostVotes pv on pv.PostId = qs.QuestionId
  left join lateral (
    select
      a.AnswerId as BestAnswerId,
      a.Score as BestAnswerScore,
      a.IsAccepted as BestAnswerIsAccepted,
      count(*) filter (where a.CreationDate >= now() - interval '1 year') over () as AnswerCountRecent
    from Answers a
    where a.QuestionId = qs.QuestionId
    order by (case when a.IsAccepted=1 then 0 else 1 end), a.Score desc nulls last, a.CreationDate desc
    limit 1
  ) ba on true
),
-- tag co-occurrence matrix for benchmark of set operators and grouping
TagPairs as (
  select distinct
    q1.Tag as TagA,
    q2.Tag as TagB,
    count(distinct q1.QuestionId) as CooccurrenceCount
  from Questions q1
  join Questions q2 on q1.QuestionId = q2.QuestionId and q1.Tag < q2.Tag
  group by q1.Tag, q2.Tag
),
-- synthetic heavy expression section: compute a volatility score using string ops, null logic and subqueries
Volatility as (
  select
    qd.QuestionId,
    qd.Tag,
    qd.CompositePopularity,
    -- nickname generation based on title: keep alphanumerics, collapse spaces, substrings, null-safe operations
    lower(regexp_replace(coalesce(qd.Title,''), '[^A-Za-z0-9 ]','', 'g')) as CleanTitle,
    left(replace(lower(coalesce(qd.Title,'')), ' ', '_'), 50) as TitleSlug,
    -- recent edit activity: count of PostHistory edits in last 90 days via correlated scalar subquery
    (select count(*) from PostHistory ph where ph.PostId = qd.QuestionId and ph.CreationDate >= now() - interval '90 days') as RecentEdits,
    -- comments density: correlated count on comments
    (select count(*) from Comments c where c.PostId = qd.QuestionId) as CommentCount,
    -- volatility score: nonlinear combination with null-safe guards
    (
      coalesce(qd.CompositePopularity,0) * 0.6
      + coalesce((select count(*) from PostHistory ph2 where ph2.PostId = qd.QuestionId),0) * 0.3
      + coalesce((select count(*) from Votes v2 where v2.PostId = qd.QuestionId and v2.VoteTypeId in (2,3)),0) * 0.1
      - greatest(0, (extract(epoch from (now() - qd.CreationDate))/86400.0 - 365)) * 0.01
    ) as VolatilityScore
  from QuestionDetail qd
),
-- final selection: combine aggregations, set operators, and complicated predicates
FinalSet as (
  select
    v.QuestionId,
    v.Tag,
    v.CompositePopularity,
    v.VolatilityScore,
    v.CleanTitle,
    v.TitleSlug,
    v.RecentEdits,
    v.CommentCount,
    qs.TagPopularity,
    qs.TagRank,
    -- popularity bucket using case with boolean logic and null handling
    case
      when v.CompositePopularity is null then 'unknown'
      when v.CompositePopularity > 50 and v.VolatilityScore > 20 then 'hot-volatile'
      when v.CompositePopularity > 50 then 'hot'
      when v.CompositePopularity between 20 and 50 then 'warm'
      else 'cold'
    end as PopularityClass,
    -- top cooccurring tag (correlated subquery with NULL-safe ordering)
    (select tp.TagB from TagPairs tp where tp.TagA = v.Tag order by tp.CooccurrenceCount desc nulls last limit 1) as TopCoTag,
    -- existence checks and set operator simulation: does user have any gold badges?
    case when exists (select 1 from Badges b where b.UserId = qs.OwnerUserId and b.Class = 1) then true else false end as OwnerHasGoldBadge
  from Volatility v
  left join QuestionStats qs on qs.QuestionId = v.QuestionId and qs.Tag = v.Tag
)
-- final output: union of top-per-tag with an extra set operator to include synthetic anomalies
select *
from (
  -- select top 3 per tag by CompositePopularity
  select *
  from (
    select
      f.*,
      row_number() over (partition by f.Tag order by f.CompositePopularity desc nulls last, f.VolatilityScore desc) as rn
    from FinalSet f
  ) t
  where t.rn <= 3

  union

  -- include low-popularity high-volatility anomalies via EXCEPT/INTERSECT style logic simulated with windowing
  select *
  from FinalSet f2
  where f2.PopularityClass = 'cold'
    and f2.VolatilityScore > (
      select avg(VolatilityScore) from FinalSet where VolatilityScore is not null
    )
) results
order by Tag, CompositePopularity desc nulls last, VolatilityScore desc;