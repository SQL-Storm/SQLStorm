-- {"query": "1512.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2555} 

WITH UserActivitySummary AS (
    -- Summarizes user-specific activity, including post counts, comment counts, and votes given/received.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        MAX(U.LastAccessDate) AS LastUserAccess,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edits made by the user
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Votes received on user's posts
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailsBase AS (
    -- Provides detailed metrics per post, including first answer date, distinct editors, and window functions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Tags,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 50) || '...') AS PostTitlePreview,
        LENGTH(P.Body) AS BodyLength,
        -- Window function: Rank posts by score within each user's contributions
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS UserPostRank,
        -- Window function: Calculate average score of previous 5 posts by the user (rolling average)
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScore,
        -- Correlated subquery: Date of the first answer for a question (only applicable for questions)
        (
            SELECT MIN(A.CreationDate)
            FROM Posts A
            WHERE A.ParentId = P.Id
            AND A.PostTypeId = 2
        ) AS FirstAnswerDate,
        -- Correlated subquery: Count of distinct non-owner editors for the post
        (
            SELECT COUNT(DISTINCT ph_inner.UserId)
            FROM PostHistory ph_inner
            WHERE ph_inner.PostId = P.Id
            AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
            AND ph_inner.UserId IS NOT NULL
            AND ph_inner.UserId != P.OwnerUserId
        ) AS DistinctEditorCount
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Only Questions and Answers
),
PostProblematicFlags AS (
    -- Identifies posts that are either deleted or linked as duplicates, using a set operator (UNION ALL).
    -- Using UNION ALL to potentially count multiple problematic flags per post if they exist,
    -- but distinct count later ensures each post is only counted once for "problematic".
    SELECT PostId
    FROM PostHistory
    WHERE PostHistoryTypeId = 12 -- Post Deleted
    UNION ALL
    SELECT PostId
    FROM PostLinks
    WHERE LinkTypeId = 3 -- Linked as Duplicate
),
PostClosureDetails AS (
    -- Aggregates specific details about post closures, including off-topic counts.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalCloseEvents,
        SUM(CASE WHEN COALESCE(PH.Comment, '') LIKE '%102%' THEN 1 ELSE 0 END) AS OffTopicCloseCount, -- 102 is 'Off-topic' close reason
        MAX(PH.CreationDate) AS LastCloseDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) -- All relevant close event types
    GROUP BY PH.PostId
),
FrequentBadgesPerUser AS (
    -- Counts specific badge classes for each user.
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserPostAggregates AS (
    -- Aggregates various post-related metrics per user from the detailed post CTEs.
    SELECT
        PDB.OwnerUserId AS UserId,
        COUNT(PDB.PostId) AS TotalUserPosts,
        COUNT(PDB.PostId) FILTER (WHERE PDB.PostTypeId = 1) AS UserQuestions,
        COUNT(PDB.PostId) FILTER (WHERE PDB.PostTypeId = 2) AS UserAnswers,
        COUNT(PDB.PostId) FILTER (WHERE PDB.PostTypeId = 1 AND PDB.ClosedDate IS NOT NULL) AS UserClosedQuestions,
        COUNT(DISTINCT PPF.PostId) AS UserProblematicPosts, -- Count distinct to avoid duplicates if a post is both deleted and a duplicate
        COALESCE(AVG(PDB.PostScore) FILTER (WHERE PDB.PostTypeId = 1), 0) AS AvgUserQuestionScore,
        COALESCE(AVG(PDB.PostScore) FILTER (WHERE PDB.PostTypeId = 2), 0) AS AvgUserAnswerScore,
        COALESCE(AVG(PDB.DistinctEditorCount) FILTER (WHERE PDB.PostTypeId IN (1,2)), 0) AS AvgDistinctEditorsPerPost,
        COALESCE(AVG(EXTRACT(EPOCH FROM (PDB.FirstAnswerDate - PDB.PostCreationDate))) / (60 * 60 * 24), 0) AS AvgDaysToFirstAnswerForQuestions,
        COALESCE(AVG(EXTRACT(EPOCH FROM (PDB.LastEditDate - PDB.PostCreationDate))) / (60 * 60 * 24), 0) AS AvgDaysToLastEdit,
        MAX(PDB.RollingAvgUserPostScore) AS MaxRollingAvgPostScore, -- Maximum of rolling average as a summary metric
        STRING_AGG(
            CASE WHEN PDB.UserPostRank <= 3
                 THEN PDB.PostTitlePreview || ' [S:' || PDB.PostScore || ' V:' || PDB.ViewCount || ']'
                 ELSE NULL
            END, '; ' ORDER BY PDB.UserPostRank) FILTER (WHERE PDB.UserPostRank <= 3) AS Top3PostsSummary,
        SUM(COALESCE(PCD.OffTopicCloseCount, 0)) AS TotalOffTopicClosures
    FROM PostDetailsBase PDB
    LEFT JOIN PostProblematicFlags PPF ON PDB.PostId = PPF.PostId
    LEFT JOIN PostClosureDetails PCD ON PDB.PostId = PCD.PostId
    GROUP BY PDB.OwnerUserId
)
SELECT
    UAS.UserId,
    COALESCE(UAS.DisplayName, 'Unknown User (' || SUBSTRING(U.EmailHash, 1, 8) || ')') AS UserDisplayIdentifier,
    UAS.Reputation,
    U.CreationDate AS UserRegistrationDate,
    UAS.LastUserAccess,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalCommentsMade,
    UAS.TotalEditsMade,
    UAS.TotalUpvotesReceived,
    UAS.TotalDownvotesReceived,
    FBP.GoldBadges,
    FBP.SilverBadges,
    FBP.BronzeBadges,
    FBP.TotalBadges,
    UPA.TotalUserPosts,
    UPA.UserClosedQuestions,
    UPA.UserProblematicPosts,
    UPA.AvgUserQuestionScore,
    UPA.AvgUserAnswerScore,
    UPA.AvgDistinctEditorsPerPost,
    UPA.AvgDaysToFirstAnswerForQuestions,
    UPA.AvgDaysToLastEdit,
    UPA.Top3PostsSummary,
    UPA.TotalOffTopicClosures,
    -- User's self-description analysis based on length, using NULL logic
    CASE
        WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 500 THEN 'Verbose'
        WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) BETWEEN 100 AND 500 THEN 'Moderate'
        WHEN U.AboutMe IS NOT NULL THEN 'Brief'
        ELSE 'None Provided'
    END AS AboutMeLengthCategory,
    -- String expression: Cleaned and normalized location, handling NULLs and replacing commas
    LOWER(TRIM(REPLACE(COALESCE(U.Location, 'Unspecified Location'), ',', ''))) AS NormalizedUserLocation,
    -- Boolean flag for users who have a high volume of problematic posts (e.g., deleted or duplicates)
    (UPA.TotalUserPosts > 10 AND UPA.UserProblematicPosts * 100.0 / NULLIF(UPA.TotalUserPosts, 0) > 20) AS HasHighProblematicPostRate,
    -- Calculate closure rate for user's questions, handling division by zero using NULLIF
    ROUND(
        (UPA.UserClosedQuestions * 100.0) / NULLIF(UPA.UserQuestions, 0),
        2
    ) AS QuestionClosureRatePercentage,
    -- User engagement category based on reputation and activity
    CASE
        WHEN UAS.Reputation >= 10000 AND UPA.UserQuestions >= 50 AND UPA.UserAnswers >= 100 THEN 'Veteran Expert'
        WHEN UAS.