WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      UserDisplayName,
      Comment,
      Text,
      CreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
  ),
  LatestPostEdits AS (
    SELECT
      Id,
      OwnerUserId,
      LastEditorUserId,
      LastEditDate,
      Title,
      Tags,
      AnswerCount,
      ViewCount,
      Score,
      CommentCount,
      FavoriteCount,
      ClosedDate,
      CommunityOwnedDate,
      LastActivityDate,
      ROW_NUMBER() OVER (PARTITION BY Id ORDER BY LastActivityDate DESC) AS rn
    FROM Posts
    WHERE PostTypeId = 1 -- Questions only
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
      SUM(CASE WHEN p.AnswerCount IS NOT NULL AND p.AnswerCount > 0 THEN 1 ELSE 0 END) AS AnsweredQuestions,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(b.Date) AS LastBadgeDate,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    LEFT JOIN Comments c
      ON c.UserId = u.Id
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  )
SELECT
  lpe.Id AS QuestionId,
  lpe.Title AS QuestionTitle,
  ua.UserName AS QuestionOwner,
  ua.Reputation,
  ua.UserCreationDate,
  ua.QuestionCount,
  ua.PositiveScoreQuestions,
  ua.AnsweredQuestions,
  ua.BadgeCount,
  ua.LastBadgeDate,
  ua.LastCommentDate,
  lpe.LastEditDate,
  lpe.Score AS QuestionScore,
  lpe.ViewCount AS QuestionViewCount,
  lpe.AnswerCount AS QuestionAnswerCount,
  lpe.CommentCount AS QuestionCommentCount,
  lpe.FavoriteCount AS QuestionFavoriteCount,
  CASE
    WHEN lpe.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN lpe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS QuestionStatus,
  rph.Comment AS LastPostHistoryComment,
  rph.Text AS LastPostHistoryText,
  CASE
    WHEN lpe.OwnerUserId = rph.UserId THEN 'Same as Owner'
    ELSE 'Different Editor'
  END AS EditOwnershipStatus,
  CASE
    WHEN ua.UserName IS NULL OR ua.Reputation < 1000 THEN 'Low Activity User'
    ELSE 'Active User'
  END AS UserActivityLevel,
  COALESCE(ua.UserName, 'Deleted User') AS DisplayUserName
FROM LatestPostEdits lpe
LEFT JOIN UserActivity ua
  ON lpe.OwnerUserId = ua.UserId
LEFT JOIN RankedPostHistory rph
  ON lpe.Id = rph.PostId AND rph.rn = 1
WHERE
  lpe.Score > 5 -- Focus on higher-scoring questions
  AND lpe.ViewCount > 1000 -- Focus on questions with significant views
  AND ua.UserCreationDate < DATE '2020-01-01' -- Older users
  AND ua.Reputation BETWEEN 500 AND 50000 -- Moderate reputation
  AND EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = lpe.Id AND pl.LinkTypeId = 3 -- Duplicate links
  )

UNION ALL

SELECT
  lpe.Id AS QuestionId,
  lpe.Title AS QuestionTitle,
  ua.UserName AS QuestionOwner,
  ua.Reputation,
  ua.UserCreationDate,
  ua.QuestionCount,
  ua.PositiveScoreQuestions,
  ua.AnsweredQuestions,
  ua.BadgeCount,
  ua.LastBadgeDate,
  ua.LastCommentDate,
  lpe.LastEditDate,
  lpe.Score AS QuestionScore,
  lpe.ViewCount AS QuestionViewCount,
  lpe.AnswerCount AS QuestionAnswerCount,
  lpe.CommentCount AS QuestionCommentCount,
  lpe.FavoriteCount AS QuestionFavoriteCount,
  CASE
    WHEN lpe.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN lpe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS QuestionStatus,
  rph.Comment AS LastPostHistoryComment,
  rph.Text AS LastPostHistoryText,
  CASE
    WHEN lpe.OwnerUserId = rph.UserId THEN 'Same as Owner'
    ELSE 'Different Editor'
  END AS EditOwnershipStatus,
  CASE
    WHEN ua.UserName IS NULL OR ua.Reputation < 1000 THEN 'Low Activity User'
    ELSE 'Active User'
  END AS UserActivityLevel,
  COALESCE(ua.UserName, 'Deleted User') AS DisplayUserName
FROM UserActivity ua
LEFT JOIN LatestPostEdits lpe
  ON lpe.OwnerUserId = ua.UserId
LEFT JOIN RankedPostHistory rph
  ON lpe.Id = rph.PostId AND rph.rn = 1
WHERE
  ua.Reputation >= 50000 -- High reputation users
  AND ua.BadgeCount > 10
  AND ua.UserCreationDate > DATE '2022-01-01' -- Newer users
  AND NOT EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = lpe.Id AND pl.LinkTypeId = 3
  );