WITH RECURSIVE BadgeDepths AS (
  SELECT u.Id AS UserId, b.Id AS BadgeId, 1 AS Depth
  FROM Users u
  JOIN Badges b ON u.Id = b.UserId
  WHERE b.Class = 1 AND b.TagBased = TRUE
  UNION ALL
  SELECT bd.UserId, n.BadgeId, bd.Depth + 1
  FROM BadgeDepths bd
  JOIN (
    SELECT b_inner.Id AS BadgeId, b_inner.UserId AS UserSiblingId
    FROM Badges b_inner
  ) n ON bd.UserId = n.UserSiblingId
  WHERE n.BadgeId <> bd.BadgeId AND bd.Depth < 3
),

QuestionAnswersScoreCounts AS (
  SELECT
    q.Id AS QuestionId,
    ('<' || REPLACE(COALESCE(q.Tags, ''), '><', '>; <') || '>') AS ParsedTags,
    COUNT(a.Id) FILTER (WHERE a.CreationDate > q.CreationDate AND a.Score > 0) AS PositiveAnswerCount,
    SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS Makeina
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Tags
)

SELECT
  qasc.QuestionId,
  qasc.ParsedTags,
  qasc.PositiveAnswerCount,
  qasc.Makeina
FROM QuestionAnswersScoreCounts qasc;