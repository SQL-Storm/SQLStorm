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
      AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_for_type,
      SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_for_type
    FROM
      Posts AS p
      JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS NumberOfPosts,
      MAX(CreationDate) AS LastPostDate
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      UserId
  ),
  PostCommentsAndVotes AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT c.Id) AS CommentCountTotal,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
      COUNT(DISTINCT pv.Id) AS VoteCountTotal,
      SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount, -- VoteTypeId 2 is UpMod
      SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount -- VoteTypeId 3 is DownMod
    FROM
      Posts AS p
      LEFT JOIN Comments AS c
      ON p.Id = c.PostId
      LEFT JOIN Votes AS pv
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
      Id,
      Title,
      OwnerUserId,
      Score,
      FavoriteCount,
      CreationDate
    FROM
      RankedPosts
    WHERE
      PostTypeId = 1 AND rn_score_desc <= 10
  ),
  TopAnswers AS (
    SELECT
      Id,
      ParentId,
      OwnerUserId,
      Score,
      CreationDate
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
      AVG(CAST(ta.Score AS FLOAT)) AS AvgAnswerScoreForQuestion,
      MAX(ta.CreationDate) AS LastAnswerDate,
      COALESCE(pcv.CommentCountTotal, 0) AS QuestionCommentCount,
      COALESCE(pcv.UpVoteCount, 0) AS QuestionUpVoteCount,
      COALESCE(pcv.DownVoteCount, 0) AS QuestionDownVoteCount
    FROM
      TopQuestions AS tq
      LEFT JOIN TopAnswers AS ta
      ON tq.Id = ta.ParentId
      LEFT JOIN PostCommentsAndVotes AS pcv
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
    WHEN DATEDIFF(day, qd.QuestionCreationDate, GETDATE()) > 365 THEN 'Older than 1 Year'
    WHEN DATEDIFF(day, qd.QuestionCreationDate, GETDATE()) BETWEEN 30 AND 365 THEN 'Between 1 Month and 1 Year'
    ELSE 'Less than 1 Month'
  END AS AgeCategory,
  CONCAT(
    'Tags: ',
    REPLACE(REPLACE(REPLACE(p.Tags, '><', ' '), '<', ''), '>', '')
  ) AS FormattedTags,
  COALESCE(pl.RelatedPostCount, 0) AS LinkCount
FROM
  QuestionDetails AS qd
  LEFT JOIN Users AS u_q
  ON qd.QuestionOwnerUserId = u_q.Id
  LEFT JOIN UserActivity AS ua
  ON qd.QuestionOwnerUserId = ua.UserId
  LEFT JOIN UserBadges AS ub
  ON qd.QuestionOwnerUserId = ub.UserId
  JOIN RankedPosts AS rp
  ON qd.QuestionId = rp.PostId AND rp.PostTypeId = 1 -- Ensure we are joining on the question row
  LEFT JOIN Posts AS p
  ON qd.QuestionId = p.Id
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(Id) AS RelatedPostCount
    FROM
      PostLinks
    WHERE
      LinkTypeId = 1 -- Linked
    GROUP BY
      PostId
  ) AS pl
  ON qd.QuestionId = pl.PostId
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionFavoriteCount DESC,
  qd.QuestionCreationDate DESC
LIMIT 100;
