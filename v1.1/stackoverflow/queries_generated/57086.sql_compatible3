WITH TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        MAX(P.CreationDate) AS LastPostDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    WHERE
        U.Reputation > 1000
    GROUP BY
        U.Id, U.DisplayName, U.Reputation
    ORDER BY
        TotalScore DESC
    LIMIT 100
),
ActiveTags AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        COUNT(P.Id) AS TaggedPostCount,
        SUM(P.Score) AS TaggedPostScore,
        SUM(C.Score) AS TaggedCommentScore,
        MAX(P.CreationDate) AS LastTaggedPostDate
    FROM
        Tags T
    LEFT JOIN
        Posts P ON POSITION(CONCAT('<', T.TagName, '>') IN COALESCE(P.Tags, '')) > 0
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE
        P.PostTypeId = 1
        AND U.Reputation > 25
    GROUP BY
        T.Id, T.TagName
    ORDER BY
        TaggedPostCount DESC
    LIMIT 50
),
RecentPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount AS OriginalCommentCount,
        P.FavoriteCount,
        COALESCE(C.Count, 0) AS CommentCount,
        COALESCE(V.Count, 0) AS VoteCount
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS Count FROM Comments GROUP BY PostId) C ON P.Id = C.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS Count FROM Votes GROUP BY PostId) V ON P.Id = V.PostId
    WHERE
        P.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
        AND P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        C.Count,
        V.Count
    ORDER BY
        P.CreationDate DESC
    LIMIT 1000
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.PostCount,
    TU.TotalScore,
    TU.TotalUpVotes,
    TU.TotalDownVotes,
    TU.LastPostDate,
    AT.TagId,
    AT.TagName,
    AT.TaggedPostCount,
    AT.TaggedPostScore,
    AT.TaggedCommentScore,
    AT.LastTaggedPostDate,
    RP.PostId,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Title,
    RP.Tags,
    RP.AnswerCount,
    RP.OriginalCommentCount,
    RP.FavoriteCount,
    COALESCE(RP.CommentCount, 0) AS ResolvedCommentCount,
    COALESCE(RP.VoteCount, 0) AS ResolvedVoteCount
FROM
    TopUsers TU
CROSS JOIN
    ActiveTags AT
LEFT JOIN
    RecentPosts RP ON TU.UserId = RP.OwnerUserId
    AND RP.Tags IS NOT NULL
    AND POSITION(CONCAT('<', AT.TagName, '>') IN RP.Tags) > 0
GROUP BY
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.PostCount,
    TU.TotalScore,
    TU.TotalUpVotes,
    TU.TotalDownVotes,
    TU.LastPostDate,
    AT.TagId,
    AT.TagName,
    AT.TaggedPostCount,
    AT.TaggedPostScore,
    AT.TaggedCommentScore,
    AT.LastTaggedPostDate,
    RP.PostId,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Title,
    RP.Tags,
    RP.AnswerCount,
    RP.OriginalCommentCount,
    RP.FavoriteCount,
    RP.CommentCount,
    RP.VoteCount
ORDER BY
    TU.TotalScore DESC,
    AT.TaggedPostCount DESC,
    RP.CreationDate DESC
LIMIT 100;