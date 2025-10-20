-- {"query": "43032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 404} 
WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
),
TopQuestions AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 100
),
UserBadgesCount AS (
    SELECT UserId, COUNT(*) as BadgeCount
    FROM Badges
    GROUP BY UserId
),
CommentMetrics AS (
    SELECT PostId, COUNT(*) as TotalComments, AVG(Score) as AvgCommentScore
    FROM Comments
    GROUP BY PostId
)
SELECT 
    hru.DisplayName,
    hru.Reputation,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    cm.TotalComments,
    cm.AvgCommentScore,
    ubc.BadgeCount,
    STRING_TO_ARRAY(SUBSTRING(tq.Tags, 2, LENGTH(tq.Tags) - 2), '><') as TagsArray
FROM HighReputationUsers hru
JOIN TopQuestions tq ON hru.Id = tq.OwnerUserId
LEFT JOIN UserBadgesCount ubc ON hru.Id = ubc.UserId
LEFT JOIN CommentMetrics cm ON tq.Id = cm.PostId
WHERE tq.rn <= 5
ORDER BY hru.Reputation DESC, tq.Score DESC;