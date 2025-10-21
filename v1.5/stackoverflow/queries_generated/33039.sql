-- {"query": "33039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 252} 
SELECT
    p.PostTypeId,
    COUNT(*) AS total_posts,
    AVG(p.Score) AS average_score,
    MAX(p.ViewCount) AS max_views,
    STRING_AGG(p.Tags, ',') AS tag_combinations,
    COUNT(DISTINCT p.OwnerUserId) AS unique_users,
    COUNT(DISTINCT c.UserId) AS unique_commenters,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
    COUNT(DISTINCT pl.RelatedPostId) AS linked_posts,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,6,10,20,24,37,38) THEN 1 END) AS significant_edit_events
FROM
    Posts p
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
LEFT JOIN
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId
GROUP BY
    p.PostTypeId
ORDER BY
    total_posts DESC;