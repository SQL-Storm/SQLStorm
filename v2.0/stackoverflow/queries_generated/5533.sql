-- {"query": "5533.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 942} 
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagCount
  FROM Tags t
  GROUP BY t.TagName
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COALESCE(v.TotalVotes, 0) AS TotalVotes
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, SUM(BountyAmount) AS TotalVotes
    FROM Votes v
    GROUP BY UserId
  ) v ON v.UserId = u.Id
),
BenchmarkData AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.Tags,
    LEAD(r.PostId) OVER (ORDER BY r.rn) AS NextPostId,
    LAG(r.PostId) OVER (ORDER BY r.rn) AS PrevPostId
  FROM RecentPopularQuestions r
  WHERE r.rn <= 100
),
ComplexFilters AS (
  SELECT
    p.PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    CASE
      WHEN p.ViewCount > 1000 THEN 'HighView'
      WHEN p.Score > 50 THEN 'HighScore'
      ELSE 'Moderate'
    END AS Tier,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.PostId) AS LinkCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.PostId AND v.VoteTypeId = 3) AS DownVotes
  FROM Posts p
  JOIN BenchmarkData b ON b.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
    AND p.LastActivityDate > p.CreationDate
),
CorrelatedAnalysis AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.CreationDate,
    cf.ViewCount,
    cf.Score,
    cf.Tags,
    cf.Tier,
    cf.CommentCount,
    cf.LinkCount,
    cf.UpVotes,
    cf.DownVotes,
    (cf.UpVotes - cf.DownVotes) / NULLIF(cf.CommentCount, 0) AS EngagementRatio,
    (SELECT AVG(UpVotes) FROM ComplexFilters) AS AvgPostUpVotes,
    (SELECT MAX(EngagementRatio) FROM (
       SELECT (UpVotes - DownVotes) / NULLIF(CommentCount, 0) AS EngagementRatio
       FROM ComplexFilters
     ) t) AS MaxEngagement
  FROM ComplexFilters cf
),
FinalOutput AS (
  SELECT
    ca.PostId,
    ca.Title,
    ca.CreationDate,
    ca.ViewCount,
    ca.Score,
    ca.Tags,
    ca.Tier,
    ca.CommentCount,
    ca.LinkCount,
    ca.UpVotes,
    ca.DownVotes,
    ca.EngagementRatio,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.TotalVotes
  FROM CorrelatedAnalysis ca
  LEFT JOIN UserEngagement u ON u.UserId = (SELECT OwnerUserId FROM Posts p WHERE p.Id = ca.PostId)
)
SELECT *
FROM FinalOutput
ORDER BY Tier DESC, EngagementRatio DESC NULLS LAST
LIMIT 200;