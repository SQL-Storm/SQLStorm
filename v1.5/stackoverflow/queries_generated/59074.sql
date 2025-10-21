-- {"query": "59074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 725} 
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
    COUNT(DISTINCT bh.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
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
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    MAX(bh.CreationDate) as LastActivity,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN bh.Id END) as StatusChanges,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN bh.Id END) as EditCount,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as RankByScore,
    RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as RankByType,
    DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) as RecentRank,
    NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT PostId, UNNEST(string_to_array(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) as TagName
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != ''
) t ON p.Id = t.PostId
WHERE p.CreationDate >= '2020-01-01'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.Score > 0
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId
HAVING COUNT(DISTINCT c.Id) >= 5
    AND COUNT(DISTINCT v.Id) >= 10
    AND COUNT(DISTINCT bh.Id) >= 3
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;