-- {"query": "26025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 488} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    SUM(p.Score) AS TotalScore
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    COUNT(DISTINCT p.Id) > 10 AND SUM(p.Score) > 100
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS PostCount
  FROM 
    Tags t
  JOIN 
    Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(DISTINCT p.Id) > 5
),
UserTagScore AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    t.TagName, 
    SUM(p.Score) AS TagScore
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Tags t ON t.Id = ANY(string_to_array(p.Tags, '><'))
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
  GROUP BY 
    u.Id, u.DisplayName, t.TagName
)
SELECT 
  tu.DisplayName, 
  tt.TagName, 
  uts.TagScore, 
  ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY uts.TagScore DESC) AS RowNum
FROM 
  TopUsers tu
JOIN 
  UserTagScore uts ON tu.Id = uts.Id
JOIN 
  TopTags tt ON uts.TagName = tt.TagName
WHERE 
  tu.PostCount > 20 AND tt.PostCount > 10
  AND uts.TagScore > (SELECT AVG(TagScore) FROM UserTagScore)
  AND tu.Id NOT IN (SELECT UserId FROM Votes WHERE VoteTypeId = 3)
  AND tu.Id IN (SELECT UserId FROM Badges WHERE Class = 1)
ORDER BY 
  tu.PostCount DESC, uts.TagScore DESC;
