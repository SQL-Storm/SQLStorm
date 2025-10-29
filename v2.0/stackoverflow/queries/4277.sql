WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostsCreated,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.ViewCount AS DECIMAL(18,2))) AS AvgViewCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
  ),
  PostCommentStats AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
      AVG(CAST(c.Score AS DECIMAL(18,2))) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    GROUP BY p.Id
  ),
  UserPostHistory AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPosts,
      SUM(CASE WHEN rpe.PostHistoryTypeId IN (4, 6) THEN 1 ELSE 0 END) AS TitleTagEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM RankedPostEdits rpe
    GROUP BY rpe.UserId
  ),
  UserVoteSummary AS (
    SELECT
      uv.UserId,
      COUNT(DISTINCT uv.PostId) AS VotedPosts,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCast,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCast
    FROM Votes uv
    JOIN VoteTypes vt
      ON uv.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod')
    GROUP BY uv.UserId
  ),
  RecentUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      CAST( (EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM u.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
      CAST( (EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM u.LastAccessDate)) / 86400 AS INTEGER) AS DaysSinceLastAccess,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'HasWebsite'
        WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 'HasLocation'
        ELSE 'NoProfileInfo'
      END AS ProfileStatus
    FROM Users u
    WHERE u.Id <> -1
  )
SELECT
  ru.Id AS UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.DaysSinceCreation,
  ru.DaysSinceLastAccess,
  ru.ProfileStatus,
  COALESCE(uc.PostsCreated, 0) AS TotalPostsCreated,
  COALESCE(uc.QuestionsAsked, 0) AS TotalQuestionsAsked,
  COALESCE(uc.AnswersGiven, 0) AS TotalAnswersGiven,
  COALESCE(uc.TotalScore, 0) AS TotalScoreReceived,
  COALESCE(uc.AvgViewCount, 0.0) AS AveragePostViewCount,
  COALESCE(uph.EditedPosts, 0) AS PostsEdited,
  COALESCE(uph.TitleTagEdits, 0) AS TitleTagEditsMade,
  COALESCE(uph.BodyEdits, 0) AS BodyEditsMade,
  COALESCE(uvs.UpVotesCast, 0) AS UpVotesCast,
  COALESCE(uvs.DownVotesCast, 0) AS DownVotesCast,
  COALESCE(pcs.CommentCount, 0) AS TotalCommentsOnPosts,
  COALESCE(pcs.PositiveComments, 0) AS PositiveCommentsOnPosts,
  COALESCE(pcs.AvgCommentScore, 0.0) AS AverageCommentScore,
  CASE
    WHEN ru.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Inactive'
    WHEN ru.Reputation < 1000 THEN 'Newbie'
    WHEN ru.Reputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
    ELSE 'Expert'
  END AS UserTier,
  (
    SELECT string_agg(b.Name, ', ' ORDER BY b.Date DESC)
    FROM Badges b
    WHERE b.UserId = ru.Id AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT COUNT(*)
    FROM Badges b
    WHERE b.UserId = ru.Id AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT COUNT(*)
    FROM Badges b
    WHERE b.UserId = ru.Id AND b.Class = 3
  ) AS BronzeBadgeCount,
  COALESCE(
    (
      SELECT COUNT(DISTINCT pl.PostId)
      FROM PostLinks pl
      JOIN Posts p
        ON pl.PostId = p.Id
      WHERE p.OwnerUserId = ru.Id AND pl.LinkTypeId = 3
    ),
    0
  ) AS PostsLinkedAsDuplicate,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = ru.Id AND p.ClosedDate IS NOT NULL AND (CAST( (EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM p.ClosedDate)) / 86400 AS INTEGER) < 30)
    ) THEN 'RecentlyClosedPost'
    ELSE 'NoRecentClosure'
  END AS RecentClosureActivity
FROM RecentUsers ru
LEFT JOIN UserContribution uc
  ON ru.Id = uc.OwnerUserId
LEFT JOIN UserPostHistory uph
  ON ru.Id = uph.UserId
LEFT JOIN UserVoteSummary uvs
  ON ru.Id = uvs.UserId
LEFT JOIN (
  SELECT DISTINCT
    p.OwnerUserId,
    pcs.PostId,
    pcs.CommentCount,
    pcs.PositiveComments,
    pcs.AvgCommentScore,
    pcs.LastCommentDate
  FROM Posts p
  JOIN PostCommentStats pcs
    ON p.Id = pcs.PostId
) pcs
  ON ru.Id = pcs.OwnerUserId
GROUP BY
  ru.Id,
  ru.DisplayName,
  ru.Reputation,
  ru.DaysSinceCreation,
  ru.DaysSinceLastAccess,
  ru.ProfileStatus,
  uc.PostsCreated,
  uc.QuestionsAsked,
  uc.AnswersGiven,
  uc.TotalScore,
  uc.AvgViewCount,
  uph.EditedPosts,
  uph.TitleTagEdits,
  uph.BodyEdits,
  uvs.UpVotesCast,
  uvs.DownVotesCast,
  pcs.CommentCount,
  pcs.PositiveComments,
  pcs.AvgCommentScore,
  pcs.PostId,
  pcs.LastCommentDate,
  ru.LastAccessDate
ORDER BY
  ru.Reputation DESC,
  ru.LastAccessDate ASC;