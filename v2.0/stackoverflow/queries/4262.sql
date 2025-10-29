-- {"query": "4262.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1670}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserEditSummary AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS PostsEditedCount,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
      MAX(rpe.CreationDate) AS LastEditDateByUser
    FROM
      RankedPostEdits rpe
    GROUP BY
      rpe.UserId
    HAVING
      COUNT(DISTINCT rpe.PostId) > 5
  ),
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate AS QuestionCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      CASE WHEN COUNT(DISTINCT ph.Id) > 0 THEN 1 ELSE 0 END AS HasEdits,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      p.ClosedDate
    FROM
      Posts p
    LEFT JOIN
      Comments c
      ON p.Id = c.PostId
    LEFT JOIN
      Votes v
      ON p.Id = v.PostId
    LEFT JOIN
      PostHistory ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate,
      p.ClosedDate
  ),
  AnswerStats AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(DISTINCT p.Id) AS AnswerCountForQuestion,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpVotes,
      SUM(CASE WHEN p.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswersWithOwners,
      AVG(CASE WHEN p.OwnerUserId IS NOT NULL THEN p.Score ELSE NULL END) AS AverageAnswerScore
    FROM
      Posts p
    LEFT JOIN
      Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  )
SELECT
  qs.QuestionId,
  u.DisplayName AS QuestionOwnerDisplayName,
  qs.Title AS QuestionTitle,
  qs.QuestionCreationDate,
  qs.AnswerCount AS DirectAnswerCount,
  COALESCE(ans.AnswerCountForQuestion, 0) AS TotalAnswerCount,
  qs.CommentCount AS QuestionCommentCount,
  COALESCE(ans.AnswersWithOwners, 0) AS AnswersWithOwnersCount,
  COALESCE(ans.AnswerUpVotes, 0) AS TotalAnswerUpVotes,
  qs.FavoriteCount AS QuestionFavoriteCount,
  qs.ViewCount AS QuestionViewCount,
  qs.UpVotes AS QuestionUpVotes,
  qs.DownVotes AS QuestionDownVotes,
  qs.IsClosed,
  ues.PostsEditedCount AS UserPostsEdited,
  ues.TitleEdits AS UserTitleEdits,
  ues.BodyEdits AS UserBodyEdits,
  ues.TagEdits AS UserTagEdits,
  CASE
    WHEN qs.QuestionCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') AND qs.ViewCount > 10000 THEN 'High Volume Old Question'
    WHEN qs.AnswerCount > 50 THEN 'Highly Answered'
    WHEN qs.CommentCount > 20 THEN 'Highly Commented'
    WHEN qs.FavoriteCount > 100 THEN 'Highly Favorited'
    WHEN qs.UpVotes - qs.DownVotes > 100 THEN 'Highly Voted'
    WHEN qs.IsClosed = 1 THEN 'Closed Question'
    ELSE 'Standard Question'
  END AS QuestionCategorization,
  CASE
    WHEN qs.OwnerUserId = ues.UserId THEN 'Same User Edited'
    ELSE 'Different User Edited'
  END AS EditUserRelation,
  SUBSTRING(qs.Title FROM 1 FOR 50) AS TruncatedTitle,
  CASE
    WHEN ues.LastEditDateByUser IS NULL THEN 'No Edits by Active Editor'
    WHEN qs.QuestionCreationDate > ues.LastEditDateByUser THEN 'Editor Active Before Question'
    ELSE 'Editor Active After Question'
  END AS EditDateComparison,
  CASE
    WHEN qs.AnswerCount = 0 AND qs.FavoriteCount > 0 THEN 'No Answers, But Favorited'
    WHEN qs.AnswerCount > 0 AND qs.CommentCount = 0 THEN 'Answers, But No Comments'
    WHEN qs.ViewCount > 0 AND qs.AnswerCount = 0 THEN 'No Answers, But Viewed'
    WHEN qs.ViewCount IS NULL THEN 'No View Count Data'
    ELSE 'Typical Post'
  END AS PostCharacteristic,
  qs.Title || ' - Owner: ' || COALESCE(u.DisplayName, '') AS TitleWithOwner,
  CAST(qs.ViewCount AS DOUBLE PRECISION) / NULLIF(qs.AnswerCount, 0) AS ViewsPerAnswer,
  COALESCE(qs.FavoriteCount, 0) + COALESCE(qs.AnswerCount, 0) AS TotalEngagement,
  CASE WHEN qs.OwnerUserId IS NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipType
FROM
  QuestionStats qs
LEFT JOIN
  Users u
  ON qs.OwnerUserId = u.Id
LEFT JOIN
  AnswerStats ans
  ON qs.QuestionId = ans.QuestionId
LEFT JOIN
  UserEditSummary ues
  ON qs.OwnerUserId = ues.UserId
WHERE
  qs.ViewCount > 100
  AND (qs.AnswerCount + qs.CommentCount) > 5
  AND u.Reputation > 1000
ORDER BY
  qs.ViewCount DESC,
  qs.FavoriteCount DESC,
  qs.AnswerCount DESC,
  qs.QuestionCreationDate ASC;