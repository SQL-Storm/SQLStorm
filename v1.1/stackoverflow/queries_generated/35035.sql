-- {"query": "35035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 707} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.CreationDate < NOW() - INTERVAL '2 years'
    ORDER BY u.Reputation DESC
    LIMIT 50
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '1 year'
    GROUP BY b.UserId
),
HighlyViewedQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
      AND p.ViewCount > 10000
),
LinkedAnswers AS (
    SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.OwnerUserId, a.Score, a.CreationDate
    FROM Posts a
    JOIN PostLinks pl ON a.ParentId = pl.RelatedPostId
    WHERE a.PostTypeId = 2
    AND pl.LinkTypeId = 3  -- Duplicate links
),
QuestionEditActivity AS (
    SELECT ph.PostId, COUNT(*) AS EditCount, MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY ph.PostId
)
SELECT tu.DisplayName,
       tu.Reputation,
       COALESCE(ub.GoldCount,0) AS GoldBadges,
       COALESCE(ub.SilverCount,0) AS SilverBadges,
       COALESCE(ub.BronzeCount,0) AS BronzeBadges,
       COUNT(DISTINCT hvq.Id) AS QuestionsOver10kViews,
       AVG(hvq.Score) FILTER (WHERE hvq.Id IS NOT NULL) AS AvgQuestionScore,
       SUM(hvq.AnswerCount) FILTER (WHERE hvq.Id IS NOT NULL) AS TotalQuestionAnswers,
       AVG(hvq.TagCount) FILTER (WHERE hvq.Id IS NOT NULL) AS AvgTagCount,
       COUNT(DISTINCT la.AnswerId) AS DuplicateAnswersAuthored,
       AVG(la.Score) FILTER (WHERE la.AnswerId IS NOT NULL) AS AvgDuplicateAnswerScore,
       MAX(qea.EditCount) AS MaxEditsOnSinglePost,
       MAX(qea.LastEdit) AS MostRecentEdit
FROM TopUsers tu
LEFT JOIN UserBadges ub ON tu.Id = ub.UserId
LEFT JOIN HighlyViewedQuestions hvq ON hvq.OwnerUserId = tu.Id
LEFT JOIN LinkedAnswers la ON la.OwnerUserId = tu.Id
LEFT JOIN QuestionEditActivity qea ON qea.PostId = hvq.Id
GROUP BY tu.Id, tu.DisplayName, tu.Reputation, ub.GoldCount, ub.SilverCount, ub.BronzeCount
ORDER BY tu.Reputation DESC;