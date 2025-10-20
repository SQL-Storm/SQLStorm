-- {"query": "193.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1565} 
WITH
user_scores AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGivenOnOwnPosts,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGivenOnOwnPosts,
    COALESCE(SUM(COALESCE(v.BountyAmount, 0)), 0) AS BountyAwardsOnBehalf
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
recent_activity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  GROUP BY p.OwnerUserId
)
SELECT
  COALESCE(u.Id, ra.UserId) AS UserId,
  u.DisplayName,
  u.Reputation,
  ua.UpvotesGivenOnOwnPosts,
  ua.DownvotesGivenOnOwnPosts,
  ra.PostCount,
  ra.TotalViews,
  ra.LastActivity
FROM users u
LEFT JOIN user_scores ua ON ua.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.UserId = u.Id
ORDER BY ra.TotalViews DESC NULLS LAST
LIMIT 100;