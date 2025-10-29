-- {"query": "1750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3074} 
WITH UserEngagementMetrics AS (
    -- Calculates various engagement metrics for each user, including post counts, comment counts, and average post score.
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalQuestionViews,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalFavoriteCounts,
        MAX(P.CreationDate) AS LastPostCreationDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id
),
PostClosureAnalysis AS (
    -- Identifies posts that have been closed and subsequently reopened, calculating the time difference.
    -- It also extracts the close reason and associates events with the post owner.
    SELECT
        PH_Close.PostId,
        PH_Close.UserId AS CloserUserId, -- User who initiated the close event
        PH_Reopen.UserId AS ReopenerUserId, -- User who initiated the reopen event
        PH_Close.CreationDate AS ClosedDate,
        PH_Reopen.CreationDate AS ReopenedDate,
        AGE(PH_Reopen.CreationDate, PH_Close.CreationDate) AS TimeToReopenInterval,
        P.OwnerUserId,
        P.Title,
        COALESCE(CR.Name, 'Unknown Reason') AS CloseReasonName,
        -- Extracts the CloseReasonId from the comment, handling both formats (e.g., '101' or 'ClosedReasonId="101"')
        COALESCE(CAST(SUBSTRING(PH_Close.Comment FROM 'ClosedReasonId="(\d+)"') AS smallint),
                 CAST(PH_Close.Comment AS smallint)) AS CloseReasonId,
        -- Assigns a row number to distinguish multiple close/reopen cycles for the same post,
        -- prioritizing the latest reopened event.
        ROW_NUMBER() OVER (PARTITION BY PH_Close.PostId ORDER BY PH_Reopen.CreationDate DESC, PH_Close.CreationDate DESC) AS rn_post_reopen_event
    FROM PostHistory PH_Close
    INNER JOIN PostHistory PH_Reopen ON PH_Close.PostId = PH_Reopen.PostId
                                       AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
                                       AND PH_Reopen.PostHistoryTypeId = 11 -- Post Reopened
                                       AND PH_Reopen.CreationDate > PH_Close.CreationDate -- Ensure reopen date is after close date
    INNER JOIN Posts P ON PH_Close.PostId = P.Id
    LEFT JOIN CloseReasonTypes CR ON COALESCE(CAST(SUBSTRING(PH_Close.Comment FROM 'ClosedReasonId="(\d+)"') AS smallint),
                                                CAST(PH_Close.Comment AS smallint)) = CR.Id
    WHERE P.OwnerUserId IS NOT NULL
),
UserBadgeMilestones AS (
    -- Aggregates badge counts and finds the earliest date for each badge class (Gold, Silver, Bronze) for users.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MIN(CASE WHEN B.Class = 1 THEN B.Date END) AS FirstGoldBadgeDate,
        MIN(CASE WHEN B.Class = 2 THEN B.Date END) AS FirstSilverBadgeDate,
        MIN(CASE WHEN B.Class = 3 THEN B.Date END) AS FirstBronzeBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
TagPerformanceMetrics AS (
    -- Calculates aggregated performance metrics (views, answers, questions) for each tag across all posts.
    -- This CTE parses the 'Tags' string from posts.
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
        SUM(P.ViewCount) AS TotalTagViews,
        SUM(P.AnswerCount) AS TotalTagAnswers,
        COUNT(P.Id) AS TotalTagQuestions
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))
),
AnalyzedUsers AS (
    -- Main analysis for users who have experienced a question closure and reopening, or have a gold badge.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.AvgPostScore,
        UE.TotalQuestionViews,
        UE.TotalFavoriteCounts,
        B.GoldBadges,
        B.SilverBadges,
        B.BronzeBadges,
        B.FirstGoldBadgeDate,
        -- Correlated subquery: Finds the most viewed tag among the user's own questions.
        (
            SELECT TPM.TagName
            FROM Posts UP
            JOIN LATERAL UNNEST(string_to_array(SUBSTRING(UP.Tags FROM 2 FOR LENGTH(UP.Tags) - 2), '><')) AS user_tag(t) ON TRUE
            JOIN TagPerformanceMetrics TPM ON TRIM(user_tag.t) = TPM.TagName
            WHERE UP.OwnerUserId = U.Id
              AND UP.PostTypeId = 1
              AND UP.Tags IS NOT NULL AND LENGTH(UP.Tags) > 2
            GROUP BY TPM.TagName
            ORDER BY SUM(TPM.TotalTagViews) DESC, SUM(TPM.TotalTagQuestions) DESC
            LIMIT 1
        ) AS TopOwnedTagByViews,
        -- Window function: Divides users into 5 tiers based on their reputation and total posts.
        NTILE(5) OVER (ORDER BY U.Reputation DESC, UE.TotalPosts DESC) AS ReputationActivityTier,
        -- Correlated subquery: Checks if the user has any 'Offensive' votes on their posts.
        EXISTS (
            SELECT 1
            FROM Votes V
            JOIN Posts P_V ON V.PostId = P_V.Id
            WHERE P_V.OwnerUserId = U.Id
              AND V.VoteTypeId = 4 -- Offensive vote type
            LIMIT 1
        ) AS HasOffensiveVotes,
        -- Aggregates metrics from the PostClosureAnalysis for the user.
        COUNT(PCA.PostId) AS TotalClosedReopenedQuestions,
        COALESCE(AVG(EXTRACT(EPOCH FROM PCA.TimeToReopenInterval)) / 3600.0, 0.0) AS AvgHoursToReopenQuestion,
        MAX(PCA.ClosedDate) AS LatestQuestionClosedDate,
        -- Complex calculation: "User Responsiveness Score" - a weighted score combining reputation,
        -- average post score, total badges, and inversely proportional to average reopen time.
        (U.Reputation * COALESCE(UE.AvgPostScore, 0.0) + (COALESCE(B.TotalBadges, 0) * 10.0))
        / NULLIF(1.0 + COALESCE(AVG(EXTRACT(EPOCH FROM PCA.TimeToReopenInterval)) / 3600.0, 0.0), 0.0) AS UserResponsivenessScore,
        -- String expression: Provides a snippet of the 'AboutMe' field, handling NULLs.
        COALESCE(SUBSTRING(U.AboutMe FROM 1 FOR 50), 'No description') AS AboutMeSnippet,
        -- NULL logic: Indicates if a user has a website URL.
        CASE WHEN U.WebsiteUrl IS NULL THEN 'N/A' ELSE 'Provided' END AS HasWebsiteUrl,
        -- Aggregates titles and close reasons of all affected (closed/reopened) questions owned by the user.
        ARRAY_AGG(DISTINCT PCA.Title || ' (' || COALESCE(PCA.CloseReasonName, 'N/A') || ')') FILTER (WHERE PCA.PostId IS NOT NULL) AS AffectedQuestionTitles
    FROM Users U
    LEFT JOIN UserEngagementMetrics UE ON U.Id = UE.UserId
    LEFT JOIN UserBadgeMilestones B ON U.Id = B.UserId
    LEFT JOIN PostClosureAnalysis PCA ON U.Id = PCA.OwnerUserId AND PCA.rn_post_reopen_event = 1 -- Only consider the primary close/reopen event for each post
    WHERE U.Reputation > 100 -- Filters for more established users
      AND UE.TotalPosts > 5 -- Filters for users with some activity
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        UE.TotalPosts, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments, UE.AvgPostScore,
        UE.TotalQuestionViews, UE.TotalFavoriteCounts,
        B.GoldBadges, B.SilverBadges, B.BronzeBadges, B.FirstGoldBadgeDate,
        U.AboutMe, U.WebsiteUrl
    HAVING
        COUNT(PCA.PostId) >= 1 -- Users with at least one closed/reopened question
        OR COALESCE(B.GoldBadges, 0) >= 1 -- Or users with at least one gold badge
),
TopReputationUsers AS (
    -- Identifies a distinct group of users with very high reputation who were not included in the 'AnalyzedUsers' CTE.
    -- This CTE demonstrates the use of a set operator (UNION ALL) later.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalComments,
        UE.AvgPostScore,
        UE.TotalQuestionViews,
        UE.TotalFavoriteCounts,
        B.GoldBadges,
        B.SilverBadges,
        B.BronzeBadges,
        B.FirstGoldBadgeDate,
        NULL::varchar(50) AS TopOwnedTagByViews, -- Not calculated for this set, explicit NULL with type
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationActivityTier,
        EXISTS (
            SELECT 1
            FROM Votes V
            JOIN Posts P_V ON V.PostId = P_V.Id
            WHERE P_V.OwnerUserId = U.Id
              AND V.VoteTypeId = 4
            LIMIT 1
        ) AS HasOffensiveVotes,
        0 AS TotalClosedReopenedQuestions,
        0.0 AS AvgHoursToReopenQuestion,
        NULL::timestamp AS LatestQuestionClosedDate,
        U.Reputation * COALESCE(UE.AvgPostScore, 0.0) AS UserResponsivenessScore, -- Simplified score for this group
        COALESCE(SUBSTRING(U.AboutMe FROM 1 FOR 50), 'No description') AS AboutMeSnippet,
        CASE WHEN U.WebsiteUrl IS NULL THEN 'N/A' ELSE 'Provided' END AS HasWebsiteUrl,
        ARRAY[]::text[] AS AffectedQuestionTitles -- Empty array for this group
    FROM Users U
    LEFT JOIN UserEngagementMetrics UE ON U.Id = UE.UserId
    LEFT JOIN UserBadgeMilestones B ON U.Id = B.UserId
    WHERE U.Reputation > 100000 -- Very high reputation threshold
      AND U.Id NOT IN (SELECT UserId FROM AnalyzedUsers) -- Exclude users already covered by the main analysis
      AND COALESCE(UE.TotalAnswers, 0) > 50 -- Focus on prolific answerers
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        UE.TotalPosts, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments, UE.AvgPostScore,
        UE.TotalQuestionViews, UE.TotalFavoriteCounts,
        B.GoldBadges, B.SilverBadges, B.BronzeBadges, B.FirstGoldBadgeDate,
        U.AboutMe, U.WebsiteUrl
)
-- Final result: Combines the 'AnalyzedUsers' and 'TopReputationUsers' sets using UNION ALL,
-- then orders the combined result.
SELECT *
FROM AnalyzedUsers
UNION ALL
SELECT *
FROM TopReputationUsers
ORDER BY Reputation DESC, UserResponsivenessScore DESC NULLS LAST;