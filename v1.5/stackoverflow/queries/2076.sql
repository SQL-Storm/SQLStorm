-- {"query": "2076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 380} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        MAX(p.LastActivityDate) AS LastActiveDate
    FROM 
        Users u
    INNER JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY 
        u.Id, u.DisplayName
),
HighReputationAnswers AS (
    SELECT 
        p.Id AS PostId,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS AnswerRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
    AND 
        p.Score > 2
),
BadgedUsers AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ',') AS Badges
    FROM 
        Badges b
    WHERE 
        b.Class = 1
    GROUP BY 
        b.UserId
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.LastActiveDate,
    COUNT(ha.PostId) AS TopAnswersCount,
    COALESCE(bu.Badges, 'No Gold Badges') AS GoldBadges
FROM 
    RecentActiveUsers ru
LEFT JOIN 
    HighReputationAnswers ha ON ru.UserId = ha.OwnerUserId
LEFT JOIN 
    BadgedUsers bu ON ru.UserId = bu.UserId
WHERE 
    ha.AnswerRank = 1 OR ha.AnswerRank IS NULL
GROUP BY 
    ru.UserId, ru.DisplayName, ru.LastActiveDate, bu.Badges
HAVING 
    COUNT(ha.PostId) > 5
ORDER BY 
    ru.LastActiveDate DESC;