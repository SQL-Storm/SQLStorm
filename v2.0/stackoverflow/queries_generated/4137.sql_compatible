WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.Score,
      p.CreationDate AS QuestionCreationDate,
      ROW_NUMBER() OVER (
        ORDER BY
          p.ViewCount DESC,
          p.FavoriteCount DESC,
          p.Score DESC
      ) AS rn_global,
      DENSE_RANK() OVER (
        PARTITION BY
          DATE_TRUNC('month', p.CreationDate)
        ORDER BY
          p.Score DESC
      ) AS dr_monthly_score,
      LAG(p.Score, 1, 0) OVER (
        ORDER BY
          p.CreationDate
      ) AS prev_day_score
    FROM
      Posts p
    WHERE
      p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.OwnerUserId IS NOT NULL
      AND p.ViewCount > 1000
  ),
  AnswerStats AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(a.Score) AS TotalAnswerScore,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM
      Posts a
    INNER JOIN
      Posts p
      ON a.ParentId = p.Id
    WHERE
      a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
      AND p.PostTypeId = 1
      AND p.ClosedDate IS NULL
    GROUP BY
      p.ParentId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS PostEditCount,
      SUM(
        CASE
          WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1
          ELSE 0
        END
      ) AS BodyEditCount
    FROM
      Users u
    LEFT JOIN
      PostHistory ph
      ON u.Id = ph.UserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      COUNT(DISTINCT ph.PostId) > 5
  ),
  CommentSentiment AS (
    SELECT
      c.PostId AS QuestionId,
      AVG(
        CASE
          WHEN LOWER(c.Text) LIKE '%great%' THEN 1.0
          WHEN LOWER(c.Text) LIKE '%excellent%' THEN 1.0
          WHEN LOWER(c.Text) LIKE '%helpful%' THEN 1.0
          WHEN LOWER(c.Text) LIKE '%thanks%' THEN 0.5
          WHEN LOWER(c.Text) LIKE '%good%' THEN 0.5
          WHEN LOWER(c.Text) LIKE '%bad%' THEN -0.5
          WHEN LOWER(c.Text) LIKE '%terrible%' THEN -1.0
          WHEN LOWER(c.Text) LIKE '%wrong%' THEN -1.0
          WHEN LOWER(c.Text) LIKE '%hate%' THEN -1.0
          ELSE 0.0
        END
      ) AS AvgCommentSentiment
    FROM
      Comments c
    INNER JOIN
      Posts p
      ON c.PostId = p.Id
    WHERE
      p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND c.UserId IS NOT NULL
    GROUP BY
      c.PostId
  )
SELECT
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreationDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  rq.ViewCount,
  rq.FavoriteCount,
  rq.Score AS QuestionScore,
  COALESCE(ans.AnswerCount, 0) AS TotalAnswers,
  COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(ans.AverageAnswerScore, 0.0) AS AverageAnswerScore,
  CASE
    WHEN ans.LastAnswerDate IS NULL THEN 'Never Answered'
    WHEN ans.LastAnswerDate < (rq.QuestionCreationDate + INTERVAL '7 days') THEN 'Fast Answer'
    ELSE 'Slow Answer'
  END AS AnswerSpeedCategory,
  COALESCE(cs.AvgCommentSentiment, 0.0) AS OverallCommentSentiment,
  ua.PostEditCount AS OwnerPostEditCount,
  ua.BodyEditCount AS OwnerBodyEditCount,
  rq.rn_global,
  rq.dr_monthly_score,
  rq.prev_day_score,
  CASE
    WHEN rq.Score > rq.prev_day_score * 1.5 THEN 'Significant Growth'
    WHEN rq.Score < rq.prev_day_score * 0.5 THEN 'Significant Decline'
    ELSE 'Stable'
  END AS ScoreTrend,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'HasWebsite'
    ELSE 'NoWebsite'
  END AS UserWebsiteStatus,
  CASE
    WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'NoBio'
    WHEN CHAR_LENGTH(u.AboutMe) > 500 THEN 'LongBio'
    ELSE 'ShortBio'
  END AS UserBioStatus,
  PL.LinkCount AS OutgoingLinkCount,
  COALESCE(PH.RevisionCount, 0) AS PostRevisionCount
FROM
  RankedQuestions rq
LEFT JOIN
  Users u
  ON rq.OwnerUserId = u.Id
LEFT JOIN
  AnswerStats ans
  ON rq.QuestionId = ans.QuestionId
LEFT JOIN
  CommentSentiment cs
  ON rq.QuestionId = cs.QuestionId
LEFT JOIN
  UserActivity ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS LinkCount FROM PostLinks WHERE LinkTypeId = 1 GROUP BY PostId
) PL
  ON rq.QuestionId = PL.PostId
LEFT JOIN (
  SELECT PostId, COUNT(*) AS RevisionCount FROM PostHistory WHERE PostHistoryTypeId IN (2, 5, 8) GROUP BY PostId
) PH
  ON rq.QuestionId = PH.PostId
WHERE
  rq.rn_global <= 100
  AND (rq.dr_monthly_score <= 5 OR rq.dr_monthly_score IS NULL)
ORDER BY
  rq.rn_global;