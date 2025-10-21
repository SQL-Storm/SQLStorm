-- {"query": "20036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1258} 
WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    SUM(p.Score) AS TotalScore,
    SUM(p.FavoriteCount) AS TotalFavorites,
    MAX(p.LastActivityDate) AS LastPostActivity,
    (
      SELECT
        string_agg(b.Name, ', ' ORDER BY b.Date)
      FROM
        (
          SELECT
            Name,
            Date,
            ROW_NUMBER() OVER (
              PARTITION BY
                UserId
              ORDER BY
                Date DESC
            ) as rn
          FROM
            Badges
          WHERE
            UserId = u.Id
            AND Class = 1
        ) b
      WHERE
        b.rn <= 3
    ) AS LastThreeGoldBadges
  FROM
    Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE
    u.Reputation > 1000
    AND u.AboutMe IS NOT NULL
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate
), RankedAnswers AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    q.Title AS QuestionTitle,
    q.Tags AS QuestionTags,
    q.ViewCount AS QuestionViewCount,
    p.CreationDate - q.CreationDate AS TimeToAnswer,
    RANK() OVER (
      PARTITION BY
        p.OwnerUserId
      ORDER BY
        p.Score DESC,
        p.CreationDate ASC
    ) AS AnswerRank,
    LAG(p.Score, 1, 0) OVER (
      PARTITION BY
        p.OwnerUserId
      ORDER BY
        p.CreationDate
    ) AS PreviousAnswerScore,
    SUM(p.Score) OVER (
      PARTITION BY
        p.OwnerUserId
      ORDER BY
        p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING
        AND CURRENT ROW
    ) AS CumulativeScore
  FROM
    Posts p
    JOIN Posts q ON p.ParentId = q.Id
  WHERE
    p.PostTypeId = 2 -- Answers
    AND p.OwnerUserId IN (
      SELECT
        UserId
      FROM
        UserActivitySummary
      WHERE
        AnswerCount > 20
    )
), PostHistoryAnalysis AS (
    SELECT
      ph.UserId,
      ph.PostId,
      COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as TotalEdits,
      MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) as LastClosedDate,
      (SELECT crt.Name FROM CloseReasonTypes crt WHERE crt.Id = CAST(NULLIF(ph.Comment, '') AS smallint)) AS CloseReason
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, ph.PostId, ph.Comment
)
SELECT
  uas.DisplayName,
  uas.Reputation,
  ra.QuestionTitle,
  ra.Score AS AnswerScore,
  ra.AnswerRank,
  ra.TimeToAnswer,
  (
    uas.TotalScore / NULLIF(
      EXTRACT(
        DAY
        FROM
          (
            uas.LastPostActivity - uas.UserCreationDate
          )
      ),
      0
    )
  ) AS DailyScoreAverage,
  ra.CumulativeScore,
  ra.Score - ra.PreviousAnswerScore AS ScoreDeltaFromPrevious,
  uas.LastThreeGoldBadges,
  pha.TotalEdits,
  COALESCE(pha.CloseReason, 'Not Closed by User') AS PostCloseReason
FROM
  UserActivitySummary uas
  JOIN RankedAnswers ra ON uas.UserId = ra.OwnerUserId
  LEFT JOIN PostHistoryAnalysis pha ON uas.UserId = pha.UserId AND ra.PostId = pha.PostId
WHERE
  ra.AnswerRank <= 5
  AND uas.AnswerCount > uas.QuestionCount
  AND (
    ra.QuestionTags LIKE '%<sql>%'
    OR ra.QuestionTags LIKE '%<python>%'
  )
  AND EXISTS (
    SELECT
      1
    FROM
      Comments c
    WHERE
      c.PostId = ra.PostId
      AND c.Score > 5
      AND c.UserId != ra.OwnerUserId
  )
UNION ALL
SELECT
  '-- TOP TAG CONTRIBUTORS --' AS DisplayName,
  t.Id AS Reputation,
  p.Title,
  p.Score,
  t.Count,
  NULL,
  NULL,
  NULL,
  NULL,
  t.TagName,
  NULL,
  NULL
FROM
  Tags t
  JOIN Posts p ON t.WikiPostId = p.Id
WHERE
  t.Count > (
    SELECT
      AVG(Count) * 2
    FROM
      Tags
  )
  AND t.IsModeratorOnly = 'f'
ORDER BY
  Reputation DESC,
  AnswerScore DESC
LIMIT 200;