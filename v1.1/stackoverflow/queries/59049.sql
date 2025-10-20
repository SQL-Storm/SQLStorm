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
    STRING_AGG(DISTINCT tags_agg.TagName, ', ') AS Tags,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS HasAcceptedAnswer,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS Status,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    MAX(ph.CreationDate) AS LastActivity,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgScorePerUser,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RankByScore
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT p2.Id AS PostId, STRING_AGG(t.TagName, ', ') AS TagName
    FROM Posts p2
    JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
    WHERE p2.Tags IS NOT NULL
    GROUP BY p2.Id
) AS tags_agg ON p.Id = tags_agg.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE p.CreationDate >= DATE '2020-01-01'
    AND p.PostTypeId IN (1, 2)
    AND p.Score > 0
    AND u.Reputation > 100
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.AcceptedAnswerId, 
    p.ClosedDate, p.CommunityOwnedDate, tags_agg.TagName, b.Id, u.Id
HAVING COUNT(DISTINCT c.Id) >= 5
   AND COUNT(DISTINCT v.Id) >= 10
   AND COUNT(DISTINCT ph.Id) >= 3
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;