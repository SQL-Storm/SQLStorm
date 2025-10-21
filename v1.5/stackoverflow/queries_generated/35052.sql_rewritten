-- {"query": "35052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 708} 
WITH RecentBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date
    FROM
        Badges b
    WHERE
        b.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
TopTagUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore
    FROM
        Users u
        JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
        AND (
            p.Tags LIKE '%<python>%'
            OR p.Tags LIKE '%<java>%'
            OR p.Tags LIKE '%<javascript>%'
        )
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(p.Id) > 10
        AND SUM(p.Score) > 100
),
AnswerStats AS (
    SELECT
        ans.OwnerUserId AS UserId,
        COUNT(ans.Id) AS AnswersWritten,
        AVG(ans.Score) AS AvgAnswerScore,
        SUM(CASE WHEN ans.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days' THEN 1 ELSE 0 END) AS AnswersLastMonth
    FROM
        Posts ans
    WHERE
        ans.PostTypeId = 2
    GROUP BY
        ans.OwnerUserId
),
FavoriteCounts AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM
        Posts p
    WHERE
        p.FavoriteCount IS NOT NULL
    GROUP BY
        p.OwnerUserId
)
SELECT
    ttu.UserId,
    ttu.DisplayName,
    ttu.PostCount AS TagPostsLastYear,
    ttu.TotalScore AS TagPostScore,
    COALESCE(asq.AnswersWritten, 0) AS AnswersWritten,
    COALESCE(asq.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(asq.AnswersLastMonth, 0) AS AnswersWrittenLast30Days,
    COALESCE(fc.TotalFavorites, 0) AS FavoriteCount,
    ARRAY_AGG(DISTINCT rb.BadgeName) FILTER (WHERE rb.BadgeName IS NOT NULL) AS RecentBadges,
    MAX(rb.Class) FILTER (WHERE rb.Class IS NOT NULL) AS HighestBadgeClass,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.LastAccessDate
FROM
    TopTagUsers ttu
    LEFT JOIN AnswerStats asq ON asq.UserId = ttu.UserId
    LEFT JOIN FavoriteCounts fc ON fc.UserId = ttu.UserId
    LEFT JOIN RecentBadges rb ON rb.UserId = ttu.UserId
    JOIN Users u ON u.Id = ttu.UserId
GROUP BY
    ttu.UserId, ttu.DisplayName, ttu.PostCount, ttu.TotalScore,
    asq.AnswersWritten, asq.AvgAnswerScore, asq.AnswersLastMonth,
    fc.TotalFavorites, u.Reputation, u.UpVotes, u.DownVotes, u.Location, u.LastAccessDate
ORDER BY
    ttu.TotalScore DESC,
    u.Reputation DESC
LIMIT 100;