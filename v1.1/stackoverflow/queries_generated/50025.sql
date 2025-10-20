-- {"query": "50025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1202} 

WITH QuestionTags AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate AS QuestionDate,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.FavoriteCount,
    p.Title,
    EXTRACT(YEAR FROM p.CreationDate) AS QuestionYear,
    t.TagName
  FROM Posts p,
       unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  JOIN Tags t ON t.TagName = TagName
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
    AND t.Count > 1000 -- Popular tags only
),
UserAnnualStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
    MAX(b.Name) FILTER (WHERE b.Class = 1 AND EXTRACT(YEAR FROM b.Date) = EXTRACT(YEAR FROM p.CreationDate)) AS GoldBadgeEarnedThisYear,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2 AND EXTRACT(YEAR FROM v.CreationDate) = EXTRACT(YEAR FROM p.CreationDate)) AS UpvotesGiven
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.Reputation > 5000 AND p.CreationDate > '2015-01-01'
  GROUP BY u.Id, u.DisplayName, u.Reputation, ActivityYear
),
RankedAnswers AS (
  SELECT
    a.Id AS AnswerId,
    a.OwnerUserId,
    a.ParentId AS QuestionId,
    a.CreationDate AS AnswerDate,
    a.Score AS AnswerScore,
    ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
  FROM Posts a
  WHERE a.PostTypeId = 2 -- Answer
),
UserTagPerformance AS (
  SELECT
    qt.OwnerUserId AS UserId,
    qt.QuestionYear AS ActivityYear,
    qt.TagName,
    COUNT(DISTINCT qt.PostId) AS QuestionsAsked,
    SUM(qt.QuestionScore) AS TotalQuestionScore,
    AVG(qt.ViewCount) AS AvgQuestionViews,
    SUM(ra.AnswerScore) AS ScoreOfBestAnswer,
    AVG(ra_all.AnswerScore) AS AvgAnswerScoreOnQuestions
  FROM QuestionTags qt
  LEFT JOIN RankedAnswers ra ON qt.PostId = ra.QuestionId AND ra.AnswerRank = 1
  LEFT JOIN Posts ra_all ON qt.PostId = ra_all.ParentId AND ra_all.PostTypeId = 2
  WHERE qt.OwnerUserId IS NOT NULL
  GROUP BY qt.OwnerUserId, qt.QuestionYear, qt.TagName
),
FinalRanking AS (
  SELECT
    utp.UserId,
    utp.ActivityYear,
    utp.TagName,
    uas.DisplayName,
    uas.Reputation,
    utp.QuestionsAsked,
    utp.TotalQuestionScore,
    utp.AvgQuestionViews,
    utp.ScoreOfBestAnswer,
    uas.GoldBadgeEarnedThisYear,
    uas.UpvotesGiven,
    (utp.TotalQuestionScore + (utp.ScoreOfBestAnswer * 2)) / (utp.QuestionsAsked + 1) AS WeightedPerformanceScore,
    ROW_NUMBER() OVER(PARTITION BY utp.ActivityYear, utp.TagName ORDER BY (utp.TotalQuestionScore + (utp.ScoreOfBestAnswer * 2)) / (utp.QuestionsAsked + 1) DESC) AS TagRank
  FROM UserTagPerformance utp
  JOIN UserAnnualStats uas ON utp.UserId = uas.UserId AND utp.ActivityYear = uas.ActivityYear
  WHERE utp.QuestionsAsked > 2
)
SELECT
  fr.ActivityYear,
  fr.TagName,
  fr.TagRank,
  fr.DisplayName,
  fr.Reputation,
  fr.WeightedPerformanceScore,
  fr.QuestionsAsked,
  fr.TotalQuestionScore,
  fr.ScoreOfBestAnswer,
  (SELECT p.Title FROM Posts p JOIN RankedAnswers ra ON p.Id = ra.QuestionId WHERE ra.OwnerUserId = fr.UserId AND ra.QuestionId IN (SELECT PostId FROM QuestionTags WHERE TagName = fr.TagName) ORDER BY ra.AnswerScore DESC LIMIT 1) AS TopAnsweredQuestionTitle,
  fr.GoldBadgeEarnedThisYear,
  fr.UpvotesGiven
FROM FinalRanking fr
WHERE fr.TagRank <= 5
ORDER BY fr.ActivityYear DESC, fr.TagName ASC, fr.TagRank ASC;
