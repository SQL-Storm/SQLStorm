-- {"query": "43020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 639} 
WITH UserReputation AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN b.Class = 1 THEN 100 ELSE CASE WHEN b.Class = 2 THEN 50 ELSE 10 END END) AS BadgeScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
),
UserTopQuestions AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        ARRAY_AGG(DISTINCT tq.Title) AS TopQuestionTitles,
        AVG(tq.Score) AS AvgTopQuestionScore
    FROM UserReputation u
    JOIN TopQuestions tq ON u.Id = tq.OwnerUserId
    WHERE tq.rn <= 5
    GROUP BY u.Id, u.DisplayName
),
FinalResult AS (
    SELECT 
        ur.Id,
        ur.DisplayName,
        ur.Reputation,
        ur.BadgeScore,
        utq.TopQuestionTitles,
        utq.AvgTopQuestionScore,
        COUNT(DISTINCT ph.PostId) AS TotalEditedPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId BETWEEN 1 AND 9 THEN 1 ELSE 0 END) AS TotalRevisions,
        AVG(CASE WHEN ph.PostHistoryTypeId BETWEEN 1 AND 9 THEN EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) END) AS AvgEditTimeMinutes
    FROM UserReputation ur
    LEFT JOIN UserTopQuestions utq ON ur.Id = utq.UserId
    LEFT JOIN PostHistory ph ON ur.Id = ph.UserId
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.CreationDate > cast('2024-10-01' as date) - INTERVAL '6 months'
    GROUP BY ur.Id, ur.DisplayName, ur.Reputation, ur.BadgeScore, utq.TopQuestionTitles, utq.AvgTopQuestionScore
)
SELECT *
FROM FinalResult
ORDER BY Reputation DESC, AvgTopQuestionScore DESC
LIMIT 100;