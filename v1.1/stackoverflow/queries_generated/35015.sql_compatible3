WITH TopActiveUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(P.ViewCount) AS TotalViews,
        SUM(P.Score) AS TotalScore,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM
        Users U
        LEFT JOIN Posts P ON U.Id = P.OwnerUserId
        LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE
        U.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
        AND P.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
    GROUP BY
        U.Id, U.DisplayName
    HAVING
        COUNT(DISTINCT P.Id) > 50
),
UserTagCounts AS (
    SELECT
        OwnerUserId AS UserId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM Tags)) AS TagString,
        Id AS PostId
    FROM Posts
    WHERE PostTypeId = 1
),
Numbers AS (
    SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
    UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
    UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
),
UserTagsExpanded AS (
    SELECT
        u.UserId,
        NULLIF(TRIM(BOTH ' ' FROM split_part(u.TagString, '><', n.n)), '') AS TagName
    FROM UserTagCounts u
    JOIN Numbers n ON n.n <= 1 + (LENGTH(u.TagString) - LENGTH(REPLACE(u.TagString, '><', '')))
    WHERE u.TagString IS NOT NULL AND u.TagString <> ''
),
UserTagAggregates AS (
    SELECT
        UserId,
        TagName,
        COUNT(*) AS TagCount
    FROM UserTagsExpanded
    WHERE TagName IS NOT NULL AND TagName <> ''
    GROUP BY UserId, TagName
),
UserTopTag AS (
    SELECT
        uta.UserId,
        uta.TagName
    FROM (
        SELECT
            UserId,
            TagName,
            TagCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
        FROM UserTagAggregates
    ) uta
    WHERE uta.rn = 1
)
SELECT
    T.UserId,
    T.DisplayName,
    T.TotalPosts,
    T.TotalViews,
    T.TotalScore,
    T.TotalBadges,
    PT.Name AS MostCommonPostType,
    COALESCE(UT.TagName, 'N/A') AS MostUsedTag,
    ROUND(AVG(C.Score)::double precision, 2) AS AverageCommentScore,
    COUNT(DISTINCT V.Id) AS TotalVotesReceived
FROM
    TopActiveUsers T
    LEFT JOIN Posts P ON T.UserId = P.OwnerUserId
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN UserTopTag UT ON T.UserId = UT.UserId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON V.PostId = P.Id
WHERE
    P.Id IS NOT NULL
GROUP BY
    T.UserId, T.DisplayName, T.TotalPosts, T.TotalViews, T.TotalScore, 
    T.TotalBadges, PT.Name, UT.TagName
ORDER BY
    T.TotalScore DESC, T.TotalViews DESC
LIMIT 20;