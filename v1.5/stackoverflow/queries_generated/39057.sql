-- {"query": "39057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2960} 

WITH
-- Extract all questions
Questions AS (
  SELECT
    Id,
    Title,
    Score,
    ViewCount,
    CreationDate,
    Tags,
    AcceptedAnswerId,
    OwnerUserId
  FROM Posts
  WHERE PostTypeId = 1
),
-- Explode tag lists into one row per (question, tag)
QuestionTags AS (
  SELECT
    q.Id        AS QuestionId,
    LOWER(tag)  AS TagName
  FROM Questions q
  CROSS JOIN LATERAL
    unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag
),
-- Aggregate basic stats per tag
TagSummary AS (
  SELECT
    qt.TagName,
    COUNT(*)          AS TotalQuestions,
    AVG(q.Score)      AS AvgQuestionScore,
    SUM(q.ViewCount)  AS TotalViews
  FROM QuestionTags qt
  JOIN Questions q
    ON q.Id = qt.QuestionId
  GROUP BY qt.TagName
),
-- Compute answer statistics per question
AnswerSummary AS (
  SELECT
    p.ParentId                   AS QuestionId,
    COUNT(*)                     AS AnswerCount,
    AVG(p.Score)                 AS AvgAnswerScore,
    SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerFlag
  FROM Posts p
  JOIN Questions q
    ON q.Id = p.ParentId
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
-- Compute badge & vote stats per user
UserBadgeStats AS (
  SELECT
    u.Id                           AS UserId,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven
  FROM Users u
  LEFT JOIN Badges b
    ON b.UserId = u.Id
  LEFT JOIN Votes v
    ON v.UserId = u.Id
  GROUP BY u.Id
),
-- Rank users per tag by highest question score
UserTagStats AS (
  SELECT
    qt.TagName,
    q.OwnerUserId,
    RANK() OVER (PARTITION BY qt.TagName ORDER BY q.Score DESC) AS ScoreRank
  FROM QuestionTags qt
  JOIN Questions q
    ON q.Id = qt.QuestionId
),
-- Pick the top-scoring user for each tag
TopUserPerTag AS (
  SELECT
    TagName,
    OwnerUserId
  FROM UserTagStats
  WHERE ScoreRank = 1
),
-- Combine tag summary, answer summary and badge stats for top user per tag
TopTags AS (
  SELECT
    ts.TagName,
    ts.TotalQuestions,
    ts.AvgQuestionScore,
    ts.TotalViews,
    COALESCE(ans.AnswerCount, 0)     AS AnswerCount,
    COALESCE(ans.AvgAnswerScore, 0)  AS AvgAnswerScore,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.UpVotesGiven,
    ubs.DownVotesGiven
  FROM TagSummary ts
  LEFT JOIN AnswerSummary ans
    ON ans.QuestionId = (
         SELECT MIN(qt2.QuestionId)
         FROM QuestionTags qt2
         WHERE qt2.TagName = ts.TagName
       )
  LEFT JOIN TopUserPerTag tup
    ON tup.TagName = ts.TagName
  LEFT JOIN UserBadgeStats ubs
    ON ubs.UserId = tup.OwnerUserId
),
-- Rank tags by popularity and quality
RankedTags AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      ORDER BY TotalQuestions DESC, AvgQuestionScore DESC
    ) AS TagRank
  FROM TopTags
)
-- Final output: Top 50 tags with associated metrics
SELECT
  rt.TagRank,
  rt.TagName,
  rt.TotalQuestions,
  rt.AvgQuestionScore,
  rt.TotalViews,
  rt.AnswerCount,
  rt.AvgAnswerScore,
  rt.GoldBadges,
  rt.SilverBadges,
  rt.BronzeBadges,
  rt.UpVotesGiven,
  rt.DownVotesGiven
FROM RankedTags rt
WHERE rt.TagRank <= 50
ORDER BY rt.TagRank;
