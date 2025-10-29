WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
  ),
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      AVG(p.Score) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews,
      MAX(p.CreationDate) AS LatestPostDate,
      (
        SELECT
          COUNT(*)
        FROM Votes v
        WHERE
          v.UserId = p.OwnerUserId AND v.VoteTypeId = 2
      ) AS TotalUpvotesGiven
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  PostsWithDetailedHistory AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      ph.PostHistoryTypeId,
      ph.CreationDate AS HistoryDate,
      ph.UserId AS HistoryUserId,
      ph.Comment AS HistoryComment,
      CASE
        WHEN ph.PostHistoryTypeId = 10 THEN 'Post Closed'
        WHEN ph.PostHistoryTypeId = 11 THEN 'Post Reopened'
        WHEN ph.PostHistoryTypeId = 12 THEN 'Post Deleted'
        WHEN ph.PostHistoryTypeId = 13 THEN 'Post Undeleted'
        WHEN ph.PostHistoryTypeId = 19 THEN 'Question Protected'
        WHEN ph.PostHistoryTypeId = 20 THEN 'Question Unprotected'
        ELSE pht.Name
      END AS HistoryTypeName
    FROM Posts p
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20)
  )
SELECT
  u.DisplayName,
  ups.TotalPosts,
  ups.AvgScore,
  ups.TotalViews,
  ups.LatestPostDate,
  ups.TotalUpvotesGiven,
  rp.Title AS LatestQuestionTitle,
  rp.Score AS LatestQuestionScore,
  pwh.HistoryTypeName AS LatestHistoryAction,
  pwh.HistoryDate AS LatestHistoryDate,
  COALESCE(rp.PostTypeName, 'Unknown') AS UserPostType,
  CASE
    WHEN u.Location IS NULL THEN 'No Location Provided'
    WHEN u.Location LIKE '%USA%' THEN 'USA Resident'
    ELSE 'Other Location'
  END AS LocationCategory,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 3
  ) AS BronzeBadgeCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks pl
      WHERE
        pl.PostId = rp.PostId AND pl.LinkTypeId = 3
    ) THEN 'Is a Duplicate Link'
    ELSE 'Not a Duplicate Link'
  END AS DuplicateLinkStatus
FROM Users u
JOIN UserPostStats ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN RankedPosts rp
  ON u.Id = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN PostsWithDetailedHistory pwh
  ON rp.PostId = pwh.PostId AND pwh.HistoryDate = (
    SELECT
      MAX(sub_pwh.HistoryDate)
    FROM PostsWithDetailedHistory sub_pwh
    WHERE
      sub_pwh.PostId = pwh.PostId
  )
WHERE
  ups.TotalPosts > 50
  AND u.Reputation > 1000
  AND u.CreationDate < DATE '2020-01-01'
GROUP BY
  u.DisplayName,
  ups.TotalPosts,
  ups.AvgScore,
  ups.TotalViews,
  ups.LatestPostDate,
  ups.TotalUpvotesGiven,
  rp.Title,
  rp.Score,
  pwh.HistoryTypeName,
  pwh.HistoryDate,
  rp.PostTypeName,
  u.Location,
  u.Id,
  rp.PostId
ORDER BY
  ups.TotalViews DESC
LIMIT 100;