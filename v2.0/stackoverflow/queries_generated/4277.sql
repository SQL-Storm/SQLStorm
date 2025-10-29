-- {"query": "4277.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1685} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostsCreated,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.ViewCount AS DECIMAL(18, 2))) AS AvgViewCount
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
  ),
  PostCommentStats AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
      AVG(CAST(c.Score AS DECIMAL(18, 2))) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    GROUP BY p.Id
  ),
  UserPostHistory AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPosts,
      SUM(CASE WHEN rpe.PostHistoryTypeId IN (4, 6) THEN 1 ELSE 0 END) AS TitleTagEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM RankedPostEdits AS rpe
    GROUP BY rpe.UserId
  ),
  UserVoteSummary AS (
    SELECT
      uv.UserId,
      COUNT(DISTINCT uv.PostId) AS VotedPosts,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCast,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCast
    FROM Votes AS uv
    JOIN VoteTypes AS vt
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
      DATEDIFF(day, u.CreationDate, GETDATE()) AS DaysSinceCreation,
      DATEDIFF(day, u.LastAccessDate, GETDATE()) AS DaysSinceLastAccess,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'HasWebsite'
        WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 'HasLocation'
        ELSE 'NoProfileInfo'
      END AS ProfileStatus
    FROM Users AS u
    WHERE u.Id <> -1 -- Exclude community user
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
    WHEN ru.LastAccessDate < DATEADD(month, -6, GETDATE()) THEN 'Inactive'
    WHEN ru.Reputation < 1000 THEN 'Newbie'
    WHEN ru.Reputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
    ELSE 'Expert'
  END AS UserTier,
  STUFF(
    (
      SELECT
        ', ' + b.Name
      FROM Badges AS b
      WHERE
        b.UserId = ru.Id AND b.Class = 1
      ORDER BY
        b.Date DESC
      FOR XML PATH('')
    ),
    1,
    2,
    ''
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = ru.Id AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = ru.Id AND b.Class = 3
  ) AS BronzeBadgeCount,
  COALESCE(
    (
      SELECT
        COUNT(DISTINCT pl.PostId)
      FROM PostLinks AS pl
      JOIN Posts AS p
        ON pl.PostId = p.Id
      WHERE
        p.OwnerUserId = ru.Id AND pl.LinkTypeId = 3 -- Duplicate Link
    ),
    0
  ) AS PostsLinkedAsDuplicate,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Posts AS p
      WHERE
        p.OwnerUserId = ru.Id AND p.ClosedDate IS NOT NULL AND DATEDIFF(day, p.ClosedDate, GETDATE()) < 30
    ) THEN 'RecentlyClosedPost'
    ELSE 'NoRecentClosure'
  END AS RecentClosureActivity
FROM RecentUsers AS ru
LEFT JOIN UserContribution AS uc
  ON ru.Id = uc.OwnerUserId
LEFT JOIN UserPostHistory AS uph
  ON ru.Id = uph.UserId
LEFT JOIN UserVoteSummary AS uvs
  ON ru.Id = uvs.UserId
LEFT JOIN (
  SELECT DISTINCT
    p.OwnerUserId,
    pcs.*
  FROM Posts AS p
  JOIN PostCommentStats AS pcs
    ON p.Id = pcs.PostId
) AS pcs
  ON ru.Id = pcs.OwnerUserId
ORDER BY
  ru.Reputation DESC,
  ru.LastAccessDate ASC;
