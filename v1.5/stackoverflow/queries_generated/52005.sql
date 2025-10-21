-- {"query": "52005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 562} 
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
    SUM(CASE WHEN a.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AnswersAccepted,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(DISTINCT v_up.Id) AS TotalUpvotesReceived,
    COUNT(DISTINCT v_down.Id) AS TotalDownvotesReceived,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    SUM(v_bounty.BountyAmount) AS TotalBountySpent
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Posts a ON a.Id = p.AcceptedAnswerId  -- For accepted answers
LEFT JOIN 
    Comments c ON p.Id = c.PostId AND c.UserId = u.Id
LEFT JOIN 
    Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2
LEFT JOIN 
    Votes v_down ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
LEFT JOIN 
    Votes v_bounty ON v_bounty.UserId = u.Id AND v_bounty.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 10
ORDER BY 
    u.Reputation DESC, TotalBadges DESC
LIMIT 100;