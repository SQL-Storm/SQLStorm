WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId,
        tag.TagName AS TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        -- split tags like '<tag1><tag2>' into rows using a string-splitting approach
        SELECT TRIM(value) AS TagName, post_id
        FROM (
            SELECT
                p.Id AS post_id,
                -- remove leading '<' and trailing '>' if both present
                CASE
                    WHEN p.Tags IS NULL THEN ''
                    WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END AS tags_normalized
            FROM Posts p
            WHERE p.PostTypeId = 1
        ) posts_for_split,
        -- split by '><' into rows using a recursive CTE compatible approach
        LATERAL (
            SELECT value
            FROM (
                WITH RECURSIVE splitter(s, rest) AS (
                    SELECT '', tags_normalized
                    UNION ALL
                    SELECT
                        CASE
                            WHEN INSTR(rest, '><') = 0 THEN rest
                            ELSE SUBSTR(rest, 1, INSTR(rest, '><') - 1)
                        END,
                        CASE
                            WHEN INSTR(rest, '><') = 0 THEN ''
                            ELSE SUBSTR(rest, INSTR(rest, '><') + 2)
                        END
                    FROM splitter
                    WHERE rest <> ''
                )
                SELECT s AS value
                FROM splitter
                WHERE s <> ''
            )
        ) split_vals
    ) tag ON tag.post_id = p.Id
    JOIN Tags t ON t.TagName = tag.TagName
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, tag.TagName
),
TagPerformanceRanking AS (
    SELECT 
        TagName,
        RANK() OVER (ORDER BY SUM(PostCount) DESC) AS PopularityRank,
        RANK() OVER (ORDER BY AVG(AvgPostScore) DESC) AS QualityRank
    FROM UserTagActivity
    GROUP BY TagName
)
SELECT 
    uta.TagName,
    tpr.PopularityRank,
    tpr.QualityRank,
    COUNT(DISTINCT uta.UserId) AS UniqueContributors,
    SUM(uta.PostCount) AS TotalPosts,
    ROUND(AVG(uta.AvgPostScore), 2) AS AverageTagScore,
    MAX(uta.MaxViewCount) AS MaxTagViewCount
FROM UserTagActivity uta
JOIN TagPerformanceRanking tpr ON uta.TagName = tpr.TagName
WHERE uta.PostCount > 5
GROUP BY uta.TagName, tpr.PopularityRank, tpr.QualityRank
ORDER BY UniqueContributors DESC, TotalPosts DESC
LIMIT 50;