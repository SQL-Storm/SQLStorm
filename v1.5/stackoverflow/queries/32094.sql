-- {"query": "32094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 333} 
WITH TopUsersByReputation AS (
  SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    U.Reputation, 
    RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
  FROM Users U
),
TopPostsPerUser AS (
  SELECT 
    P.OwnerUserId, 
    P.Id AS PostId, 
    P.Score, 
    ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS ScoreRank
  FROM Posts P
  WHERE P.PostTypeId IN (1, 2)
)
SELECT 
  TUR.UserId, 
  TUR.DisplayName, 
  TUR.Reputation, 
  TP.PostId, 
  TP.Score, 
  COUNT(C.Id) AS CommentCount, 
  SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
  SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  SUM(V.BountyAmount) AS TotalBountyAwarded
FROM TopUsersByReputation TUR
JOIN TopPostsPerUser TP ON TUR.UserId = TP.OwnerUserId AND TP.ScoreRank = 1
LEFT JOIN Comments C ON TP.PostId = C.PostId
LEFT JOIN Votes V ON TP.PostId = V.PostId
WHERE TUR.ReputationRank <= 100
GROUP BY TUR.UserId, TUR.DisplayName, TUR.Reputation, TP.PostId, TP.Score
ORDER BY TUR.Reputation DESC, TP.Score DESC;