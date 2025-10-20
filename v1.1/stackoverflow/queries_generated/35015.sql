-- {"query": "35015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 545} 
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
        U.CreationDate > NOW() - INTERVAL '2 years'
        AND P.CreationDate > NOW() - INTERVAL '2 years'
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
    ROUND(AVG(C.Score),2) AS AverageCommentScore,
    COUNT(DISTINCT V.Id) AS TotalVotesReceived
FROM
    TopActiveUsers T
    LEFT JOIN Posts P ON T.UserId = P.OwnerUserId
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN LATERAL (
        SELECT 
            unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName
    ) TagSplit ON P.PostTypeId = 1 -- Only questions have tags
    LEFT JOIN LATERAL (
        SELECT 
            TagName
        FROM (
            SELECT
                unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName,
                COUNT(*) AS TagCount
            FROM Posts
            WHERE OwnerUserId = T.UserId AND PostTypeId = 1
            GROUP BY TagName
            ORDER BY TagCount DESC
            LIMIT 1
        ) t
    ) MostUsedTag ON TRUE
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