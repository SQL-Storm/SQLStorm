WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(p.Id) AS PostCount
  FROM Tags t
  LEFT JOIN Posts p ON p.Tags IS NOT NULL AND p.Tags LIKE '%' || t.TagName || '%'
  GROUP BY t.TagName
  HAVING COUNT(p.Id) > 100
),
QuestionAnswers AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
AnswerPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ParentId, 
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS BountyAmount
  FROM Posts p
  WHERE p.PostTypeId = 2
)
SELECT 
  tu.DisplayName, 
  tt.TagName, 
  qa.Title, 
  qa.Score, 
  qa.ViewCount, 
  qa.AnswerCount, 
  qa.CommentCount, 
  ap.Score AS AnswerScore, 
  ap.BountyAmount,
  tu.UpVotes,
  tu.Id AS TopUserId,
  qa.Id AS QuestionId,
  ap.ParentId
FROM TopUsers tu
JOIN QuestionAnswers qa ON tu.Id = qa.Id
JOIN TopTags tt ON EXISTS (
  SELECT 1 FROM Posts p WHERE p.Id = qa.Id AND p.Tags IS NOT NULL AND p.Tags LIKE '%' || tt.TagName || '%'
)
JOIN AnswerPosts ap ON qa.Id = ap.ParentId
WHERE COALESCE(ap.BountyAmount, 0) > 100
GROUP BY
  tu.DisplayName,
  tt.TagName,
  qa.Title,
  qa.Score,
  qa.ViewCount,
  qa.AnswerCount,
  qa.CommentCount,
  ap.Score,
  ap.BountyAmount,
  tu.UpVotes,
  tu.Id,
  qa.Id,
  ap.ParentId
ORDER BY tu.UpVotes DESC, qa.Score DESC, ap.Score DESC
LIMIT 100;