-- {"query": "5343.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 640}
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
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
    AVG(CAST(t.ExcerptPostId AS NUMERIC)) AS ExcerptAnchor
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY SUM(t.Count) DESC
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
    tt.ExcerptAnchor
  FROM recent_user_activity up
  LEFT JOIN (
    SELECT
      u.Id AS UserId,
      ta.TagName,
      ta.Count AS TagUsage,
      ta.ExcerptPostId
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Tags ta ON ta.TagName = p.Tags
    GROUP BY u.Id, ta.TagName, ta.Count, ta.ExcerptPostId
    HAVING COUNT(*) > 0
  ) AS t ON t.UserId = up.UserId
  LEFT JOIN top_tags tt ON tt.TagName = t.TagName
  WHERE up.Reputation > 1000
),
vote_types_per_user AS (
  SELECT
    cs.UserId,
    STRING_AGG(vt.Name || ':' || CAST(vt.Id AS VARCHAR), '|' ) AS VoteTypesSeen
  FROM complex_stats cs
  LEFT JOIN Votes v ON v.UserId = cs.UserId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY cs.UserId
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
  COALESCE(vtu.VoteTypesSeen, '') AS VoteTypesSeen
FROM complex_stats cs
LEFT JOIN vote_types_per_user vtu ON vtu.UserId = cs.UserId
GROUP BY
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
  vtu.VoteTypesSeen
ORDER BY cs.TotalBounty DESC, cs.Reputation DESC
LIMIT 100;