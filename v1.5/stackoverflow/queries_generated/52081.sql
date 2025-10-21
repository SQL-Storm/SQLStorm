-- {"query": "52081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 743} 
WITH BadgeCounts AS (
  SELECT
    UserId,
    SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY UserId
),
PostStats AS (
  SELECT
    OwnerUserId,
    SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) AS QuestionScore,
    SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS AnswerScore,
    SUM(Score) AS TotalPostScore,
    COUNT(*) AS TotalPosts,
    AVG(Score) AS AvgScore
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
VoteStats AS (
  SELECT
    p.OwnerUserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
  FROM Votes v
  JOIN Posts p ON v.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
CommentStats AS (
  SELECT
    UserId,
    COUNT(*) AS TotalComments,
    AVG(Score) AS AvgCommentScore
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
EditHistory AS (
  SELECT
    UserId,
    COUNT(*) AS TotalEdits
  FROM PostHistory
  WHERE UserId IS NOT NULL
  GROUP BY UserId
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.Location,
  bc.GoldBadges,
  bc.SilverBadges,
  bc.BronzeBadges,
  bc.TotalBadges,
  ps.QuestionScore,
  ps.AnswerScore,
  ps.TotalPostScore,
  ps.TotalPosts,
  ps.AvgScore,
  vs.UpvotesReceived,
  vs.DownvotesReceived,
  cs.TotalComments,
  cs.AvgCommentScore,
  eh.TotalEdits,
  (u.Reputation * 1.0 + 
   COALESCE(bc.GoldBadges, 0) * 100 + 
   COALESCE(bc.SilverBadges, 0) * 50 + 
   COALESCE(bc.BronzeBadges, 0) * 25 + 
   COALESCE(ps.TotalPostScore, 0) * 0.1 + 
   COALESCE(vs.UpvotesReceived, 0) * 0.5 - 
   COALESCE(vs.DownvotesReceived, 0) * 2 + 
   COALESCE(cs.TotalComments, 0) * 0.05 + 
   COALESCE(eh.TotalEdits, 0) * 0.02) AS CompositeScore
FROM Users u
LEFT JOIN BadgeCounts bc ON u.Id = bc.UserId
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN VoteStats vs ON u.Id = vs.OwnerUserId
LEFT JOIN CommentStats cs ON u.Id = cs.UserId
LEFT JOIN EditHistory eh ON u.Id = eh.UserId
ORDER BY CompositeScore DESC
LIMIT 100;