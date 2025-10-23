-- {"query": "180.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1816} 
WITH user_reputation AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS JoinedDate,
    (SELECT MAX(CreationDate) FROM Votes WHERE UserId = u.Id) AS LastVoteDate
  FROM Users u
),
user_post_stats AS (
  SELECT
    p.OwnerUserId AS Id,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
user_badge_summary AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    ARRAY_AGG(b.Name) AS BadgeNames
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  r.Id,
  r.DisplayName,
  r.Reputation,
  COALESCE(s.PostCount, 0) AS PostCount,
  r.LastVoteDate,
  COALESCE(b.BadgeCount, 0) AS BadgeCount,
  COALESCE(b.BadgeNames, ARRAY[]::text[]) AS BadgeNames,
  COUNT(pl.Id) AS LinkedPostLinks,
  COALESCE(s.ScoreSum, 0) AS ScoreSum,
  SUM(CASE WHEN t.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
  SUM(CASE WHEN t.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
  RANK() OVER (ORDER BY r.Reputation DESC, COALESCE(s.PostCount, 0) DESC) AS RepRank
FROM user_reputation r
LEFT JOIN user_post_stats s ON s.Id = r.Id
LEFT JOIN user_badge_summary b ON b.UserId = r.Id
LEFT JOIN Posts p ON p.OwnerUserId = r.Id
LEFT JOIN Votes t ON t.UserId = r.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
GROUP BY
  r.Id,
  r.DisplayName,
  r.Reputation,
  r.LastVoteDate,
  s.PostCount,
  s.ScoreSum,
  b.BadgeCount,
  b.BadgeNames
ORDER BY RepRank
LIMIT 200;