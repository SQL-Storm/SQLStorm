-- {"query": "45007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 16058, "output_tokens": 2858} 
WITH active_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS total_posts,
        COUNT(DISTINCT c.Id) AS total_comments,
        COUNT(DISTINCT b.Id) AS total_badges
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000 AND 
        u.CreationDate > TIMESTAMP '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
), 
tag_analysis AS (
    SELECT 
        t.TagName,
        AVG(p.Score) AS avg_tag_score,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT v.Id) AS vote_count
    FROM 
        Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
)
SELECT 
    au.DisplayName, 
    au.Reputation,
    au.total_posts,
    au.total_comments,
    au.total_badges,
    MAX(ta.avg_tag_score) AS highest_tag_score,
    MAX(ta.post_count) AS max_tag_posts
FROM 
    active_users au
CROSS JOIN 
    tag_analysis ta
WHERE 
    au.total_posts > 10
ORDER BY 
    au.Reputation DESC, 
    au.total_posts DESC
LIMIT 100;