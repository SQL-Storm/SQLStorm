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
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END AS PostStatus,
    MAX(bh.CreationDate) AS LastActivity,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN bh.Id END) AS StatusChanges,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN bh.Id END) AS EditCount,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAvgScore,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
    RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByType,
    DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) AS RecentRank,
    NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId,
           TRIM(BOTH '<>' FROM tag) AS TagName
    FROM (
        SELECT p2.Id,
               CASE 
                 WHEN p2.Tags LIKE '<%' AND p2.Tags LIKE '%>' THEN SUBSTRING(p2.Tags FROM 2 FOR (CHAR_LENGTH(p2.Tags) - 2))
                 ELSE p2.Tags
               END AS inner_tags
        FROM Posts p2
        WHERE p2.Tags IS NOT NULL AND p2.Tags <> ''
    ) p2,
    -- use a generic split implementation: split by '><' into rows.
    -- For compatibility, use a recursive CTE to split the string into rows.
    LATERAL (
      WITH RECURSIVE parts(idx, rest, piece) AS (
        SELECT 1 AS idx,
               p2.inner_tags AS rest,
               NULL::text AS piece
        UNION ALL
        SELECT idx + 1,
               CASE
                 WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                 ELSE ''
               END,
               CASE
                 WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                 ELSE rest
               END
        FROM parts
        WHERE rest <> ''
      )
      SELECT piece AS tag
      FROM parts
      WHERE piece IS NOT NULL AND piece <> ''
    ) AS split
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATE '2020-01-01'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND p.Score > 0
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, 
    p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId, p.OwnerUserId
HAVING COUNT(DISTINCT c.Id) >= 5
    AND COUNT(DISTINCT v.Id) >= 10
    AND COUNT(DISTINCT bh.Id) >= 3
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;