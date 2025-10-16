-- {"query": "1025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 435} 

WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS Rnk
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id
), PostDetails AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.CommentCount,
        COALESCE(b.Name, 'No Badge') AS UserBadge,
        u.Reputation
    FROM 
        RecentPosts rp
    LEFT JOIN 
        Users u ON rp.OwnerUserId = u.Id
    LEFT JOIN 
        Badges b ON u.Id = b.UserId AND b.Class = 1 -- Gold badges
    WHERE 
        rp.Rnk = 1
), CommentStats AS (
    SELECT 
        PostId,
        AVG(Score) AS AvgCommentScore,
        COUNT(*) AS TotalComments
    FROM 
        Comments
    GROUP BY 
        PostId
)

SELECT 
    pd.PostId,
    pd.Title,
    pd.CreationDate,
    pd.Score,
    pd.ViewCount,
    pd.CommentCount,
    pd.UserBadge,
    pd.Reputation,
    cs.AvgCommentScore,
    cs.TotalComments,
    CASE 
        WHEN pd.Score IS NULL THEN 'Unscored'
        WHEN pd.Score > 50 THEN 'High Score'
        ELSE 'Low Score'
    END AS ScoreCategory
FROM 
    PostDetails pd
LEFT JOIN 
    CommentStats cs ON pd.PostId = cs.PostId
WHERE 
    (pd.Reputation > 100 OR pd.UserBadge != 'No Badge')
ORDER BY 
    pd.CreationDate DESC
LIMIT 100;
