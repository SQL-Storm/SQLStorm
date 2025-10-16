WITH RecentActiveUsers AS (
    SELECT 
        Id AS UserId,
        DisplayName,
        Reputation,
        RANK() OVER (ORDER BY LastAccessDate DESC) AS RankByLastAccess
    FROM Users
    WHERE Reputation > 1000
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByUserScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
)
SELECT 
    ru.DisplayName AS RecentUser,
    ru.Reputation,
    tq.Title AS TopQuestionTitle,
    COALESCE(tq.Score, 0) AS TopQuestionScore,
    (COALESCE(tq.Score, 0) * 10 + ru.Reputation) AS ScoreWeighted,
    CASE 
        WHEN u.Location IS NOT NULL THEN u.Location 
        ELSE 'Unknown' 
    END AS UserLocation,
    tq.CreationDate
FROM RecentActiveUsers ru
LEFT JOIN TopQuestions tq ON ru.UserId = tq.OwnerUserId AND tq.RankByUserScore = 1
LEFT JOIN Users u ON ru.UserId = u.Id
WHERE ru.RankByLastAccess <= 100
GROUP BY
    ru.DisplayName,
    ru.Reputation,
    ru.UserId,
    tq.Title,
    tq.Score,
    tq.RankByUserScore,
    tq.OwnerUserId,
    tq.CreationDate,
    u.Location
ORDER BY ScoreWeighted DESC, tq.CreationDate DESC;