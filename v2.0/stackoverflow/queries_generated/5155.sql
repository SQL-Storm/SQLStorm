-- {"query": "5155.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 999} 
WITH 
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.AccountId IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TagTagMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPosts,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(tg.TagName, 1, length(tg.TagName)), ','))
  ) AS s(tag) ON true
  GROUP BY t.TagName
),
ComplexPostAgg AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) OVER (PARTITION BY p.Id) AS CommentCountWindow,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
TemporalStats AS (
  SELECT
    p.PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id) AS ReferencedFromCount
  FROM Posts p
  WHERE p.ClosedDate IS NULL
),
OuterJoinBenchmark AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.LastActivity,
    tr.TagPosts,
    tr.AvgPostScore,
    tr.TotalViews,
    ca.PostId,
    ca.Title,
    ca.CreationDate,
    ca.LastActivityDate,
    ca.Score AS PostScore,
    ca.ViewCount
  FROM RecentUserActivity rua
  LEFT JOIN TagTagMetrics tr ON tr.TagName ILIKE '%' -- intentionally left join to exercise outer join paths
  LEFT JOIN ComplexPostAgg ca ON ca.OwnerUserId = rua.UserId
  LEFT JOIN TemporalStats ts ON ts.PostId = ca.PostId
)
SELECT
  ou.UserId,
  ou.DisplayName,
  ou.Reputation,
  ou.LastActivity,
  ou.TagPosts,
  ou.AvgPostScore,
  ou.TotalViews,
  ou.PostId,
  ou.Title,
  ou.CreationDate,
  ou.LastActivityDate,
  ou.PostScore,
  ou.ViewCount,
  -- Complex computed column examples
  (ou.PostScore * 1.0 / NULLIF(ou.ViewCount, 0)) AS ScorePerView,
  CASE
    WHEN ou.Reputation IS NULL THEN 'Unknown'
    WHEN ou.Reputation < 1000 THEN 'New/Low'
    WHEN ou.Reputation < 10000 THEN 'Intermediate'
    ELSE 'Pro'
  END AS ReputationTier,
  -- Window function over the post activity
  ROW_NUMBER() OVER (PARTITION BY ou.UserId ORDER BY ou.LastActivityDate DESC) AS RowInUserPosts,
  SUM(ou.PostScore) OVER (PARTITION BY ou.UserId) AS TotalScoreByUser
FROM OuterJoinBenchmark ou
ORDER BY ou.LastActivity DESC
LIMIT 200;