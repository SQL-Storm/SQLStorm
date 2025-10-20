WITH tag_counts AS (
  SELECT Id, PostTypeId,
    array_length(regexp_split_to_array(Tags, '><'), 1) AS tag_count
  FROM Posts
  WHERE PostTypeId = 1
),
dup_pairs AS (
  SELECT d.PostId, d.RelatedPostId,
    EXTRACT(EPOCH FROM (p.CreationDate - d.CreationDate)) AS diff_sec
  FROM PostLinks d
  JOIN Posts p ON p.Id = d.RelatedPostId
  WHERE d.LinkTypeId = 3
)
SELECT u.Id AS UserId,
       u.DisplayName,
       u.Reputation,
       COUNT(DISTINCT q.Id) AS QuestionCount,
       COALESCE(SUM(q.Score), 0) AS TotalQuestionScore,
       AVG(COALESCE(tc.tag_count, 0) * 1.0) AS AvgTagsPerQuestion,
       COUNT(DISTINCT a.Id) AS AnswerCount,
       COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
       COUNT(v.Id) AS VoteCount,
       COUNT(DISTINCT b.Id) AS GoldBadgeCount,
       MAX(v.CreationDate) AS LastVoteDate,
       COUNT(DISTINCT dp.PostId) AS DuplicateQuestionCount,
       AVG(dp.diff_sec) AS AvgDupTimeSeconds
FROM Users u
LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
LEFT JOIN Votes v ON v.PostId = q.Id OR v.PostId = a.Id
LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
LEFT JOIN tag_counts tc ON tc.Id = q.Id
LEFT JOIN dup_pairs dp ON dp.PostId = q.Id
WHERE q.AcceptedAnswerId IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY u.Reputation DESC
LIMIT 50;