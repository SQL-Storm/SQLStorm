-- {"query": "48054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 359} 
SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate AS PostLastActivityDate,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score > 5
    ) AS HighScoreCommentCount,
    (
        SELECT COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) AS EditorCount,
    (
        SELECT AVG(CAST(SUBSTRING(Text, '[0-9]+', 1) AS INTEGER))
        FROM PostHistory
        WHERE PostId = p.Id AND PostHistoryTypeId = 2 AND Text LIKE '%<pre>%'
    ) AS AvgCodeBlockLength
FROM
    Posts p
JOIN
    Users u ON p.OwnerUserId = u.Id
WHERE
    p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= DATE('now', '-1 year')
    AND p.Score > 10
    AND p.ViewCount > 1000
ORDER BY
    p.Score DESC, p.ViewCount DESC
LIMIT 100;