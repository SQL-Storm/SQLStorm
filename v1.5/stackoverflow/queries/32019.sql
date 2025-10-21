-- {"query": "32019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 394} 
WITH UserActivityRanking AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(p.Id) AS TotalPosts,
        COUNT(c.Id) AS TotalComments,
        COUNT(v.Id) AS TotalVotes,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(p.Id) DESC) AS Rank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
HighScoringPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        u.DisplayName
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
    ORDER BY 
        p.Score DESC
    LIMIT 10
)
SELECT 
    uar.UserId, 
    uar.DisplayName, 
    uar.TotalScore, 
    uar.TotalPosts, 
    uar.TotalComments, 
    uar.TotalVotes, 
    hsp.PostId, 
    hsp.Title AS HighScoringPostTitle, 
    hsp.Score AS HighScoringPostScore,
    hsp.DisplayName AS HighScoringPostOwner
FROM 
    UserActivityRanking uar
LEFT JOIN 
    HighScoringPosts hsp ON uar.UserId = hsp.PostId
WHERE 
    uar.Rank <= 10
ORDER BY 
    uar.Rank;