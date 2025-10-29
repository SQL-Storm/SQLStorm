-- {"query": "1870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3362} 

WITH UserBaseWithBadgeInfo AS (
    -- Gathers essential user information and pre-aggregates badge data, handling users with no badges.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.Location,
        U.AboutMe,
        U.Views,
        COALESCE(B.TotalBadges, 0) AS TotalBadges,
        COALESCE(B.GoldBadges, 0) AS GoldBadges,
        COALESCE(B.SilverBadges, 0) AS SilverBadges,
        COALESCE(B.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(B.TagBasedBadges, 0) AS TagBasedBadges
    FROM Users AS U
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(Id) AS TotalBadges,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            SUM(CASE WHEN TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
        FROM Badges
        GROUP BY UserId
    ) AS B ON U.Id = B.UserId
    WHERE U.Reputation >= 100 -- Filter for users with a minimum reputation
      AND U.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1' YEAR) -- Only consider users active in the last year
),
UserEngagementSummary AS (
    -- Aggregates post, comment, and vote data for each user, building on UserBaseWithBadgeInfo.
    SELECT
        UB.UserId,
        UB.DisplayName,
        UB.Reputation,
        UB.UserCreationDate,
        UB.LastAccessDate,
        UB.UserUpVotesGiven,
        UB.UserDownVotesGiven,
        UB.Location,
        UB.AboutMe,
        UB.Views,
        UB.TotalBadges,
        UB.GoldBadges,
        UB.SilverBadges,
        UB.BronzeBadges,
        UB.TagBasedBadges,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotesOnPosts, -- Upvotes received on user's posts
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotesOnPosts -- Downvotes received on user's posts
    FROM UserBaseWithBadgeInfo AS UB
    LEFT JOIN Posts AS P ON UB.UserId = P.OwnerUserId
    LEFT JOIN Comments AS C ON UB.UserId = C.UserId
    LEFT JOIN Votes AS PV ON P.Id = PV.PostId -- Joins votes to posts to count received votes
    WHERE P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2' YEAR) OR C.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2' YEAR) -- Focus on recent activity
    GROUP BY
        UB.UserId, UB.DisplayName, UB.Reputation, UB.UserCreationDate, UB.LastAccessDate,
        UB.UserUpVotesGiven, UB.DownVotes, UB.Location, UB.AboutMe, UB.Views,
        UB.TotalBadges, UB.GoldBadges, UB.SilverBadges, UB.BronzeBadges, UB.TagBasedBadges
),
PostPerformanceMetrics AS (
    -- Calculates various performance metrics for individual questions and answers, including a correlated subquery and window functions.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        COALESCE(P.ViewCount, 0) AS EffectiveViewCount,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400.0 AS DaysActive, -- Post's active duration in days
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - P.CreationDate)) / 86400.0 AS DaysSinceCreation, -- Post's age in days
        CASE
            WHEN P.PostTypeId = 1 AND COALESCE(P.ViewCount, 0) > 0 THEN CAST(P.Score AS REAL) / P.ViewCount
            WHEN P.PostTypeId = 2 AND COALESCE(P.CommentCount, 0) > 0 THEN CAST(P.Score AS REAL) / P.CommentCount -- Answer score relative to comments
            WHEN P.PostTypeId = 2 THEN CAST(P.Score AS REAL) -- If no comments, just score
            ELSE 0.0
        END AS PerformanceRatio,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankByScore, -- Ranks posts per user and type
        NTILE(10) OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS PostEngagementTier, -- Divides all posts into 10 engagement tiers
        -- String expression to check for specific tags (case-insensitive)
        (CASE WHEN P.Tags IS NOT NULL AND (LOWER(P.Tags) LIKE '%<sql>%' OR LOWER(P.Tags) LIKE '%<database>%' OR LOWER(P.Tags) LIKE '%<postgresql>%') THEN TRUE ELSE FALSE END) AS IsSqlOrDbPost,
        -- Correlated subquery: average score of comments for this specific post
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = P.Id AND C.CreationDate >= P.CreationDate AND C.Score IS NOT NULL) AS AvgCommentScoreOnPost
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2) -- Focus on questions and answers
      AND P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3' YEAR) -- Consider posts from the last 3 years
),
PostHistoryTimeline AS (
    -- Tracks significant post lifecycle events from PostHistory.
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate, -- Post Closed
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate, -- Post Reopened
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDateByHistory, -- Edit Title, Body, Tags
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS TotalEditEvents -- Total edit history entries
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 4, 5, 6) -- Filter for relevant history types
    GROUP BY PH.PostId
),
UserPostAggregates AS (
    -- Aggregates post performance metrics per user for overall statistics.
    SELECT
        PPM.OwnerUserId AS UserId,
        COUNT(PPM.PostId) AS TotalPostsAnalyzed,
        SUM(CASE WHEN PPM.IsSqlOrDbPost THEN 1 ELSE 0 END) AS SqlDbPostCount,
        AVG(PPM.PerformanceRatio) AS AvgPostPerformanceRatio
    FROM PostPerformanceMetrics AS PPM
    GROUP BY PPM.OwnerUserId
)
SELECT
    UES.UserId,
    COALESCE(UES.DisplayName, 'Anonymous User') AS UserName, -- Handle potentially NULL display names
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    UES.TotalPosts,
    UES.TotalQuestions,
    UES.TotalAnswers,
    UES.TotalPostScore,
    UES.TotalComments,
    UES.TotalCommentScore,
    UES.ReceivedUpVotesOnPosts,
    UES.ReceivedDownVotesOnPosts,
    UES.TotalBadges,
    UES.GoldBadges,
    UES.SilverBadges,
    UES.BronzeBadges,
    PPM_Q.PostId AS TopQuestionId,
    PPM_Q.PostScore AS TopQuestionScore,
    PPM_Q.ViewCount AS TopQuestionViews,
    PPM_Q.DaysActive AS TopQuestionDaysActive,
    PPM_Q.PerformanceRatio AS TopQuestionPerformanceRatio,
    PPM_Q.AvgCommentScoreOnPost AS TopQuestionAvgCommentScore,
    PPM_Q.Tags AS TopQuestionTags,
    PPM_A.PostId AS TopAnswerId,
    PPM_A.PostScore AS TopAnswerScore,
    PPM_A.DaysActive AS TopAnswerDaysActive,
    PPM_A.PerformanceRatio AS TopAnswerPerformanceRatio,
    PPM_A.AvgCommentScoreOnPost AS TopAnswerAvgCommentScore,
    PHT.LastClosedDate,
    PHT.LastReopenedDate,
    PHT.LastEditDateByHistory,
    COALESCE(PHT.TotalEditEvents, 0) AS TotalEditEventsOnTopPost, -- Handle NULL for posts with no history
    UPA.SqlDbPostCount AS UserSqlDbPostCount, -- Total SQL/DB related posts by user
    COALESCE(UPA.AvgPostPerformanceRatio, 0.0) AS UserAvgPostPerformanceRatio, -- Average performance ratio of all user's posts
    -- Complicated calculation for "Influence Score", normalized by user's age in years
    (UES.Reputation * 0.5 + UES.ReceivedUpVotesOnPosts * 0.3 + UES.GoldBadges * 10 + UES.SilverBadges * 5 + UES.TotalQuestions * 2 + UES.TotalAnswers * 1.5 + COALESCE(UES.TotalCommentScore, 0) * 0.1) /
    (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - UES.UserCreationDate)) / (86400.0 * 365.25) + 1.0) AS InfluenceScore,
    -- Categorizes users based on their post activity
    CASE
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers = 0 THEN 'Questioner'
        WHEN UES.TotalAnswers > 0 AND UES.TotalQuestions = 0 THEN 'Answerer'
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers > 0 AND UES.TotalAnswers >= UES.TotalQuestions THEN 'Contributor (Answer Heavy)'
        WHEN UES.TotalQuestions > 0 AND UES.TotalAnswers > 0 AND UES.TotalQuestions > UES.TotalAnswers THEN 'Contributor (Question Heavy)'
        ELSE 'Passive'
    END AS UserType,
    -- String expression: checks if user's location indicates a US/UK presence, case-insensitive
    CASE
        WHEN UES.Location IS NOT NULL AND (LOWER(UES.Location) LIKE '%usa%' OR LOWER(UES.Location) LIKE '%united states%' OR LOWER(UES.Location) LIKE '%uk%' OR LOWER(UES.Location) LIKE '%united kingdom%' OR LOWER(UES.Location) LIKE '%canada%') THEN TRUE
        ELSE FALSE
    END AS IsGeoTargetedEnglishSpeaking,
    -- Correlated subquery: finds the date of the user's latest Gold badge (if any)
    (SELECT MAX(B2.Date) FROM Badges B2 WHERE B2.UserId = UES.UserId AND B2.Class = 1) AS LatestGoldBadgeDate,
    -- Correlated subquery: counts recent edit history events initiated by the user
    (SELECT COUNT(DISTINCT PH2.PostId) FROM PostHistory PH2 WHERE PH2.UserId = UES.UserId AND PH2.PostHistoryTypeId IN (4,5,6) AND PH2.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '30' DAY)) AS RecentEditsByUserCount,
    -- Example of complex NULL logic with COALESCE and a calculation
    COALESCE(PPM_Q.DaysSinceCreation, PPM_A.DaysSinceCreation, 0) AS DaysSinceTopPostCreation,
    (CASE WHEN UES.AboutMe IS NOT NULL AND CHAR_LENGTH(UES.AboutMe) > 100 THEN 'Verbose' ELSE 'Concise' END) AS AboutMeStyle
