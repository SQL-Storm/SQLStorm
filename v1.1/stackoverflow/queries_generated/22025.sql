-- {"query": "22025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1096} 

WITH UserStats AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         u.LastAccessDate,
         COUNT(DISTINCT p.Id) AS NumPosts,
         COALESCE(SUM(p.Score), 0) AS TotalPostScore,
         AVG(p.ViewCount) FILTER (WHERE p.ViewCount IS NOT NULL) AS AvgViewCount,
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
         (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score IS NOT NULL AND c.Score > (SELECT AVG(Score) FROM Comments WHERE Score IS NOT NULL)) AS HighScoreCommentsAboveAvg
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
BadgeStats AS (
  SELECT UserId,
         COUNT(*) AS NumBadges,
         COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
         STRING_AGG(Name, ' | ') AS BadgeNames,
         MAX(Date) AS LatestBadgeDate
  FROM Badges
  GROUP BY UserId
),
PostDetails AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.PostTypeId,
         p.Score,
         CASE WHEN p.Tags IS NOT NULL THEN CARDINALITY(REGEXP_SPLIT_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) ELSE 0 END AS TagCount,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'Open' END AS PostStatus,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS PostRank,
         RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY LENGTH(COALESCE(p.Body, '')) DESC) AS BodyLengthRank
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserAnswerStats AS (
  SELECT p.ParentId AS QuestionId,
         p.OwnerUserId AS AnswererId,
         COUNT(*) AS NumAnswersToQuestion,
         MAX(p.Score) AS MaxAnswerScoreToQuestion
  FROM Posts p
  WHERE p.PostTypeId = 2 -- Answers
  GROUP BY p.ParentId, p.OwnerUserId
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.NumPosts,
       CASE WHEN us.NumPosts > 0 THEN ROUND(us.TotalPostScore::NUMERIC / us.NumPosts, 2) ELSE 0 END AS AvgPostScore,
       us.AvgViewCount,
       us.UpVotesReceived,
       us.HighScoreCommentsAboveAvg,
       bs.NumBadges,
       bs.GoldBadges,
       bs.BadgeNames,
       pd.TopScorePost,
       pd.TopBodyLength,
       pd.ClosedPostsCount,
       uas.TotalAnswersGiven,
       uas.AvgMaxScorePerQuestion,
       (us.Reputation + us.TotalPostScore + 10 * COALESCE(bs.NumBadges, 0) + COALESCE(us.UpVotesReceived, 0)) AS ProductivityScore,
       CASE WHEN us.Reputation > 1000 AND COALESCE(bs.NumBadges, 0) > 5 THEN 'High Performer'
            WHEN us.NumPosts > 0 AND us.TotalPostScore / NULLIF(us.NumPosts, 0) > 10 THEN 'Consistent'
            ELSE 'Casual' END AS UserCategory,
       EXTRACT(EPOCH FROM AGE(CURRENT_TIMESTAMP, us.LastAccessDate)) / 86400 AS DaysSinceLastAccess,
       EXTRACT(YEAR FROM COALESCE(bs.LatestBadgeDate, us.LastAccessDate)) AS BadgeYear
FROM UserStats us
LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
LEFT JOIN (SELECT OwnerUserId,
                  MAX(Score) AS TopScorePost,
                  MAX(CASE WHEN BodyLengthRank = 1 THEN LENGTH(COALESCE(p.Body, '')) END) AS TopBodyLength,
                  COUNT(CASE WHEN PostStatus = 'Closed' THEN 1 END) AS ClosedPostsCount
           FROM PostDetails pd
           JOIN Posts p ON p.Id = pd.Id
           GROUP BY OwnerUserId) pd ON pd.OwnerUserId = us.Id
LEFT JOIN (SELECT AnswererId,
                  COUNT(DISTINCT QuestionId) AS TotalAnswersGiven,
                  AVG(MaxAnswerScoreToQuestion) AS AvgMaxScorePerQuestion
           FROM UserAnswerStats
           GROUP BY AnswererId) uas ON uas.AnswererId = us.Id
WHERE us.Reputation > 1
  AND (bs.NumBadges IS NOT NULL OR us.NumPosts > 0)
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = us.Id AND p.Score < -5)
ORDER BY ProductivityScore DESC, us.Reputation DESC, bs.NumBadges DESC NULLS LAST
LIMIT 500;
