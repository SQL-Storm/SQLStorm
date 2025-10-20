WITH RECURSIVE RecursiveCTE AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.Reputation AS OwnerReputation,
        U.DisplayName AS OwnerDisplayName,
        LAG(P.Id) OVER (ORDER BY P.CreationDate) AS PrevPostId,
        LEAD(P.Id) OVER (ORDER BY P.CreationDate) AS NextPostId
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE
        P.PostTypeId = 1
    UNION ALL
    SELECT
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.Reputation,
        U.DisplayName,
        R.PrevPostId,
        R.NextPostId
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    JOIN
        RecursiveCTE R ON P.Id = R.NextPostId
    WHERE
        P.PostTypeId = 1
)
SELECT
    R.PostId,
    R.PostTypeId,
    R.CreationDate,
    R.Score,
    R.ViewCount,
    R.OwnerUserId,
    R.LastActivityDate,
    R.Title,
    R.Tags,
    R.AnswerCount,
    R.CommentCount,
    R.FavoriteCount,
    R.OwnerReputation,
    R.OwnerDisplayName,
    R.PrevPostId,
    R.NextPostId,
    V.VoteTypeId,
    V.CreationDate AS VoteDate,
    V.UserId AS VoterId,
    V.BountyAmount,
    C.Id AS CommentId,
    C.Score AS CommentScore,
    C.Text AS CommentText,
    C.CreationDate AS CommentDate,
    C.UserId AS CommentUserId,
    C.UserDisplayName AS CommentUserDisplayName,
    PH.PostHistoryTypeId,
    PH.RevisionGUID,
    PH.CreationDate AS PostHistoryDate,
    PH.UserId AS PostHistoryUserId,
    PH.UserDisplayName AS PostHistoryUserDisplayName,
    PH.Comment AS PostHistoryComment,
    PH.Text AS PostHistoryText,
    (SELECT STRING_AGG(T2.TagName, ', ') FROM Tags T2 WHERE R.PostId = T2.ExcerptPostId) AS RelatedTags
FROM
    RecursiveCTE R
LEFT JOIN
    Votes V ON R.PostId = V.PostId
LEFT JOIN
    Comments C ON R.PostId = C.PostId
LEFT JOIN
    PostHistory PH ON R.PostId = PH.PostId
LEFT JOIN
    Tags T ON R.PostId = T.WikiPostId
GROUP BY
    R.PostId,
    R.PostTypeId,
    R.CreationDate,
    R.Score,
    R.ViewCount,
    R.OwnerUserId,
    R.LastActivityDate,
    R.Title,
    R.Tags,
    R.AnswerCount,
    R.CommentCount,
    R.FavoriteCount,
    R.OwnerReputation,
    R.OwnerDisplayName,
    R.PrevPostId,
    R.NextPostId,
    V.VoteTypeId,
    V.CreationDate,
    V.UserId,
    V.BountyAmount,
    C.Id,
    C.Score,
    C.Text,
    C.CreationDate,
    C.UserId,
    C.UserDisplayName,
    PH.PostHistoryTypeId,
    PH.RevisionGUID,
    PH.CreationDate,
    PH.UserId,
    PH.UserDisplayName,
    PH.Comment,
    PH.Text,
    T.WikiPostId;