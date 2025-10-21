-- {"query": "59014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 891} 
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
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
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
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS PostStatus,
    MAX(bh.CreationDate) AS LastEditDate,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = p.OwnerUserId 
     AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = p.OwnerUserId 
     AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = p.OwnerUserId 
     AND b.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = p.OwnerUserId 
     AND p2.PostTypeId = 2) AS TotalAnswers,
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = p.OwnerUserId 
     AND p3.PostTypeId = 1) AS TotalQuestions,
    (SELECT COUNT(*) 
     FROM Votes v2 
     WHERE v2.PostId = p.Id 
     AND v2.VoteTypeId IN (2, 3)) AS UpDownVotes,
    (SELECT COUNT(*) 
     FROM Votes v3 
     WHERE v3.PostId = p.Id 
     AND v3.VoteTypeId = 5) AS FavoriteVotes,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId = p.Id 
     AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT PostId, TagName
    FROM Posts p2
    JOIN (
        SELECT Id, UNNEST(string_to_array(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL
    ) tags ON p2.Id = tags.Id
) t ON p.Id = t.PostId
WHERE p.CreationDate >= '2010-01-01'
    AND p.CreationDate < '2023-01-01'
    AND p.Id > 1000000
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.AnswerCount, 
    p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.ParentId,
    p.OwnerUserId
HAVING 
    COUNT(DISTINCT v.Id) > 0
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;