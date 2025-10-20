-- {"query": "49022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1468} 
WITH RecentHighScoringAnswers AS (
    -- Identify high-scoring answers to popular questions within the last 5 years
    SELECT
        P.Id AS AnswerId,
        P.ParentId AS QuestionId,
        P.OwnerUserId AS AnswererUserId,
        P.Score AS AnswerScore,
        P.CreationDate AS AnswerCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.Tags AS QuestionTags
    FROM Posts P
    INNER JOIN Posts Q ON P.ParentId = Q.Id
    WHERE
        P.PostTypeId = 2 -- Is an answer
        AND Q.PostTypeId = 1 -- Is a question
        AND P.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
        AND Q.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
        AND P.Score >= 20 -- Minimum answer score
        AND Q.Score >= 50 -- Minimum question score
        AND Q.ViewCount >= 1000 -- Minimum question view count
),
UserAnswerSummary AS (
    -- Aggregate answer statistics for each user
    SELECT
        AnswererUserId,
        COUNT(AnswerId) AS TotalAnswers,
        SUM(AnswerScore) AS TotalAnswerScore,
        AVG(AnswerScore) AS AvgAnswerScore,
        MAX(AnswerScore) AS MaxAnswerScore,
        COUNT(DISTINCT QuestionId) AS UniqueQuestionsAnswered,
        SUM(QuestionScore) AS TotalQuestionScoreOfAnsweredQuestions,
        SUM(QuestionViewCount) AS TotalQuestionViewCountOfAnsweredQuestions
    FROM RecentHighScoringAnswers
    GROUP BY AnswererUserId
    HAVING COUNT(AnswerId) >= 5 -- Users with at least 5 high-scoring answers in the filtered set
),
UserTagContributions AS (
    -- Extract and count tags from questions answered by each user
    SELECT
        rsa.AnswererUserId,
        LOWER(UNNEST(string_to_array(SUBSTRING(rsa.QuestionTags, 2, LENGTH(rsa.QuestionTags) - 2), '><'))) AS TagName,
        COUNT(*) AS TagCount
    FROM RecentHighScoringAnswers rsa
    WHERE rsa.QuestionTags IS NOT NULL AND LENGTH(rsa.QuestionTags) > 2
    GROUP BY rsa.AnswererUserId, LOWER(UNNEST(string_to_array(SUBSTRING(rsa.QuestionTags, 2, LENGTH(rsa.QuestionTags) - 2), '><')))
),
TopTagsPerUser AS (
    -- Identify the top 5 most contributed tags for each user
    SELECT
        utc.AnswererUserId,
        STRING_AGG(utc.TagName || ' (' || utc.TagCount || ')', '; ' ORDER BY utc.TagCount DESC, utc.TagName ASC) AS TopContributedTags
    FROM (
        SELECT
            AnswererUserId,
            TagName,
            TagCount,
            ROW_NUMBER() OVER (PARTITION BY AnswererUserId ORDER BY TagCount DESC, TagName ASC) AS rn
        FROM UserTagContributions
    ) utc
    WHERE utc.rn <= 5 -- Limit to top 5 tags per user
    GROUP BY utc.AnswererUserId
),
UserModerationActivity AS (
    -- Count close and reopen votes made by users in the last 5 years
    SELECT
        ph.UserId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVoteCount, -- Post Closed
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenVoteCount -- Post Reopened
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
      AND ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.UserId
),
UserBadgeAchievements AS (
    -- Summarize badge achievements for users in the last 5 years
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
    GROUP BY b.UserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.UpVotes AS UserUpVotes,
    U.DownVotes AS UserDownVotes,
    UAS.TotalAnswers,
    UAS.AvgAnswerScore,
    UAS.MaxAnswerScore,
    UAS.UniqueQuestionsAnswered,
    UAS.TotalQuestionScoreOfAnsweredQuestions,
    UAS.TotalQuestionViewCountOfAnsweredQuestions,
    TTPU.TopContributedTags,
    COALESCE(UMA.CloseVoteCount, 0) AS UserCloseVotes,
    COALESCE(UMA.ReopenVoteCount, 0) AS UserReopenVotes,
    COALESCE(UBA.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBA.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBA.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBA.BronzeBadges, 0) AS BronzeBadges,
    RANK() OVER (
        ORDER BY
            UAS.TotalAnswerScore DESC,
            UAS.AvgAnswerScore DESC,
            U.Reputation DESC,
            COALESCE(UBA.GoldBadges, 0) DESC,
            UAS.TotalAnswers DESC,
            COALESCE(UMA.CloseVoteCount, 0) DESC -- Tie-breaker: users who also actively moderate
    ) AS OverallRank
FROM Users U
INNER JOIN UserAnswerSummary UAS ON U.Id = UAS.AnswererUserId
LEFT JOIN TopTagsPerUser TTPU ON U.Id = TTPU.AnswererUserId
LEFT JOIN UserModerationActivity UMA ON U.Id = UMA.UserId
LEFT JOIN UserBadgeAchievements UBA ON U.Id = UBA.UserId
WHERE U.Reputation >= 1000 -- Filter out users with low reputation
ORDER BY OverallRank
LIMIT 100;