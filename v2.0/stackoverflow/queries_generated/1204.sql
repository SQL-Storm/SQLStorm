-- {"query": "1204.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2396} 

WITH UserActivityBadgeStats AS (
    SELECT
        U.Id AS UserId,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Reputation,
        U.Location,
        U.Views AS UserProfileViews,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.Score, 0)) AS SumPostScores,
        AVG(COALESCE(C.Score, 0)) AS AvgCommentScore,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate, C.CreationDate)) AS LatestActivityDate,
        MIN(B.Date) AS FirstBadgeAwardDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.CreationDate, U.LastAccessDate, U.Reputation, U.Location, U.Views, U.UpVotes, U.DownVotes
),
UserQuestionSummaries AS (
    SELECT
        Q.OwnerUserId AS UserId,
        COUNT(DISTINCT Q.Id) AS UserTotalQuestions,
        AVG(Q.Score) AS AvgQuestionScore,
        AVG(Q.ViewCount) AS AvgQuestionViews,
        SUM(COALESCE(Q.FavoriteCount, 0)) AS TotalQuestionFavorites,
        SUM(CASE
                WHEN Q.Tags IS NOT NULL AND EXISTS (
                    SELECT 1
                    FROM UNNEST(string_to_array(substring(Q.Tags, 2, length(Q.Tags)-2), '><')) AS tag
                    WHERE tag IN ('sql', 'database', 'performance', 'query-optimization', 'bigdata')
                ) THEN 1 ELSE 0 END
            ) AS RelevantTagQuestions,
        AVG(EXTRACT(EPOCH FROM (AccAns.CreationDate - Q.CreationDate)) / (60 * 60 * 24)) AS AvgAcceptedAnswerTimeDays,
        SUM(COALESCE(NumDuplicateLinks.Count, 0)) AS TotalLinkedDuplicates,
        SUM(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS QuestionsClosedCount,
        SUM(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS QuestionsReopenedCount,
        MAX(Q.CreationDate) AS LatestQuestionDate
    FROM
        Posts Q
    LEFT JOIN Posts AccAns ON Q.AcceptedAnswerId = AccAns.Id AND AccAns.PostTypeId = 2
    LEFT JOIN (SELECT PostId, COUNT(*) AS Count FROM PostLinks WHERE LinkTypeId = 3 GROUP BY PostId) AS NumDuplicateLinks ON Q.Id = NumDuplicateLinks.PostId
    LEFT JOIN PostHistory PH_Close ON Q.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON Q.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    WHERE
        Q.PostTypeId = 1 -- Only questions
    GROUP BY
        Q.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    UABS.UserCreationDate,
    UABS.LastAccessDate,
    UABS.Location,
    UABS.UserProfileViews,
    UABS.UpVotes,
    UABS.DownVotes,

    -- User activity stats
    COALESCE(UABS.TotalPostsOwned, 0) AS TotalPostsOwned,
    COALESCE(UABS.TotalQuestionsOwned, 0) AS TotalQuestionsOwned,
    COALESCE(UABS.TotalAnswersOwned, 0) AS TotalAnswersOwned,
    COALESCE(UABS.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(UABS.SumPostScores, 0) AS SumPostScores,
    UABS.AvgCommentScore,
    UABS.LatestActivityDate,
    UABS.FirstBadgeAwardDate,
    COALESCE(UABS.GoldBadgesCount, 0) AS GoldBadgesCount,
    COALESCE(UABS.SilverBadgesCount, 0) AS SilverBadgesCount,
    COALESCE(UABS.BronzeBadgesCount, 0) AS BronzeBadgesCount,

    -- Derived user metrics
    EXTRACT(DAY FROM (UABS.LastAccessDate - UABS.UserCreationDate)) AS UserTenureDays,
    COALESCE(UABS.GoldBadgesCount, 0) + COALESCE(UABS.SilverBadgesCount, 0) + COALESCE(UABS.BronzeBadgesCount, 0) AS TotalBadges,

    -- Question specific summaries
    COALESCE(UQS.UserTotalQuestions, 0) AS TotalUserQuestions,
    UQS.AvgQuestionScore,
    UQS.AvgQuestionViews,
    COALESCE(UQS.TotalQuestionFavorites, 0) AS TotalQuestionFavorites,
    COALESCE(UQS.RelevantTagQuestions, 0) AS CountRelevantTagQuestions,
    UQS.AvgAcceptedAnswerTimeDays,
    COALESCE(UQS.TotalLinkedDuplicates, 0) AS TotalDuplicateQuestionsLinked,
    COALESCE(UQS.QuestionsClosedCount, 0) AS TotalQuestionsClosed,
    COALESCE(UQS.QuestionsReopenedCount, 0) AS TotalQuestionsReopened,
    UQS.LatestQuestionDate,

    -- Window Functions
    RANK() OVER (ORDER BY U.Reputation DESC, U.Id ASC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
    AVG(COALESCE(UABS.SumPostScores, 0)) OVER (PARTITION BY COALESCE(UABS.Location, 'Unknown')) AS AvgKarmaInLocationGroup,
    SUM(COALESCE(UABS.TotalQuestionsOwned, 0)) OVER (ORDER BY UABS.UserCreationDate ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeQuestionsOverall,

    -- Correlated Subquery: Find the user's highest voted post ID.
    (
        SELECT P_corr.Id
        FROM Posts P_corr
        WHERE P_corr.OwnerUserId = U.Id
        ORDER BY P_corr.Score DESC, P_corr.CreationDate DESC
        LIMIT 1
    ) AS HighestVotedPostId,

    -- Complicated Predicate/Expression: Is user an 'early adopter' with high reputation?
    CASE
        WHEN U.Reputation > 5000 AND UABS.UserCreationDate < '2012-01-01' AND COALESCE(UABS.TotalQuestionsOwned, 0) >= 10 THEN 'Early High Rep Questioner'
        WHEN U.Reputation > 10000 AND COALESCE(UABS.TotalAnswersOwned, 0) > COALESCE(UABS.TotalQuestionsOwned, 0) * 2 THEN 'Dedicated Answerer'
        WHEN UABS.FirstBadgeAwardDate IS NOT NULL AND UABS.FirstBadgeAwardDate < UABS.UserCreationDate + INTERVAL '7 days' THEN 'Fast Badge Achiever'
        ELSE 'Regular User'
    END AS UserPersonaCategory,

    -- String Expressions
    UPPER(SUBSTRING(COALESCE(U.Location, 'N/A') FROM 1 FOR 5)) AS LocationAbbreviation,
    REPLACE(TRANSLATE(COALESCE(U.DisplayName, ''), ' ', '_'), '.', '') AS CleanDisplayName,
    -- NULL Logic with COALESCE for display
    COALESCE(U.AboutMe, 'No "About Me" provided') AS AboutMeContent,
    COALESCE(U.WebsiteUrl, 'No Website') AS UserWebsite,

    -- More complex calculation: Ratio of answers to questions, handling division by zero
    CASE
        WHEN COALESCE(UABS.TotalQuestionsOwned, 0) > 0
        THEN CAST(COALESCE(UABS.TotalAnswersOwned, 0) AS NUMERIC) / UABS.TotalQuestionsOwned
        ELSE NULL -- Avoid division by zero
    END AS AnswerToQuestionRatio,

    -- Identify users with significant post history but no accepted answers (if they asked questions)
    CASE
        WHEN COALESCE(UABS.TotalQuestionsOwned, 0) > 20 AND COALESCE(UQS.TotalUserQuestions, 0) > 0 AND COALESCE(UQS.AvgAcceptedAnswerTimeDays, 0) = 0 THEN 'Questioner with Unaccepted Answers'
        WHEN U.DownVotes > U.UpVotes * 2 AND U.DownVotes > 100 THEN 'High Downvoter Profile'
        ELSE NULL
    END AS SpecificUserFlag

FROM
    Users U
LEFT JOIN UserActivityBadgeStats UABS ON U.Id = UABS.UserId
LEFT JOIN UserQuestionSummaries UQS ON U.Id = UQS.UserId
WHERE
    U.Reputation > 500
    AND COALESCE(UABS.LatestActivityDate, U.LastAccessDate) >= '2020-01-01' -- Active users recently, handling NULL from CTE
    AND (U.DisplayName IS NOT NULL AND LENGTH(U.DisplayName) > 3)
    AND (
        U.Location LIKE '%United States%' OR
        U.Location LIKE '%Canada%' OR
        U.Location LIKE '%UK%' OR
        U.Location IS NULL
    ) -- Complex NULL logic and string patterns
ORDER BY
    ReputationRank ASC, U.Id ASC
LIMIT 5000;
