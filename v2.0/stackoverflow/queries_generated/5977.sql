-- {"query": "5977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 870} 
WITH
-- 1) aggregate user activity with ranking by reputation and activity recency
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    MAX(p.CreationDate) AS LastPostDate,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounty
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
  GROUP BY u.Id
),
-- 2) compute recent activity score using window functions and NULL-safe expressions
RecentActivity AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.UserCreationDate,
    a.LastAccessDate,
    a.QuestionCount,
    a.AnswerCount,
    a.LastPostDate,
    a.TotalBounty,
    -- score combines recency, productivity and rewards; handles NULLs gracefully
    (CASE WHEN a.LastPostDate IS NULL THEN 0 ELSE EXTRACT(EPOCH FROM (NOW() - a.LastPostDate)) END) AS RecencySeconds,
    (a.QuestionCount + a.AnswerCount) * 100 +
      (CASE WHEN a.TotalBounty IS NULL THEN 0 ELSE a.TotalBounty END) AS ProductivityScore
  FROM UserActivity a
),
-- 3) identify top performers with complex predicates and correlated subquery
TopPerformers AS (
  SELECT
    ra.UserId,
    ra.DisplayName,
    ra.Reputation,
    ra.RecencySeconds,
    ra.ProductivityScore,
    ra.LastPostDate
  FROM RecentActivity ra
  WHERE
    ra.Reputation > 1000
    OR ra.ProductivityScore > 1000
    OR EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = ra.UserId
        AND p.PostTypeId = 1
        AND p.Score > 50
        AND p.CreationDate > (CURRENT_DATE - INTERVAL '365 days')
    )
),
-- 4) create a derived set using set operations: union with a synthetic cohort
Cohort AS (
  SELECT UserId, DisplayName, Reputation, LastPostDate, ProductivityScore
  FROM TopPerformers
  UNION
  SELECT u.Id, u.DisplayName, u.Reputation, NULL, 0
  FROM Users u
  WHERE u.Reputation BETWEEN 500 AND 1000
),
-- 5) final ranking with window functions, joining with posts and comments
FinalRank AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.LastPostDate,
    c.ProductivityScore,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN c.LastPostDate IS NULL THEN 0 ELSE 1 END
      ORDER BY c.Reputation DESC, c.ProductivityScore DESC, c.LastPostDate DESC NULLS LAST
    ) AS RankWithinGroup
  FROM Cohort c
)
SELECT
  fr.UserId,
  fr.DisplayName,
  fr.Reputation,
  fr.LastPostDate,
  fr.ProductivityScore,
  fr.RankWithinGroup,
  -- 6) additional analytic metrics: average post age per user and tag diversity
  (SELECT AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)))
     FROM Posts p
     WHERE p.OwnerUserId = fr.UserId) AS AvgPostAgeSeconds,
  (SELECT COUNT(*) FROM (
     SELECT unnest(string_to_array(p.Tags, ',') ) AS tag
     FROM Posts p
     WHERE p.OwnerUserId = fr.UserId AND p.Tags IS NOT NULL
  ) t) AS TagDiversity
FROM FinalRank fr
ORDER BY fr.RankWithinGroup ASC
LIMIT 100;