-- {"query": "4489.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2107}
WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 1 ELSE 0 END) AS TagEdits,
      MAX(p.CreationDate) AS LastPostCreationDate,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      COUNT(DISTINCT c.Id) AS TotalComments,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM
      Users u
    LEFT JOIN
      Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      PostHistory ph
      ON u.Id = ph.UserId AND p.Id = ph.PostId
    LEFT JOIN
      Comments c
      ON u.Id = c.UserId AND p.Id = c.PostId
    LEFT JOIN
      Votes v
      ON u.Id = v.UserId AND p.Id = v.PostId
    WHERE
      u.Id BETWEEN 1 AND 10000
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostEngagementBase AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.LastActivityDate,
      p.ClosedDate,
      COALESCE(AVG(c.Score), 0) AS AvgCommentScore,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM
      Posts p
    LEFT JOIN
      Comments c
      ON p.Id = c.PostId
    LEFT JOIN
      Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId BETWEEN 1 AND 10000
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.LastActivityDate,
      p.ClosedDate
  ),
  PostEngagement AS (
    SELECT
      pe.*,
      ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.LastActivityDate DESC, pe.PostId) AS PostRankByActivity
    FROM
      PostEngagementBase pe
  )
SELECT
  ua.DisplayName,
  u.Reputation,
  u.CreationDate,
  ua.PostHistoryCount,
  ua.BodyEdits,
  ua.TitleEdits,
  ua.TagEdits,
  ua.TotalPosts,
  ua.TotalComments,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  pe.Title AS FirstQuestionTitle,
  pe.Score AS FirstQuestionScore,
  pe.AnswerCount AS FirstQuestionAnswerCount,
  pe.CommentCount AS FirstQuestionCommentCount,
  pe.FavoriteCount AS FirstQuestionFavoriteCount,
  pe.TotalUpvotes AS FirstQuestionTotalUpvotes,
  pe.TotalDownvotes AS FirstQuestionTotalDownvotes,
  pe.AvgCommentScore AS FirstQuestionAvgCommentScore,
  pe.IsClosed AS FirstQuestionIsClosed,
  COALESCE(u2.DisplayName, 'Community') AS LastEditorDisplayName,
  CASE
    WHEN ua.LastPostCreationDate IS NULL THEN 'Never Posted'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' DAY) THEN 'Within Last Day'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY) THEN 'Within Last Week'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Within Last Month'
    ELSE 'Older than a Month'
  END AS RecencyOfActivity,
  CASE
    WHEN LENGTH(u.AboutMe) > 100 THEN 'Long Bio'
    WHEN u.AboutMe IS NULL THEN 'No Bio'
    ELSE 'Short Bio'
  END AS AboutMeLength,
  CASE
    WHEN ua.PostHistoryCount > 50 THEN 'High Activity'
    WHEN ua.PostHistoryCount > 10 THEN 'Medium Activity'
    ELSE 'Low Activity'
  END AS ActivityLevel,
  pl.RelatedPostId AS LinkedToPostId,
  CASE
    WHEN pt.Name = 'Question' THEN 'Q'
    WHEN pt.Name = 'Answer' THEN 'A'
    ELSE 'Other'
  END AS PostTypeCategory
FROM
  UserActivity ua
LEFT JOIN
  Users u
  ON ua.UserId = u.Id
LEFT JOIN
  PostEngagement pe
  ON ua.UserId = pe.OwnerUserId AND pe.PostRankByActivity = 1
LEFT JOIN
  Posts p
  ON ua.UserId = p.OwnerUserId AND p.Id = (
    SELECT pl2.RelatedPostId
    FROM PostLinks pl2
    WHERE pl2.PostId = ua.UserId AND pl2.LinkTypeId = 1
    LIMIT 1
  )
LEFT JOIN
  Users u2
  ON p.LastEditorUserId = u2.Id
LEFT JOIN
  PostLinks pl
  ON ua.UserId = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN
  PostTypes pt
  ON p.PostTypeId = pt.Id
WHERE
  (ua.DisplayName ILIKE '%john%' OR ua.DisplayName ILIKE '%doe%')
  OR ua.PostHistoryCount > 100
  OR ua.UpvotesGiven > ua.DownvotesGiven * 2

UNION ALL

SELECT
  ua.DisplayName,
  u.Reputation,
  u.CreationDate,
  ua.PostHistoryCount,
  ua.BodyEdits,
  ua.TitleEdits,
  ua.TagEdits,
  ua.TotalPosts,
  ua.TotalComments,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  pe.Title AS FirstQuestionTitle,
  pe.Score AS FirstQuestionScore,
  pe.AnswerCount AS FirstQuestionAnswerCount,
  pe.CommentCount AS FirstQuestionCommentCount,
  pe.FavoriteCount AS FirstQuestionFavoriteCount,
  pe.TotalUpvotes AS FirstQuestionTotalUpvotes,
  pe.TotalDownvotes AS FirstQuestionTotalDownvotes,
  pe.AvgCommentScore AS FirstQuestionAvgCommentScore,
  pe.IsClosed AS FirstQuestionIsClosed,
  COALESCE(u2.DisplayName, 'Community') AS LastEditorDisplayName,
  CASE
    WHEN ua.LastPostCreationDate IS NULL THEN 'Never Posted'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' DAY) THEN 'Within Last Day'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY) THEN 'Within Last Week'
    WHEN ua.LastPostCreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Within Last Month'
    ELSE 'Older than a Month'
  END AS RecencyOfActivity,
  CASE
    WHEN LENGTH(u.AboutMe) > 100 THEN 'Long Bio'
    WHEN u.AboutMe IS NULL THEN 'No Bio'
    ELSE 'Short Bio'
  END AS AboutMeLength,
  CASE
    WHEN ua.PostHistoryCount > 50 THEN 'High Activity'
    WHEN ua.PostHistoryCount > 10 THEN 'Medium Activity'
    ELSE 'Low Activity'
  END AS ActivityLevel,
  pl2.RelatedPostId AS LinkedToPostId,
  CASE
    WHEN pt2.Name = 'Question' THEN 'Q'
    WHEN pt2.Name = 'Answer' THEN 'A'
    ELSE 'Other'
  END AS PostTypeCategory
FROM
  UserActivity ua
JOIN
  Users u
  ON ua.UserId = u.Id
LEFT JOIN
  PostEngagement pe
  ON ua.UserId = pe.OwnerUserId AND pe.PostRankByActivity = 1
LEFT JOIN
  Posts p_main
  ON ua.UserId = p_main.LastEditorUserId
LEFT JOIN
  Users u2
  ON p_main.LastEditorUserId = u2.Id
LEFT JOIN
  PostLinks pl2
  ON ua.UserId = pl2.RelatedPostId AND pl2.LinkTypeId = 3
LEFT JOIN
  Posts p2
  ON ua.UserId = p2.Id AND p2.Id = pl2.PostId
LEFT JOIN
  PostTypes pt2
  ON p2.PostTypeId = pt2.Id
WHERE
  ua.DisplayName IS NULL OR ua.PostHistoryCount < 10
  OR ua.DownvotesGiven >= ua.UpvotesGiven;