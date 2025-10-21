-- {"query": "59093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 699} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    MAX(ph.CreationDate) as LastActivity,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END as PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    COUNT(DISTINCT b.Id) as BadgeCount,
    AVG(p.Score) over (partition by u.Id) as UserAvgScore,
    RANK() over (order by p.Score desc) as ScoreRank,
    DENSE_RANK() over (partition by p.PostTypeId order by p.Score desc) as TypeScoreRank
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT PostId, TagName 
    FROM Posts p2 
    JOIN unnest(string_to_array(p2.Tags, '><')) AS tag ON tag != ''
    JOIN Tags t ON t.TagName = replace(replace(tag, '<', ''), '>', '')
) t ON p.Id = t.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.CreationDate >= '2020-01-01 00:00:00'
    AND (p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL)
    AND u.Reputation > 1000
    AND (p.Score >= 0 OR p.Score IS NULL)
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.PostTypeId, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.AcceptedAnswerId
HAVING 
    COUNT(DISTINCT c.Id) >= 0 
    AND COUNT(DISTINCT v.Id) >= 0
ORDER BY 
    p.Score DESC,
    p.CreationDate DESC
LIMIT 10000;