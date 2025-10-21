WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN Votes v ON p.Id = v.PostId
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
     AND SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) < 500
),
QuestionPosts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.CreationDate
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE pt.Name = 'Question'
),
AnswerPosts AS (
  SELECT p.Id, p.Score, p.ParentId, p.CreationDate
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE pt.Name = 'Answer'
),
TopQuestionPosts AS (
  SELECT qp.Id, qp.Title, qp.Score, qp.ViewCount, qp.Tags, qp.CreationDate,
         ROW_NUMBER() OVER (ORDER BY qp.Score DESC) AS RowNum
  FROM QuestionPosts qp
)
SELECT tu.DisplayName, tu.UpVotes, tu.DownVotes,
       tqp.Title, tqp.Score, tqp.ViewCount, tqp.Tags, tqp.CreationDate,
       ap.Score AS AnswerScore, ap.CreationDate AS AnswerDate
FROM TopUsers tu
JOIN TopQuestionPosts tqp ON tu.Id = tqp.Id
JOIN AnswerPosts ap ON tqp.Id = ap.ParentId
WHERE tqp.RowNum <= 10 AND ap.Score > 10
ORDER BY tqp.Score DESC;