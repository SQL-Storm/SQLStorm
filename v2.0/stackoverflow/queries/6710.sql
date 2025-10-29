-- {"query": "6710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 638} 
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastPostClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastPostReopened,
    MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastPostDeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate END) AS LastPostUndeleted,
    MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.CreationDate END) AS LastPostLocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.CreationDate END) AS LastPostUnlocked,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate END) AS LastPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.CreationDate END) AS LastPostNoticeRemoved,
    COALESCE(SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END), 0) AS TotalPositiveScorePosts,
    COALESCE(SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END), 0) AS TotalNegativeScorePosts,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE Class = 1 AND TagBased = FALSE
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100 
    AND SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 50
ORDER BY 
    TotalPosts DESC, 
    TotalQuestions DESC;