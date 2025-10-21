WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        MAX(P.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY U.Reputation DESC) AS ReputationRank
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Posts A ON P.Id = A.ParentId AND A.PostTypeId = 2
    GROUP BY
        U.Id, U.Reputation, U.DisplayName
),
PostStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.Tags,
        V.VoteTypeId,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        STRING_AGG(T.TagName, ', ') AS TagList,
        LAG(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore,
        LEAD(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostScore
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Tags T ON P.Id = T.ExcerptPostId OR P.Id = T.WikiPostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.Tags, V.VoteTypeId
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges B
    GROUP BY
        B.UserId
)

SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.TotalPosts,
    UA.TotalAnswers,
    UA.QuestionScore,
    UA.AnswerScore,
    UA.LastPostDate,
    UA.ReputationRank,
    BS.TotalBadges,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    PS.PostId,
    PS.PostTypeId,
    P.Title,
    PS.CreationDate,
    PS.Score,
    PS.ViewCount,
    PS.AnswerCount,
    PS.CommentCount,
    PS.TagList,
    PS.TotalVotes,
    PS.UpVotes,
    PS.DownVotes,
    PS.PreviousPostScore,
    PS.NextPostScore,
    B.Name AS BadgeName,
    B.Class AS BadgeClass
FROM
    UserActivity UA
LEFT JOIN
    BadgeSummary BS ON UA.UserId = BS.UserId
LEFT JOIN
    PostStats PS ON PS.OwnerUserId = UA.UserId
LEFT JOIN
    Posts P ON PS.PostId = P.Id
LEFT JOIN
    Badges B ON UA.UserId = B.UserId AND B.Date = (SELECT MAX(B2.Date) FROM Badges B2 WHERE B2.UserId = UA.UserId)
WHERE
    UA.TotalPosts > 10
    AND PS.PostTypeId IN (1, 2)
    AND PS.CreationDate >= (CAST('2023-10-01 00:00:00' AS TIMESTAMP) + INTERVAL '-1 year')
ORDER BY
    UA.Reputation DESC,
    PS.Score DESC;