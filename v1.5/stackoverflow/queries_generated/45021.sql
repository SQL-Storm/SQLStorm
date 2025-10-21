-- {"query": "45021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 48174, "output_tokens": 8216} 
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, Tag
), RankedUserStats AS (
    SELECT 
        UserId, 
        DisplayName, 
        Tag, 
        TagCount,
        SUM(TagCount) OVER (PARTITION BY UserId) AS TotalUserTagPosts
    FROM TopUserTags
    WHERE TagRank <= 3
)
SELECT 
    r.UserId, 
    r.DisplayName, 
    r.Tag, 
    r.TagCount, 
    r.TotalUserTagPosts,
    ROUND(r.TagCount * 100.0 / r.TotalUserTagPosts, 2) AS TagPercentage,
    (SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = r.UserId AND p.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = r.UserId AND b.Class = 1) AS GoldBadgeCount
FROM RankedUserStats r
JOIN Tags t ON r.Tag = t.TagName
WHERE r.TotalUserTagPosts > 10 AND t.Count > 1000
ORDER BY r.TotalUserTagPosts DESC, r.TagCount DESC
LIMIT 100;