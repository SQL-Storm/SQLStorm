-- {"query": "6823.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 581}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) AS PostWithPositiveScore,
    COUNT(DISTINCT CASE WHEN pv.VoteTypeId = 2 THEN p.Id END) AS PostsUpvoted,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Id END) AS DuplicatePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MIN(ph.CreationDate) AS FirstPostHistory,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    AVG(p.Score) AS AvgScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS CommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes pv ON p.Id = pv.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN 
    (
      SELECT 
        ph2.PostId,
        ROW_NUMBER() OVER (PARTITION BY ph2.PostId ORDER BY ph2.CreationDate DESC) AS rn
      FROM 
        PostHistory ph2
      WHERE 
        ph2.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
    ) ph_votes ON p.Id = ph_votes.PostId AND ph_votes.rn = 1
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5
ORDER BY 
    u.Reputation DESC;