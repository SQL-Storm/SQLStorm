-- {"query": "88.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 213} 
WITH CTE_PostScore AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        SUM(v.VoteTypeId) OVER (PARTITION BY p.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
),
Subquery_TopPosts AS (
    SELECT
        PostId,
        Title,
        Score,
        TotalVotes,
        RANK() OVER (ORDER BY TotalVotes DESC) AS Rank
    FROM CTE_PostScore
    WHERE TotalVotes > 0
)
SELECT
    sp.PostId,
    sp.Title,
    sp.Score,
    sp.TotalVotes,
    sp.Rank,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    b.Name AS BadgeName,
    b.Class AS BadgeClass
FROM Subquery_TopPosts sp
LEFT JOIN Users u ON u.Id = sp.PostId
LEFT JOIN Badges b ON b.UserId = sp.PostId
WHERE sp.Rank <= 10
ORDER BY sp.Rank;