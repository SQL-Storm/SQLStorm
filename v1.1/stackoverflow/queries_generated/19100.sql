-- {"query": "19100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2881} 

WITH UserActivitySummary AS (
    -- Summarize user post/comment activity, including user creation date and location for further analysis.
    -- Handles potential NULLs in activity dates using COALESCE with a very old timestamp.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.CreationDate,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(GREATEST(COALESCE(P.LastActivityDate, '1900-01-01 00:00:00'::timestamp), COALESCE(C.CreationDate, '1900-01-01 00:00:00'::timestamp), U.LastAccessDate)) AS LatestUserActivity,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.CreationDate, U.Location
),
PostStats AS (
    -- Calculate essential statistics for posts, including a "hotness" score and a rank within each post type.
    -- COALESCE is used for nullable score/viewcount to ensure calculations don't result in NULL.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.ViewCount,
        P.Score,
        P.FavoriteCount,
        P.AnswerCount,
        P.ClosedDate,
        P.Title,
        P.Tags,
        COALESCE(P.ViewCount, 0) * COALESCE(P.Score, 0) AS PostEngagementScore,
        CASE
            WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN P.PostTypeId = 1 THEN 'Open Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other Post Type'
        END AS PostStatusCategory,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY COALESCE(P.ViewCount, 0) DESC, COALESCE(P.Score, 0) DESC, P.CreationDate DESC) AS PostTypeViewRank
    FROM Posts P
    WHERE P.CreationDate >= '2020-01-01 00:00:00'::timestamp -- Filter for relatively recent posts to manage data volume
),
UserBadgeActivity AS (
    -- Aggregate badge information for each user, calculate a weighted badge score, and check for specific gold badges.
    -- Includes a correlated subquery to check for gold badges related to 'sql' tag.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 100 WHEN B.Class = 2 THEN 50 WHEN B.Class = 3 THEN 10 ELSE 0 END) AS BadgeScore,
        MAX(B.Date) AS LastBadgeDate,
        EXISTS (
            SELECT 1
            FROM Badges B2
            INNER JOIN Tags T ON B2.Name = T.TagName
            WHERE B2.UserId = B.UserId
              AND B2.Class = 1
              AND LOWER(T.TagName) LIKE '%sql%'
        ) AS HasGoldSqlBadge
    FROM Badges B
    GROUP BY B.UserId
),
ModerationActions AS (
    -- Combine different types of moderation-related events from PostHistory and Votes tables using UNION ALL.
    -- Uses ROW_NUMBER to deduplicate actions for the same PostId and type, keeping the most recent.
    SELECT
        PH.PostId,
        PH.UserId AS ActionTriggerUserId,
        PH.CreationDate AS ActionDate,
        PHT.Name AS ActionType,
        PH.Comment AS ActionComment,
        PH.Text AS ActionDetails,
        'History' AS SourceTable,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34) -- Specific moderation actions

    UNION ALL

    SELECT
        V.PostId,
        V.UserId AS ActionTriggerUserId,
        V.CreationDate AS ActionDate,
        VT.Name AS ActionType,
        NULL AS ActionComment,
        NULL AS ActionDetails,
        'Votes' AS SourceTable,
        ROW_NUMBER() OVER (PARTITION BY V.PostId, V.VoteTypeId ORDER BY V.CreationDate DESC) AS rn
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    WHERE V.VoteTypeId IN (4, 12, 15) -- Offensive, Spam, ModeratorReview flags
),
FilteredModerationActions AS (
    -- Selects only the most recent distinct moderation action per post from the combined set.
    SELECT
        PostId,
        ActionTriggerUserId,
        ActionDate,
        ActionType,
        ActionComment,
        ActionDetails,
        SourceTable
    FROM ModerationActions
    WHERE rn = 1
)
-- Main query to combine all derived information and perform final aggregations and calculations.
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserViews,
    UAS.TotalPosts,
    UAS.TotalComments,
    UAS.LatestUserActivity,
    UAS.QuestionCount,
    UAS.AnswerCount,
    UBA.TotalBadges,
    UBA.BadgeScore,
    UBA.LastBadgeDate,
    UBA.HasGoldSqlBadge,
    SUM(PS.PostEngagementScore) AS TotalPostEngagementScore,
    AVG(PS.PostEngagementScore) AS AvgPostEngagementScore,
    COUNT(DISTINCT CASE WHEN PS.PostStatusCategory = 'Closed Question' THEN PS.PostId END) AS ClosedQuestionsCount,
    COUNT(DISTINCT FMA.PostId) AS TotalModerationActionsOnPosts,
    MAX(FMA.ActionDate) AS LastModerationActionDate,
    -- Complex string expression combining user info with NULL handling and hashing.
    COALESCE(UPPER(SUBSTRING(UAS.DisplayName, 1, 3)), 'UNK') || '-' ||
    LPAD(CAST(UAS.UserId AS TEXT), 7, '0') || '-' ||
    MD5(COALESCE(UAS.Location, 'NO_LOCATION')) AS UserIdentifierHash,
    COALESCE(SUM(CASE WHEN PS.PostTypeId = 1 AND PS.ViewCount > 1000 AND PS.AnswerCount > 5 THEN 1 ELSE 0 END), 0) AS HighEngagementQuestionContributions,
    -- Correlated subquery to count duplicate questions linked by the user's questions.
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
          AND EXISTS (
            SELECT 1
            FROM Posts p_owner
            WHERE p_owner.Id = pl.PostId
              AND p_owner.OwnerUserId = UAS.UserId
              AND p_owner.PostTypeId = 1
          )
    ) AS DuplicatedQuestionsLinkedCount,
    -- Sophisticated NULL logic and conditional expression for categorizing user engagement.
    CASE
        WHEN UAS.Reputation >= 10000 AND UBA.BadgeScore >= 500 AND UAS.LatestUserActivity >= CURRENT_DATE - INTERVAL '90 days' THEN 'Highly Active & Reputable'
        WHEN UAS.Reputation >= 5000 AND UBA.BadgeScore >= 100 AND UAS.LatestUserActivity >= CURRENT_DATE - INTERVAL '180 days' THEN 'Active Contributor'
        WHEN COALESCE(UAS.Reputation, 0) < 100 OR UAS.LatestUserActivity IS NULL OR UBA.TotalBadges IS NULL THEN 'Inactive/Unknown'
        ELSE 'Casual User'
    END AS UserEngagementTier,
    -- Average days to close a question, using a FILTER clause for aggregation and NULL handling for timestamp differences.
    AVG(EXTRACT(EPOCH FROM (PS.ClosedDate - PS.CreationDate)) / 3600 / 24) FILTER (WHERE PS.PostTypeId = 1 AND PS.ClosedDate IS NOT NULL) AS AvgDaysToCloseQuestion,
    -- Aggregates distinct tags from user's questions, filtering out NULLs and using string manipulation.
    STRING_AGG(DISTINCT TRIM(SUBSTRING(tag_val, 2, LENGTH(tag_val)-2)), ', ') FILTER (WHERE PS.PostTypeId = 1 AND PS.Tags IS NOT NULL) AS AssociatedQuestionTagsSummary,
    -- Correlated subquery to find the average reputation of users created around the same time period.
    (
        SELECT AVG(u_inner.Reputation)
        FROM Users u_inner
        WHERE u_inner.CreationDate >= UAS.CreationDate - INTERVAL '1 year'
          AND u_inner.CreationDate <= UAS.CreationDate + INTERVAL '1 year'
    ) AS AvgReputationOfContemporaries,
    -- Correlated subquery to find the maximum engagement score of any single post owned by the user.
    (
        SELECT MAX(ps_inner.PostEngagementScore)
        FROM PostStats ps_inner
        WHERE ps_inner.OwnerUserId = UAS.UserId
    ) AS MaxIndividualPostEngagementScore,
    -- Window function to rank users based on reputation and latest activity.
    RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.LatestUserActivity DESC) AS OverallUserRank
