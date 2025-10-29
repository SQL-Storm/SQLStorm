-- {"query": "5974.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 514}
SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    -- use standard aggregation for tags: string_agg of distinct tag names (nulls filtered)
    -- many databases don't have ARRAY_AGG with FILTER; use STRING_AGG where available. If array desired, some dialects support JSON_AGG.
    STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
    MAX(CASE WHEN bh.PostHistoryTypeId = 10 THEN bh.CreationDate ELSE NULL END) AS LastClosedDate,
    MAX(CASE WHEN bh.PostHistoryTypeId IN (16, 36) THEN bh.CreationDate ELSE NULL END) AS CommunityOwnedDateEstimate,
    CASE
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN a.CreationDate
        ELSE NULL
    END AS LastAcceptedAnswerDate,
    COUNT(DISTINCT b.Id) AS BadgeCount
FROM
    Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
-- match tags by id or by textual representation of p.Tags; normalize both sides to text to avoid type mismatch
LEFT JOIN Tags t ON CAST(t.Id AS TEXT) = CAST(p.Tags AS TEXT)
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory bh ON bh.PostId = p.Id
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
GROUP BY
    p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId,
    u.DisplayName, u.Reputation, p.FavoriteCount, a.CreationDate
HAVING
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0
ORDER BY
    p.CreationDate DESC, p.Score DESC
LIMIT 100;