-- {"query": "1372.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2898} 
WITH UserEngagement AS (
    -- CTE 1: Summarize user engagement metrics, account age, and voting activity
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - U.CreationDate)) / (60 * 60 * 24 * 365.25) AS AccountAgeYears, -- Account age in years
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN PA.AcceptedAnswerId = P.Id AND P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersAccepted, -- For answers by this user
        MAX(P.LastActivityDate) AS LastPostActivity,
        AVG(P.Score) AS AvgPostScore,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts PA ON P.Id = PA.AcceptedAnswerId AND P.PostTypeId = 2 -- Link answers to questions where they were accepted
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
BadgeSummary AS (
    -- CTE 2: Summarize badge counts per user, including unique badge names
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT B.Name) AS UniqueBadgeNames
    FROM Badges B
    GROUP BY B.UserId
),
PostTagAnalysis AS (
    -- CTE 3: Analyze posts for tags and calculate an engagement score
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        (
            SELECT SUM(COALESCE(SubC.Score, 0))
            FROM Comments SubC
            WHERE SubC.PostId = P.Id
        ) AS TotalCommentScoreForPost, -- Correlated subquery for total comment score on a post
        (
            SELECT SubPH.Text
            FROM PostHistory SubPH
            WHERE SubPH.PostId = P.Id
              AND SubPH.PostHistoryTypeId = 5 -- Edit Body
              AND SubPH.UserId = P.OwnerUserId -- Edited by owner
            ORDER BY SubPH.CreationDate DESC
            LIMIT 1
        ) AS LastOwnerBodyEdit, -- Correlated subquery for last body edit by owner, if any
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'), 1) AS NumberOfTags, -- PostgreSQL specific tag parsing
        (P.Score * 0.5) + (COALESCE(P.ViewCount, 0) * 0.1) + (COALESCE(P.AnswerCount, 0) * 0.75) + (COALESCE(P.CommentCount, 0) * 0.2) + (COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN P.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2) -- Only questions (1) and answers (2)
),
RankedPosts AS (
    -- CTE 4: Apply window functions and complex post-specific metrics
    SELECT
        PTA.*,
        ROW_NUMBER() OVER (PARTITION BY PTA.OwnerUserId ORDER BY PTA.EngagementScore DESC, PTA.CreationDate DESC) AS PostRankByUser,
        NTILE(5) OVER (ORDER BY PTA.EngagementScore DESC) AS EngagementTier, -- Divide posts into 5 engagement tiers
        LAG(PTA.CreationDate, 1, PTA.CreationDate) OVER (PARTITION BY PTA.OwnerUserId ORDER BY PTA.CreationDate) AS PreviousPostDate,
        (PTA.PostScore - AVG(PTA.PostScore) OVER (PARTITION BY PTA.OwnerUserId)) AS ScoreDeviationFromUserAvg
    FROM PostTagAnalysis PTA
    WHERE PTA.CreationDate >= '2022-01-01' -- Focus on more recent posts for ranking
      AND PTA.PostScore > 0 -- Only consider posts with positive scores
),
ModeratorActivity AS (
    -- CTE 5: Identify posts that underwent moderator actions and aggregate action details
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) AS FirstModeratorActionDate,
        MAX(PH.CreationDate) AS LastModeratorActionDate,
        COUNT(DISTINCT PH.PostHistoryTypeId) AS UniqueModeratorActionTypes,
        STRING_AGG(DISTINCT PHT.Name, '; ') AS ModeratorActionNames, -- Aggregate action names, PostgreSQL specific
        COUNT(PH.Id) AS TotalModeratorActions
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Closed, Reopened, Deleted, Undeleted, Locked, Unlocked, Protected, Unprotected
    GROUP BY PH.PostId
),
FullAnalysisResult AS (
    -- CTE 6: Combines all previous CTEs and applies final categorization and filtering
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.CreationDate,
        UE.AccountAgeYears,
        UE.QuestionsAsked,
        UE.AnswersProvided,
        UE.AnswersAccepted,
        COALESCE(BS.GoldBadges, 0) AS GoldBadges, -- Use COALESCE for users with no badges
        COALESCE(BS.SilverBadges, 0) AS SilverBadges,
        COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
        RP.PostId,
        RP.PostScore,
        RP.PostViewCount,
        RP.EngagementScore,
        RP.PostRankByUser,
        RP.EngagementTier,
        RP.PostStatus,
        RP.TotalCommentScoreForPost,
        RP.LastOwnerBodyEdit,
        RP.NumberOfTags,
        RP.ScoreDeviationFromUserAvg,
        COALESCE(MA.TotalModeratorActions, 0) AS TotalModeratorActions, -- COALESCE for posts with no moderator activity
        MA.ModeratorActionNames,
        CASE
            WHEN UE.Reputation > 10000 AND COALESCE(BS.GoldBadges, 0) >= 1 THEN 'Veteran-Gold-Influencer'
            WHEN UE.AccountAgeYears > 5 AND UE.AnswersAccepted >= 10 THEN 'Experienced-Contributor'
            WHEN RP.EngagementTier <= 2 AND RP.PostTypeId = 1 THEN 'High-Engagement-Question'
            WHEN RP.EngagementTier <= 2 AND RP.PostTypeId = 2 AND RP.PostScore > 50 THEN 'High-Value-Answer'
            ELSE 'General-User-Post'
        END AS UserPostCategory,
        COALESCE(
            UE.DisplayName || ' (' || UE.Reputation || ')',
            'Anonymous User'
        ) AS UserIdentifier, -- String concatenation and NULL logic
        AVG(RP.EngagementScore) OVER (PARTITION BY UE.UserId) AS UserAverageEngagementScore,
        COUNT(RP.PostId) OVER (PARTITION BY UE.UserId) AS UserTotalRankedPosts
    FROM UserEngagement UE
    LEFT JOIN BadgeSummary BS ON UE.UserId = BS.UserId
    JOIN RankedPosts RP ON UE.UserId = RP.OwnerUserId
    LEFT JOIN ModeratorActivity MA ON RP.PostId = MA.PostId
    WHERE
        UE.Reputation > 1000 -- Filter for users with a minimum reputation
        AND UE.TotalPosts > 0
        AND RP.EngagementScore > 10 -- Only posts with significant engagement
        AND (RP.NumberOfTags IS NULL OR RP.NumberOfTags BETWEEN 1 AND 5) -- Questions with 1-5 tags, or non-question posts
        AND (
            RP.PostStatus = 'Answered'
            OR (RP.PostStatus = 'Has Answers' AND RP.PostScore > 20)
            OR (RP.PostStatus = 'Open' AND RP.PostViewCount > 1000)
        )
        AND (
            (UE.AccountAgeYears > 3 AND UE.QuestionsAsked > 5 AND UE.AnswersProvided > 10) -- Experienced users with balanced activity
            OR (UE.UpVotes > 500 AND UE.DownVotes < 50) -- Users with high positive voting ratio
        )
        AND NOT EXISTS ( -- Anti-correlated subquery: Exclude users who have zero silver badges but many gold badges (e.g., highly specialized users who might not answer broadly)
            SELECT 1
            FROM BadgeSummary SubBS
            WHERE SubBS.UserId = UE.UserId AND SubBS.SilverBadges = 0 AND SubBS.GoldBadges >= 3
        )
)
-- Final query: Select 'Veteran-Gold-Influencer' posts,
-- EXCEPT those posts made by users who have asked fewer than 50 questions.
-- This filters for influential users who are also active question askers.
SELECT
    DisplayName,
    Reputation,
    AccountAgeYears,
    QuestionsAsked,
    AnswersProvided,
    AnswersAccepted,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostId,
    PostScore,
    PostViewCount,
    EngagementScore,
    PostRankByUser,
    EngagementTier,
    PostStatus,
    TotalCommentScoreForPost,
    LastOwnerBodyEdit,
    NumberOfTags,
    ScoreDeviationFromUserAvg,
    TotalModeratorActions,
    ModeratorActionNames,
    UserPostCategory,
    UserIdentifier,
    UserAverageEngagementScore,
    UserTotalRankedPosts
FROM FullAnalysisResult
WHERE UserPostCategory = 'Veteran-Gold-Influencer'
EXCEPT
SELECT
    DisplayName,
    Reputation,
    AccountAgeYears,
    QuestionsAsked,
    AnswersProvided,
    AnswersAccepted,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostId,
    PostScore,
    PostViewCount,
    EngagementScore,
    PostRankByUser,
    EngagementTier,
    PostStatus,
    TotalCommentScoreForPost,
    LastOwnerBodyEdit,
    NumberOfTags,
    ScoreDeviationFromUserAvg,
    TotalModeratorActions,
    ModeratorActionNames,
    UserPostCategory,
    UserIdentifier,
    UserAverageEngagementScore,
    UserTotalRankedPosts
FROM FullAnalysisResult
WHERE QuestionsAsked < 50
ORDER BY
    Reputation DESC,
    EngagementScore DESC,
    DisplayName
LIMIT 1000;