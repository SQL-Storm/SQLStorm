WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        tag_value AS Tag,
        COUNT(*) AS TagCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL (
        SELECT value AS tag_value
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS value
    ) AS t
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, tag_value
),
RankedUserStats AS (
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
    ROUND(r.TagCount * 100.0 / NULLIF(r.TotalUserTagPosts, 0), 2) AS TagPercentage,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = r.UserId AND p.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = r.UserId AND b.Class = 1) AS GoldBadgeCount
FROM RankedUserStats r
JOIN Tags t ON r.Tag = t.TagName
WHERE r.TotalUserTagPosts > 10 AND t.Count > 1000
ORDER BY r.TotalUserTagPosts DESC, r.TagCount DESC
LIMIT 100;