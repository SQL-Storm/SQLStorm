-- {"query": "6913.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 587}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        P.PostTypeId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId IN (1, 2)
),
BadgeCounts AS (
    SELECT 
        U.Id AS User_Id,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS Badge_Count
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS Post_Id,
        COUNT(C.Id) AS Comment_Count,
        MAX(C.Score) AS Max_Comment_Score
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY P.Id
)
SELECT 
    RP.Id AS Post_Id,
    RP.Title AS Post_Title,
    RP.Score AS Post_Score,
    RP.ViewCount AS Post_View_Count,
    RP.rank_score AS Rank_Score,
    RP.rank_views AS Rank_Views,
    RP.CreationDate AS Post_Creation_Date,
    COALESCE(BCount.Badge_Count, 0) AS Badge_Count,
    COALESCE(CS.Comment_Count, 0) AS Comment_Count,
    CS.Max_Comment_Score AS Max_Comment_Score,
    CASE 
        WHEN RP.rank_score <= 3 THEN 'Top Scored'
        WHEN RP.rank_views <= 3 THEN 'Top Viewed'
        ELSE 'Regular'
    END AS Top_Rank,
    U.Reputation AS Owner_Reputation,
    U.DisplayName AS Owner_DisplayName,
    RP.OwnerUserId,
    RP.PostTypeId
FROM RankedPosts RP
LEFT JOIN BadgeCounts BCount ON RP.OwnerUserId = BCount.User_Id
LEFT JOIN CommentStats CS ON RP.Id = CS.Post_Id
JOIN Users U ON RP.OwnerUserId = U.Id
WHERE RP.PostTypeId = 1
  AND (RP.rank_score <= 3 OR RP.rank_views <= 3)
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.PostTypeId,
    RP.rank_score,
    RP.rank_views,
    BCount.Badge_Count,
    CS.Comment_Count,
    CS.Max_Comment_Score,
    U.Reputation,
    U.DisplayName
ORDER BY RP.PostTypeId, RP.rank_score DESC, RP.rank_views DESC;