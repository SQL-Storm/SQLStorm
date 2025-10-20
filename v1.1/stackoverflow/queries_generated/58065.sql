-- {"query": "58065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1244} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    WHERE u.Reputation > 10000
      AND u.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT OwnerUserId, 
           AVG(Score) AS AvgPostScore,
           MAX(ViewCount) AS MaxViews,
           SUM(AnswerCount) AS TotalAnswersGenerated,
           COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
           COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswersProvided
    FROM Posts
    WHERE CreationDate BETWEEN '2022-01-01' AND '2023-12-31'
    GROUP BY OwnerUserId
),
VoteAnalysis AS (
    SELECT v.UserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpvotesReceived,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownvotesReceived,
           COUNT(DISTINCT v.PostId) AS DistinctPostsVotedOn
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY v.UserId
),
BadgeAchievements AS (
    SELECT UserId, 
           COUNT(*) AS TotalBadges,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges
    WHERE Date BETWEEN '2021-01-01' AND '2023-12-31'
    GROUP BY UserId
)
SELECT au.DisplayName, au.Reputation, au.ReputationRank,
       ps.AvgPostScore, ps.MaxViews, ps.TotalAnswersGenerated,
       va.UpvotesReceived, va.DownvotesReceived, va.DistinctPostsVotedOn,
       ba.TotalBadges, ba.GoldBadges,
       (SELECT COUNT(*) FROM Comments WHERE UserId = au.Id) AS TotalComments,
       (SELECT COUNT(*) FROM PostHistory WHERE UserId = au.Id 
        AND PostHistoryTypeId IN (2,5,8)) AS ContentEditsMade
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
LEFT JOIN BadgeAchievements ba ON au.Id = ba.UserId
WHERE ps.QuestionsAsked > 50 OR ps.AnswersProvided > 100
ORDER BY au.ReputationRank, ps.AvgPostScore DESC, va.UpvotesReceived DESC
LIMIT 100;
