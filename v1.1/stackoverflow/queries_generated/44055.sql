-- {"query": "44055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 482}

WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.Reputation, u.CreationDate AS UserCreationDate, u.UpVotes, u.DownVotes, u.Views, u.AccountId,
         ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  WHERE p.CreationDate >= '2022-01-01' AND p.CreationDate < '2023-01-01'
)
SELECT 
  COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
  COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount,
  COUNT(CASE WHEN PostTypeId = 3 THEN 1 END) AS WikiCount,
  COUNT(CASE WHEN PostTypeId = 4 THEN 1 END) AS TagWikiExcerptCount,
  COUNT(CASE WHEN PostTypeId = 5 THEN 1 END) AS TagWikiCount,
  AVG(Score) AS AvgScore,
  AVG(ViewCount) AS AvgViewCount,
  AVG(Reputation) AS AvgUserReputation,
  AVG(UserCreationDate - CreationDate) AS AvgDaysSinceUserCreation,
  AVG(UpVotes) AS AvgUserUpVotes,
  AVG(DownVotes) AS AvgUserDownVotes,
  AVG(Views) AS AvgUserViews,
  COUNT(DISTINCT AccountId) AS UniqueAccountCount
FROM cte
WHERE rn = 1;
