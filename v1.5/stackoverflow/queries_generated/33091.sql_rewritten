-- {"query": "33091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 339} 
SELECT 
    p.PostTypeId,
    COUNT(*) AS total_posts,
    AVG(p.Score) AS average_score,
    AVG(p.ViewCount) AS average_views,
    MAX(p.CreationDate) AS most_recent_post_date,
    COUNT(DISTINCT u.Id) AS unique_users,
    COUNT(c.Id) AS total_comments,
    AVG(c.Score) FILTER (WHERE c.Score IS NOT NULL) AS average_comment_score,
    COUNT(DISTINCT b.Id) AS unique_badge_users,
    COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 2) AS total_upvotes,
    COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 3) AS total_downvotes,
    COUNT(DISTINCT hl.PostId) AS posts_with_history,
    COUNT(DISTINCT pl.PostId) AS linked_posts,
    COUNT(DISTINCT t.Id) AS total_tags
FROM 
    Posts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
LEFT JOIN 
    PostHistory hl ON hl.PostId = p.Id
LEFT JOIN 
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
WHERE 
    p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    p.PostTypeId;