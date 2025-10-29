-- {"query": "6160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 527}
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.LastActivityDate) AS LastActivity,
    b.Name AS BadgeEarned,
    t.TagName AS MostFrequentTag,
    v.VoteTypeId AS MostVotedType
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT 
         UserId, 
         TagName, 
         ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY Count DESC) AS Rank
      FROM 
         (
           SELECT 
              p.OwnerUserId AS UserId, 
              t.TagName, 
              COUNT(*) AS Count
           FROM 
              Posts p
           JOIN 
              Tags t ON POSITION(',' || CAST(t.Id AS VARCHAR) || ',' IN ',' || COALESCE(p.Tags,'') || ',') > 0
           GROUP BY 
              p.OwnerUserId, t.TagName
         ) AS tag_counts
    ) AS t ON u.Id = t.UserId AND t.Rank = 1
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (
      SELECT 
         PostId, 
         VoteTypeId, 
         ROW_NUMBER() OVER(PARTITION BY PostId ORDER BY COALESCE(BountyAmount,0) DESC) AS Rank
      FROM 
         Votes
      WHERE 
         VoteTypeId IN (8, 9)
    ) AS v ON p.Id = v.PostId AND v.Rank = 1
WHERE 
    u.Reputation > 10000
    AND (u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') OR u.LastAccessDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, t.TagName, v.VoteTypeId
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC
LIMIT 100;