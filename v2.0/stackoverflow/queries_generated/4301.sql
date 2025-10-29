-- {"query": "4301.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1723} 

WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate,
      LAG(CreationDate, 1, CreationDate) OVER (PARTITION BY PostId ORDER BY CreationDate) AS PreviousCreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (2, 5) /* Body Edit, Initial Body */
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(DISTINCT p.Id) > 0
  ),
  RecentEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PreviousCreationDate,
      ph.rn
    FROM RankedPostHistory AS ph
    WHERE
      ph.rn <= 10 /* Consider the 10 most recent edits */
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount,
  p.CommentCount AS PostCommentCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  p.FavoriteCount,
  ph_last.CreationDate AS LastEditDate,
  ph_last.PreviousCreationDate AS PreviousEditDate,
  (
    ph_last.CreationDate - ph_last.PreviousCreationDate
  ) AS TimeBetweenLastTwoEdits,
  ua.PostCount AS UserTotalPosts,
  ua.QuestionCount AS UserQuestionCount,
  ua.AnswerCount AS UserAnswerCount,
  ua.AverageScore AS UserAverageScore,
  ua.CommentCount AS UserCommentCount,
  COALESCE(u.Location, 'Unknown') AS UserLocation,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN INSTR(u.WebsiteUrl, 'stackoverflow.com') > 0 THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS UserWebsiteType,
  CASE
    WHEN p.OwnerUserId = -1 THEN 'Community'
    WHEN u.Reputation > 50000 THEN 'High Reputation'
    WHEN u.Reputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS UserReputationLevel,
  TAGS_TO_ARRAY(p.Tags) AS ParsedTags,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 5
  ) AS HighScoreCommentCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3 /* Duplicate Link */
    ) THEN 'IsDuplicate'
    ELSE 'NotDuplicate'
  END AS DuplicateStatus,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 2 /* Upvote */
  ) AS TotalUpvotes,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 3 /* Downvote */
  ) AS TotalDownvotes
FROM Posts AS p
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN RecentEdits AS ph_last
  ON p.Id = ph_last.PostId AND ph_last.rn = 1
LEFT JOIN UserActivity AS ua
  ON p.OwnerUserId = ua.UserId
WHERE
  p.PostTypeId IN (1, 2) /* Questions and Answers */
  AND p.CreationDate >= '2023-01-01'
  AND u.Id IS NOT NULL /* Exclude community-owned posts for user-specific metrics */
  AND ua.PostCount >= 10 /* Users with at least 10 posts */
UNION ALL
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  NULL AS OwnerDisplayName,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount,
  p.CommentCount AS PostCommentCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  p.FavoriteCount,
  NULL AS LastEditDate,
  NULL AS PreviousEditDate,
  NULL AS TimeBetweenLastTwoEdits,
  0 AS UserTotalPosts,
  0 AS UserQuestionCount,
  0 AS UserAnswerCount,
  NULL AS UserAverageScore,
  0 AS UserCommentCount,
  'Community' AS UserLocation,
  'Community' AS UserWebsiteType,
  'Community' AS UserReputationLevel,
  TAGS_TO_ARRAY(p.Tags) AS ParsedTags,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 5
  ) AS HighScoreCommentCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3 /* Duplicate Link */
    ) THEN 'IsDuplicate'
    ELSE 'NotDuplicate'
  END AS DuplicateStatus,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 2 /* Upvote */
  ) AS TotalUpvotes,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId = 3 /* Downvote */
  ) AS TotalDownvotes
FROM Posts AS p
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
WHERE
  p.PostTypeId IN (1, 2) /* Questions and Answers */
  AND p.CreationDate >= '2023-01-01'
  AND p.OwnerUserId = -1 /* Community owned posts */
