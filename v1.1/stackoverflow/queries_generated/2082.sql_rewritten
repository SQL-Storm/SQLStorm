-- {"query": "2082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 433} 
WITH RecentPosts AS (
    SELECT 
        p.Id AS PostID,
        p.CreationDate,
        p.Score,
        u.DisplayName,
        COALESCE(b.Name, 'No Badge') AS BadgeName
    FROM 
        Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE 
        p.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days'
),
HighScorePosts AS (
    SELECT 
        PostID, 
        DisplayName,
        BadgeName,
        Score,
        DENSE_RANK() OVER (ORDER BY Score DESC) AS Rank
    FROM 
        RecentPosts
    WHERE 
        Score > 10
),
ActiveUsers AS (
    SELECT 
        u.Id AS UserID,
        u.DisplayName,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE 
        u.LastAccessDate > cast('2024-10-01' as date) - INTERVAL '90 days'
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) > 5
)
SELECT 
    hp.PostID,
    hp.DisplayName AS PostOwner,
    hp.BadgeName,
    hp.Score,
    hp.Rank,
    au.DisplayName AS ActiveUser,
    CASE 
        WHEN au.UpVotesCount IS NULL THEN 'No recent activity'
        ELSE CONCAT('Up votes: ', au.UpVotesCount, ', Comments: ', au.CommentCount)
    END AS Activity
FROM 
    HighScorePosts hp
LEFT JOIN ActiveUsers au ON hp.DisplayName = au.DisplayName
WHERE 
    hp.Rank <= 5
ORDER BY 
    hp.Score DESC, au.UpVotesCount DESC;