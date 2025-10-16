WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS PostCount
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 100
),
TopTags AS (
  SELECT t.TagName, COUNT(DISTINCT p.Id) AS PostCount
  FROM Tags t
  JOIN Posts p ON t.Id = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  HAVING COUNT(DISTINCT p.Id) > 50
),
QuestionVotes AS (
  SELECT p.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
AnswerVotes AS (
  SELECT p.Id, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  WHERE p.PostTypeId = 2
  GROUP BY p.Id
)
SELECT 
  tu.DisplayName AS TopUser,
  tt.TagName AS TopTag,
  p.Title AS QuestionTitle,
  p.Body AS QuestionBody,
  p.Score AS QuestionScore,
  qv.UpVotes AS QuestionUpVotes,
  qv.DownVotes AS QuestionDownVotes,
  a.Body AS AnswerBody,
  a.Score AS AnswerScore,
  av.UpVotes AS AnswerUpVotes,
  av.DownVotes AS AnswerDownVotes,
  ph.Comment AS PostHistoryComment,
  tu.PostCount AS TopUserPostCount,
  tt.PostCount AS TopTagPostCount
FROM TopUsers tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN TopTags tt ON p.Tags LIKE '%' || tt.TagName || '%'
JOIN QuestionVotes qv ON p.Id = qv.Id
JOIN Posts a ON p.Id = a.ParentId
JOIN AnswerVotes av ON a.Id = av.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
WHERE p.PostTypeId = 1
  AND a.PostTypeId = 2
GROUP BY
  tu.DisplayName,
  tt.TagName,
  p.Title,
  p.Body,
  p.Score,
  qv.UpVotes,
  qv.DownVotes,
  a.Body,
  a.Score,
  av.UpVotes,
  av.DownVotes,
  ph.Comment,
  tu.Id,
  tu.PostCount,
  tt.PostCount,
  p.Id,
  a.Id,
  ph.PostId
ORDER BY TopUserPostCount DESC, TopTagPostCount DESC, p.Score DESC;