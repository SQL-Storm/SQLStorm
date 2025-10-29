WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
        JOIN Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
        JOIN Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id, U.DisplayName
),
CloseReasons AS (
    SELECT 
        P.Id AS PostId,
        CASE 
            WHEN PH.PostHistoryTypeId = 10 THEN (SELECT Name FROM CloseReasonTypes CRT WHERE CRT.Id = CAST(PH.Comment AS INTEGER))
            ELSE NULL
        END AS CloseReason
    FROM 
        Posts P
        LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId = 10
),
MergedPosts AS (
    SELECT 
        PM.Id AS MergedPostId,
        PM.Title AS MergedPostTitle,
        PM.Score AS MergedPostScore,
        PM.ViewCount AS MergedPostViewCount,
        PM.CreationDate AS MergedPostCreationDate,
        PM.LastActivityDate AS MergedPostLastActivityDate,
        PM.OwnerUserId AS MergedPostOwnerUserId,
        PM.OwnerDisplayName AS MergedPostOwnerDisplayName,
        PM.LastEditorUserId AS MergedPostLastEditorUserId,
        PM.LastEditorDisplayName AS MergedPostLastEditorDisplayName,
        PM.LastEditDate AS MergedPostLastEditDate,
        PM.ClosedDate AS MergedPostClosedDate,
        PM.CommunityOwnedDate AS MergedPostCommunityOwnedDate,
        PM.ContentLicense AS MergedPostContentLicense,
        PM.AnswerCount AS MergedPostAnswerCount,
        PM.CommentCount AS MergedPostCommentCount,
        PM.FavoriteCount AS MergedPostFavoriteCount,
        P.Id AS ParentPostId,
        P.Title AS ParentPostTitle,
        P.Score AS ParentPostScore,
        P.ViewCount AS ParentPostViewCount,
        P.CreationDate AS ParentPostCreationDate,
        P.LastActivityDate AS ParentPostLastActivityDate,
        P.OwnerUserId AS ParentPostOwnerUserId,
        P.OwnerDisplayName AS ParentPostOwnerDisplayName,
        P.LastEditorUserId AS ParentPostLastEditorUserId,
        P.LastEditorDisplayName AS ParentPostLastEditorDisplayName,
        P.LastEditDate AS ParentPostLastEditDate,
        P.ClosedDate AS ParentPostClosedDate,
        P.CommunityOwnedDate AS ParentPostCommunityOwnedDate,
        P.ContentLicense AS ParentPostContentLicense,
        P.AnswerCount AS ParentPostAnswerCount,
        P.CommentCount AS ParentPostCommentCount,
        P.FavoriteCount AS ParentPostFavoriteCount
    FROM 
        Posts PM
        LEFT JOIN Posts P ON PM.ParentId = P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title AS PostTitle,
    RP.Score AS PostScore,
    RP.ViewCount AS PostViewCount,
    RP.CreationDate AS PostCreationDate,
    RP.Rank,
    RP.DisplayName AS OwnerDisplayName,
    RP.Reputation AS OwnerReputation,
    RP.LastAccessDate AS OwnerLastAccessDate,
    B.BadgeCount AS OwnerBadgeCount,
    CR.CloseReason AS CloseReason,
    MP.MergedPostId AS MergedPostId,
    MP.MergedPostTitle AS MergedPostTitle,
    MP.MergedPostScore AS MergedPostScore,
    MP.MergedPostViewCount AS MergedPostViewCount,
    MP.MergedPostCreationDate AS MergedPostCreationDate,
    MP.MergedPostLastActivityDate AS MergedPostLastActivityDate,
    MP.MergedPostOwnerUserId AS MergedPostOwnerUserId,
    MP.MergedPostOwnerDisplayName AS MergedPostOwnerDisplayName,
    MP.MergedPostLastEditorUserId AS MergedPostLastEditorUserId,
    MP.MergedPostLastEditorDisplayName AS MergedPostLastEditorDisplayName,
    MP.MergedPostLastEditDate AS MergedPostLastEditDate,
    MP.MergedPostClosedDate AS MergedPostClosedDate,
    MP.MergedPostCommunityOwnedDate AS MergedPostCommunityOwnedDate,
    MP.MergedPostContentLicense AS MergedPostContentLicense,
    MP.MergedPostAnswerCount AS MergedPostAnswerCount,
    MP.MergedPostCommentCount AS MergedPostCommentCount,
    MP.MergedPostFavoriteCount AS MergedPostFavoriteCount,
    MP.ParentPostId AS ParentPostId,
    MP.ParentPostTitle AS ParentPostTitle,
    MP.ParentPostScore AS ParentPostScore,
    MP.ParentPostViewCount AS ParentPostViewCount,
    MP.ParentPostCreationDate AS ParentPostCreationDate,
    MP.ParentPostLastActivityDate AS ParentPostLastActivityDate,
    MP.ParentPostOwnerUserId AS ParentPostOwnerUserId,
    MP.ParentPostOwnerDisplayName AS ParentPostOwnerDisplayName,
    MP.ParentPostLastEditorUserId AS ParentPostLastEditorUserId,
    MP.ParentPostLastEditorDisplayName AS ParentPostLastEditorDisplayName,
    MP.ParentPostLastEditDate AS ParentPostLastEditDate,
    MP.ParentPostClosedDate AS ParentPostClosedDate,
    MP.ParentPostCommunityOwnedDate AS ParentPostCommunityOwnedDate,
    MP.ParentPostContentLicense AS ParentPostContentLicense,
    MP.ParentPostAnswerCount AS ParentPostAnswerCount,
    MP.ParentPostCommentCount AS ParentPostCommentCount,
    MP.ParentPostFavoriteCount AS ParentPostFavoriteCount
FROM 
    RankedPosts RP
    FULL OUTER JOIN BadgeCounts B ON RP.OwnerUserId = B.UserId
    LEFT JOIN CloseReasons CR ON RP.Id = CR.PostId
    LEFT JOIN MergedPosts MP ON RP.Id = COALESCE(MP.MergedPostId, MP.ParentPostId)
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;