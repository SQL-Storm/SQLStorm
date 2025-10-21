-- {"query": "178.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2089} 
WITH UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    MAX(p.LastActivityDate) AS MostRecentActivity,
    MAX(p.Title) FILTER (WHERE p.Title IS NOT NULL) AS MostRecentTitle,
    MAX(p.Id) AS LastPostId
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
PostActivityDetails AS (
  SELECT
    ra.UserId,
    ra.MostRecentActivity,
    ra.MostRecentTitle,
    ra.LastPostId
  FROM RecentActivity ra
),
OpenCloseSummary AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedCount,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenedCount
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY p.OwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(us.PostCount, 0) AS PostCount,
  COALESCE(us.AvgPostScore, 0) AS AvgPostScore,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  pa.MostRecentActivity AS MostRecentActivity,
  pa.MostRecentTitle AS MostRecentTitle,
  ocs.ClosedCount,
  ocs.ReopenedCount,
  -- correlated subquery: number of comments written by the user
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS UserCommentCount,
  -- example window function: rank users by Reputation within 100 top by activity date
  RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS RankByReputation
FROM Users u
LEFT JOIN UserStats us ON us.UserId = u.Id
LEFT JOIN PostActivityDetails pa ON pa.UserId = u.Id
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN OpenCloseSummary ocs ON ocs.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT 1 AS dummy
) AS d ON TRUE
ORDER BY u.Reputation DESC NULLS LAST, u.LastAccessDate DESC
LIMIT 100;