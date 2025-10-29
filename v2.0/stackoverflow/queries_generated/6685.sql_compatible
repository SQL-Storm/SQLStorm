WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
),
TagCounts AS (
    SELECT
        T.ExcerptPostId AS PostId,
        T.TagName,
        COUNT(*) AS Count
    FROM
        Tags T
    GROUP BY
        T.ExcerptPostId, T.TagName
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.DisplayName,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.Views,
    RP.UpVotes,
    RP.DownVotes,
    BC.BadgeCount,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    COALESCE(CS.MaxCommentScore, 0) AS MaxCommentScore,
    COALESCE(CS.MinCommentScore, 0) AS MinCommentScore,
    STRING_AGG(TC.TagName, ', ' ORDER BY TC.Count DESC) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    TagCounts TC ON RP.Id = TC.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.DisplayName, RP.Reputation, RP.Location, RP.AboutMe, RP.Views, RP.UpVotes, RP.DownVotes, RP.OwnerUserId, BC.BadgeCount, CS.CommentCount, CS.MaxCommentScore, CS.MinCommentScore
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;