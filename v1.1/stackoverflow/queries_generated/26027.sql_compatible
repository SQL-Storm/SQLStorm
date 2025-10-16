WITH RECURSIVE QuestionAnswerCTE AS (
  SELECT p1.Id AS QuestionId, p2.Id AS AnswerId, p2.Score AS AnswerScore, p1.AcceptedAnswerId
  FROM Posts p1
  JOIN Posts p2 ON p1.Id = p2.ParentId
  WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 2
),
TopAnswerCTE AS (
  SELECT QuestionId, AnswerId, AnswerScore, 
    ROW_NUMBER() OVER (PARTITION BY QuestionId ORDER BY AnswerScore DESC) AS AnswerRank
  FROM QuestionAnswerCTE
),
AcceptedAnswerCTE AS (
  SELECT p1.Id AS QuestionId, p2.Id AS AnswerId
  FROM Posts p1
  JOIN Posts p2 ON p1.AcceptedAnswerId = p2.Id
  WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 2
),
UserReputationCTE AS (
  SELECT u.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS ReputationChange
  FROM Users u
  JOIN Votes v ON u.Id = v.UserId
  GROUP BY u.Id
)
SELECT 
  p1.Id AS QuestionId, 
  p1.Title AS QuestionTitle, 
  p1.Score AS QuestionScore, 
  p1.ViewCount AS QuestionViewCount, 
  p1.AnswerCount AS QuestionAnswerCount, 
  p2.Id AS AcceptedAnswerId, 
  p2.Score AS AcceptedAnswerScore, 
  u1.DisplayName AS QuestionOwnerDisplayName, 
  u1.Reputation AS QuestionOwnerReputation, 
  u2.DisplayName AS AcceptedAnswerOwnerDisplayName, 
  u2.Reputation AS AcceptedAnswerOwnerReputation,
  t1.TagName AS QuestionTag1, 
  t2.TagName AS QuestionTag2,
  v.VoteTypeId AS VoteType,
  ph.Comment AS PostHistoryComment,
  ph.UserId AS PostHistoryUserId,
  CASE 
    WHEN t3.TagName IS NOT NULL THEN 'ModeratorOnly'
    WHEN t4.TagName IS NOT NULL THEN 'Required'
    ELSE 'Normal'
  END AS QuestionTagType
FROM Posts p1
JOIN QuestionAnswerCTE q ON p1.Id = q.QuestionId
JOIN TopAnswerCTE t ON q.QuestionId = t.QuestionId AND q.AnswerId = t.AnswerId
JOIN AcceptedAnswerCTE a ON p1.Id = a.QuestionId
JOIN Posts p2 ON a.AnswerId = p2.Id
JOIN Users u1 ON p1.OwnerUserId = u1.Id
JOIN Users u2 ON p2.OwnerUserId = u2.Id
JOIN Tags t1 ON p1.Id = t1.ExcerptPostId
JOIN Tags t2 ON p1.Id = t2.WikiPostId
LEFT JOIN Tags t3 ON t3.Id = t1.Id AND t3.IsModeratorOnly = TRUE
LEFT JOIN Tags t4 ON t4.Id = t2.Id AND t4.IsRequired = TRUE
JOIN Votes v ON p2.Id = v.PostId
JOIN PostHistory ph ON p2.Id = ph.PostId
WHERE 
  p1.PostTypeId = 1 AND 
  p2.PostTypeId = 2 AND 
  v.VoteTypeId = 2 AND 
  ph.PostHistoryTypeId = 10 AND 
  t1.TagName IS NOT NULL AND 
  t2.TagName IS NOT NULL AND 
  u1.Reputation > 1000 AND 
  u2.Reputation > 1000 AND 
  p1.Score > 10 AND 
  p2.Score > 10 AND 
  p1.ViewCount > 1000 AND 
  p1.AnswerCount > 10
ORDER BY 
  p1.Score DESC, 
  p2.Score DESC, 
  u1.Reputation DESC, 
  u2.Reputation DESC
LIMIT 100;