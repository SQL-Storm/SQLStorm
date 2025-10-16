-- {"query": "2048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 492} 

WITH TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM
        Users U
        LEFT JOIN Posts P ON U.Id = P.OwnerUserId
        LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE
        U.Reputation > 5000
    GROUP BY
        U.Id, U.DisplayName
),
ActivePosts AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.Score,
        COALESCE(SUM(V.VoteTypeId = 2), 0) AS UpVotes,
        COUNT(DISTINCT C.Id) AS CommentCount
    FROM
        Posts P
        LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId = 2
        LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY
        P.Id, P.Title, P.Score
),
RecentBadgeActivity AS (
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        RANK() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS BadgeRank
    FROM
        Badges B
    WHERE
        B.Date >= NOW() - INTERVAL '30 days'
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.TotalQuestionScore,
    TU.TotalAnswerScore,
    TU.BadgeCount,
    AP.PostId,
    AP.Title,
    AP.Score AS PostScore,
    AP.UpVotes AS PostUpVotes,
    AP.CommentCount AS PostComments,
    RB.BadgeName
FROM
    TopUsers TU
    LEFT JOIN ActivePosts AP ON TU.UserId = AP.OwnerUserId
    LEFT JOIN RecentBadgeActivity RB ON TU.UserId = RB.UserId AND RB.BadgeRank = 1
WHERE
    AP.PostScore IS NOT NULL
ORDER BY
    TU.TotalQuestionScore + TU.TotalAnswerScore DESC,
    AP.PostScore DESC;
