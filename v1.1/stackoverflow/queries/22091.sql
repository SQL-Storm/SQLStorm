-- {"query": "22091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 848} 
WITH user_post_stats AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) AS PostCount,
         SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) AS QuestionScore,
         SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS AnswerScore,
         AVG(Score) AS AvgScore,
         COUNT(CASE WHEN Tags IS NOT NULL THEN 1 END) AS TaggedPostCount
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
user_vote_stats AS (
  SELECT v.UserId,
         COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesReceived,
         COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesReceived,
         SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(BountyAmount, 0) ELSE 0 END) AS TotalBountyGiven
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.UserId
),
user_comment_stats AS (
  SELECT UserId,
         COUNT(*) AS CommentCount,
         AVG(COALESCE(Score, 0)) AS AvgCommentScore
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
user_badge_stats AS (
  SELECT UserId,
         COUNT(*) AS BadgeCount,
         COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
         STRING_AGG(Name, ', ') AS BadgeNames
  FROM Badges
  GROUP BY UserId
),
top_active_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
         COALESCE(p.PostCount, 0) AS PostCount,
         COALESCE(p.QuestionScore, 0) AS QuestionScore,
         COALESCE(p.AnswerScore, 0) AS AnswerScore,
         COALESCE(v.UpVotesReceived, 0) - COALESCE(v.DownVotesReceived, 0) AS NetUpvotes,
         COALESCE(c.CommentCount, 0) AS CommentCount,
         CASE WHEN b.BadgeCount IS NULL THEN 0 ELSE b.BadgeCount END AS BadgeCount,
         RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
         COALESCE((p.QuestionScore + p.AnswerScore) / NULLIF(p.PostCount, 0), 0) AS AvgPostScore,
         LEFT(COALESCE(u.DisplayName, 'Anonymous'), 10) || '...' AS ShortName,
         (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score > 10 AND p2.PostTypeId IN (1,2)) AS HighScorePosts
  FROM Users u
  LEFT JOIN user_post_stats p ON u.Id = p.UserId
  LEFT JOIN user_vote_stats v ON u.Id = v.UserId
  LEFT JOIN user_comment_stats c ON u.Id = c.UserId
  LEFT JOIN user_badge_stats b ON u.Id = b.UserId
  WHERE u.Reputation > 100
    AND (COALESCE(p.PostCount, 0) > 5 OR COALESCE(c.CommentCount, 0) > 10)
)
SELECT * FROM top_active_users
UNION ALL
SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, 0,0,0,0,0,0, RANK() OVER (ORDER BY u.Reputation DESC) + 1000, 0, LEFT(COALESCE(u.DisplayName, 'Anonymous'), 10) || '...', 
       (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Date > u.CreationDate)
FROM Users u
WHERE u.Reputation <= 100 AND EXISTS (
  SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class <= 2
)
ORDER BY ReputationRank, NetUpvotes DESC
LIMIT 200;