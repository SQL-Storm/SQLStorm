-- {"query": "6168.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 564} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ClosedDate ELSE NULL END) AS LastClosedQuestion,
    MAX(CASE WHEN p.PostTypeId = 3 THEN p.CommunityOwnedDate ELSE NULL END) AS LastCommunityOwnedWiki,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    MAX(ph.RevisionGUID) AS LastRevisionGUID,
    MAX(ph.CreationDate) AS LastPostHistoryEvent,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastClosedReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment ELSE NULL END) AS LastPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.Comment ELSE NULL END) AS LastPostNoticeRemoved
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND u.LastAccessDate > DATEADD(month, -6, CURRENT_TIMESTAMP)
    AND (u.Location IS NOT NULL OR u.DisplayName IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT v.PostId) > 100
ORDER BY 
    TotalPosts DESC, AvgPostScore DESC;
