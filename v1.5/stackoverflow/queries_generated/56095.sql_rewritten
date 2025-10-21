-- {"query": "56095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 368} 
WITH UserActivity AS (
  SELECT 
    u.Id, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    SUM(p.Score) AS TotalScore, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id
),
TopUsers AS (
  SELECT 
    Id, 
    PostCount, 
    TotalScore, 
    UpVotes, 
    DownVotes,
    ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS Rank
  FROM 
    UserActivity
)
SELECT 
  tu.Id, 
  u.DisplayName, 
  tu.PostCount, 
  tu.TotalScore, 
  tu.UpVotes, 
  tu.DownVotes, 
  tu.Rank,
  pth.Name AS PostHistoryTypeName,
  COUNT(DISTINCT ph.PostId) AS PostHistoryCount
FROM 
  TopUsers tu
JOIN 
  Users u ON tu.Id = u.Id
JOIN 
  PostHistory ph ON u.Id = ph.UserId
JOIN 
  PostHistoryTypes pth ON ph.PostHistoryTypeId = pth.Id
WHERE 
  tu.Rank <= 10
GROUP BY 
  tu.Id, 
  u.DisplayName, 
  tu.PostCount, 
  tu.TotalScore, 
  tu.UpVotes, 
  tu.DownVotes, 
  tu.Rank,
  pth.Name
ORDER BY 
  tu.Rank;