-- {"query": "54038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1403} 

WITH tag_stats AS (
    SELECT
        t.TagName,
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answer_posts,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS question_posts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS closed_issues,
        COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 3) AS duplicates,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) AS rnk
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '\\>\\<') AS split(tag)
    JOIN Tags t ON t.TagName = split.tag
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN PostLinks l ON l.PostId = p.Id AND l.LinkTypeId = 3
    WHERE p.CreationDate > '2020-01-01'
    GROUP BY t.TagName, p.OwnerUserId
)
SELECT
    ts.TagName,
    u.DisplayName,
    ts.OwnerUserId,
    ts.answer_posts,
    ts.question_posts,
    ts.upvotes,
    ts.downvotes,
    ts.favorites,
    ts.closed_issues,
    ts.duplicates
FROM tag_stats ts
JOIN Users u ON u.Id = ts.OwnerUserId
WHERE ts.rnk <= 5
ORDER BY ts.TagName, ts.rnk;
