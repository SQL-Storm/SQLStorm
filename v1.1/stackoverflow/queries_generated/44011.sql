-- {"query": "44011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 389}

SELECT 
    p.Id AS PostId, 
    p.Title, 
    p.Body, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    u.Views, 
    u.UpVotes, 
    u.DownVotes, 
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id) AS BadgeCount, 
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id) AS PostHistoryCount, 
    (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCount, 
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = p.Id OR RelatedPostId = p.Id) AS PostLinkCount, 
    (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id) AS VoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
ORDER BY 
    p.Score DESC
LIMIT 
    100;
```

This query retrieves the top 100 posts based on their score, and includes various performance-related metrics such as view count, answer count, comment count, favorite count, user reputation, badge count, post history count, comment count, post link count, and vote count. This data can be useful for analyzing the performance and engagement of the top posts on the site.
