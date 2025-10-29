-- {"query": "5343.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 640} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounty,
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
top_tags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagUsage,
    AVG(t.ExcerptPostId) AS ExcerptAnchor
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY TagUsage DESC
  LIMIT 10
),
complex_stats AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.PostCount,
    up.TotalBounty,
    up.Upvotes,
    up.Downvotes,
    up.LastActivity,
    t.TagName,
    t.TagUsage,
    t.ExcerptAnchor
  FROM recent_user_activity up
  LEFT JOIN (
    SELECT
      u.Id AS UserId,
      ta.TagName,
      ta.Count AS TagUsage
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Tags ta ON ta.Id = p.Tags -- (requires Tags to be parsed; placeholder for complexity)
    GROUP BY u.Id, ta.TagName, ta.Count
    HAVING COUNT(*) > 0
  ) AS t ON t.UserId = up.UserId
  LEFT JOIN top_tags tt ON tt.TagName = t.TagName
  WHERE up.Reputation > 1000
)
SELECT
  cs.UserId,
  cs.DisplayName,
  cs.Reputation,
  cs.PostCount,
  cs.TotalBounty,
  cs.Upvotes,
  cs.Downvotes,
  cs.LastActivity,
  cs.TagName,
  cs.TagUsage,
  cs.ExcerptAnchor,
  CASE
    WHEN cs.Reputation > 5000 THEN 'Legendary'
    WHEN cs.Reputation > 1000 THEN 'Rising'
    ELSE 'Emerging'
  END AS Tier,
  STRING_AGG(DISTINCT CONCAT(vt.Name, ':', vt.Id), '|') OVER (PARTITION BY cs.UserId) AS VoteTypesSeen
FROM complex_stats cs
LEFT JOIN Votes v ON v.UserId = cs.UserId
LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
ORDER BY cs.TotalBounty DESC, cs.Reputation DESC
LIMIT 100;