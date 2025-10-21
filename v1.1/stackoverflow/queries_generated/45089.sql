-- {"query": "45089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 412}
WITH TagRankedUsers AS (
  SELECT 
    t.TagName,
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS AnswerCount,
    DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS TagRank
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 2
  GROUP BY t.TagName, u.Id, u.DisplayName
), TopTagExperts AS (
  SELECT 
    TagName,
    UserId,
    DisplayName,
    AnswerCount
  FROM TagRankedUsers
  WHERE TagRank <= 5
)
SELECT 
  t.TagName,
  COUNT(DISTINCT tte.UserId) AS ExpertCount,
  AVG(tte.AnswerCount) AS AverageAnswersPerExpert,
  SUM(v.VoteCount) AS TotalVotes
FROM TopTagExperts tte
JOIN Tags t ON tte.TagName = t.TagName
JOIN (
  SELECT PostId, COUNT(*) AS VoteCount
  FROM Votes
  WHERE VoteTypeId IN (2, 8)
  GROUP BY PostId
) v ON v.PostId IN (
  SELECT Id 
  FROM Posts 
  WHERE OwnerUserId = tte.UserId 
    AND Tags LIKE '%' || tte.TagName || '%'
)
GROUP BY t.TagName
ORDER BY TotalVotes DESC
LIMIT 100;
