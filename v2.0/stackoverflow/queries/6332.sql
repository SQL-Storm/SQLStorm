SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.LastEditDate ELSE NULL END) AS LastQuestionEdit,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.LastEditDate ELSE NULL END) AS LastAnswerEdit,
    MAX(v.CreationDate) AS LastVote,
    MAX(CASE WHEN bh.Name = 'Gold' THEN bh.Date ELSE NULL END) AS LastGoldBadge,
    MAX(CASE WHEN bh.Name = 'Silver' THEN bh.Date ELSE NULL END) AS LastSilverBadge,
    MAX(CASE WHEN bh.Name = 'Bronze' THEN bh.Date ELSE NULL END) AS LastBronzeBadge,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
    -- build PopularTags without DISTINCT+ORDER BY inside aggregate for portability:
    -- use ARRAY_AGG/DISTINCT where supported or aggregate then deduplicate in subquery; here we use STRING_AGG on a subquery
    (
      SELECT STRING_AGG(tag, ', ' ORDER BY tag)
      FROM (
        SELECT DISTINCT t2.TagName AS tag
        FROM Posts p2
        JOIN Tags t2 ON p2.Id = t2.ExcerptPostId
        WHERE p2.OwnerUserId = u.Id
          AND p2.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      ) s
    ) AS PopularTags,
    (
      SELECT STRING_AGG(title, ', ' ORDER BY title)
      FROM (
        SELECT DISTINCT p3.Title AS title
        FROM Posts p3
        JOIN PostLinks pl3 ON p3.Id = pl3.PostId
        WHERE p3.OwnerUserId = u.Id
          AND pl3.LinkTypeId = 3
          AND p3.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      ) s2
    ) AS DuplicatePosts
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Badges bh ON u.Id = bh.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistoryTypes pht ON ph.Id = ph.PostHistoryTypeId
WHERE 
    u.Reputation > 1000
    AND (p.CreationDate IS NULL OR p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC;