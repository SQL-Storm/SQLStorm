SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id ELSE NULL END) AS TotalPositiveScorePosts,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.AnswerCount, 0) ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.FavoriteCount, 0) ELSE 0 END) AS TotalFavoritesToQuestions,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalClosedPosts,
    SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS TotalCommunityOwnedPosts,
    SUM(CASE WHEN bh.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalPostsClosed,
    SUM(CASE WHEN bh.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalPostsReopened,
    /* Portable aggregated tags: attempt standard SQL string aggregation */
    (
      SELECT STRING_AGG(distinct_tag, ',') 
      FROM (
        SELECT DISTINCT TRIM(tag) AS distinct_tag
        FROM Posts p2,
             LATERAL (
               -- split tags like '<tag1><tag2>' into rows: replace angle brackets with a delimiter then split
               SELECT regexp_split_to_table(
                 regexp_replace(COALESCE(p2.Tags, ''), '^<|>$', '') , '><'
               ) AS tag
             ) t
        WHERE p2.OwnerUserId = u.Id
      ) sub
    ) AS Top10Tags,
    b.Name AS TopBadge,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeIsTagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory bh ON p.Id = bh.PostId
WHERE 
    (b.Date IS NULL OR b.Date = (SELECT MAX(Date) FROM Badges WHERE UserId = u.Id))
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.Name,
    b.Class,
    b.TagBased
HAVING 
    AVG(p.Score) > 0
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;