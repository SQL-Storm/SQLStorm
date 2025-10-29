-- {"query": "5306.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 860} 
WITH TopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    STRING_AGG(DISTINCT vt.Name, ',') AS VoteTypesApplied
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 100
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId,
    p.Tags, p.LastActivityDate, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation
), ActiveTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
), TagSimilarity AS (
  SELECT
    t1.TagName AS TagA,
    t2.TagName AS TagB,
    COUNT(*) AS CoOccur
  FROM Posts p1
  JOIN Posts p2 ON p1.Id = p2.Id -- same question
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p1.Tags, 2, length(p1.Tags)-2), '><')) AS TagA
  ) a
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagB
  ) b
  WHERE p1.Id = p2.Id AND p1.PostTypeId = 1
  GROUP BY t1.TagName, t2.TagName
  ORDER BY CoOccur DESC
  LIMIT 50
)
SELECT
  tq.QuestionId,
  tq.Title,
  tq.CreationDate,
  tq.ViewCount,
  tq.Score,
  tq.OwnerDisplayName,
  tq.OwnerReputation,
  tq.Tags,
  tq.LastActivityDate,
  tq.AnswerCount,
  tq.CommentCount,
  tq.FavoriteCount,
  (
    SELECT STRING_AGG(CONCAT(vt.Name, ':', v.BountyAmount), ',')
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.PostId = tq.QuestionId
  ) AS VoteDetail,
  (
    SELECT MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END)
    FROM Votes v
  ) AS LastUpvoteDate,
  (
    SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = tq.QuestionId AND pl.LinkTypeId = 1
  ) AS LinkedCount,
  (
    SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = tq.QuestionId
  ) AS ReferencedFromCount,
  (
    SELECT AVG(p2.Score)
    FROM Posts p2
    WHERE p2.ParentId = tq.QuestionId
  ) AS AvgChildScore,
  (
    SELECT STRING_AGG(DISTINCT vt.Name, ',')
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.PostId = tq.QuestionId
  ) AS AllVoteTypes
FROM TopQuestions tq
ORDER BY tq.LastActivityDate DESC
LIMIT 100;