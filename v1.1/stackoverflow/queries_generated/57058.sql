-- {"query": "57058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1278} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
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
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalPostScore,
        TotalComments,
        TotalVotes,
        TotalBadges
    FROM
        UserActivity
    WHERE
        Reputation > 10000
    ORDER BY
        Reputation DESC
    LIMIT 100
),
RecentPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.AnswerCount,
        P.CommentCount,
        U.DisplayName AS OwnerDisplayName,
        T.TagName
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Tags T ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate > NOW() - INTERVAL '30 days'
    ORDER BY
        P.CreationDate DESC
),
TopTags AS (
    SELECT
        T.TagName,
        COUNT(RP.PostId) AS TagUsageCount
    FROM
        RecentPosts RP
    JOIN
        Tags T ON RP.TagName = T.TagName
    GROUP BY
        T.TagName
    ORDER BY
        TagUsageCount DESC
    LIMIT 20
), HighActivityPosts AS (
    SELECT
        RP.PostId,
        RP.PostTypeId,
        RP.PostCreationDate,
        RP.Score,
        RP.ViewCount,
        RP.OwnerUserId,
        RP.OwnerDisplayName,
        RP.AnswerCount,
        RP.CommentCount,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT C.Id) AS TotalComments
    FROM
        RecentPosts RP
    LEFT JOIN
        Votes V ON RP.PostId = V.PostId
    LEFT JOIN
        Comments C ON RP.PostId = C.PostId
    GROUP BY
        RP.PostId, RP.PostTypeId, RP.PostCreationDate, RP.Score, RP.ViewCount, RP.OwnerUserId, RP.OwnerDisplayName, RP.AnswerCount, RP.CommentCount
    HAVING
        (TotalVotes > 10 OR TotalComments > 5)
    ORDER BY
        TotalVotes DESC, TotalComments DESC
    LIMIT 50
) SELECT
HU.UserId,
HU.Reputation,
HU.UserCreationDate,
HU.LastAccessDate,
HU.TotalPosts,
HU.TotalQuestions,
HU.TotalAnswers,
HU.TotalPostScore,
HU.TotalComments,
HU.TotalVotes,
HU.TotalBadges,
HA.PostId,
HA.PostTypeId,
HA.PostCreationDate,
HA.Score,
HA.ViewCount,
HA.OwnerUserId,
HA.OwnerDisplayName,
HA.AnswerCount,
HA.CommentCount,
HA.TotalVotes AS PostTotalVotes,
HA.TotalComments AS PostTotalComments,
TT.TagName,
TT.TagUsageCount
FROM
HighReputationUsers HU
JOIN
HighActivityPosts HA ON HU.UserId = HA.OwnerUserId
LEFT JOIN
TopTags TT ON HA.TagName = TT.TagName
ORDER BY
HU.Reputation DESC,
HA.PostTotalVotes DESC,
HA.PostTotalComments DESC;
