
WITH RecursivePostHistory AS (
    SELECT 
        P.Id AS PostId,
        PH.CreationDate,
        PH.UserId,
        PH.Comment,
        PH.Text,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY P.Id ORDER BY PH.CreationDate DESC) AS rn
    FROM 
        Posts P
    JOIN 
        PostHistory PH ON P.Id = PH.PostId
),
RecentBadges AS (
    SELECT 
        U.Id AS UserId,
        COUNT(*) AS BadgeCount,
        GROUP_CONCAT(B.Name SEPARATOR ', ') AS BadgeNames
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Date > DATE_SUB('2024-10-01', INTERVAL 1 YEAR)
    GROUP BY 
        U.Id
),
FilteredPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        COALESCE((
            SELECT COUNT(*) 
            FROM Votes V 
            WHERE V.PostId = P.Id AND V.VoteTypeId = 3
        ), 0) AS DownVotes,
        COALESCE((
            SELECT COUNT(*) 
            FROM Votes V 
            WHERE V.PostId = P.Id AND V.VoteTypeId = 2
        ), 0) AS UpVotes,
        (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P.Id) AS CommentCount,
        (SELECT MAX(CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS LastCommentDate
    FROM 
        Posts P
    WHERE 
        P.CreationDate >= DATE_SUB('2024-10-01', INTERVAL 6 MONTH) 
        AND P.Score IS NOT NULL
)
SELECT 
    FP.Title,
    FP.CreationDate,
    FP.ViewCount,
    FP.UpVotes,
    FP.DownVotes,
    FP.CommentCount,
    RB.BadgeCount,
    RB.BadgeNames,
    RPH.UserId AS LastEditorId,
    RPH.Comment AS LastEditComment
FROM 
    FilteredPosts FP
LEFT JOIN 
    RecentBadges RB ON RB.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = FP.Id LIMIT 1)
LEFT JOIN 
    RecursivePostHistory RPH ON RPH.PostId = FP.Id AND RPH.rn = 1
WHERE 
    (FP.LastCommentDate IS NULL OR FP.LastCommentDate < DATE_SUB('2024-10-01 12:34:56', INTERVAL 30 DAY))
    AND (FP.UpVotes - FP.DownVotes) > 5
ORDER BY 
    FP.ViewCount DESC
LIMIT 50;