FROM
    UserEngagementSummary AS UES
LEFT JOIN
    PostPerformanceMetrics AS PPM_Q ON UES.UserId = PPM_Q.OwnerUserId AND PPM_Q.PostTypeId = 1 AND PPM_Q.PostRankByScore = 1 -- Join for top question
LEFT JOIN
    PostPerformanceMetrics AS PPM_A ON UES.UserId = PPM_A.OwnerUserId AND PPM_A.PostTypeId = 2 AND PPM_A.PostRankByScore = 1 -- Join for top answer
LEFT JOIN
    PostHistoryTimeline AS PHT ON COALESCE(PPM_Q.PostId, PPM_A.PostId) = PHT.PostId -- Use history of the highest-scoring question or answer
LEFT JOIN
    UserPostAggregates AS UPA ON UES.UserId = UPA.UserId -- Join for aggregated post statistics per user
WHERE
    UES.Reputation > 500
    AND UES.TotalPosts > 2
    AND (PPM_Q.PostId IS NOT NULL OR PPM_A.PostId IS NOT NULL) -- Ensure user has at least one identified top post
    AND UES.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '6' MONTH) -- Filter for recently very active users
ORDER BY
    InfluenceScore DESC, UES.Reputation DESC, UES.LastAccessDate DESC
LIMIT 1000;
