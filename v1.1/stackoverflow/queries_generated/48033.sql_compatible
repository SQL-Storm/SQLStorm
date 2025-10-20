WITH RankedAnswers AS (
  SELECT
    p.Id AS PostId,
    p.ParentId AS QuestionId,
    p.OwnerUserId AS AnswererUserId,
    p.CreationDate AS AnswerCreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
  FROM Posts p
  WHERE
    p.PostTypeId = 2 AND p.ParentId IS NOT NULL
),
TopQuestions AS (
  SELECT
    Id AS QuestionId,
    OwnerUserId AS QuestionOwnerUserId,
    Title AS QuestionTitle,
    Tags AS QuestionTags,
    CreationDate AS QuestionCreationDate,
    Score AS QuestionScore,
    AnswerCount,
    FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS q_rn
  FROM Posts
  WHERE
    PostTypeId = 1 AND Score > 1000 AND AnswerCount > 10
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM Users u
  LEFT JOIN Badges b
    ON u.Id = b.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  WHERE
    u.Reputation > 5000
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate
),
QuestionMetrics AS (
  SELECT
    tq.QuestionId,
    tq.QuestionTitle,
    tq.QuestionTags,
    tq.QuestionCreationDate,
    tq.QuestionScore,
    tq.AnswerCount,
    tq.FavoriteCount,
    ue.UserId AS QuestionOwnerUserId,
    ue.DisplayName AS QuestionOwnerDisplayName,
    ue.Reputation AS QuestionOwnerReputation,
    ra.PostId AS BestAnswerId,
    ra.AnswerCreationDate AS BestAnswerCreationDate,
    ra.AnswererUserId AS BestAnswererUserId,
    ue_ans.DisplayName AS BestAnswererDisplayName,
    ue_ans.Reputation AS BestAnswererReputation,
    CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - tq.QuestionCreationDate)) / 86400 AS INTEGER) AS QuestionAgeDays,
    CASE WHEN EXISTS (
      SELECT 1
      FROM PostHistory ph
      WHERE
        ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId = 10
    ) THEN 1 ELSE 0 END AS IsClosed
  FROM TopQuestions tq
  LEFT JOIN RankedAnswers ra
    ON tq.QuestionId = ra.QuestionId AND ra.rn = 1
  LEFT JOIN UserEngagement ue
    ON tq.QuestionOwnerUserId = ue.UserId
  LEFT JOIN UserEngagement ue_ans
    ON ra.AnswererUserId = ue_ans.UserId
)
SELECT
  qm.QuestionId,
  qm.QuestionTitle,
  qm.QuestionTags,
  qm.QuestionCreationDate,
  qm.QuestionScore,
  qm.AnswerCount,
  qm.FavoriteCount,
  qm.QuestionOwnerUserId,
  qm.QuestionOwnerDisplayName,
  qm.QuestionOwnerReputation,
  qm.BestAnswerId,
  qm.BestAnswerCreationDate,
  qm.BestAnswererUserId,
  qm.BestAnswererDisplayName,
  qm.BestAnswererReputation,
  qm.QuestionAgeDays,
  qm.IsClosed,
  (
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.PostId = qm.QuestionId
  ) AS QuestionCommentCount,
  (
    SELECT SUM(Score)
    FROM Comments c
    WHERE c.PostId = qm.QuestionId
  ) AS QuestionTotalCommentScore,
  (
    SELECT COUNT(*)
    FROM PostLinks pl
    WHERE pl.PostId = qm.QuestionId OR pl.RelatedPostId = qm.QuestionId
  ) AS RelatedPostLinksCount
FROM QuestionMetrics qm
WHERE
  qm.QuestionScore > 500 AND qm.AnswerCount > 5
GROUP BY
  qm.QuestionId,
  qm.QuestionTitle,
  qm.QuestionTags,
  qm.QuestionCreationDate,
  qm.QuestionScore,
  qm.AnswerCount,
  qm.FavoriteCount,
  qm.QuestionOwnerUserId,
  qm.QuestionOwnerDisplayName,
  qm.QuestionOwnerReputation,
  qm.BestAnswerId,
  qm.BestAnswerCreationDate,
  qm.BestAnswererUserId,
  qm.BestAnswererDisplayName,
  qm.BestAnswererReputation,
  qm.QuestionAgeDays,
  qm.IsClosed
ORDER BY
  qm.QuestionScore DESC,
  qm.FavoriteCount DESC
LIMIT 100;