
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pgnt.Rank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNum,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS ScoreCategory,
        COALESCE(NULLIF(SUBSTRING(p.Body, 1, 100), ''), 'No Content') AS ShortBody,
        COALESCE(c.CommentsCount, 0) AS TotalComments
    FROM 
        Posts p
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS CommentsCount
        FROM 
            Comments
        GROUP BY 
            PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN (
        SELECT 
            Id,
            ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS Rank
        FROM 
            Posts
    ) pgnt ON p.Id = pgnt.Id
    WHERE 
        p.ViewCount > (SELECT AVG(ViewCount) FROM Posts) 
        AND (p.CreationDate > DATEADD(year, -1, CAST('2024-10-01' AS date)))
)

SELECT 
    rp.PostId,
    rp.Title,
    rp.ShortBody,
    rp.Score,
    rp.ScoreCategory,
    rp.CreationDate,
    rp.TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVotesCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVotesCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId = 10) AS CloseVotesCount,
    CASE 
        WHEN rp.RowNum = 1 THEN 'Most Recent Post'
        ELSE NULL 
    END AS PostFlag
FROM 
    RankedPosts rp
WHERE 
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId IN (1, 2)) 
ORDER BY 
    rp.Rank, rp.Score DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;
