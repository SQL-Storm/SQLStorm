-- {"query": "6556.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 490}
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
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Score END) AS HighestScoredQuestion,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS HighestScoredAnswer,
    -- emulate STRING_AGG DISTINCT ordered by t.Count DESC using subquery aggregation
    (SELECT STRING_AGG(tagname, ', ')
     FROM (
         SELECT t2.TagName AS tagname
         FROM Tags t2
         JOIN Posts p2 ON p2.Id = t2.ExcerptPostId
         WHERE p2.OwnerUserId = u.Id
         GROUP BY t2.TagName, COALESCE(t2.Count, 0)
         ORDER BY COALESCE(MAX(t2.Count), 0) DESC, t2.TagName
     ) sub
    ) AS MostUsedTags
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
LEFT JOIN 
    (SELECT 
         ph2.PostId,
         ph2.RevisionGUID,
         ph2.CreationDate,
         ph2.UserId,
         ph2.UserDisplayName,
         ph2.Text,
         ph2.ContentLicense
     FROM 
         PostHistory ph2
     WHERE 
         ph2.PostHistoryTypeId = 1) FirstEdit ON p.Id = FirstEdit.PostId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (SELECT AccountId FROM Users WHERE AccountId > 0)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;