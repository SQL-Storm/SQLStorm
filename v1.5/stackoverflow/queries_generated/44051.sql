-- {"query": "44051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116994, "output_tokens": 41342} 

SELECT 
    p.Id, 
    p.Title, 
    p.Body,
    p.CreationDate,
    p.ViewCount,
    p.AnswerCount,
    p.Score,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS OwnerBadgeCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
ORDER BY p.CreationDate DESC
LIMIT 100;
```

This query retrieves the top 100 most recent open questions from the StackOverflow database. It includes various metrics such as the post's title, body, creation date, view count, answer count, score, owner's display name and reputation, comment count, upvotes, downvotes, owner's badge count, and the number of duplicate links. The results are ordered by the post's creation date in descending order.