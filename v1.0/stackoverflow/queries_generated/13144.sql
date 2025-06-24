-- Performance Benchmarking Query
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(a.Id) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2 -- answers related to their parent question
    WHERE 
        p.PostTypeId = 1 -- only questions
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    DENSE_RANK() OVER (ORDER BY rp.Score DESC) AS ScoreRank
FROM 
    RankedPosts rp
WHERE 
    rp.Rank <= 100 -- limiting to the latest 100 posts for benchmarking
ORDER BY 
    rp.CreationDate DESC;
