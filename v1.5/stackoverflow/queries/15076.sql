-- {"query": "15076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 179795, "output_tokens": 52850} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(b.Id) DESC) AS LocationBadgeRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE 
        u.Reputation > 1000 
        AND (u.Location IS NOT NULL OR u.Location != '')
    GROUP BY 
        u.Id, u.DisplayName, u.Location
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagPopularityRank
    FROM 
        Tags t
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.QuestionCount,
    ubc.AvgQuestionScore,
    tp.TagName,
    tp.TagCount,
    CASE 
        WHEN ubc.GoldBadgeCount > 10 THEN 'High Impact'
        WHEN ubc.GoldBadgeCount > 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS UserContributionTier,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ubc.UserId)
         AND pl.LinkTypeId = 3), 0
    ) AS DuplicateLinksCount
FROM 
    UserBadgeCounts ubc
CROSS JOIN 
    TagPopularity tp
WHERE 
    ubc.LocationBadgeRank <= 3
    AND tp.TagPopularityRank <= 50
    AND (ubc.AvgQuestionScore > 2 OR ubc.GoldBadgeCount > 5)
ORDER BY 
    ubc.GoldBadgeCount DESC, 
    ubc.QuestionCount DESC
LIMIT 100;