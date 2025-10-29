-- {"query": "1143.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3287} 

WITH UserEngagementSummary AS (
    -- Summarizes user activity including post counts, scores, and comment engagement
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGivenBySelf,
        U.DownVotes AS TotalDownVotesGivenBySelf,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsOwned,
        COALESCE(SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswers,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViewsOnOwned,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreEarnedOnOwned,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMadeBySelf,
        -- Calculate average score per post owned by the user, handling division by zero
        CAST(COALESCE(SUM(P.Score), 0) AS decimal) / NULLIF(COUNT(DISTINCT P.Id), 0) AS AvgPostScorePerOwnedPost,
        -- Calculate ratio of comments made by user relative to their total posts
        CAST(COALESCE(COUNT(DISTINCT C.Id), 0) AS decimal) / NULLIF(COUNT(DISTINCT P.Id), 0) AS CommentToPostRatio
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostHistoricalAnalysis AS (
    -- Analyzes post-level activity, including edits, closures, and community ownership
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.CommentCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        P.Tags,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Title,
        -- Calculate time difference in hours between post creation and its last activity
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursUntilLastActivity,
        -- Checks if the post has been edited by a user other than the original owner
        EXISTS (
            SELECT 1
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
              AND PH.UserId IS NOT NULL
              AND PH.UserId != P.OwnerUserId
              AND PH.CreationDate > P.CreationDate -- Ensure it's an actual edit, not initial creation event
        ) AS WasEditedByOtherUser,
        -- Counts distinct other users who have edited the post
        (SELECT COUNT(DISTINCT PH_inner.UserId)
         FROM PostHistory PH_inner
         WHERE PH_inner.PostId = P.Id
           AND PH_inner.PostHistoryTypeId IN (4,5,6)
           AND PH_inner.UserId IS NOT NULL
           AND PH_inner.UserId != P.OwnerUserId) AS DistinctOtherEditorsCount,
        P.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned,
        -- Calculate the time difference (in days) between this post's creation and the owner's previous post's activity date
        EXTRACT(EPOCH FROM (P.CreationDate - LAG(P.LastActivityDate, 1, P.CreationDate)
            OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate))) / 86400.0 AS DaysSincePreviousPostActivity
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
UserBadgeMetrics AS (
    -- Aggregates badge counts for each user
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
PostCloseReasons AS (
    -- Identifies the latest close reason for each post that has been closed
    SELECT
        PH.PostId,
        MAX(PH.CreationDate) AS LastClosedDate,
        -- Uses a correlated subquery to fetch the CloseReasonName based on the PostHistory's comment field
        (SELECT CR.Name FROM CloseReasonTypes CR WHERE CR.Id = CAST(PH_inner.Comment AS smallint) LIMIT 1) AS CloseReasonName
    FROM PostHistory PH
    JOIN PostHistory PH_inner ON PH.Id = PH_inner.Id AND PH_inner.PostHistoryTypeId = 10 -- Only consider 'Post Closed' history entries
    WHERE PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId, PH_inner.Comment
),
TopUserQuestionDetails AS (
    -- Selects the highest scoring question for each user to represent their question quality
    SELECT
        PHA.PostId AS QuestionId,
        PHA.OwnerUserId AS QuestionOwnerId,
        PHA.Title AS QuestionTitle,
        PHA.CreationDate AS QuestionCreationDate,
        PHA.Score AS QuestionScore,
        PHA.ViewCount AS QuestionViewCount,
        PHA.FavoriteCount AS QuestionFavoriteCount,
        PHA.AnswerCount AS QuestionAnswerCount,
        PHA.CommentCount AS QuestionCommentCount,
        PHA.Tags AS QuestionTags,
        PHA.ClosedDate AS QuestionClosedDate,
        PCR.LastClosedDate AS QuestionLastClosedDate,
        PCR.CloseReasonName AS QuestionCloseReason,
        PHA.HoursUntilLastActivity,
        PHA.WasEditedByOtherUser,
        PHA.DistinctOtherEditorsCount,
        PHA.IsCommunityOwned,
        -- Correlated subqueries to find details of the highest scoring answer for this question
        (SELECT A.Id FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerId,
        (SELECT A.Score FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerScore,
        (SELECT A.OwnerUserId FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerOwnerUserId,
        -- Calculates time in hours from creation to last edit, using COALESCE for unedited posts
        EXTRACT(EPOCH FROM (COALESCE(PHA.LastEditDate, PHA.CreationDate) - PHA.CreationDate)) / 3600.0 AS HoursToLastEdit,
        -- Ranks questions by score within each user, used to pick the top question
        RANK() OVER (PARTITION BY PHA.OwnerUserId ORDER BY PHA.Score DESC, PHA.CreationDate DESC) AS QuestionScoreRankByUser
    FROM PostHistoricalAnalysis PHA
    LEFT JOIN PostCloseReasons PCR ON PHA.PostId = PCR.PostId
    WHERE PHA.PostTypeId = 1 -- Only consider questions
)
-- Main query: Combines all processed data to provide a comprehensive user and post analysis
SELECT
    UES.UserId,
    UES.DisplayName AS UserDisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    -- Calculate days since last access relative to the current timestamp
    EXTRACT(DAY FROM (NOW() - UES.LastAccessDate)) AS DaysSinceLastAccess,
    UES.TotalUpVotesGivenBySelf,
    UES.TotalDownVotesGivenBySelf,
    UES.QuestionsPosted,
    UES.AnswersPosted,
    UES.TotalPostsOwned,
    UES.QuestionsWithAcceptedAnswers,
    UES.TotalQuestionViewsOnOwned,
    UES.TotalPostScoreEarnedOnOwned,
    UES.TotalCommentsMadeBySelf,
    UES.AvgPostScorePerOwnedPost,
    UES.CommentToPostRatio,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.TotalBadges,
    UBM.LastBadgeAwardDate,
    -- Average days between sequential posts by the user, aggregated from PostHistoricalAnalysis
    (SELECT AVG(PHA2.DaysSincePreviousPostActivity)
     FROM PostHistoricalAnalysis PHA2
     WHERE PHA2.OwnerUserId = UES.UserId AND PHA2.PostTypeId IN (1,2)
     GROUP BY PHA2.OwnerUserId) AS AvgDaysBetweenPosts,
    TQ.QuestionId,
    TQ.QuestionTitle,
    TQ.QuestionCreationDate,
    TQ.QuestionScore,
    TQ.QuestionViewCount,
    TQ.QuestionFavoriteCount,
    TQ.QuestionAnswerCount,
    TQ.QuestionCommentCount,
    TQ.QuestionTags,
    TQ.QuestionLastClosedDate,
    TQ.QuestionCloseReason,
    TQ.HoursUntilLastActivity,
    TQ.WasEditedByOtherUser,
    TQ.DistinctOtherEditorsCount,
    TQ.IsCommunityOwned,
    TQ.TopAnswerId,
    TQ.TopAnswerScore,
    TQ.TopAnswerOwnerUserId,
    TQ.HoursToLastEdit,
    TQ.QuestionScoreRankByUser,
    -- Overall rank of the user based on reputation across all users
    RANK() OVER (ORDER BY UES.Reputation DESC, UES.UserId ASC) AS UserReputationRank,
    -- Ratio of answers to total posts, using NULLIF for safety
    CAST(UES.AnswersPosted AS decimal) / NULLIF(UES.TotalPostsOwned, 0) AS AnswerToTotalPostRatio,
    -- Extracts the primary location guess from the user's location string, defaulting if NULL
    COALESCE(
        SPLIT_PART(U_main.Location, ',', 1), -- Get the first part (e.g., city/state)
        'Unknown Location'
    ) AS PrimaryLocationGuess,
    CASE WHEN U_main.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(U_main.WebsiteUrl)) > 0 THEN TRUE ELSE FALSE END AS HasWebsiteProfile,
    TMPT.TagName AS MostPopularTagBySelf,
    TMPT.QuestionCountWithTag AS MostPopularTagQuestionCountBySelf,
    -- Checks if the user's top question has any related duplicate links
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = TQ.QuestionId
          AND PL.LinkTypeId = 3 -- LinkType 3 represents a 'Duplicate' link
    ) AS TopQuestionHasDuplicateLinks,
    -- Counts complex questions owned by the user based on body length and presence of code blocks
    (SELECT
        SUM(CASE WHEN LENGTH(P_body.Body) > 1500 THEN 1 ELSE 0 END) + -- Long body
        SUM(CASE WHEN P_body.Body ILIKE '%<code>%</code>%' THEN 1 ELSE 0 END) -- Contains code block
     FROM Posts P_body WHERE P_body.OwnerUserId = UES.UserId AND P_body.PostTypeId = 1) AS ComplexQuestionsCountOwned,
    -- Calculates a custom weighted score for user engagement and contribution
    (UES.Reputation * 0.4) + (UES.TotalPostScoreEarnedOnOwned * 0.25) + (UBM.TotalBadges * 0.2) + (UES.QuestionsPosted * 0.1) + (UES.AnswersPosted * 0.05) AS UserWeightedScore
FROM UserEngagementSummary UES
LEFT JOIN UserBadgeMetrics UBM ON UES.UserId = UBM.UserId
LEFT JOIN TopUserQuestionDetails TQ ON UES.UserId = TQ.QuestionOwnerId AND TQ.QuestionScoreRankByUser = 1 -- Selects the single highest-scoring question per user
LEFT JOIN Users U_main ON UES.UserId = U_main.Id -- Re-join to original Users table for additional fields not in UES
LEFT JOIN (
    -- Subquery to find the most popular tag for each user based on their questions
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(*) AS QuestionCountWithTag,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(*) DESC, TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) ASC) AS rn
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY P.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))
) TMPT ON UES.UserId = TMPT.UserId AND TMPT.rn = 1 -- Filters for the top tag (rn=1) for each user
WHERE UES.Reputation > 500 -- Filters for users with substantial reputation
  AND UES.TotalPostsOwned > 10 -- Filters for users with a minimum number of posts
ORDER BY UserWeightedScore DESC, UES.UserId ASC
LIMIT 1000;
