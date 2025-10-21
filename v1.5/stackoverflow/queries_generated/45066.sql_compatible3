WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgUserPostScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 1000
),
TagAnalytics AS (
    SELECT 
        PostId,
        TRIM(BOTH '><') AS Tag,
        Score,
        PostRank,
        TotalUserPosts
    FROM (
        SELECT
            PostId,
            UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR CHAR_LENGTH(Tags) - 2), '><')) AS Tag,
            Score,
            PostRank,
            TotalUserPosts
        FROM 
            RankedUserPosts
    ) AS t
),
-- Fallback for engines without STRING_TO_ARRAY and UNNEST support
TagAnalyticsCompat AS (
    SELECT
        ta.PostId,
        ta.Tag,
        ta.Score,
        ta.PostRank,
        ta.TotalUserPosts
    FROM
        TagAnalytics ta
    UNION ALL
    SELECT
        ru.PostId,
        NULL AS Tag,
        ru.Score,
        ru.PostRank,
        ru.TotalUserPosts
    FROM
        RankedUserPosts ru
    WHERE
        NOT EXISTS (SELECT 1 FROM TagAnalytics ta WHERE ta.PostId = ru.PostId)
)
SELECT 
    Tag,
    COUNT(DISTINCT PostId) AS PostCount,
    ROUND(AVG(Score), 2) AS AvgTagScore,
    MAX(Score) AS MaxTagScore
FROM 
    TagAnalyticsCompat
WHERE 
    PostRank <= 10
    AND TotalUserPosts > 5
GROUP BY 
    Tag
HAVING 
    COUNT(DISTINCT PostId) > 100
ORDER BY 
    AvgTagScore DESC, 
    PostCount DESC
LIMIT 50;