-- {"query": "33020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 345} 
SELECT
    p.PostTypeId,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS total_posts,
    AVG(p.Score) AS average_score,
    AVG(p.ViewCount) AS average_views,
    COUNT(DISTINCT c.Id) AS comment_count,
    COUNT(DISTINCT v.Id) AS vote_count,
    COUNT(DISTINCT b.Id) AS badge_count,
    (SELECT COUNT(*) FROM Posts q WHERE q.PostTypeId = 1 AND q.CreationDate >= NOW() - INTERVAL '365 days') AS questions_last_year,
    (SELECT COUNT(*) FROM Comments com WHERE com.CreationDate >= NOW() - INTERVAL '365 days') AS comments_last_year,
    (SELECT COUNT(*) FROM Votes vo WHERE vo.CreationDate >= NOW() - INTERVAL '365 days') AS votes_last_year,
    STRING_AGG(DISTINCT t.TagName, ', ') AS popular_tags
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    PostTags pt ON pt.PostId = p.Id -- Assuming a PostTags mapping table if exists
LEFT JOIN
    Tags t ON t.Id = pt.TagId -- Replace with actual join if PostTags exists
LEFT JOIN
    Badges b ON b.UserId = u.Id
WHERE
    p.CreationDate >= '2020-01-01'
GROUP BY
    p.PostTypeId,
    u.Reputation
ORDER BY
    total_posts DESC
LIMIT 50;