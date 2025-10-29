-- {"query": "6652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 427} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LastAccountActivity,
    b.Name AS LatestBadge,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS MostRecentPostActivity,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP AS (ORDER BY t.Count DESC) AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    (SELECT 
         Id, 
         STRING_TO_ARRAY(Tags, '<' || '''' || '>') AS TagArray
     FROM 
         Posts
     WHERE 
         PostTypeId = 1) ptags ON p.Id = ptags.Id
LEFT JOIN 
    UNNEST(ptags.TagArray) AS t(TagName) WITH ORDINALITY ON TRUE
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC, 
    TotalQuestionScore DESC;
