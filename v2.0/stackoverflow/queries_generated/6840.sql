-- {"query": "6840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 548} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(p.Score) AS HighestScoredPost,
    AVG(p.Score) AS AverageScore,
    MIN(p.LastEditDate) AS FirstEditedPost,
    MAX(p.LastEditDate) AS MostRecentlyEditedPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.UserId = u.Id
    ) AS CommentCount,
    (
        SELECT SUM(p.Score) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
    ) AS TotalOwnerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = u.Id
    ) AS AcceptedAnswerCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = ANY (STRING_TO_ARRAY(p.Tags, '<')::int[])
GROUP BY 
    u.Id
ORDER BY 
    u.Reputation DESC;
