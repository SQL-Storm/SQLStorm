-- {"query": "59087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 923} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    COUNT(ph.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        ELSE 'Other'
    END AS PostType,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCountActual,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    COALESCE(p.ViewCount, 0) AS TotalViews,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS PostStatus,
    DATEDIFF(day, p.CreationDate, COALESCE(p.LastActivityDate, p.CreationDate)) AS DaysSinceCreation,
    DATEDIFF(day, p.CreationDate, GETDATE()) AS DaysSinceCreationTotal,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.UserId END) AS UniqueVoters,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.UserId END) AS UniqueBookmarkers,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.UserId END) AS UniqueModerators,
    AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
    MAX(p.Score) OVER (PARTITION BY p.OwnerUserId) AS MaxScoreByUser,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Ranking,
    NTILE(10) OVER (ORDER BY p.Score DESC) AS ScoreDecile,
    PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT pt.PostId, t.TagName
    FROM Posts pt
    JOIN (
        SELECT Id, UNNEST(string_to_array(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t ON pt.Id = t.Id
) t ON p.Id = t.PostId
LEFT JOIN (
    SELECT b.UserId, b.Name
    FROM Badges b
    WHERE b.TagBased = 0
) b ON p.OwnerUserId = b.UserId
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= DATEADD(year, -1, GETDATE())
  AND (p.Score > 0 OR p.ViewCount > 100)
  AND p.DeletedDate IS NULL
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.PostTypeId, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.ParentId, 
    p.LastActivityDate
HAVING 
    COUNT(c.Id) BETWEEN 0 AND 100
    AND COUNT(v.Id) BETWEEN 0 AND 500
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC,
    p.CreationDate DESC
TOP 10000;