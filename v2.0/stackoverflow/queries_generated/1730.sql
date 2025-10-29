-- {"query": "1730.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2703} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        COUNT(DISTINCT C.Id) AS TotalCommentsAuthored,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- UpMod
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven, -- DownMod
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        NTILE(4) OVER (ORDER BY U.Reputation DESC) AS ReputationQuartile,
        AVG(P_Owned.Score) FILTER (WHERE P_Owned.PostTypeId = 1) AS AvgQuestionScoreOnOwnPosts,
        SUM(CASE WHEN U.LastAccessDate > U.CreationDate + INTERVAL '1 year' THEN 1 ELSE 0 END) AS ActiveAfterFirstYear,
        COALESCE(U.AboutMe, '') LIKE '%developer%' AS IsDeveloperInAboutMe
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId -- Votes given by the user
    LEFT JOIN
        Posts P_Owned ON U.Id = P_Owned.OwnerUserId -- For AvgQuestionScoreOnOwnPosts and other post-related metrics
    LEFT JOIN
        Votes PV ON P_Owned.Id = PV.PostId -- Votes received on user's posts
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.AboutMe
),
PostActivityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        SUM(CASE WHEN V.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UpvotesAndFavoritesOnPost,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnPost,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByScoreAndView,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600 AS HoursSinceCreationToLastActivity, -- In hours
        (SELECT U.DisplayName FROM Users U WHERE U.Id = P.OwnerUserId) AS PostOwnerDisplayNameFallback, -- Non-correlated subquery example
        (SELECT AcceptedAnswer.Score FROM Posts AcceptedAnswer WHERE AcceptedAnswer.Id = P.AcceptedAnswerId) AS AcceptedAnswerScore, -- Correlated subquery example
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        SUM(V.BountyAmount) FILTER (WHERE V.VoteTypeId IN (8,9)) OVER (PARTITION BY P.Id) AS TotalBountyAmount,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsCount
    FROM
        Posts P
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.LastActivityDate, P.ClosedDate, P.CommunityOwnedDate, P.OwnerUserId, P.AcceptedAnswerId
),
HistoricalEventAnalysis AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDateFromHistory,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDateFromHistory,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenCount,
        MAX(CASE
            WHEN PH.PostHistoryTypeId = 11 AND LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) = 10
            THEN PH.CreationDate
            ELSE NULL
        END) AS LastReopenAfterCloseDate,
        -- Check if a post was migrated away and then back (or vice-versa)
        MAX(CASE WHEN PH.PostHistoryTypeId = 35 AND LEAD(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) = 36 THEN TRUE ELSE FALSE END) AS MigratedAwayAndBack
    FROM
        PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 17, 35, 36) -- Closed, Reopened, Deleted, Undeleted, Migrated (old/away/here)
    GROUP BY
        PH.PostId
),
TagPerformanceMetrics AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostsWithTag,
        AVG(P.Score) AS AvgScoreForTag,
        SUM(P.ViewCount) AS TotalViewsForTag,
        MAX(P.CreationDate) AS LatestPostDateForTag,
        MIN(P.CreationDate) AS OldestPostDateForTag,
        (SELECT COUNT(DISTINCT Badges.UserId) FROM Badges WHERE Badges.Name = T.TagName AND Badges.TagBased = TRUE) AS TagBadgeHoldersCount -- Correlated subquery for tag badge holders
    FROM
        Tags T
    JOIN
        Posts P ON P.Tags LIKE '%' || T.TagName || '%' -- Using LIKE for tag matching
    GROUP BY
        T.TagName
)
-- Main Query Combining All CTEs
SELECT
    P.Id AS PostId,
    P.Title,
    P.Body,
    P.CreationDate AS PostCreationDate,
    P.Score,
    P.ViewCount,
    U.DisplayName AS OwnerDisplayName,
    UES.Reputation AS OwnerReputation,
    UES.TotalPostsAuthored AS OwnerTotalPosts,
    UES.AvgQuestionScoreOnOwnPosts,
    PAM.TotalCommentsOnPost,
    PAM.UpvotesAndFavoritesOnPost,
    PAM.DownvotesOnPost,
    PAM.PostStatus,
    PAM.RankByScoreAndView,
    TPM.TagName AS DominantTagName,
    TPM.AvgScoreForTag,
    TPM.PostsWithTag,
    HEA.CloseCount,
    HEA.ReopenCount,
    HEA.LastReopenAfterCloseDate,
    HEA.MigratedAwayAndBack,
    COALESCE(P.LastEditorDisplayName, 'No Recent Editor Name') AS LastEditorDisplayName, -- NULL logic
    EXTRACT(YEAR FROM P.CreationDate) AS CreationYear,
    LENGTH(P.Body) AS BodyLength,
    (P.Score * 1.0 / GREATEST(COALESCE(P.ViewCount, 0), 1)) AS ScoreToViewRatio, -- Avoid division by zero, using GREATEST for non-negative
    (UES.TotalUpvotesReceivedOnPosts * 1.0 / GREATEST((UES.TotalUpvotesReceivedOnPosts + UES.TotalDownvotesReceivedOnPosts), 1)) AS OwnerUpvoteRatio, -- More NULL logic and div by zero
    CASE
        WHEN P.ViewCount > 50000 AND P.Score > 200 THEN 'Viral Impact'
        WHEN P.ViewCount > 10000 AND P.Score > 50 THEN 'High Impact'
        WHEN P.ViewCount > 1000 OR P.Score > 10 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    'https://stackoverflow.com/questions/' || P.Id AS PostUrl, -- String concatenation
    SUM(P.FavoriteCount) OVER (PARTITION BY UES.ReputationQuartile) AS TotalFavoritesInOwnerReputationQuartile, -- Aggregate window function
    AVG(PAM.AcceptedAnswerScore) OVER (PARTITION BY P.PostTypeId) AS AvgAcceptedAnswerScoreForPostType,
    AVG(PAM.TotalBountyAmount) OVER (PARTITION BY P.PostTypeId) AS AvgBountyForPostType,
    MAX(PAM.UniqueEditorsCount) OVER (PARTITION BY P.Id) AS MaxUniqueEditorsOnPost,
    LOWER(SUBSTRING(P.Title FROM 1 FOR 50)) AS TruncatedLowerTitle, -- String manipulation
    (P.OwnerUserId IS NOT NULL AND P.AcceptedAnswerId IS NULL AND PAM.AnswerCount > 0) AS HasUnacceptedAnswers
