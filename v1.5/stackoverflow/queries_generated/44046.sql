-- {"query": "44046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 415}

SELECT 
    p.Id, 
    p.Title, 
    p.Body, 
    p.Tags, 
    p.CreationDate, 
    p.LastEditDate, 
    p.LastActivityDate, 
    p.Score, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.Location AS OwnerLocation,
    u.WebsiteUrl AS OwnerWebsiteUrl,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS BadgeCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS HistoryCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS FavoriteCount
FROM 
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
ORDER BY 
    p.LastActivityDate DESC
LIMIT 100;
