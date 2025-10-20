-- {"query": "58021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1157} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount,
           DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE p.CreationDate BETWEEN '2022-01-01' AND '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
VoteStats AS (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes
    GROUP BY PostId
),
BadgeAchievers AS (
    SELECT UserId, COUNT(Id) AS GoldBadges,
           MAX(Date) AS LastGoldBadgeDate
    FROM Badges
    WHERE Class = 1 AND Date BETWEEN '2022-01-01' AND '2023-01-01'
    GROUP BY UserId
    HAVING COUNT(Id) >= 5
)
SELECT au.DisplayName, au.Reputation, au.PostCount,
       vs.Upvotes, vs.Downvotes, ba.GoldBadges,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = au.Id AND c.CreationDate BETWEEN '2022-01-01' AND '2023-01-01') AS CommentCount,
       (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = au.Id AND p2.PostTypeId = 1) AS AvgQuestionScore,
       (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = au.Id AND ph.PostHistoryTypeId IN (5,6)) AS EditsMade
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
JOIN VoteStats vs ON p.Id = vs.PostId
JOIN BadgeAchievers ba ON au.Id = ba.UserId
WHERE p.AnswerCount > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1)
  AND vs.Upvotes > vs.Downvotes * 2
  AND p.ClosedDate IS NULL
ORDER BY au.ReputationRank, ba.GoldBadges DESC, vs.Upvotes DESC
LIMIT 100;
