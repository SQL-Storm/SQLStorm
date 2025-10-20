-- {"query": "57099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1083} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
HighReputationUsers AS (
    SELECT
        UserId
    FROM
        UserActivity
    WHERE
        Reputation > 10000
),
RecentActiveUsers AS (
    SELECT
        UserId
    FROM
        UserActivity
    WHERE
        LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopTags AS (
    SELECT
        T.TagName,
        T.Count,
        T.ExcerptPostId,
        T.WikiPostId
    FROM
        Tags T
    WHERE
        T.Count > 1000
    ORDER BY
        T.Count DESC
    LIMIT 10
),
TopPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.Tags
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE
        P.PostTypeId = 1
    AND
        P.Score > 100
    ORDER BY
        P.Score DESC
    LIMIT 50
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalPostScore,
    UA.LastPostDate,
    UA.TotalComments,
    UA.TotalCommentScore,
    UA.TotalUpVotes,
    UA.TotalDownVotes,
    UA.TotalBadges,
    CASE WHEN HU.UserId IS NOT NULL THEN 'High Reputation User' ELSE 'Normal User' END AS ReputationStatus,
    CASE WHEN RA.UserId IS NOT NULL THEN 'Recently Active' ELSE 'Not Recently Active' END AS ActivityStatus,
    TT.TagName,
    TT.Count,
    TP.PostId,
    TP.PostTypeId,
    TP.CreationDate,
    TP.Score,
    TP.ViewCount,
    TP.Title,
    TP.OwnerDisplayName
FROM
    UserActivity UA
LEFT JOIN
    HighReputationUsers HU ON UA.UserId = HU.UserId
LEFT JOIN
    RecentActiveUsers RA ON UA.UserId = RA.UserId
LEFT JOIN
    TopTags TT ON 1=1
LEFT JOIN
    TopPosts TP ON UA.UserId = TP.OwnerUserId
ORDER BY
    UA.Reputation DESC,
    TP.Score DESC
LIMIT 100;