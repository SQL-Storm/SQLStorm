-- {"query": "6193.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 590} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxPostViews,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.CreationDate) AS LatestPost,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Tags t
        WHERE t.Id IN (
            SELECT TagId 
            FROM PostTags pt 
            WHERE pt.PostId = p.Id
        )
    ) AS TaggedWith,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    WITH RECURSIVE PostHierarchy AS (
        SELECT 
            p.Id AS PostId, 
            p.ParentId AS ParentPostId, 
            1 AS Level
        FROM 
            Posts p
        WHERE 
            p.PostTypeId = 2 AND p.ParentId IS NOT NULL
        UNION ALL
        SELECT 
            ph.PostId, 
            p.Id AS ParentPostId, 
            ph.Level + 1 AS Level
        FROM 
            PostHierarchy ph
            INNER JOIN Posts p ON ph.ParentPostId = p.Id
        WHERE 
            p.PostTypeId = 2 AND p.ParentId IS NOT NULL
    )
    SELECT 
        COUNT(*) 
    FROM 
        PostHierarchy
    WHERE 
        Level > 1
) AS NestedReplyCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
GROUP BY 
    u.Id
HAVING 
    u.Reputation > 1000
ORDER BY 
    TotalPosts DESC, 
    AvgPostScore DESC;
