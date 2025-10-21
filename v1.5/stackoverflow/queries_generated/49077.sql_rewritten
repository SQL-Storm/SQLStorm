-- {"query": "49077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1600} 
WITH PopularEditedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        COUNT(ph.Id) AS EditHistoryEntryCount,
        p.ViewCount
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 -- Questions
      AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title, Body, Tags
    GROUP BY p.Id, p.ViewCount
    HAVING COUNT(ph.Id) > 10 -- Questions edited or rolled back more than 10 times
       AND p.ViewCount > 10000 -- Popular questions with high view count
),
HighScoringAnswersToPopularEditedQuestions AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesOnAnswer,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesOnAnswer,
        a.CreationDate AS AnswerCreationDate
    FROM Posts a
    JOIN Votes v ON a.Id = v.PostId
    JOIN PopularEditedQuestions peq ON a.ParentId = peq.QuestionId
    WHERE a.PostTypeId = 2 -- Is an answer
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 50 -- Answers with more than 50 upvotes
       AND (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)) > 40 -- Net score greater than 40
),
ActiveGoldBadgeUsers AS (
    SELECT DISTINCT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserRegistrationDate,
        u.LastAccessDate AS UserLastActivityDate
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class = 1 -- Gold badges
      AND u.Reputation > 75000 -- Highly reputable users
      AND u.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '9 months') -- Active in the last 9 months
),
UserOverallCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS SumOfCommentScores,
        AVG(c.Score) AS AverageCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
      AND c.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') -- Only consider recent comments
    GROUP BY c.UserId
    HAVING COUNT(c.Id) > 20 -- At least 20 comments
),
UserAnsweredQuestionTags AS (
    SELECT
        hsa.OwnerUserId AS UserId,
        q.Id AS QuestionId,
        TRIM(UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><'))) AS TagName
    FROM HighScoringAnswersToPopularEditedQuestions hsa
    JOIN Posts q ON hsa.QuestionId = q.Id
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND LENGTH(q.Tags) > 2
),
UserTopTagsSummary AS (
    SELECT
        uat.UserId,
        STRING_AGG(uat.TagName || ' (' || uat.TagCount || ')', '; ' ORDER BY uat.TagCount DESC, uat.TagName) AS Top5TagsWithCounts
    FROM (
        SELECT
            UserId,
            TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC, TagName) AS rn
        FROM UserAnsweredQuestionTags
        GROUP BY UserId, TagName
    ) AS uat
    WHERE uat.rn <= 5 -- Top 5 tags
    GROUP BY uat.UserId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId AS QuestionId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS NumberOfDuplicateLinks
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    agu.UserId,
    agu.DisplayName,
    agu.Reputation,
    agu.UserRegistrationDate,
    agu.UserLastActivityDate,
    COUNT(DISTINCT hsa.AnswerId) AS CountOfHighScoringAnswers,
    SUM(hsa.TotalUpvotesOnAnswer) AS SumOfUpvotesOnHighScoringAnswers,
    SUM(hsa.TotalUpvotesOnAnswer) - SUM(hsa.TotalDownvotesOnAnswer) AS NetScoreOnHighScoringAnswers,
    COUNT(DISTINCT peq.QuestionId) AS CountOfPopularEditedQuestionsAnswered,
    MAX(ucos.TotalCommentsMade) AS TotalCommentsByUser,
    MAX(ucos.SumOfCommentScores) AS TotalCommentScoreByUser,
    MAX(ucos.AverageCommentScore) AS AvgCommentScoreByUser,
    MAX(ucos.LatestCommentDate) AS LatestCommentActivity,
    utt.Top5TagsWithCounts,
    COALESCE(SUM(pla.NumberOfLinkedPosts), 0) AS TotalLinkedQuestionsRelatedToAnswers,
    COALESCE(SUM(pla.NumberOfDuplicateLinks), 0) AS TotalDuplicateQuestionsRelatedToAnswers,
    DENSE_RANK() OVER (ORDER BY SUM(hsa.TotalUpvotesOnAnswer) DESC, COUNT(DISTINCT hsa.AnswerId) DESC, agu.Reputation DESC, MAX(ucos.SumOfCommentScores) DESC) AS UserPerformanceRank
FROM ActiveGoldBadgeUsers agu
JOIN HighScoringAnswersToPopularEditedQuestions hsa ON agu.UserId = hsa.OwnerUserId
JOIN PopularEditedQuestions peq ON hsa.QuestionId = peq.QuestionId
LEFT JOIN UserOverallCommentStats ucos ON agu.UserId = ucos.UserId
LEFT JOIN UserTopTagsSummary utt ON agu.UserId = utt.UserId
LEFT JOIN PostLinkAnalysis pla ON peq.QuestionId = pla.QuestionId
WHERE hsa.AnswerCreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '4 years') -- Answers within last 4 years
GROUP BY agu.UserId, agu.DisplayName, agu.Reputation, agu.UserRegistrationDate, agu.UserLastActivityDate, utt.Top5TagsWithCounts
HAVING COUNT(DISTINCT hsa.AnswerId) >= 10 -- Users with at least 10 such answers
ORDER BY UserPerformanceRank
LIMIT 200;