-- {"query": "6534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 402} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(b.Date) AS LastBadgeEarned,
    AVG(p.Score) AS AvgScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
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
         pt.Id AS PostId, 
         STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), ''><<') AS TagArray
     FROM 
         Posts pt
     WHERE 
         pt.PostTypeId = 1) t ON p.Id = t.PostId
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 year'
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    AvgScore DESC, 
    TotalUpVotes DESC
LIMIT 100;
