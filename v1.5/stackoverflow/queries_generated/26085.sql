-- {"query": "26085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 663} 

WITH 
  TopUsers AS (
    SELECT 
      u.Id, 
      u.DisplayName, 
      u.Reputation, 
      COUNT(DISTINCT p.Id) AS PostCount
    FROM 
      Users u
    LEFT JOIN 
      Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
      u.Id, 
      u.DisplayName, 
      u.Reputation
    ORDER BY 
      u.Reputation DESC
    LIMIT 100
  ),
  TopTags AS (
    SELECT 
      t.TagName, 
      COUNT(DISTINCT p.Id) AS PostCount
    FROM 
      Tags t
    LEFT JOIN 
      Posts p ON t.Id = p.Id
    GROUP BY 
      t.TagName
    ORDER BY 
      PostCount DESC
    LIMIT 50
  ),
  PostHistoryStats AS (
    SELECT 
      pht.PostHistoryTypeId, 
      AVG(p.Score) AS AveragePostScore, 
      COUNT(DISTINCT p.Id) AS PostCount
    FROM 
      PostHistory pht
    LEFT JOIN 
      Posts p ON pht.PostId = p.Id
    GROUP BY 
      pht.PostHistoryTypeId
  ),
  VoteStats AS (
    SELECT 
      vt.VoteTypeId, 
      COUNT(DISTINCT v.Id) AS VoteCount, 
      AVG(p.Score) AS AveragePostScore
    FROM 
      Votes v
    LEFT JOIN 
      Posts p ON v.PostId = p.Id
    LEFT JOIN 
      VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
      vt.VoteTypeId
  )
SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  tu.PostCount AS UserPostCount, 
  tt.TagName, 
  tt.PostCount AS TagPostCount, 
  phts.AveragePostScore AS AveragePostScoreForHistoryType, 
  vs.VoteCount AS VoteCount, 
  vs.AveragePostScore AS AveragePostScoreForVoteType
FROM 
  Users u
LEFT JOIN 
  TopUsers tu ON u.Id = tu.Id
LEFT JOIN 
  Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
  PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
  Tags t ON pl.RelatedPostId = t.Id
LEFT JOIN 
  TopTags tt ON t.TagName = tt.TagName
LEFT JOIN 
  PostHistory pht ON p.Id = pht.PostId
LEFT JOIN 
  PostHistoryStats phts ON pht.PostHistoryTypeId = phts.PostHistoryTypeId
LEFT JOIN 
  Votes v ON p.Id = v.PostId
LEFT JOIN 
  VoteStats vs ON v.VoteTypeId = vs.VoteTypeId
WHERE 
  u.Reputation > 1000 
  AND p.Score > 10 
  AND phts.AveragePostScore > 5 
  AND vs.VoteCount > 50
ORDER BY 
  u.Reputation DESC, 
  tu.PostCount DESC, 
  tt.PostCount DESC, 
  phts.AveragePostScore DESC, 
  vs.VoteCount DESC;
