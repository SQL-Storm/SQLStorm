WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        tag AS Tag,
        COUNT(*) AS TagCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL (
        WITH RECURSIVE split(pos, rest, tag) AS (
            SELECT
                1 AS pos,
                CASE
                    WHEN p.Tags LIKE '<%>' THEN SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END AS rest,
                CAST(NULL AS VARCHAR) AS tag
            UNION ALL
            SELECT
                pos + 1,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTR(rest, POSITION('><' IN rest) + 2)
                    ELSE ''
                END,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTR(rest, 1, POSITION('><' IN rest) - 1)
                    ELSE rest
                END
            FROM split
            WHERE rest <> ''
        )
        SELECT tag FROM split WHERE tag IS NOT NULL
    ) s(tag)
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, tag
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
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = r.UserId AND p2.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = r.UserId AND b.Class = 1) AS GoldBadgeCount
FROM RankedUserStats r
JOIN Tags t ON r.Tag = t.TagName
WHERE r.TotalUserTagPosts > 10 AND t.Count > 1000
GROUP BY
    r.UserId,
    r.DisplayName,
    r.Tag,
    r.TagCount,
    r.TotalUserTagPosts,
    t.TagName,
    t.Count
ORDER BY r.TotalUserTagPosts DESC, r.TagCount DESC
LIMIT 100;