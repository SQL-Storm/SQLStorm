-- {"query": "1432.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2983} 

WITH UserActivitySummary AS (
    -- Summarizes core user activity metrics, including reputation growth over initial period
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(P.Score) AS OverallPostScoreReceived,
        AVG(P.Score) AS AvgPostScoreReceived,
        -- Calculate reputation growth within the first 3 months compared to initial state
        U.Reputation - COALESCE((
            SELECT SUM(P_Initial.Score)
            FROM Posts P_Initial
            WHERE P_Initial.OwnerUserId = U.Id
            AND P_Initial.CreationDate < U.CreationDate + INTERVAL '3 months'
        ), 0) AS ReputationGrowthAfterInitialPeriod
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > 10000
    AND U.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionPerformanceMetrics AS (
    -- Gathers performance details for questions, including advanced ranking and subquery checks
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.Title,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.ClosedDate,
        COALESCE(Q.LastEditDate, Q.CreationDate) AS EffectiveLastEditDate,
        -- Parses tags into an array
        STRING_TO_ARRAY(SUBSTRING(Q.Tags, 2, LENGTH(Q.Tags) - 2), '><') AS TagsArray,
        -- Count unique users who answered this question
        (
            SELECT COUNT(DISTINCT A_sub.OwnerUserId)
            FROM Posts A_sub
            WHERE A_sub.ParentId = Q.Id AND A_sub.PostTypeId = 2
        ) AS UniqueAnswerersCount,
        -- Window function: Rank questions by score within each owner's questions
        RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS QuestionScoreRankByOwner,
        -- Window function: Calculate the moving average of question scores by the same user
        AVG(Q.Score) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgQuestionScore,
        -- Correlated subquery: Find the highest score of an accepted answer for this question
        (
            SELECT MAX(PA.Score)
            FROM Posts PA
            WHERE PA.Id = Q.AcceptedAnswerId
        ) AS AcceptedAnswerMaxScore,
        CASE
            WHEN Q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN Q.AnswerCount = 0 AND Q.CreationDate < CURRENT_DATE - INTERVAL '1 year' THEN 'StaleNoAnswers'
            WHEN Q.FavoriteCount > 50 AND Q.AcceptedAnswerId IS NULL AND Q.AnswerCount > 0 THEN 'PopularUnaccepted'
            ELSE 'ActiveOrUncategorized'
        END AS QuestionCategoryBasedOnStatus
    FROM Posts Q
    WHERE Q.PostTypeId = 1
    AND Q.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    AND Q.OwnerUserId IS NOT NULL -- Exclude community wiki or deleted owner posts
),
AnswerDetails AS (
    -- Focuses on answers, including acceptance status and comparison to previous answers
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        A.CommentCount AS AnswerCommentCount,
        Q.Title AS ParentQuestionTitle,
        Q.ViewCount AS ParentQuestionViewCount,
        -- Check if this specific answer was accepted for its parent question
        CASE WHEN Q.AcceptedAnswerId = A.Id THEN TRUE ELSE FALSE END AS IsAcceptedByQuestioner,
        -- Window function: Compare current answer's score with the immediately previous one by the same user
        LAG(A.Score, 1, 0) OVER (PARTITION BY A.OwnerUserId ORDER BY A.CreationDate) AS PreviousAnswerScoreByUser,
        -- Window function: Rank answers within a specific question by score
        DENSE_RANK() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate) AS AnswerRankInQuestion
    FROM Posts A
    JOIN Posts Q ON A.ParentId = Q.Id
    WHERE A.PostTypeId = 2
    AND A.OwnerUserId IS NOT NULL
    AND A.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
),
ModerationEventLog AS (
    -- Tracks post moderation history, like closes and reopens, and associated reasons
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.UserId AS ModeratorOrVoterUserId,
        PHT.Name AS HistoryEventTypeName,
        COALESCE(CR.Name, 'N/A') AS CloseReasonName,
        -- Calculate time difference from the previous event on the same post
        EXTRACT(HOUR FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) AS HoursSincePreviousEvent,
        -- Count how many times a post has been closed by this type of event
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalCloseEventsForPost,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalReopenEventsForPost
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CR.Id::text -- Assuming Comment contains CloseReasonId for type 10
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13) -- Post Closed, Reopened, Deleted, Undeleted
),
TagPerformanceBreakdown AS (
    -- Analyzes performance and popularity of individual tags
    SELECT
        TagName_Unnested AS TagName,
        COUNT(DISTINCT QPM.QuestionId) AS QuestionsWithTagCount,
        SUM(QPM.QuestionScore) AS TotalTagScore,
        AVG(QPM.QuestionScore) AS AverageTagScore,
        MAX(QPM.ViewCount) AS MaxViewCountForTag,
        -- Categorize tags into popularity buckets based on question count
        NTILE(4) OVER (ORDER BY COUNT(DISTINCT QPM.QuestionId) DESC) AS TagPopularityQuartile,
        -- Correlated subquery: Find the highest accepted answer score for any question with this tag
        (
            SELECT MAX(AD_sub.AnswerScore)
            FROM AnswerDetails AD_sub
            JOIN QuestionPerformanceMetrics QPM_sub ON AD_sub.QuestionId = QPM_sub.QuestionId
            CROSS JOIN UNNEST(QPM_sub.TagsArray) AS TagName_Sub_Unnested
            WHERE TagName_Sub_Unnested = TagName_Unnested AND AD_sub.IsAcceptedByQuestioner = TRUE
        ) AS MaxAcceptedAnswerScoreForTag
    FROM QuestionPerformanceMetrics QPM
    CROSS JOIN UNNEST(QPM.TagsArray) AS TagName_Unnested -- Unnesting the tags array for per-tag analysis
    GROUP BY TagName_Unnested
    HAVING COUNT(DISTINCT QPM.QuestionId) > 25 AND AVG(QPM.QuestionScore) > 5
)
-- Main query to combine insights from all CTEs
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPostsCreated,
    UAS.TotalQuestionsAsked,
    UAS.TotalAnswersPosted,
    UAS.ReputationGrowthAfterInitialPeriod,
    QPM.QuestionId,
    QPM.Title AS QuestionTitle,
    QPM.QuestionCreationDate,
    QPM.QuestionScore,
    QPM.ViewCount AS QuestionViewCount,
    QPM.QuestionCategoryBasedOnStatus,
    QPM.QuestionScoreRankByOwner,
    QPM.RollingAvgQuestionScore,
    QPM.AcceptedAnswerMaxScore,
    AD.AnswerId,
    AD.AnswerScore,
    AD.IsAcceptedByQuestioner,
    AD.PreviousAnswerScoreByUser,
    AD.AnswerRankInQuestion,
    COALESCE(TPB.TagName, 'NoPrimaryTag') AS PrimaryTag, -- Use COALESCE for tags if not present
    TPB.QuestionsWithTagCount AS PrimaryTagQuestionCount,
    TPB.AverageTagScore AS PrimaryTagAvgScore,
    TPB.TagPopularityQuartile,
    MO.HistoryEventTypeName AS LastModerationAction,
    MO.CloseReasonName AS LastCloseReason,
    MO.HoursSincePreviousEvent AS HoursBetweenModerationEvents,
    MO.TotalCloseEventsForPost,
    -- Complicated calculation: Ratio of Accepted Answers to Total Answers by a user in the last year, capped at 1.0
    NULLIF(CAST(COUNT(CASE WHEN AD_Recent.IsAcceptedByQuestioner THEN 1 END) AS DECIMAL) /
           NULLIF(COUNT(DISTINCT AD_Recent.AnswerId), 0), 0) AS UserRecentAcceptedAnswerRatio
