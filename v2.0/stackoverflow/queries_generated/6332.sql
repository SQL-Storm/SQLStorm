-- {"query": "6332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 624} 

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
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS (ORDER BY t.TagName) AS PopularTags,
    STRING_AGG(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN p.Title ELSE NULL END, ', ') WITHIN GROUP AS (ORDER BY p.Title) AS DuplicatePosts
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
    AND p.CreationDate >= DATEADD(year, -1, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC;