FROM UserActivitySummary UAS
LEFT JOIN UserBadgeActivity UBA ON UAS.UserId = UBA.UserId
LEFT JOIN PostStats PS ON UAS.UserId = PS.OwnerUserId
LEFT JOIN FilteredModerationActions FMA ON UAS.UserId = FMA.ActionTriggerUserId
-- Lateral join to split tags string into individual tags for aggregation (PostgreSQL specific).
LEFT JOIN LATERAL (
    SELECT UNNEST(regexp_split_to_array(SUBSTRING(PS.Tags FROM 2 FOR LENGTH(PS.Tags)-2), '><')) AS tag_val
) AS TagsSplit ON PS.Tags IS NOT NULL AND PS.PostTypeId = 1
WHERE
    UAS.Reputation > 500
    AND (PS.PostEngagementScore IS NULL OR PS.PostEngagementScore > 10) -- Complex predicate with NULL logic
    AND (
        (PS.PostTypeViewRank <= 100 AND PS.PostTypeId = 1) -- Users who contributed to a top-ranked question
        OR UBA.BadgeScore > 200 -- OR have a high badge score
        OR FMA.ActionTriggerUserId IS NOT NULL -- OR participated in any moderation action
    )
    AND UAS.DisplayName IS NOT NULL -- Ensures only users with a display name are considered
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserViews,
    UAS.TotalPosts,
    UAS.TotalComments,
    UAS.LatestUserActivity,
    UAS.QuestionCount,
    UAS.AnswerCount,
    UBA.TotalBadges,
    UBA.BadgeScore,
    UBA.LastBadgeDate,
    UBA.HasGoldSqlBadge,
    UAS.Location,
    UAS.CreationDate -- Required for the correlated subquery AvgReputationOfContemporaries
HAVING
    (COUNT(FMA.PostId) > 0 OR SUM(PS.Score) > 100) -- Users who either moderated or have posts with high total score
    AND MAX(COALESCE(PS.ViewCount, 0)) > 50 -- At least one post with more than 50 views
ORDER BY
    OverallUserRank ASC, TotalPostEngagementScore DESC
LIMIT 100;
