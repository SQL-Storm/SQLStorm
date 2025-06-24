
WITH PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.Reputation AS OwnerReputation,
        COUNT(DISTINCT c.Id) AS CommentCountDistinct,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= '2022-01-01'  
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.AnswerCount, 
        p.CommentCount, p.FavoriteCount, u.Reputation
),
TagMetrics AS (
    SELECT 
        t.TagName,
        SUM(pm.ViewCount) AS TotalViewCount,
        AVG(pm.Score) AS AverageScore,
        SUM(pm.AnswerCount) AS TotalAnswerCount
    FROM 
        PostMetrics pm
    JOIN 
        Posts p ON pm.PostId = p.Id
    CROSS APPLY (SELECT TRIM(value) AS TagName FROM STRING_SPLIT(p.Tags, ',')) AS tag
    JOIN 
        Tags t ON t.TagName = tag.TagName
    GROUP BY 
        t.TagName
)
SELECT 
    tm.TagName,
    tm.TotalViewCount,
    tm.AverageScore,
    tm.TotalAnswerCount
FROM 
    TagMetrics tm
ORDER BY 
    tm.TotalViewCount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
