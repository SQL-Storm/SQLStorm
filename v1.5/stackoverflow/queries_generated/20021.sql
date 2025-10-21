-- {"query": "20021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1535} 

WITH UserMetrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    (EXTRACT(epoch FROM (NOW() - u.CreationDate)) / 86400) AS AccountAgeDays,
    u.AboutMe,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges
  FROM Users u
  LEFT JOIN (
    SELECT
      UserId,
      COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
      COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
      COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
  WHERE u.Reputation > 1000 AND u.AccountId IS NOT NULL
), PostStats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.CreationDate,
    p.ViewCount,
    p.FavoriteCount,
    p.Tags,
    p.ParentId,
    (
      SELECT EXTRACT(epoch FROM (MIN(c.CreationDate) - p.CreationDate)) / 60
      FROM Comments c
      WHERE c.PostId = p.Id
    ) AS MinsToFirstComment,
    q.AcceptedAnswerId AS QuestionAcceptedAnswerId,
    p.Id = q.AcceptedAnswerId AS IsAcceptedAnswer,
    CASE
      WHEN p.PostTypeId = 2 THEN RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC)
      ELSE NULL
    END AS AnswerRankByScore,
    EXTRACT(epoch FROM (p.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer
  FROM Posts p
  LEFT JOIN Posts q ON p.PostTypeId = 2 AND p.ParentId = q.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.OwnerUserId IS NOT NULL
    AND p.CommunityOwnedDate IS NULL
), UserEngagement AS (
  SELECT
    ps.OwnerUserId,
    COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 AND ps.Tags LIKE '%<sql>%' THEN ps.PostId END) AS SqlQuestionCount,
    AVG(ps.Score) AS AvgScore,
    SUM(ps.ViewCount) AS TotalViews,
    SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumQuestions,
    SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswers,
    SUM(CASE WHEN ps.IsAcceptedAnswer THEN 1 ELSE 0 END)::decimal / NULLIF(SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS PctAcceptedAnswers,
    AVG(ps.AnswerRankByScore) FILTER (WHERE ps.PostTypeId = 2) AS AvgAnswerRank,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ps.HoursToAnswer) FILTER (WHERE ps.PostTypeId = 2) AS MedianHoursToAnswer,
    MIN(ps.MinsToFirstComment) AS QuickestCommentMinutes
  FROM PostStats ps
  GROUP BY ps.OwnerUserId
  HAVING SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) > 5
), ContentRevisions AS (
  (
    SELECT UserId, MAX(CreationDate) AS LastMajorRevisionDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (5, 8)
    GROUP BY UserId
  )
  UNION ALL
  (
    SELECT OwnerUserId, MAX(CreationDate) AS LastMajorRevisionDate
    FROM Posts
    WHERE LastEditorUserId != OwnerUserId AND LastEditorUserId IS NOT NULL
    GROUP BY OwnerUserId
  )
)
SELECT
  FinalRank,
  DisplayName,
  Reputation,
  CompositeScore,
  AccountAgeDays,
  NumQuestions,
  NumAnswers,
  PctAcceptedAnswers,
  AvgAnswerRank,
  LastMajorRevisionDate
FROM (
  SELECT
    um.DisplayName,
    um.Reputation,
    um.AccountAgeDays,
    ue.NumQuestions,
    ue.NumAnswers,
    ue.PctAcceptedAnswers,
    ue.AvgAnswerRank,
    MAX(cr.LastMajorRevisionDate) OVER (PARTITION BY um.UserId) AS LastMajorRevisionDate,
    DENSE_RANK() OVER (ORDER BY
      (
        LN(um.Reputation) * 2
        + (ue.AvgScore * 0.1)
        + (COALESCE(ue.PctAcceptedAnswers, 0) * 30)
        - (COALESCE(ue.AvgAnswerRank, 10) * 5)
        - LN(1 + COALESCE(ue.MedianHoursToAnswer, 100))
        + (um.GoldBadges * 15 + um.SilverBadges * 7 + um.BronzeBadges * 3)
        + (CASE WHEN LENGTH(um.AboutMe) > 200 THEN 10 ELSE 0 END)
      ) DESC NULLS LAST
    ) AS FinalRank,
    (
      LN(um.Reputation) * 2
      + (ue.AvgScore * 0.1)
      + (COALESCE(ue.PctAcceptedAnswers, 0) * 30)
      - (COALESCE(ue.AvgAnswerRank, 10) * 5)
      - LN(1 + COALESCE(ue.MedianHoursToAnswer, 100))
      + (um.GoldBadges * 15 + um.SilverBadges * 7 + um.BronzeBadges * 3)
      + (CASE WHEN LENGTH(um.AboutMe) > 200 THEN 10 ELSE 0 END)
    ) AS CompositeScore
  FROM UserMetrics um
  JOIN UserEngagement ue ON um.UserId = ue.OwnerUserId
  LEFT JOIN ContentRevisions cr ON um.UserId = cr.UserId
  WHERE ue.SqlQuestionCount >= 1
    AND um.UserId NOT IN (
      SELECT DISTINCT v.UserId
      FROM Votes v
      WHERE v.VoteTypeId = 10 AND v.UserId IS NOT NULL
    )
) AS RankedUsers
WHERE FinalRank <= 100
ORDER BY FinalRank;
