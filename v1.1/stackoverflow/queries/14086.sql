SELECT 
    CONCAT(COALESCE(u.DisplayName, 'DELETED'), ' ', COALESCE(u.Location, '')) AS "Author Location",
    DATE '2024-10-01' - CAST(p.CreationDate AS DATE) AS "Post Age (Days)",
    COALESCE(NULLIF(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), ''), 'NONE') AS "Post Tags",
    CASE WHEN pt.Name = 'Question' THEN 
        COALESCE(CAST(p.AnswerCount AS VARCHAR), 'NONE')
    ELSE 'N/A' END AS "Answer Count",
    COALESCE(CAST(p.CommentCount AS VARCHAR), 'NONE') AS "Comment Count",
    COALESCE(CAST(p.FavoriteCount AS VARCHAR), 'NONE') AS "Favorite Count",
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
         WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
         ELSE 'Open' END AS "Post Status",
    COALESCE(CAST((CAST(p.LastActivityDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE') AS "Days to Last Activity",
    COALESCE(CAST((CAST(p.LastEditDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE') AS "Days to Last Edit",
    COALESCE(CAST((CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE') AS "Days to Closure",
    COALESCE(CAST((CAST(p.CommunityOwnedDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE') AS "Days to Community Ownership",
    COALESCE(CAST(p.ViewCount AS VARCHAR), 'NONE') AS "View Count",
    COALESCE(CAST(p.Score AS VARCHAR), 'NONE') AS "Post Score",
    COALESCE(CAST(u.Reputation AS VARCHAR), 'NONE') AS "Author Reputation",
    COALESCE(CAST(u.UpVotes AS VARCHAR), 'NONE') AS "Author Upvotes",
    COALESCE(CAST(u.DownVotes AS VARCHAR), 'NONE') AS "Author Downvotes",
    COALESCE(CAST(u.Views AS VARCHAR), 'NONE') AS "Author Views",
    CASE WHEN p.PostTypeId = 2 THEN 
        (SELECT COALESCE(CAST(p2.Score AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.ParentId)
    ELSE 'N/A' END AS "Parent Post Score",
    CASE WHEN p.PostTypeId = 1 THEN 
        (SELECT COALESCE(CAST(p2.AnswerCount AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.Id)
    ELSE 'N/A' END AS "Question Answer Count",
    CASE WHEN p.PostTypeId = 2 THEN 
        (SELECT COALESCE(CAST(p2.Score AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.AcceptedAnswerId)
    ELSE 'N/A' END AS "Accepted Answer Score",
    p.CreationDate,
    p.Id,
    p.OwnerUserId,
    pt.Name
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
GROUP BY
    CONCAT(COALESCE(u.DisplayName, 'DELETED'), ' ', COALESCE(u.Location, '')),
    DATE '2024-10-01' - CAST(p.CreationDate AS DATE),
    COALESCE(NULLIF(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), ''), 'NONE'),
    CASE WHEN pt.Name = 'Question' THEN 
        COALESCE(CAST(p.AnswerCount AS VARCHAR), 'NONE')
    ELSE 'N/A' END,
    COALESCE(CAST(p.CommentCount AS VARCHAR), 'NONE'),
    COALESCE(CAST(p.FavoriteCount AS VARCHAR), 'NONE'),
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
         WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
         ELSE 'Open' END,
    COALESCE(CAST((CAST(p.LastActivityDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE'),
    COALESCE(CAST((CAST(p.LastEditDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE'),
    COALESCE(CAST((CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE'),
    COALESCE(CAST((CAST(p.CommunityOwnedDate AS DATE) - CAST(p.CreationDate AS DATE)) AS VARCHAR), 'NONE'),
    COALESCE(CAST(p.ViewCount AS VARCHAR), 'NONE'),
    COALESCE(CAST(p.Score AS VARCHAR), 'NONE'),
    COALESCE(CAST(u.Reputation AS VARCHAR), 'NONE'),
    COALESCE(CAST(u.UpVotes AS VARCHAR), 'NONE'),
    COALESCE(CAST(u.DownVotes AS VARCHAR), 'NONE'),
    COALESCE(CAST(u.Views AS VARCHAR), 'NONE'),
    CASE WHEN p.PostTypeId = 2 THEN 
        (SELECT COALESCE(CAST(p2.Score AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.ParentId)
    ELSE 'N/A' END,
    CASE WHEN p.PostTypeId = 1 THEN 
        (SELECT COALESCE(CAST(p2.AnswerCount AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.Id)
    ELSE 'N/A' END,
    CASE WHEN p.PostTypeId = 2 THEN 
        (SELECT COALESCE(CAST(p2.Score AS VARCHAR), 'NONE') 
         FROM Posts p2 
         WHERE p2.Id = p.AcceptedAnswerId)
    ELSE 'N/A' END,
    p.CreationDate,
    p.Id,
    p.OwnerUserId,
    pt.Name
ORDER BY p.CreationDate DESC
LIMIT 100;