-- {"query": "395.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 30023} 
WITH Base AS (
  SELECT
     p.Id AS PostId,
     p.Title AS Title,
     p.Tags AS Tags,
     p.CreationDate AS CreationDate,
     p.LastActivityDate AS LastActivityDate,
     p.Score AS Score,
     p.ViewCount AS ViewCount,
     p.CommentCount AS CommentCount,
     (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
     COALESCE((SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0) AS BountyTotal,
     COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
     COALESCE(u.Reputation, 0) AS OwnerReputation,
     (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
     (CASE WHEN p.Tags IS NULL OR length(p.Tags) <= 2 THEN NULL ELSE (string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'))[1] END) AS FirstTag
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
TopScore AS (
  SELECT
     PostId,
     Title,
     Tags,
     CreationDate,
     LastActivityDate,
     Score,
     ViewCount,
     CommentCount,
     AnswerCount,
     BountyTotal,
     OwnerDisplayName,
     OwnerReputation,
     LinkCount,
     FirstTag AS TagName,
     'TopScore' AS Category,
     ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC) AS Rank
  FROM Base
),
TopBounty AS (
  SELECT
     PostId,
     Title,
     Tags,
     CreationDate,
     LastActivityDate,
     Score,
     ViewCount,
     CommentCount,
     AnswerCount,
     BountyTotal,
     OwnerDisplayName,
     OwnerReputation,
     LinkCount,
     FirstTag AS TagName,
     'TopBounty' AS Category,
     ROW_NUMBER() OVER (ORDER BY BountyTotal DESC, Score DESC) AS Rank
  FROM Base
)
SELECT PostId, Title, Tags, CreationDate, LastActivityDate, Score, ViewCount, CommentCount, AnswerCount, BountyTotal, OwnerDisplayName, OwnerReputation, TagName, Category, Rank
FROM TopScore
UNION ALL
SELECT PostId, Title, Tags, CreationDate, LastActivityDate, Score, ViewCount, CommentCount, AnswerCount, BountyTotal, OwnerDisplayName, OwnerReputation, TagName, Category, Rank
FROM TopBounty
ORDER BY Category, Rank;