FROM
    Posts P
INNER JOIN -- Using INNER JOIN because we are interested in posts that have a known owner for most analysis
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN
    UserEngagementSummary UES ON U.Id = UES.UserId
LEFT JOIN
    PostActivityMetrics PAM ON P.Id = PAM.PostId
LEFT JOIN
    HistoricalEventAnalysis HEA ON P.Id = HEA.PostId
LEFT JOIN LATERAL ( -- Lateral join to find the "dominant" tag (e.g., one with highest popularity/score) for each post
    SELECT T_Lat.TagName, TPM_Lat.AvgScoreForTag, TPM_Lat.PostsWithTag
    FROM unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS PostTag
    JOIN TagPerformanceMetrics TPM_Lat ON PostTag = TPM_Lat.TagName
    ORDER BY TPM_Lat.PostsWithTag DESC, TPM_Lat.AvgScoreForTag DESC
    LIMIT 1
) TPM ON TRUE
WHERE
    P.PostTypeId = 1 -- Focus on Questions
    AND P.CreationDate >= '2023-01-01' -- Recent posts
    AND P.ViewCount > 100 -- Only posts with some views
    AND P.Tags IS NOT NULL -- Must have tags to be considered
    AND (
        P.Title ILIKE '%sql%' -- Case-insensitive search
        OR P.Body ILIKE '%database%'
        OR P.Tags ILIKE '%<performance>%'
    )
    AND UES.ReputationQuartile = 1 -- Only from top 25% reputed users
    AND PAM.HoursSinceCreationToLastActivity > 24*7 -- Posts active for at least a week
    AND (HEA.CloseCount IS NULL OR HEA.CloseCount < 2) -- Not excessively closed
ORDER BY
    UES.Reputation DESC, P.Score DESC, P.CreationDate DESC
LIMIT 1000;
