-- {"query": "15064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 622}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadge,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostFrequencyRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TopPostRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
)
SELECT 
    u.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadge,
    ubs.UpvoteCount,
    tp.TagName AS TopTag,
    tp.Count AS TagCount,
    COALESCE(p.AnswerCount, 0) AS QuestionAnswers,
    CASE 
        WHEN u.Location IS NULL THEN 'Unknown'
        ELSE u.Location 
    END AS UserLocation,
    ROUND(
        (ubs.UpvoteCount * 1.0 / NULLIF(p.Score, 0)) * 100, 
        2
    ) AS UpvotePercentage
FROM UserBadgeStats ubs
JOIN Users u ON ubs.UserId = u.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN TagPopularity tp ON tp.Title = p.Title AND tp.TopPostRank = 1
WHERE ubs.PostFrequencyRank <= 500
    AND (u.WebsiteUrl IS NOT NULL OR u.AboutMe LIKE '%developer%')
ORDER BY ubs.TotalBadges DESC, UpvotePercentage DESC
LIMIT 100;
