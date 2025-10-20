-- {"query": "13043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 571} 

WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation, Location
    FROM Users
    WHERE Reputation > 5000 AND Location IS NOT NULL
),
QuestionMetrics AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score, p.OwnerUserId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
           COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
TopQuestionsPerUser AS (
    SELECT qm.Id, qm.Title, qm.CreationDate, qm.Score, qm.OwnerUserId
    FROM QuestionMetrics qm
    WHERE qm.rn <= 3
),
UserBadges AS (
    SELECT u.Id AS UserId, COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2)
    GROUP BY u.Id
),
CommentAnalysis AS (
    SELECT p.OwnerUserId, COUNT(c.Id) AS CommentCount, AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.OwnerUserId
)
SELECT hru.DisplayName, hru.Reputation, hru.Location,
       tqpu.Title, tqpu.CreationDate, tqpu.Score,
       ub.BadgeCount, ca.CommentCount, ca.AvgCommentLength,
       SUM(tqpu.Score) OVER (PARTITION BY hru.Id ORDER BY tqpu.CreationDate) AS CumulativeScore
FROM HighReputationUsers hru
JOIN TopQuestionsPerUser tqpu ON hru.Id = tqpu.OwnerUserId
LEFT JOIN UserBadges ub ON hru.Id = ub.UserId
LEFT JOIN CommentAnalysis ca ON hru.Id = ca.OwnerUserId
WHERE tqpu.CreationDate > '2022-01-01'
  AND hru.DisplayName NOT LIKE '%[bot]%'
ORDER BY hru.Reputation DESC, tqpu.Score DESC
LIMIT 100;
