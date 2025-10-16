-- {"query": "26057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 565} 
WITH TopUsers AS (
  SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY UserId
  HAVING SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopPosts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Tags, p.CreationDate, 
         SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
         SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  GROUP BY p.Id, p.Score, p.ViewCount, p.Tags, p.CreationDate
  HAVING SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) > 5
),
UserReputation AS (
  SELECT u.Id, u.Reputation, 
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
  FROM Users u
)
SELECT tu.UserId, u.Reputation, u.DisplayName, 
       tu.UpVotes, tu.DownVotes, 
       tp.Score, tp.ViewCount, tp.Tags, 
       tp.CloseVotes, tp.ReopenVotes, 
       ur.ReputationRank,
       CASE WHEN tu.UpVotes > 1000 AND tu.DownVotes < 100 THEN 'High Reputation' 
            WHEN tu.UpVotes < 100 AND tu.DownVotes > 100 THEN 'Low Reputation' 
            ELSE 'Medium Reputation' END AS ReputationStatus,
       STRING_AGG(DISTINCT t.TagName, ', ') AS UserTags
FROM TopUsers tu
JOIN Users u ON tu.UserId = u.Id
JOIN UserReputation ur ON u.Id = ur.Id
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN Posts p ON pl.RelatedPostId = p.Id
LEFT JOIN TopPosts tp ON p.Id = tp.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Tags t ON ph.PostId = t.ExcerptPostId
WHERE u.Reputation > 10000 AND tu.UpVotes > 500
GROUP BY tu.UserId, u.Reputation, u.DisplayName, 
         tu.UpVotes, tu.DownVotes, 
         tp.Score, tp.ViewCount, tp.Tags, 
         tp.CloseVotes, tp.ReopenVotes, 
         ur.ReputationRank
ORDER BY ur.ReputationRank DESC;