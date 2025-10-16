-- {"query": "2065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 467} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.LastAccessDate > (CURRENT_DATE - INTERVAL '1 month')
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(p.Id) > 5
),
HighReputationPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.Score > 100
),
PostAndComments AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id, p.Title
    HAVING 
        COALESCE(SUM(c.Score), 0) > 10
),
TopHighReputationPosts AS (
    SELECT 
        PostId, 
        Title, 
        Score
    FROM 
        HighReputationPosts
    WHERE 
        PostRank = 1
),
FinalResult AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        thp.PostId,
        thp.Title AS HighRepPostTitle,
        thp.Score AS HighRepPostScore,
        pac.TotalCommentScore
    FROM 
        ActiveUsers u
    LEFT JOIN 
        TopHighReputationPosts thp ON u.UserId = thp.PostId
    LEFT JOIN 
        PostAndComments pac ON thp.PostId = pac.PostId
)
SELECT 
    UserId, 
    DisplayName, 
    HighRepPostTitle, 
    HighRepPostScore, 
    TotalCommentScore
FROM 
    FinalResult
ORDER BY 
    HighRepPostScore DESC NULLS LAST, 
    TotalCommentScore DESC, 
    DisplayName ASC;
