-- {"query": "5491.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 617} 
WITH
-- top 5 most active users by total posts (questions/answers) with their badge counts
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- aggregated statistics per user: total comments and total votes on their posts
UserEngagement AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.PostCount,
    COALESCE(COUNT(c.Id), 0) AS CommentCount,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyOnPosts
  FROM ActiveUsers a
  LEFT JOIN Posts p ON p.OwnerUserId = a.UserId
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY a.UserId, a.DisplayName, a.Reputation, a.PostCount
),
-- per-user badge diversity: how many distinct badge names they have
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(DISTINCT b.Name) AS DistinctBadges
  FROM Badges b
  GROUP BY b.UserId
),
-- cross join to build a rich dataset with correlating subqueries and window functions
Final AS (
  SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.PostCount,
    uc.CommentCount,
    uc.TotalBountyOnPosts,
    COALESCE(ub.DistinctBadges, 0) AS DistinctBadges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.PostCount DESC) AS RankByReputation,
    SUM(CASE WHEN t.Name = 'Question' THEN 1 ELSE 0 END) OVER (PARTITION BY u.UserId) AS QuestionsCreated,
    SUM(CASE WHEN t.Name = 'Answer' THEN 1 ELSE 0 END) OVER (PARTITION BY u.UserId) AS AnswersGiven,
    -- correlated subquery: recent activity date on their posts
    (SELECT MAX(LastActivityDate) FROM Posts p2 WHERE p2.OwnerUserId = u.UserId) AS LastActive
  FROM ActiveUsers u
  LEFT JOIN UserEngagement uc ON uc.UserId = u.UserId
  LEFT JOIN UserBadges ub ON ub.UserId = u.UserId
  LEFT JOIN Posts t ON t.OwnerUserId = u.UserId
  GROUP BY
    u.UserId, u.DisplayName, u.Reputation, u.PostCount, uc.CommentCount, uc.TotalBountyOnPosts, ub.DistinctBadges
)
SELECT *
FROM Final
WHERE RankByReputation <= 10
ORDER BY RankByReputation;