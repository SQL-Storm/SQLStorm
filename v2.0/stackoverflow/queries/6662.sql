-- {"query": "6662.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 459}
SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.Score) DESC) AS TopScorePost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    -- join Tags by matching tag name extracted from p.Tags string.
    -- this uses a derived table to split p.Tags into rows in a dialect-neutral way where possible.
    (SELECT p2.Id AS PostId, t2.TagName
     FROM Posts p2
     CROSS JOIN LATERAL (
         SELECT TRIM(tag) AS TagName
         FROM (SELECT regexp_split_to_table(COALESCE(p2.Tags, ''), '[<>]') AS tag) s
         WHERE TRIM(tag) <> ''
     ) t2
    ) t ON p.Id = t.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId IN (1, 2) 
    AND u.Id NOT IN (SELECT Id FROM Users WHERE AccountId IS NOT NULL)
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10 
ORDER BY 
    AvgScore DESC, 
    TotalPosts DESC
LIMIT 100;