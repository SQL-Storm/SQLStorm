WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      MAX(p.CreationDate) AS LastQuestionDate,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
      CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Duplicate'
        ELSE 'Not Duplicate'
      END AS DuplicateStatus
    FROM Posts p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AcceptedAnswerCount,
  pe.PostId,
  pe.CreationDate AS PostCreationDate,
  pe.Score,
  pe.ViewCount,
  pe.AnswerCount AS PostAnswerCount,
  pe.CommentCount AS PostCommentCount,
  pe.FavoriteCount AS PostFavoriteCount,
  pe.PositiveCommentCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.DuplicateStatus,
  rpe.CreationDate AS LastEditDate,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) - ua.LastQuestionDate AS DaysSinceLastQuestion_interval,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) - ua.LastAnswerDate AS DaysSinceLastAnswer_interval,
  LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    ELSE 'Has Website'
  END AS WebsitePresence,
  u.Views AS UserTotalViews,
  CASE
    WHEN u.DownVotes > 0 THEN 'HasDownVotes'
    ELSE 'NoDownVotes'
  END AS UserVoteStatus
FROM UserActivity ua
LEFT JOIN PostEngagement pe
  ON ua.UserId = pe.OwnerUserId
LEFT JOIN RankedPostEdits rpe
  ON pe.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN Users u
  ON ua.UserId = u.Id
WHERE
  ua.QuestionCount > 5
  AND pe.Score > 0
  AND pe.ViewCount > 100
  AND pe.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
GROUP BY
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.AcceptedAnswerCount,
  pe.PostId,
  pe.CreationDate,
  pe.Score,
  pe.ViewCount,
  pe.AnswerCount,
  pe.CommentCount,
  pe.FavoriteCount,
  pe.PositiveCommentCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.DuplicateStatus,
  rpe.CreationDate,
  ua.LastQuestionDate,
  ua.LastAnswerDate,
  u.AboutMe,
  u.WebsiteUrl,
  u.Views,
  u.DownVotes
ORDER BY
  ua.Reputation DESC,
  pe.Score DESC,
  pe.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;