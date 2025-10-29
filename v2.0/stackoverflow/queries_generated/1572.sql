-- {"query": "1572.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2375} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViews,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN C.UserId = U.Id THEN C.Score ELSE 0 END), 0) AS TotalCommentScore,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate,
        -- Calculate an 'ActivityScore' based on posts, comments, and votes received
        (COALESCE(COUNT(DISTINCT P.Id) * 0.5, 0) + COALESCE(COUNT(DISTINCT C.Id) * 0.3, 0) + COALESCE(SUM(P.Score) * 0.2, 0)) AS RawActivityScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName
),
PostHistoryInsights AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade, -- Edit Title, Body, Tags
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS TotalCloseReopenVotes, -- Post Closed, Post Reopened
        SUM(CASE WHEN PH.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS InitialBodySubmissions,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (8, 9) THEN 1 ELSE 0 END) AS TotalRollbacks, -- Rollback Body, Tags
        MAX(PH.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
),
TopQuestionTags AS (
    SELECT
        P.OwnerUserId AS UserId,
        SPLIT_PART(UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM P.Tags), '><')), '><', 1) AS TagName,
        COUNT(P.Id) AS TagPostCount,
        SUM(P.Score) AS TagScoreSum,
        MAX(P.CreationDate) AS LastTagPostDate
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.OwnerUserId, SPLIT_PART(UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM P.Tags), '><')), '><', 1)
    HAVING COUNT(P.Id) >= 5 -- Consider only tags with significant contributions
),
RankedTopQuestionTags AS (
    SELECT
        UserId,
        TagName,
        TagPostCount,
        TagScoreSum,
        LastTagPostDate,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC, TagScoreSum DESC, LastTagPostDate DESC) as rn
    FROM TopQuestionTags
)
SELECT
    U.Id AS UserIdentifier,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.Views AS UserProfileViews,
    U.UpVotes AS TotalUpVotesGiven,
    U.DownVotes AS TotalDownVotesGiven,
    COALESCE(UE.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(UE.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(UE.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(UE.TotalPostScore, 0) AS UserTotalPostScore,
    COALESCE(UE.TotalQuestionViews, 0) AS UserTotalQuestionViews,
    COALESCE(UE.TotalCommentsMade, 0) AS UserTotalCommentsMade,
    COALESCE(UE.TotalCommentScore, 0) AS UserTotalCommentScore,
    COALESCE(PHI.TotalEditsMade, 0) AS UserTotalEditsMade,
    COALESCE(PHI.TotalCloseReopenVotes, 0) AS UserTotalCloseReopenVotes,
    COALESCE(UBS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS UserBronzeBadges,
    COALESCE(UBS.TotalBadges, 0) AS UserTotalBadges,
    U.Location,
    U.AboutMe,
    RTQT.TagName AS TopTagByPostCount,
    RTQT.TagPostCount AS TopTagPosts,
    RTQT.TagScoreSum AS TopTagScore,
    -- Window functions
    RANK() OVER (ORDER BY U.Reputation DESC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY COALESCE(UE.RawActivityScore, 0) DESC) AS ActivityDecile,
    AVG(U.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate)) AS AvgReputationInCreationYear,
    -- Correlated Subquery: Avg score of posts by users who commented on this user's posts, excluding the current user's own posts
    (
        SELECT COALESCE(AVG(P_Corr.Score), 0.0)
        FROM Comments C_Corr
        JOIN Posts P_Corr ON C_Corr.PostId = P_Corr.Id
        WHERE C_Corr.UserId IN (
            SELECT C2.UserId
            FROM Comments C2
            WHERE C2.PostId IN (SELECT P3.Id FROM Posts P3 WHERE P3.OwnerUserId = U.Id)
            AND C2.UserId IS NOT NULL
        )
        AND P_Corr.OwnerUserId IS NOT NULL
        AND P_Corr.OwnerUserId != U.Id
    ) AS AvgScoreOfRelatedUserPosts,
    -- Complex Calculation: Engagement to Reputation Ratio (avoid division by zero)
    (
        CASE
            WHEN U.Reputation > 0
            THEN (COALESCE(UE.RawActivityScore, 0) + COALESCE(PHI.TotalEditsMade, 0) * 0.1 + COALESCE(UBS.TotalBadges, 0) * 0.05) / U.Reputation
            ELSE 0.0
        END
    ) AS EngagementReputationRatio,
    -- String expressions:
    LOWER(SUBSTRING(U.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
    LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
    CASE
        WHEN U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Active'
        WHEN U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Recently Active'
        ELSE 'Inactive'
    END AS UserActivityStatus,
    -- NULL logic for display:
    COALESCE(U.Location, 'Unknown') AS UserLocationDisplay,
    -- Complicated predicate/expression for "Key Contributor"
    (
        (U.Reputation > 5000 AND COALESCE(UE.TotalPosts, 0) > 50 AND COALESCE(PHI.TotalEditsMade, 0) > 10)
        OR (COALESCE(UBS.GoldBadges, 0) > 0 AND COALESCE(UE.TotalCommentsMade, 0) > 100)
        OR (U.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years' AND COALESCE(UE.RawActivityScore, 0) > 100)
    ) AS IsKeyContributorCandidate
FROM Users U
LEFT JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN PostHistoryInsights PHI ON U.Id = PHI.UserId
LEFT JOIN UserBadgeStats UBS ON U.Id = UBS.UserId
LEFT JOIN RankedTopQuestionTags RTQT ON U.Id = RTQT.UserId AND RTQT.rn = 1 -- Get the single top tag for the user
WHERE
    U.Reputation IS NOT NULL AND U.Reputation > 1 -- Only consider users with actual reputation
    AND U.DisplayName IS NOT NULL AND LENGTH(U.DisplayName) > 0 -- Ensure valid display name
    AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '5 years' -- Filter for somewhat recent access
    AND (
        (COALESCE(UE.RawActivityScore, 0) > 50) -- Either has a high activity score
        OR (COALESCE(PHI.TotalEditsMade, 0) > 5) -- Or has made significant edits
        OR (COALESCE(UBS.TotalBadges, 0) > 5 AND COALESCE(UBS.SilverBadges, 0) > 0) -- Or has many badges including at least one silver
    )
ORDER BY
    GlobalReputationRank ASC,
    UserTotalPostScore DESC,
    UserTotalEditsMade DESC
LIMIT 5000;
