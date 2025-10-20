-- {"query": "59015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 809} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    MAX(ph.CreationDate) as LastEdited,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END as PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AnswerCount > 0 THEN 'Has Answers'
        ELSE 'Open'
    END as PostStatus,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.DeletionDate IS NULL) as AnswerCount,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId IN (2,3)) as UpDownVoteCount,
    (SELECT AVG(v3.BountyAmount) FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 8) as AvgBounty
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ', ') as TagName
    FROM (
        SELECT DISTINCT p.Id as PostId, TRIM(SUBSTRING(t.TagName, 2, LENGTH(t.TagName) - 2)) as TagName
        FROM Posts p
        JOIN UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS t.TagName
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) sub
    GROUP BY PostId
) t ON p.Id = t.PostId
WHERE p.CreationDate >= '2010-01-01' 
    AND p.CreationDate < '2023-01-01'
    AND p.PostTypeId IN (1,2)
    AND p.DeletionDate IS NULL
    AND (p.Score > 0 OR p.ViewCount > 100)
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.AnswerCount
HAVING COUNT(DISTINCT v.Id) > 0
    AND COUNT(DISTINCT c.Id) >= 0
    AND COUNT(DISTINCT ph.Id) >= 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;