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
    ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS Tags,
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
LEFT JOIN Tags t ON t.Id = p.Tags -- using tags as a derived relation if normalized differently; keep NULL-safe
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory bh ON bh.PostId = p.Id
WHERE
    p.PostTypeId IN (1, 2) -- questions and answers
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
    p.Id, p.Title, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId,
    u.DisplayName, u.Reputation, p.FavoriteCount
HAVING
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0
ORDER BY
    p.CreationDate DESC, p.Score DESC
LIMIT 100;