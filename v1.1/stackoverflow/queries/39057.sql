WITH
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
QuestionTags AS (
  SELECT
    q.Id AS QuestionId,
    LOWER(TRIM(tag::VARCHAR)) AS TagName
  FROM Questions q,
  UNNEST(
    string_to_array(
      REPLACE(REPLACE(substring(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags) - 2)), '><', ','), '>', ''),
      ','
    )
  ) AS tag
),
TagSummary AS (
  SELECT
    qt.TagName,
    COUNT(*) AS TotalQuestions,
    AVG(q.Score) AS AvgQuestionScore,
    SUM(q.ViewCount) AS TotalViews
  FROM QuestionTags qt
  JOIN Questions q
    ON q.Id = qt.QuestionId
  GROUP BY qt.TagName
),
AnswerSummary AS (
  SELECT
    p.ParentId AS QuestionId,
    COUNT(*) AS AnswerCount,
    AVG(p.Score) AS AvgAnswerScore,
    SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerFlag
  FROM Posts p
  JOIN Questions q
    ON q.Id = p.ParentId
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
UserBadgeStats AS (
  SELECT
    u.Id AS UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
  FROM Users u
  LEFT JOIN Badges b
    ON b.UserId = u.Id
  LEFT JOIN Votes v
    ON v.UserId = u.Id
  GROUP BY u.Id
),
UserTagStats AS (
  SELECT
    qt.TagName,
    q.OwnerUserId,
    RANK() OVER (PARTITION BY qt.TagName ORDER BY q.Score DESC) AS ScoreRank
  FROM QuestionTags qt
  JOIN Questions q
    ON q.Id = qt.QuestionId
),
TopUserPerTag AS (
  SELECT
    TagName,
    OwnerUserId
  FROM UserTagStats
  WHERE ScoreRank = 1
),
TopTags AS (
  SELECT
    ts.TagName,
    ts.TotalQuestions,
    ts.AvgQuestionScore,
    ts.TotalViews,
    COALESCE(ans.AnswerCount, 0) AS AnswerCount,
    COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
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
RankedTags AS (
  SELECT
    ts.TagName,
    ts.TotalQuestions,
    ts.AvgQuestionScore,
    ts.TotalViews,
    ts.AnswerCount,
    ts.AvgAnswerScore,
    ts.GoldBadges,
    ts.SilverBadges,
    ts.BronzeBadges,
    ts.UpVotesGiven,
    ts.DownVotesGiven,
    ROW_NUMBER() OVER (
      ORDER BY ts.TotalQuestions DESC, ts.AvgQuestionScore DESC
    ) AS TagRank
  FROM TopTags ts
)
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