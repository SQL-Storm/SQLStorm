-- {"query": "4619.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1790}
WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_score_desc,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.FavoriteCount DESC, p.CreationDate DESC) AS rn_fav_desc,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_for_type,
      SUM(CAST(p.ViewCount AS BIGINT)) OVER (PARTITION BY p.PostTypeId) AS total_views_for_type
    FROM
      Posts p
      JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  UserActivity AS (
    SELECT
      OwnerUserId AS UserId,
      COUNT(Id) AS NumberOfPosts,
      MAX(CreationDate) AS LastPostDate
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  PostCommentsAndVotes AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCountTotal,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
      COUNT(DISTINCT pv.Id) AS VoteCountTotal,
      SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM
      Posts p
      LEFT JOIN Comments c
      ON p.Id = c.PostId
      LEFT JOIN Votes pv
      ON p.Id = pv.PostId
    GROUP BY
      p.Id
  ),
  UserBadges AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadgeCount,
      COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadgeCount,
      COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM
      Badges
    GROUP BY
      UserId
  ),
  TopQuestions AS (
    SELECT
      PostId AS Id,
      CAST(NULL AS TEXT) AS Title,
      OwnerUserId,
      Score,
      FavoriteCount,
      PostCreationDate AS CreationDate
    FROM
      RankedPosts
    WHERE
      PostTypeId = 1 AND rn_score_desc <= 10
  ),
  TopAnswers AS (
    SELECT
      PostId AS Id,
      CAST(NULL AS BIGINT) AS ParentId,
      OwnerUserId,
      Score,
      PostCreationDate AS CreationDate
    FROM
      RankedPosts
    WHERE
      PostTypeId = 2 AND rn_fav_desc <= 20
  ),
  QuestionDetails AS (
    SELECT
      tq.Id AS QuestionId,
      tq.Title,
      tq.OwnerUserId AS QuestionOwnerUserId,
      tq.Score AS QuestionScore,
      tq.FavoriteCount AS QuestionFavoriteCount,
      tq.CreationDate AS QuestionCreationDate,
      COUNT(DISTINCT ta.Id) AS AnswerCountForQuestion,
      SUM(CASE WHEN ta.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswerCount,
      AVG(CAST(ta.Score AS DOUBLE PRECISION)) AS AvgAnswerScoreForQuestion,
      MAX(ta.CreationDate) AS LastAnswerDate,
      COALESCE(pcv.CommentCountTotal, 0) AS QuestionCommentCount,
      COALESCE(pcv.UpVoteCount, 0) AS QuestionUpVoteCount,
      COALESCE(pcv.DownVoteCount, 0) AS QuestionDownVoteCount
    FROM
      TopQuestions tq
      LEFT JOIN TopAnswers ta
      ON tq.Id = ta.ParentId
      LEFT JOIN PostCommentsAndVotes pcv
      ON tq.Id = pcv.PostId
    GROUP BY
      tq.Id,
      tq.Title,
      tq.OwnerUserId,
      tq.Score,
      tq.FavoriteCount,
      tq.CreationDate,
      pcv.CommentCountTotal,
      pcv.UpVoteCount,
      pcv.DownVoteCount
  )
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.QuestionOwnerUserId,
  u_q.DisplayName AS QuestionOwnerDisplayName,
  qd.QuestionScore,
  qd.QuestionFavoriteCount,
  qd.QuestionCreationDate,
  qd.AnswerCountForQuestion,
  qd.PositiveAnswerCount,
  qd.AvgAnswerScoreForQuestion,
  qd.LastAnswerDate,
  qd.QuestionCommentCount,
  qd.QuestionUpVoteCount,
  qd.QuestionDownVoteCount,
  ua.NumberOfPosts AS QuestionOwnerTotalPosts,
  ub.GoldBadgeCount AS QuestionOwnerGoldBadges,
  ub.SilverBadgeCount AS QuestionOwnerSilverBadges,
  ub.BronzeBadgeCount AS QuestionOwnerBronzeBadges,
  rp.avg_score_for_type AS AverageScoreOfAllQuestions,
  rp.total_views_for_type AS TotalViewsOfAllQuestions,
  CASE
    WHEN qd.QuestionScore > rp.avg_score_for_type THEN 'Above Average Score'
    WHEN qd.QuestionScore < rp.avg_score_for_type THEN 'Below Average Score'
    ELSE 'Average Score'
  END AS ScoreCategory,
  CASE
    WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - qd.QuestionCreationDate) > INTERVAL '365 day' THEN 'Older than 1 Year'
    WHEN (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - qd.QuestionCreationDate) BETWEEN INTERVAL '30 day' AND INTERVAL '365 day' THEN 'Between 1 Month and 1 Year'
    ELSE 'Less than 1 Month'
  END AS AgeCategory,
  CONCAT(
    'Tags: ',
    REPLACE(REPLACE(REPLACE(p.Tags, '><', ' '), '<', ''), '>', '')
  ) AS FormattedTags,
  COALESCE(pl.RelatedPostCount, 0) AS LinkCount
FROM
  QuestionDetails qd
  LEFT JOIN Users u_q
  ON qd.QuestionOwnerUserId = u_q.Id
  LEFT JOIN UserActivity ua
  ON qd.QuestionOwnerUserId = ua.UserId
  LEFT JOIN UserBadges ub
  ON qd.QuestionOwnerUserId = ub.UserId
  JOIN RankedPosts rp
  ON qd.QuestionId = rp.PostId AND rp.PostTypeId = 1
  LEFT JOIN Posts p
  ON qd.QuestionId = p.Id
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(Id) AS RelatedPostCount
    FROM
      PostLinks
    WHERE
      LinkTypeId = 1
    GROUP BY
      PostId
  ) pl
  ON qd.QuestionId = pl.PostId
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.QuestionOwnerUserId,
  u_q.DisplayName,
  qd.QuestionScore,
  qd.QuestionFavoriteCount,
  qd.QuestionCreationDate,
  qd.AnswerCountForQuestion,
  qd.PositiveAnswerCount,
  qd.AvgAnswerScoreForQuestion,
  qd.LastAnswerDate,
  qd.QuestionCommentCount,
  qd.QuestionUpVoteCount,
  qd.QuestionDownVoteCount,
  ua.NumberOfPosts,
  ub.GoldBadgeCount,
  ub.SilverBadgeCount,
  ub.BronzeBadgeCount,
  rp.avg_score_for_type,
  rp.total_views_for_type,
  p.Tags,
  pl.RelatedPostCount
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionFavoriteCount DESC,
  qd.QuestionCreationDate DESC
LIMIT 100;