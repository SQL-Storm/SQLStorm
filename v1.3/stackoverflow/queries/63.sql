with
-- recent activity: last 90 days per post with complex tag extraction
RecentPosts as (
  select
    p.id,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    coalesce(p.AnswerCount,0) as AnswerCount,
    -- explode tags into a normalized pseudo-array using string ops (tags like '<sql><performance>')
    regexp_split_to_table(
      case when p.Tags is null then '' else substring(p.Tags from 2 for char_length(p.Tags)-2) end,
      '><'
    ) as TagName
  from Posts p
  where p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
),
-- per-user aggregates including window functions and NULL logic
UserAgg as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    -- replace distinct+window (unsupported) with aggregated counts from RecentPosts per user
    coalesce(uq.RecentQuestions, 0) as RecentQuestions,
    coalesce(uq.RecentAnswers, 0) as RecentAnswers,
    coalesce(us.RecentScoreSum,0) as RecentScoreSum,
    coalesce(us.RecencyWeightedScore,0) as RecencyWeightedScore,
    uq.UserLastActivity
  from Users u
  left join (
    select
      OwnerUserId,
      count(case when PostTypeId = 1 then 1 end) as RecentQuestions,
      count(case when PostTypeId = 2 then 1 end) as RecentAnswers,
      max(LastActivityDate) as UserLastActivity
    from RecentPosts
    group by OwnerUserId
  ) uq on uq.OwnerUserId = u.Id
  left join (
    select
      OwnerUserId,
      sum(coalesce(Score,0)) as RecentScoreSum,
      sum(
        coalesce(Score,0) *
        exp(-greatest(0, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp)-CreationDate)))/ (60*60*24*30.0))
      ) as RecencyWeightedScore
    from RecentPosts
    group by OwnerUserId
  ) us on us.OwnerUserId = u.Id
  where u.Reputation >= 0
),
-- compute per-tag popularity and representative posts using correlated subqueries and tie-breakers
TagStats as (
  select
    tg.TagName,
    count(distinct rp.id) as RecentPostCount,
    sum(coalesce(rp.ViewCount,0)) as TotalViews,
    avg(coalesce(rp.Score,0)) as AvgScore,
    -- pick the highest scoring recent post per tag (tie-break by ViewCount then CreationDate)
    (select id from RecentPosts rp2
     where rp2.TagName = tg.TagName
     order by coalesce(rp2.Score,0) desc, coalesce(rp2.ViewCount,0) desc, rp2.CreationDate desc
     limit 1) as TopPostId,
    -- pick a sample author (most active)
    (select rp3.OwnerUserId from RecentPosts rp3
     where rp3.TagName = tg.TagName
     group by rp3.OwnerUserId
     order by count(*) desc, max(rp3.Score) desc
     limit 1) as TopAuthorId
  from (
    select distinct TagName from RecentPosts
  ) tg
  left join RecentPosts rp on rp.TagName = tg.TagName
  group by tg.TagName
),
-- make a candidate set combining tag stats with user aggregates and posts
Candidates as (
  select
    ts.TagName,
    ts.RecentPostCount,
    ts.TotalViews,
    ts.AvgScore,
    ts.TopPostId,
    ts.TopAuthorId,
    p.Title as TopPostTitle,
    p.Score as TopPostScore,
    p.ViewCount as TopPostViews,
    ua.DisplayName as TopAuthorName,
    ua.Reputation as TopAuthorReputation,
    ua.RecentQuestions,
    ua.RecentAnswers,
    ua.RecencyWeightedScore,
    ua.CreationDate as TopAuthorCreationDate,
    ua.LastAccessDate as TopAuthorLastAccessDate
  from TagStats ts
  left join Posts p on p.Id = ts.TopPostId
  left join UserAgg ua on ua.UserId = ts.TopAuthorId
),
-- construct a complex filter set mixing full-text-like string expressions and null logic
FilteredCandidates as (
  select
    c.TagName,
    c.RecentPostCount,
    c.TotalViews,
    c.AvgScore,
    c.TopPostId,
    c.TopAuthorId,
    c.TopPostTitle,
    c.TopPostScore,
    c.TopPostViews,
    c.TopAuthorName,
    c.TopAuthorReputation,
    c.RecentQuestions,
    c.RecentAnswers,
    c.RecencyWeightedScore,
    (
      (log(1 + nullif(c.RecentPostCount,0)) * 2.5) +
      (coalesce(c.TopAuthorReputation,0) / greatest(1, (select max(Reputation) from Users))) * 5 +
      (coalesce(c.TopPostScore,0) * 1.5) +
      (case when lower(coalesce(c.TopPostTitle,'')) like '%performance%' then 3 else 0 end) +
      (case when lower(coalesce(c.TopPostTitle,'')) like '%sql%' then 2 else 0 end) +
      (case when lower(coalesce(c.TagName,'')) like 'sql%' then 2.5 else 0 end)
    ) as HeuristicScore,
    length(c.TagName) as TagNameLength,
    -- null-safe boolean: is top author active recently?
    (coalesce((select UserLastActivity from UserAgg u where u.UserId = c.TopAuthorId), timestamp '1970-01-01') > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as TopAuthorRecentlyActive,
    -- bring in UserLastActivity for grouping later
    (select UserLastActivity from UserAgg u where u.UserId = c.TopAuthorId) as UserLastActivity
  from Candidates c
),
-- final ranking: window functions, set operators and correlated subquery for metrics
Ranked as (
  select
    fc.TagName,
    fc.RecentPostCount,
    fc.TotalViews,
    fc.AvgScore,
    fc.TopPostId,
    fc.TopPostTitle,
    fc.TopPostScore,
    fc.TopPostViews,
    fc.TopAuthorName,
    fc.TopAuthorReputation,
    fc.RecencyWeightedScore,
    fc.HeuristicScore,
    fc.TagNameLength,
    fc.TopAuthorRecentlyActive,
    fc.UserLastActivity,
    -- window functions
    dense_rank() over (order by fc.HeuristicScore desc) as RankByHeuristic,
    row_number() over (partition by substring(fc.TagName from 1 for 1) order by fc.HeuristicScore desc) as PerInitialBucketRank,
    -- complex correlated metric: median score of related posts (answers to top post)
    (
      select percentile_cont(0.5) within group (order by coalesce(p2.Score,0))
      from Posts p2
      where p2.ParentId = fc.TopPostId
    ) as MedianAnswerScore,
    -- set operator: check existence in a constructed set of "hot" tags using UNION
    case when fc.TagName in (
      select TagName from (
        select TagName from TagStats where RecentPostCount > 50
        union
        select TagName from TagStats where TotalViews > 100000
        union
        select TagName from TagStats where AvgScore > 2.5
      ) s
    ) then 1 else 0 end as IsHotTag
  from FilteredCandidates fc
  group by
    fc.TagName,
    fc.RecentPostCount,
    fc.TotalViews,
    fc.AvgScore,
    fc.TopPostId,
    fc.TopPostTitle,
    fc.TopPostScore,
    fc.TopPostViews,
    fc.TopAuthorName,
    fc.TopAuthorReputation,
    fc.RecencyWeightedScore,
    fc.HeuristicScore,
    fc.TagNameLength,
    fc.TopAuthorRecentlyActive,
    fc.UserLastActivity
)
select
  r.TagName,
  r.RecentPostCount,
  r.TotalViews,
  round(cast(r.AvgScore as numeric),2) as AvgScore,
  r.TopPostId,
  coalesce(r.TopPostTitle, '<no title>') as TopPostTitle,
  r.TopPostScore,
  r.TopPostViews,
  coalesce(r.TopAuthorName, '<anonymous>') as TopAuthorName,
  r.TopAuthorReputation,
  r.RecencyWeightedScore,
  r.HeuristicScore,
  r.TagNameLength,
  r.TopAuthorRecentlyActive,
  r.MedianAnswerScore,
  r.IsHotTag,
  r.RankByHeuristic,
  r.PerInitialBucketRank
from Ranked r
where
  r.RecentPostCount between 5 and 1000
  and (r.TotalViews > 1000 or r.AvgScore > 1.0)
  and (r.HeuristicScore > 1.5 or r.IsHotTag = 1)
order by r.RankByHeuristic asc, r.PerInitialBucketRank asc
limit 250;