-- {"query": "1840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3230} 

WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoritesReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LastPostActivity,
        -- Calculate average days since creation for owned posts, using NULLIF to avoid division by zero
        AVG(EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60*60*24)) FILTER (WHERE P.OwnerUserId IS NOT NULL) AS AvgDaysSincePostCreation,
        COUNT(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE NULL END) AS AcceptedAnswersCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS PostScore,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate AS PostLastActivityDate,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.Tags,
        P.AcceptedAnswerId,
        -- Count unique editors based on PostHistory, excluding community user (-1)
        COUNT(DISTINCT CASE WHEN PH.UserId <> -1 THEN PH.UserId ELSE NULL END) AS UniqueEditors,
        -- Count specific history events
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventsCount, -- Post Closed events
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        -- Time to first edit in hours
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN EXTRACT(EPOCH FROM (PH.CreationDate - P.CreationDate)) / (60*60) ELSE NULL END) AS TimeToFirstEditHours,
        -- Detect potential self-answers (answer by same user as question)
        MAX(CASE WHEN P.PostTypeId = 1 AND A.PostTypeId = 2 AND P.OwnerUserId = A.OwnerUserId AND P.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS HasSelfAcceptedAnswer,
        -- Calculate a complex 'stale' or 'relevance' score based on last activity vs creation date relative to its lifetime
        -- This expression aims to give higher scores to popular (score, favorites) and recently active posts,
        -- while penalizing posts that are old and inactive relative to their existence.
        P.Score * (1.0 + COALESCE(P.FavoriteCount, 0) / 10.0) /
        (1.0 + LOG(GREATEST(1, EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60*60*24))))
        * (1.0 + COALESCE(EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / NULLIF(EXTRACT(EPOCH FROM (NOW() - P.CreationDate)), 0), 0))
        AS PostEngagementIndex
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Posts A ON P.AcceptedAnswerId = A.Id -- For checking accepted answers details
    GROUP BY P.Id, P.PostTypeId, P.Score, P.CreationDate, P.LastActivityDate, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.Tags, P.AcceptedAnswerId
),
UserBadgeSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Find the user's "oldest" badge date
        MIN(B.Date) AS FirstBadgeDate,
        -- Correlated subquery: check if user has a specific set of achievement badges
        (SELECT 1 FROM Badges B_sub WHERE B_sub.UserId = U.Id AND B_sub.Name IN ('Enthusiast', 'Mortarboard', 'Socratic') LIMIT 1) AS HasKeyAchievementBadges,
        -- Another correlated subquery: count posts by this user that are linked as duplicates by other posts
        (SELECT COUNT(DISTINCT PL_corr.PostId) FROM PostLinks PL_corr JOIN Posts P_corr ON PL_corr.PostId = P_corr.Id WHERE PL_corr.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = U.Id) AND PL_corr.LinkTypeId = 3) AS DuplicateLinkedPostCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName
),
LinkedPostAnalysis AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicateLinks,
        -- Calculate the average score of posts linked to this post
        AVG(R_P.Score) FILTER (WHERE R_P.Score IS NOT NULL) AS AvgRelatedPostScore,
        -- Window function to find the time difference to the next significant post history event
        LEAD(PH.CreationDate, 1) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate) - PH.CreationDate AS TimeToNextHistoryEvent
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN Posts R_P ON PL.RelatedPostId = R_P.Id -- Related Posts details
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 35, 36) -- Only "significant" history events (creation, edits, close/reopen, migration)
    GROUP BY P.Id, P.CreationDate, PH.CreationDate, P.PostTypeId -- Grouping for LEADD function must include partition key and order by key.
)
-- Main query combining all CTEs
SELECT
    UPS.UserId,
    UPS.DisplayName,
    UPS.Reputation,
    UPS.UserCreationDate,
    UPS.TotalPosts,
    UPS.QuestionsAsked,
    UPS.AnswersGiven,
    UPS.TotalPostScore,
    UPS.TotalCommentsMade,
    UBS.TotalBadges,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    UBS.FirstBadgeDate,
    COALESCE(UBS.HasKeyAchievementBadges, 0) AS HasKeyAchievementBadges,
    UBS.DuplicateLinkedPostCount,
    PHM.PostId,
    PHM.PostTypeId,
    PHM.PostScore,
    PHM.PostCreationDate,
    PHM.PostLastActivityDate,
    PHM.ViewCount AS PostViewCount,
    PHM.AnswerCount AS PostAnswerCount,
    PHM.CommentCount AS PostCommentCount,
    PHM.FavoriteCount AS PostFavoriteCount,
    PHM.UniqueEditors,
    PHM.EditCount AS PostEditCount,
    PHM.CloseEventsCount,
    PHM.LastClosedDate,
    PHM.TimeToFirstEditHours,
    PHM.PostEngagementIndex,
    PHM.Tags AS PostTags,
    LPA.TotalLinkedPosts,
    LPA.TotalDuplicateLinks,
    LPA.AvgRelatedPostScore,
    -- Calculate a "User Engagement Rank" based on reputation, total posts, and badge count
    RANK() OVER (ORDER BY UPS.Reputation DESC, UPS.TotalPosts DESC, UBS.TotalBadges DESC) AS UserEngagementRank,
    -- Calculate a "Post Vitality Score" using a weighted average of post engagement index, related posts, and activity.
    (
        (COALESCE(PHM.PostEngagementIndex, 0) * 0.35) +
        (COALESCE(PHM.PostScore, 0) * 0.20) +
        (COALESCE(PHM.ViewCount, 0) * 0.05 / GREATEST(1, EXTRACT(EPOCH FROM (NOW() - PHM.PostCreationDate)) / (60*60*24*30.0))) + -- View count weighted by age in months
        (COALESCE(LPA.TotalLinkedPosts, 0) * 0.10) +
        (COALESCE(PHM.EditCount, 0) * 0.05) +
        (CASE WHEN PHM.PostTypeId = 1 AND PHM.AcceptedAnswerId IS NOT NULL THEN 0.15 ELSE 0 END) + -- Bonus for accepted answers on questions
        (CASE WHEN PHM.HasSelfAcceptedAnswer = 1 THEN -0.05 ELSE 0 END) + -- Penalty for self-accepted answers
        (CASE WHEN PHM.CloseEventsCount > 0 THEN -0.10 ELSE 0 END) -- Penalty for closed posts
    ) AS PostVitalityScore,
    -- Example of complex NULL/string logic for primary tag extraction
    COALESCE(
        NULLIF(
            TRIM(
                UPPER(
                    SUBSTRING(PHM.Tags, 2, POSITION('>' IN PHM.Tags) - 2)
                )
            ),
            ''
        ),
        'NO_PRIMARY_TAG_FOUND'
    ) AS PrimaryTag,
    -- Correlated subquery to check if any other user's post links to this post as a duplicate
    EXISTS (
        SELECT 1
        FROM PostLinks PL_corr
        WHERE PL_corr.RelatedPostId = PHM.PostId
          AND PL_corr.LinkTypeId = 3
          AND EXISTS (SELECT 1 FROM Posts P_linked WHERE P_linked.Id = PL_corr.PostId AND P_linked.OwnerUserId IS NOT NULL AND P_linked.OwnerUserId <> PHM.OwnerUserId)
        LIMIT 1
    ) AS HasDuplicateLinksFromOtherUsers,
    -- Window function demonstrating moving average of scores for a user's posts
    AVG(PHM.PostScore) OVER (PARTITION BY UPS.UserId ORDER BY PHM.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserPostScoreMovingAvg3Posts,
    -- Set operator example (combining with main query logic for a derived flag)
    -- Categorize users who are 'Elite Gold' (many gold badges, relatively experienced) vs. 'Question Specialists' vs. 'General Contributors'
    CASE
        WHEN UPS.UserId IN (
            (SELECT UserId FROM UserBadgeSummary WHERE GoldBadges >= 3)
            EXCEPT
            (SELECT UserId FROM UserPostStats WHERE QuestionsAsked + AnswersGiven < 20)
        ) THEN 'Elite_Experienced_Gold_User'
        WHEN UPS.UserId IN (SELECT UserId FROM UserPostStats WHERE QuestionsAsked > 50 AND AnswersGiven = 0 AND TotalPosts > 50) THEN 'Question_Specialist_HighVolume'
        ELSE 'General_Contributor_or_New'
    END AS UserCategoryClassification
FROM UserPostStats UPS
LEFT JOIN UserBadgeSummary UBS ON UPS.UserId = UBS.UserId
LEFT JOIN PostHistoricalMetrics PHM ON UPS.UserId = PHM.OwnerUserId
LEFT JOIN LinkedPostAnalysis LPA ON PHM.PostId = LPA.PostId
WHERE UPS.Reputation >= 100 -- Filter for users with some reputation
  AND (PHM.PostTypeId IS NULL OR PHM.PostScore >= -5) -- Exclude very low score posts, or include users without posts
  AND (PHM.PostCreationDate IS NULL OR PHM.PostCreationDate > (NOW() - INTERVAL '3 years')) -- Focus on more recent posts (last 3 years)
  AND (PHM.Tags IS NULL OR PHM.Tags LIKE '%<sql>%' OR PHM.Tags LIKE '%<performance>%' OR PHM.Tags LIKE '%<optimization>%') -- Filter for specific tags if posts exist
  AND (LPA.TimeToNextHistoryEvent IS NULL OR EXTRACT(HOUR FROM LPA.TimeToNextHistoryEvent) < 48) -- Only posts with quick follow-up history (within 48 hours)
  AND (PHM.CommentCount IS NULL OR PHM.CommentCount >= 1) -- Ensure posts have at least one comment, if they exist
ORDER BY PostVitalityScore DESC NULLS LAST, UPS.Reputation DESC, PHM.PostCreationDate DESC
LIMIT 5000;
