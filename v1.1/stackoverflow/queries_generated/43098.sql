-- {"query": "43098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 512} 

WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id
    ORDER BY 
        u.Reputation DESC
    LIMIT 10
), UserPostDetails AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ph.CreationDate AS LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    WHERE 
        p.OwnerUserId IN (SELECT Id FROM TopUsers)
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.BadgeCount,
    AVG(upd.Score) AS AvgScore,
    MAX(upd.Score) AS MaxScore,
    SUM(upd.ViewCount) AS TotalViewCount,
    AVG(EXTRACT(EPOCH FROM (upd.LastEditDate - upd.CreationDate))/3600) AS AvgEditTimeHours
FROM 
    TopUsers tu
JOIN 
    UserPostDetails upd ON tu.Id = upd.OwnerUserId
WHERE 
    upd.rn <= 5
GROUP BY 
    tu.Id
ORDER BY 
    tu.Reputation DESC, AvgScore DESC;
