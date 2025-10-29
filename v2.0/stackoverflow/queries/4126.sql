WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      u.CreationDate AS OwnerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CommunityOwnedDate IS NULL
      AND p.ClosedDate IS NULL
      AND p.CreationDate > cast('2024-10-01' as date) - INTERVAL '365 day'
  ),
  QuestionEngagement AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT ph.UserId) AS EditorCount
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN Votes v
      ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01' as date) - INTERVAL '365 day'
    GROUP BY
      p.Id
  ),
  TopOwners AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS QuestionCount,
      AVG(Score) AS AvgQuestionScore,
      SUM(FavoriteCount) AS TotalFavoriteCount
    FROM Posts
    WHERE
      PostTypeId = 1
      AND OwnerUserId > 0
      AND CreationDate > cast('2024-10-01' as date) - INTERVAL '730 day'
    GROUP BY
      OwnerUserId
    HAVING
      COUNT(Id) > 10
  ),
  TagSpecificAnalysis AS (
    SELECT
      p.Id AS QuestionId,
      t.TagName,
      CASE
        WHEN POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0 THEN 1
        ELSE 0
      END AS HasTagInTitle
    FROM Posts p
    JOIN Tags t
      ON EXISTS (
        SELECT 1
        FROM (
          -- split tags string like "<tag1><tag2>" into rows is dialect-specific.
          -- Use a simple check: tag name appears enclosed in angle brackets in p.Tags
          SELECT 1
        ) s
        WHERE POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0
      )
  )
SELECT
  rq.QuestionId,
  rq.OwnerUserId,
  rq.Title,
  rq.CreationDate,
  rq.Score,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.ViewCount,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.OwnerCreationDate,
  qe.CommentCount,
  qe.UpVoteCount,
  qe.DownVoteCount,
  qe.EditorCount,
  towner.QuestionCount,
  towner.AvgQuestionScore,
  towner.TotalFavoriteCount,
  tsa.TagName,
  tsa.HasTagInTitle
FROM RecentQuestions rq
JOIN QuestionEngagement qe
  ON rq.QuestionId = qe.QuestionId
LEFT JOIN TopOwners towner
  ON rq.OwnerUserId = towner.OwnerUserId
LEFT JOIN TagSpecificAnalysis tsa
  ON rq.QuestionId = tsa.QuestionId
WHERE rq.rn = 1
GROUP BY
  rq.QuestionId,
  rq.OwnerUserId,
  rq.Title,
  rq.CreationDate,
  rq.Score,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.ViewCount,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.OwnerCreationDate,
  qe.CommentCount,
  qe.UpVoteCount,
  qe.DownVoteCount,
  qe.EditorCount,
  towner.QuestionCount,
  towner.AvgQuestionScore,
  towner.TotalFavoriteCount,
  tsa.TagName,
  tsa.HasTagInTitle;