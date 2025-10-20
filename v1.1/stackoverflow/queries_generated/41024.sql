-- {"query": "41024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 423} 

SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.ContentLicense, 
    u.DisplayName AS OwnerDisplayName, 
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    AVG(v.BountyAmount) AS AvgBountyAmount,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT ph.PostId) AS TotalEdits,
    COUNT(DISTINCT pl.PostId) AS TotalLinks,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.ContentLicense, 
    u.DisplayName, 
    u.Reputation
ORDER BY 
    p.Score DESC, 
    p.CreationDate DESC
LIMIT 100;
