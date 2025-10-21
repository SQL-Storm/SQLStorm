-- {"query": "14038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 545}
WITH cte AS (
    SELECT p.Id, p.Title, p.Body, p.CreationDate, p.Score, u.DisplayName AS OwnerDisplayName, u.Reputation AS OwnerReputation, 
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8)
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
tag_stats AS (
    SELECT p.Id, 
        STRING_AGG(t.TagName, '|') AS Tags,
        COUNT(pt.TagId) AS TagCount
    FROM Posts p
    LEFT JOIN PostTags pt ON p.Id = pt.PostId
    LEFT JOIN Tags t ON pt.TagId = t.Id
    GROUP BY p.Id
)
SELECT 
    c.Id, 
    c.Title, 
    c.Body, 
    c.CreationDate, 
    c.Score, 
    c.OwnerDisplayName, 
    c.OwnerReputation,
    ts.Tags,
    ts.TagCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = c.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Answers a WHERE a.ParentId = c.Id AND a.Id <> c.Id) AS AnswerCount,
    CASE WHEN EXISTS(SELECT 1 FROM Posts p WHERE p.Id = c.Id AND p.ClosedDate IS NOT NULL) THEN 1 ELSE 0 END AS IsClosed
FROM cte c
LEFT JOIN tag_stats ts ON c.Id = ts.Id
WHERE c.rn = 1
ORDER BY c.CreationDate DESC
LIMIT 1000;
