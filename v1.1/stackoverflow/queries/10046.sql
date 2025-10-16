WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
    FROM 
        Badges
    WHERE 
        Class = 1 AND TagBased = FALSE
    GROUP BY 
        UserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        MAX(Score) AS MaxCommentScore
    FROM 
        Comments
    GROUP BY 
        PostId
),
TopTagsPerPost AS (
    SELECT
        P.Id AS PostId,
        T.TagName,
        COUNT(*) AS TagCount
    FROM
        Posts P
    JOIN
        Tags T ON P.Id = T.ExcerptPostId
    GROUP BY
        P.Id, T.TagName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.OwnerUserId,
    RP.LastEditorUserId,
    RP.LastEditDate,
    RP.rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CASE 
        WHEN RP.OwnerUserId IN (SELECT UserId FROM BadgeCounts WHERE BadgeCount >= 3) THEN 'Elite User'
        ELSE 'Regular User'
    END AS UserStatus,
    STRING_AGG(ttp.TagName, ', ' ORDER BY ttp.TagCount DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    TopTagsPerPost ttp ON RP.Id = ttp.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
WHERE 
    PH.Comment IS NOT NULL AND PH.Text IS NOT NULL
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.OwnerUserId, RP.LastEditorUserId, RP.LastEditDate, RP.rank, BC.BadgeCount, CS.CommentCount, CS.MaxCommentScore, PH.Comment, PH.Text
ORDER BY 
    RP.rank, RP.Score DESC, RP.ViewCount DESC;