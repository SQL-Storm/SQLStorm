-- {"query": "50027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 732} 

WITH QuestionTags AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.AnswerCount,
    p.ViewCount,
    t.tag
  FROM Posts p,
    LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(tag)
  WHERE
    p.PostTypeId = 1 -- Questions
    AND p.OwnerUserId IS NOT NULL
    AND p.Tags IS NOT NULL
), YearlyTagMetrics AS (
  SELECT
    EXTRACT(YEAR FROM qt.CreationDate) :: INTEGER AS QuestionYear,
    qt.tag,
    AVG(u.Reputation) AS AvgAskerReputation,
    COUNT(DISTINCT qt.PostId) AS QuestionCount,
    SUM(qt.ViewCount) AS TotalViews,
    AVG(qt.Score) AS AvgQuestionScore,
    SUM(qt.AnswerCount) :: DECIMAL / COUNT(DISTINCT qt.PostId) AS AnswerQuestionRatio,
    COUNT(DISTINCT CASE WHEN b.Class = 1 AND b.TagBased = B'1' THEN b.Id END) AS GoldBadgesForTag,
    (
      SELECT
        AVG(sub_a.Score)
      FROM Posts sub_q
        JOIN Posts sub_a ON sub_q.AcceptedAnswerId = sub_a.Id
      WHERE
        sub_q.Id IN (
          SELECT
            qti.PostId
          FROM QuestionTags qti
          WHERE
            qti.tag = qt.tag
            AND EXTRACT(YEAR FROM qti.CreationDate) = EXTRACT(YEAR FROM qt.CreationDate)
        )
    ) AS AvgAcceptedAnswerScore
  FROM QuestionTags qt
    JOIN Users u ON qt.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    AND b.Name = qt.tag
  WHERE
    u.Reputation > 1000
  GROUP BY
    QuestionYear,
    qt.tag
  HAVING
    COUNT(DISTINCT qt.PostId) > 50
), RankedTags AS (
  SELECT
    ytm.*,
    RANK() OVER (
      PARTITION BY QuestionYear
      ORDER BY
        AvgAskerReputation DESC,
        QuestionCount DESC
    ) AS YearlyRank
  FROM YearlyTagMetrics ytm
)
SELECT
  rt.QuestionYear,
  rt.YearlyRank,
  rt.tag,
  ROUND(rt.AvgAskerReputation, 0) AS AvgAskerReputation,
  rt.QuestionCount,
  rt.TotalViews,
  ROUND(rt.AvgQuestionScore, 2) AS AvgQuestionScore,
  ROUND(rt.AvgAcceptedAnswerScore, 2) AS AvgAcceptedAnswerScore,
  ROUND(rt.AnswerQuestionRatio, 2) AS AnswerQuestionRatio,
  rt.GoldBadgesForTag
FROM RankedTags rt
WHERE
  rt.YearlyRank <= 5
ORDER BY
  rt.QuestionYear DESC,
  rt.YearlyRank ASC;
