-- {"query": "33078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 273} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS total_posts,
    COUNT(DISTINCT p.OwnerUserId) AS distinct_authors,
    AVG(p.Score) AS average_score,
    SUM(p.ViewCount) AS total_views,
    COUNT(c.Id) AS total_comments,
    AVG(c.Score) AS average_comment_score,
    COUNT(DISTINCT c.UserId) AS unique_commenters,
    COUNT(v.Id) AS total_votes,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
    COUNT(DISTINCT v.UserId) AS distinct_voters,
    EXTRACT(YEAR FROM p.CreationDate) AS year,
    EXTRACT(MONTH FROM p.CreationDate) AS month
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Comments c ON p.Id = c.PostId
LEFT JOIN
    Votes v ON p.Id = v.PostId
GROUP BY
    p.PostTypeId,
    pt.Name,
    year,
    month
ORDER BY
    year DESC,
    month DESC,
    p.PostTypeId;