-- {"query": "7.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 608} 
WITH RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.CreationDate >= DATEADD(day, -180, GETDATE())
    AND p.LastActivityDate >= DATEADD(day, -30, GETDATE())
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(rp.Id) AS RecentPostCount,
    SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQuestions,
    SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswers,
    AVG(DATEDIFF(minute, rp.CreationDate, rp.LastActivityDate)) AS AvgMinutesBetweenPosts,
    MAX(rp.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN RecentActivePosts rp ON rp.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Coalesced AS (
  SELECT
    o.UserId,
    o.DisplayName,
    o.Reputation,
    o.RecentPostCount,
    o.RecentQuestions,
    o.RecentAnswers,
    o.AvgMinutesBetweenPosts,
    o.LastActive,
    -- Complex correlation: count of comments on the user's recent posts with NULL-safe checks
    (SELECT COUNT(*) FROM Comments c
     INNER JOIN Posts pr ON pr.Id = c.PostId
     WHERE pr.OwnerUserId = o.UserId
       AND pr.CreationDate >= DATEADD(day, -60, GETDATE())
       AND c.Text IS NOT NULL
    ) AS RecentPostComments,
    -- Window function: rank users by engagement score (weighted)
    ROW_NUMBER() OVER (ORDER BY
      (COALESCE(o.RecentPostCount,0) * 3
       + COALESCE(o.RecentQuestions,0)
       + COALESCE(o.RecentAnswers,0) * 2
       + COALESCE(o.RecentPostCount,0) * 5
      ) DESC
    ) AS EngagementRank
  FROM OwnerStats o
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.RecentPostCount,
  c.RecentQuestions,
  c.RecentAnswers,
  c.AvgMinutesBetweenPosts,
  c.LastActive,
  c.RecentPostComments,
  c.EngagementRank
FROM Coalesced c
ORDER BY c.EngagementRank
FETCH FIRST 100 ROWS ONLY;