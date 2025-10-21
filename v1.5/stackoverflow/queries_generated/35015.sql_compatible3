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
        U.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR
        AND P.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR
    GROUP BY
        U.Id, U.DisplayName
    HAVING
        COUNT(DISTINCT P.Id) > 50
)
SELECT
    T.UserId,
    T.DisplayName,
    T.TotalPosts,
    T.TotalViews,
    T.TotalScore,
    T.TotalBadges,
    PT.Name AS MostCommonPostType,
    COALESCE(MostUsedTag.TagName, 'N/A') AS MostUsedTag,
    ROUND(AVG(C.Score), 2) AS AverageCommentScore,
    COUNT(DISTINCT V.Id) AS TotalVotesReceived
FROM
    TopActiveUsers T
    LEFT JOIN Posts P ON T.UserId = P.OwnerUserId
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN (
        SELECT
            P.Id AS PostId,
            REGEXP_REPLACE(REGEXP_REPLACE(P.Tags, '^<', ''), '>$', '') AS TagsPlain
        FROM Posts P
    ) AS TagSplit ON P.Id = TagSplit.PostId
    LEFT JOIN (
        SELECT
            OwnerUserId,
            TagName
        FROM (
            SELECT
                OwnerUserId,
                TagName,
                COUNT(*) AS TagCount
            FROM (
                SELECT
                    OwnerUserId,
                    TRIM(TagName) AS TagName
                FROM Posts
                CROSS JOIN LATERAL (
                    SELECT TRIM(value) AS TagName
                    FROM (
                        SELECT REGEXP_SUBSTR(Tags, '[^><]+', 1, n) AS value
                        FROM (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) AS seq
                    ) AS t
                ) AS t2
                WHERE OwnerUserId IS NOT NULL
                  AND PostTypeId = 1
            ) AS inner1
            GROUP BY OwnerUserId, TagName
        ) AS s
        ORDER BY s.TagCount DESC
        LIMIT 1
    ) AS MostUsedTag ON TRUE
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON V.PostId = P.Id
WHERE
    P.Id IS NOT NULL
GROUP BY
    T.UserId, T.DisplayName, T.TotalPosts, T.TotalViews, T.TotalScore, 
    T.TotalBadges, PT.Name, MostUsedTag.TagName
ORDER BY
    T.TotalScore DESC, T.TotalViews DESC
LIMIT 20;