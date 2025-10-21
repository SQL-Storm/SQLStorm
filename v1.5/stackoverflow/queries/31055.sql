WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(c.Id) DESC, COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, u.DisplayName, p.OwnerUserId
),
TopOwnerPosts AS (
    SELECT 
        rp.OwnerName,
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.CommentCount,
        rp.Score,
        rp.Rank
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 3
)
SELECT 
    OwnerName,
    COUNT(PostId) AS TotalQuestions,
    AVG(CommentCount) AS AvgComments,
    SUM(Score) AS TotalScore
FROM 
    TopOwnerPosts
GROUP BY 
    OwnerName
ORDER BY 
    TotalScore DESC
LIMIT 5;