FROM UserActivitySummary UAS
LEFT JOIN QuestionPerformanceMetrics QPM ON UAS.UserId = QPM.OwnerUserId
LEFT JOIN AnswerDetails AD ON QPM.QuestionId = AD.QuestionId AND UAS.UserId = AD.AnswerOwnerUserId
-- Attempt to link to the "primary" tag (first tag in the array) for each question
LEFT JOIN LATERAL (SELECT QPM.TagsArray[1] AS TagName_From_Array) PrimaryTagExtractor ON TRUE
LEFT JOIN TagPerformanceBreakdown TPB ON PrimaryTagExtractor.TagName_From_Array = TPB.TagName
LEFT JOIN ModerationEventLog MO ON QPM.QuestionId = MO.PostId
-- Subquery for user's recent accepted answer ratio
LEFT JOIN AnswerDetails AD_Recent ON UAS.UserId = AD_Recent.AnswerOwnerUserId
    AND AD_Recent.AnswerCreationDate >= CURRENT_DATE - INTERVAL '1 year'
WHERE
    UAS.TotalQuestionsAsked > 0 OR UAS.TotalAnswersPosted > 0 -- Ensure active contributors
    AND (
        QPM.QuestionScore >= 5
        OR AD.AnswerScore >= 3
        OR MO.HistoryEventTypeName IN ('Post Closed', 'Post Reopened')
    )
    AND QPM.Title LIKE '%performance%' OR QPM.Title LIKE '%optimization%' OR PrimaryTagExtractor.TagName_From_Array IN ('performance', 'sql-optimization', 'big-data')
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.TotalPostsCreated, UAS.TotalQuestionsAsked, UAS.TotalAnswersPosted, UAS.ReputationGrowthAfterInitialPeriod,
    QPM.QuestionId, QPM.Title, QPM.QuestionCreationDate, QPM.QuestionScore, QPM.ViewCount, QPM.QuestionCategoryBasedOnStatus, QPM.QuestionScoreRankByOwner,
    QPM.RollingAvgQuestionScore, QPM.AcceptedAnswerMaxScore, AD.AnswerId, AD.AnswerScore, AD.IsAcceptedByQuestioner, AD.PreviousAnswerScoreByUser, AD.AnswerRankInQuestion,
    TPB.TagName, TPB.QuestionsWithTagCount, TPB.AverageTagScore, TPB.TagPopularityQuartile,
    MO.HistoryEventTypeName, MO.CloseReasonName, MO.HoursSincePreviousEvent, MO.TotalCloseEventsForPost
HAVING
    UAS.ReputationGrowthAfterInitialPeriod > 500
ORDER BY
    UAS.Reputation DESC,
    UAS.LastAccessDate DESC,
    QPM.QuestionCreationDate DESC
LIMIT 5000;
