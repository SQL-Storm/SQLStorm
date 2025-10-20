WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, 
         u.Reputation, u.CreationDate AS UserCreationDate, u.UpVotes, u.DownVotes, u.Views, u.AccountId,
         ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  WHERE p.CreationDate >= DATE '2022-01-01' AND p.CreationDate < DATE '2023-01-01'
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
  AVG(EXTRACT(EPOCH FROM (UserCreationDate - CreationDate)) / 86400.0) AS AvgDaysSinceUserCreation,
  AVG(UpVotes) AS AvgUserUpVotes,
  AVG(DownVotes) AS AvgUserDownVotes,
  AVG(Views) AS AvgUserViews,
  COUNT(DISTINCT AccountId) AS UniqueAccountCount
FROM cte
WHERE rn = 1
GROUP BY rn;