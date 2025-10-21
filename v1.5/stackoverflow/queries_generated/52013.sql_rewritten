-- {"query": "52013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 274} 
WITH UserStats AS (
  SELECT U.Id, U.Reputation, U.DisplayName, COUNT(P.Id) as NumPosts, SUM(P.Score) as TotalScore
  FROM Users U
  LEFT JOIN Posts P ON U.Id = P.OwnerUserId
  WHERE P.PostTypeId = 1
  GROUP BY U.Id, U.Reputation, U.DisplayName
),
BadgeStats AS (
  SELECT UserId, COUNT(*) as NumBadges, SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) as BadgeScore
  FROM Badges
  GROUP BY UserId
),
CommentStats AS (
  SELECT UserId, COUNT(*) as NumComments, SUM(Score) as CommentScore
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
)
SELECT US.*, BS.NumBadges, BS.BadgeScore, CS.NumComments, CS.CommentScore,
  (US.TotalScore + COALESCE(BS.BadgeScore, 0) + COALESCE(CS.CommentScore, 0)) as OverallScore
FROM UserStats US
LEFT JOIN BadgeStats BS ON US.Id = BS.UserId
LEFT JOIN CommentStats CS ON US.Id = CS.UserId
ORDER BY OverallScore DESC
LIMIT 100;