-- {"query": "15006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 674}
WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.PostTypeId,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostTypeRank,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 100
    GROUP BY 
        u.Id, u.DisplayName, p.PostTypeId
),
TagFrequency AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagUsageCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagScore
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%>' || t.TagName || '<%'
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.PostCount,
    upa.TotalScore,
    upa.AvgViewCount,
    upa.PostTypeRank,
    tf.TagName AS MostFrequentTag,
    tf.TagUsageCount,
    CASE 
        WHEN upa.TotalScore > 1000 THEN 'High Impact'
        WHEN upa.TotalScore > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS UserImpactCategory,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = upa.UserId AND v.VoteTypeId IN (2, 8)), 0
    ) AS PositiveVotes
FROM 
    UserPostActivity upa
JOIN 
    TagFrequency tf ON 
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = upa.UserId 
        AND p.Tags LIKE '%>' || tf.TagName || '<%'
    )
WHERE 
    upa.PostCount > 5
    AND tf.TagUsageCount > 100
ORDER BY 
    upa.TotalScore DESC, 
    upa.PostCount DESC
LIMIT 100;
