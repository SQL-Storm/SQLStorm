-- {"query": "26031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 456} 

WITH TopUsers AS (
  SELECT u.Id, u.DisplayName, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
         ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS RowNum
  FROM Users u
  LEFT JOIN Votes v ON u.Id = v.UserId
  GROUP BY u.Id, u.DisplayName
),
QuestionAnswers AS (
  SELECT p.Id, p.ParentId, p.Score, p.ViewCount, p.Title,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.ParentId) AS AnswerCount,
         LAG(p.Score, 1) OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) AS PrevAnswerScore
  FROM Posts p
),
TopTags AS (
  SELECT t.TagName, COUNT(*) AS Count,
         ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS RowNum
  FROM Tags t
  JOIN PostTags pt ON t.Id = pt.TagId
  GROUP BY t.TagName
)
SELECT tu.DisplayName, tu.UpVotesCount, tu.DownVotesCount,
       qa.Score, qa.ViewCount, qa.Title, qa.AnswerCount, qa.PrevAnswerScore,
       tt.TagName, tt.Count
FROM TopUsers tu
JOIN Posts p ON tu.Id = p.OwnerUserId
JOIN QuestionAnswers qa ON p.Id = qa.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON pl.RelatedPostId = t.Id
LEFT JOIN TopTags tt ON t.TagName = tt.TagName
WHERE tu.RowNum <= 10 AND tt.RowNum <= 10
  AND p.PostTypeId = 1
  AND p.Score > 10
  AND qa.AnswerCount > 5
  AND (pl.LinkTypeId = 1 OR pl.LinkTypeId IS NULL)
ORDER BY tu.UpVotesCount DESC, qa.Score DESC;
