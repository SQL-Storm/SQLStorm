-- {"query": "59045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 465} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(ph.CreationDate) AS LastActivityDate,
    AVG(v.BountyAmount) AS AvgBountyAmount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT PostId, TagName 
    FROM Posts p2 
    JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(p2.Tags, '>')) AS tag
    ) AS split
    JOIN Tags t ON split.tag = t.TagName
    WHERE p2.PostTypeId = 1 AND p2.Tags IS NOT NULL
) t ON p.Id = t.PostId
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= '2020-01-01'
  AND p.Score > 0
  AND u.Reputation > 1000
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT c.Id) > 5
   AND COUNT(DISTINCT v.Id) > 10
   AND COUNT(DISTINCT ph.Id) > 2
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;