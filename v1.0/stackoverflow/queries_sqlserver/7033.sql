
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostID,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        DENSE_RANK() OVER (PARTITION BY FORMAT(p.CreationDate, 'yyyy-MM') ORDER BY p.ViewCount DESC) AS MonthlyRank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE 
        p.CreationDate >= CAST(DATEADD(YEAR, -1, '2024-10-01') AS DATE)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score
),
FinalResults AS (
    SELECT 
        rp.PostID,
        rp.Title,
        rp.CreationDate,
        rp.ViewCount,
        rp.Score,
        rp.CommentCount,
        rp.AnswerCount,
        CASE 
            WHEN rp.MonthlyRank = 1 THEN 'Top Post of the Month'
            ELSE 'Regular Post'
        END AS RankCategory
    FROM 
        RankedPosts rp
)
SELECT 
    f.PostID,
    f.Title,
    f.CreationDate,
    f.ViewCount,
    f.Score,
    f.CommentCount,
    f.AnswerCount,
    f.RankCategory,
    u.DisplayName AS AuthorDisplayName,
    u.Reputation AS AuthorReputation
FROM 
    FinalResults f
JOIN 
    Users u ON f.PostID IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY 
    f.ViewCount DESC, f.Score DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
