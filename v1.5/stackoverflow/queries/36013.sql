-- {"query": "36013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 232} 
SELECT
  U.Id AS UserId,
  U.DisplayName,
  U.Reputation,
  COUNT(DISTINCT P.Id) AS PostsCount,
  AVG(P.Score) AS AvgPostScore,
  SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  STRING_AGG(DISTINCT DT.Name, ',') AS TopDomainsAwarded
FROM
  Users U
  LEFT JOIN Posts P ON P.OwnerUserId = U.Id
  LEFT JOIN Votes V ON V.PostId = P.Id
  LEFT JOIN (
    SELECT Id, Name
    FROM PostHistoryTypes
  ) DT ON DT.Id = 20  -- placeholder to reference a type; kept for join stability in benchmarking
WHERE
  U.AccountId IS NOT NULL
GROUP BY
  U.Id, U.DisplayName, U.Reputation
ORDER BY
  PostsCount DESC, U.Reputation DESC
LIMIT 100;