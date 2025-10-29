WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.UserId,
      ph.CreationDate,
      ph.Comment,
      ph.Text AS EditText,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestPostEdits AS (
    SELECT
      rpe.PostId,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 4 THEN rpe.EditText ELSE NULL END) AS LatestTitleEdit,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 5 THEN rpe.EditText ELSE NULL END) AS LatestBodyEdit,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 6 THEN rpe.EditText ELSE NULL END) AS LatestTagsEdit,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 4 THEN rpe.UserId ELSE NULL END) AS TitleEditorUserId,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 5 THEN rpe.UserId ELSE NULL END) AS BodyEditorUserId,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 6 THEN rpe.UserId ELSE NULL END) AS TagsEditorUserId,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 4 THEN rpe.CreationDate ELSE NULL END) AS LatestTitleEditDate,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 5 THEN rpe.CreationDate ELSE NULL END) AS LatestBodyEditDate,
      MAX(CASE WHEN rpe.PostHistoryTypeId = 6 THEN rpe.CreationDate ELSE NULL END) AS LatestTagsEditDate
    FROM RankedPostEdits rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.PostId
  ),
  PostViewCounts AS (
    SELECT
      p.Id AS PostId,
      p.ViewCount,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  ),
  HighEngagementPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Tags,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.Score,
      p.CreationDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      p.OwnerUserId
    FROM Posts p
    WHERE
      p.PostTypeId = 1
      AND p.AnswerCount > 5
      AND p.CommentCount > 0
      AND p.Score > 10
  ),
  UserPostContributions AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS QuestionCount,
      SUM(p.AnswerCount) AS TotalAnsweredInQuestions,
      COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  )
SELECT
  hp.PostId,
  hp.Title,
  hp.Tags,
  hp.AnswerCount,
  hp.CommentCount,
  hp.FavoriteCount,
  hp.Score,
  hp.PostStatus,
  pvc.ViewCount,
  pvc.ViewRank,
  CASE
    WHEN lpe.LatestTitleEdit IS NOT NULL THEN CONCAT('Title last edited by ', COALESCE(u_title.DisplayName, 'Unknown User'), ' on ', CAST(lpe.LatestTitleEditDate AS VARCHAR))
    WHEN lpe.LatestBodyEdit IS NOT NULL THEN CONCAT('Body last edited by ', COALESCE(u_body.DisplayName, 'Unknown User'), ' on ', CAST(lpe.LatestBodyEditDate AS VARCHAR))
    WHEN lpe.LatestTagsEdit IS NOT NULL THEN CONCAT('Tags last edited by ', COALESCE(u_tags.DisplayName, 'Unknown User'), ' on ', CAST(lpe.LatestTagsEditDate AS VARCHAR))
    ELSE 'No recent edits found'
  END AS LastEditSummary,
  COALESCE(upc.QuestionCount, 0) AS UserTotalQuestions,
  COALESCE(upc.TotalAnsweredInQuestions, 0) AS UserTotalAnswersInTheirQuestions,
  COALESCE(upc.CommentCount, 0) AS UserTotalComments,
  CASE
    WHEN hp.Score > 50 THEN 'Highly Scored'
    WHEN hp.Score > 10 THEN 'Moderately Scored'
    ELSE 'Standard Scored'
  END AS ScoreCategory,
  CASE
    WHEN hp.FavoriteCount > 20 THEN 'Very Popular'
    WHEN hp.FavoriteCount > 5 THEN 'Popular'
    ELSE 'Standard Popularity'
  END AS PopularityCategory,
  CASE
    WHEN u.Reputation IS NULL THEN 'No Reputation Data'
    WHEN u.Reputation > 50000 THEN 'Expert'
    WHEN u.Reputation > 10000 THEN 'Experienced'
    WHEN u.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS UserReputationLevel,
  COALESCE(u.CreationDate, DATE '1970-01-01') AS UserCreationDate,
  CASE
    WHEN hp.PostStatus = 'Closed' AND hp.Score < 0 THEN 'Negatively Scored Closed Question'
    WHEN hp.PostStatus = 'Closed' THEN 'Non-Negatively Scored Closed Question'
    ELSE hp.PostStatus
  END AS DetailedPostStatus
FROM HighEngagementPosts hp
JOIN PostViewCounts pvc
  ON hp.PostId = pvc.PostId
LEFT JOIN LatestPostEdits lpe
  ON hp.PostId = lpe.PostId
LEFT JOIN Users u_title
  ON lpe.TitleEditorUserId = u_title.Id
LEFT JOIN Users u_body
  ON lpe.BodyEditorUserId = u_body.Id
LEFT JOIN Users u_tags
  ON lpe.TagsEditorUserId = u_tags.Id
LEFT JOIN UserPostContributions upc
  ON hp.OwnerUserId = upc.OwnerUserId
LEFT JOIN Users u
  ON hp.OwnerUserId = u.Id
WHERE
  pvc.ViewRank <= 1000
  AND (hp.Score > 0 OR hp.AnswerCount > 0)
ORDER BY
  hp.Score DESC,
  hp.FavoriteCount DESC;