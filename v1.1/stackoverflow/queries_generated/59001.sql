-- {"query": "59001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 572} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(ph.CreationDate) AS LastEditDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END AS PostType,
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS HasAcceptedAnswer,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
        ELSE 'Open'
    END AS PostStatus
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT PostId, UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
) t ON p.Id = t.PostId
WHERE p.CreationDate >= '2022-01-01' 
    AND p.CreationDate < '2023-01-01'
    AND p.PostTypeId IN (1, 2)
    AND p.Score >= 0
    AND u.Reputation >= 100
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId, p.AcceptedAnswerId, p.ClosedDate, p.CommunityOwnedDate
HAVING COUNT(DISTINCT c.Id) >= 5
    AND COUNT(DISTINCT v.Id) >= 10
    AND COUNT(DISTINCT ph.Id) >= 2
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000 OFFSET 0;