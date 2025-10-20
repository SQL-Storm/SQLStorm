-- {"query": "32075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 360} 

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate,
    COALESCE(p.Score, 0) AS PostScore,
    COALESCE(p.ViewCount, 0) AS PostViewCount,
    p.CreationDate AS PostCreationDate,
    COALESCE(c.Count, 0) AS CommentCount,
    ph.HistoryCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes
FROM Users u
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(*) AS Count
    FROM Comments
    GROUP BY PostId
) c ON u.Id = c.PostId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(*) AS HistoryCount
    FROM PostHistory
    GROUP BY PostId
) ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT 
        UserId, 
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
) v ON u.Id = v.UserId
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC, BadgeClass, PostScore DESC
LIMIT 100;
