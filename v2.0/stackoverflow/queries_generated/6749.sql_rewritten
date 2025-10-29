-- {"query": "6749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 646} 
SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedAnswerId,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount END) AS TotalAnswersForQuestions,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ClosedDate END) AS LastClosedDate,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.CommunityOwnedDate END) AS LastCommunityOwnedDate,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS CloseDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.RevisionGUID END) AS CloseRevisionGUID,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment END) AS PostNotice,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate END) AS PostNoticeDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.Comment END) AS PostNoticeRemoved,
    MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.CreationDate END) AS PostNoticeRemovedDate,
    MAX(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostId,
    MAX(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostId,
    MAX(v.BountyAmount) AS MaxBountyAmount,
    AVG(v.BountyAmount) AS AvgBountyAmount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    (u.Reputation > 10000 OR u.Location IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, TotalScore DESC;