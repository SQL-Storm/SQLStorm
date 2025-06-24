
WITH UserVoteStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName
),
PopularPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.ViewCount,
        RANK() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS RankScore
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.CreationDate >= NOW() - INTERVAL 30 DAY
),
PostHistoryDetails AS (
    SELECT 
        PH.PostId,
        PH.UserId,
        PH.CreationDate,
        PHT.Name AS HistoryType,
        PH.Comment,
        PH.CreationDate AS EditDate
    FROM PostHistory PH
    INNER JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.CreationDate >= NOW() - INTERVAL 90 DAY
)
SELECT 
    UVS.DisplayName,
    COALESCE(PP.Title, 'N/A') AS PopularPostTitle,
    PP.Score AS PopularPostScore,
    PP.RankScore,
    PHD.HistoryType,
    PHD.EditDate
FROM UserVoteStats UVS
LEFT JOIN PopularPosts PP ON UVS.UserId = (SELECT U.Id FROM Users U ORDER BY RAND() LIMIT 1)
LEFT JOIN PostHistoryDetails PHD ON PP.PostId = PHD.PostId
WHERE UVS.Upvotes > UVS.Downvotes
  AND (PHD.Comment IS NOT NULL OR PHD.HistoryType IS NOT NULL)
ORDER BY UVS.DisplayName, PP.RankScore DESC;
