-- {"query": "4604.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1152} 

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
    FROM Posts AS p
    JOIN PostTypes AS pt
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
        FROM Votes AS v
        WHERE
          v.UserId = p.OwnerUserId AND v.VoteTypeId = 2 /* UpMod */
      ) AS TotalUpvotesGiven
    FROM Posts AS p
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
        ELSE ph.PostHistoryTypes.Name
      END AS HistoryTypeName
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes
      ON ph.PostHistoryTypeId = PostHistoryTypes.Id
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
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 1 /* Gold Badge */
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 2 /* Silver Badge */
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 3 /* Bronze Badge */
  ) AS BronzeBadgeCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = rp.PostId AND pl.LinkTypeId = 3 /* Duplicate */
    ) THEN 'Is a Duplicate Link'
    ELSE 'Not a Duplicate Link'
  END AS DuplicateLinkStatus
FROM Users AS u
JOIN UserPostStats AS ups
  ON u.Id = ups.OwnerUserId
LEFT JOIN RankedPosts AS rp
  ON u.Id = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN PostsWithDetailedHistory AS pwh
  ON rp.PostId = pwh.PostId AND pwh.HistoryDate = (
    SELECT
      MAX(HistoryDate)
    FROM PostsWithDetailedHistory AS sub_pwh
    WHERE
      sub_pwh.PostId = pwh.PostId
  )
WHERE
  ups.TotalPosts > 50
  AND u.Reputation > 1000
  AND u.CreationDate < '2020-01-01'
ORDER BY
  ups.TotalViews DESC
LIMIT 100;
