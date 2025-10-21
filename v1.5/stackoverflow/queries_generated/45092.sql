-- {"query": "45092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 598}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(p.Score) AS AvgPostScore
    FROM 
        Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000 
        AND p.PostTypeId IN (1, 2)
    GROUP BY 
        u.Id, u.DisplayName
), 
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM 
        Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.AvgPostScore,
    tp.TagName AS MostPopularTag,
    tp.PostCount AS TagPostCount,
    tp.AvgTagScore AS TagAvgScore
FROM 
    UserBadgeStats ubs
JOIN 
    TagPopularity tp ON tp.PostCount > 50
WHERE 
    ubs.TotalBadges > 10
    AND ubs.AvgPostScore > 5
ORDER BY 
    ubs.TotalBadges DESC, 
    tp.PostCount DESC
LIMIT 100;
