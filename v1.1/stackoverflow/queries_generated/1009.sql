-- {"query": "1009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 415} 

WITH UserScores AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(year, -1, GETDATE())
),
TopPosts AS (
    SELECT 
        pd.PostId,
        pd.Title,
        pd.CreationDate,
        pd.ViewCount,
        pd.Score,
        pd.Tags,
        us.DisplayName,
        us.TotalScore
    FROM PostDetails pd
    JOIN UserScores us ON pd.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = us.UserId)
    WHERE pd.rn = 1
)
SELECT 
    t.DisplayName,
    t.TotalScore,
    STRING_AGG(t.Title, ', ') AS RecentPosts,
    SUM(t.ViewCount) AS TotalViews,
    AVG(t.Score) AS AverageScore
FROM TopPosts t
GROUP BY t.DisplayName, t.TotalScore
ORDER BY TotalScore DESC;
