-- {"query": "1541.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3308} 

WITH UserActivitySummary AS (
    -- Aggregates core user metrics including reputation, badges, overall post and comment counts,
    -- and latest activity dates. Includes string manipulation on user location and about me.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS ProfileViews,
        U.UpVotes AS UserUpVotesCast,  -- Upvotes this user has cast
        U.DownVotes AS UserDownVotesCast, -- Downvotes this user has cast
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        LENGTH(U.AboutMe) AS AboutMeLength,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(P.Score) AS TotalPostScoreReceived,
        SUM(P.ViewCount) AS TotalPostViewsReceived,
        SUM(P.FavoriteCount) AS TotalPostFavoritesReceived,
        SUM(P.CommentCount) AS TotalCommentsOnPosts,
        MAX(P.CreationDate) AS LatestPostDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyPosted,
        COUNT(DISTINCT PH_edit.Id) FILTER (WHERE PH_edit.PostHistoryTypeId IN (4, 5, 6)) AS PostEditCount, -- Edits made by this user
        (
            -- Correlated subquery to find the most recent significant history action by the user
            SELECT MAX(PH_inner.CreationDate)
            FROM PostHistory PH_inner
            WHERE PH_inner.UserId = U.Id
            AND PH_inner.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15)
        ) AS LatestHistoryActionDate
    FROM
        Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Using V.VoteTypeId = 8 for BountyStart in SUM above
    LEFT JOIN PostHistory PH_edit ON U.Id = PH_edit.UserId -- For edits performed by the user
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate, U.Location, U.AboutMe
),
PostDetailsExtended AS (
    -- Enriches post details with derived tag information, hot status, and analyzes post history for reopen events.
    -- Includes correlated subqueries for post link metrics.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        P.ClosedDate,
        P.LastEditDate,
        COALESCE(SUBSTRING(P.Tags, 2, POSITION('><' IN P.Tags) - 2), NULLIF(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '')) AS PrimaryTag,
        CASE
            WHEN P.ViewCount > 5000 AND P.Score > 100 AND P.AnswerCount > 5 AND P.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN TRUE
            ELSE FALSE
        END AS IsHotQuestion,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS rn_latest_post_by_user,
        MAX(CASE WHEN PHE.PostHistoryTypeId = 11 AND PHE.PreviousHistoryType = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS WasReopenedAfterClosed, -- Window function to detect specific history sequence (reopened after closed)
        (
            -- Correlated subquery to count incoming links to this post
            SELECT COUNT(DISTINCT PL_inner.RelatedPostId)
            FROM PostLinks PL_inner
            WHERE PL_inner.PostId = P.Id AND PL_inner.LinkTypeId = 1
        ) AS LinkedPostCount,
        (
            -- Correlated subquery to count posts that declare this post as a duplicate
            SELECT COUNT(DISTINCT PL_inner.PostId)
            FROM PostLinks PL_inner
            WHERE PL_inner.RelatedPostId = P.Id AND PL_inner.LinkTypeId = 3
        ) AS DuplicatedByCount
    FROM
        Posts P
    LEFT JOIN (
        -- Subquery to analyze post history for reopen events using LAG window function
        SELECT
            PH_inner.PostId,
            PH_inner.PostHistoryTypeId,
            LAG(PH_inner.PostHistoryTypeId, 1) OVER (PARTITION BY PH_inner.PostId ORDER BY PH_inner.CreationDate, PH_inner.Id) AS PreviousHistoryType
        FROM PostHistory PH_inner
        WHERE PH_inner.PostHistoryTypeId IN (10, 11) -- 10 = Post Closed, 11 = Post Reopened
    ) PHE ON P.Id = PHE.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
AggregatedUserPosts AS (
    -- Aggregates detailed post metrics for posts owned by each user, including reopened counts and tag summary.
    SELECT
        PDE.OwnerUserId AS UserId,
        COUNT(DISTINCT PDE.PostId) AS TotalOwnedPosts,
        SUM(PDE.Score) AS TotalOwnedPostsScore,
        SUM(PDE.ViewCount) AS TotalOwnedPostsViewCount,
        SUM(PDE.AnswerCount) AS TotalOwnedPostsAnswerCount,
        SUM(PDE.PostCommentCount) AS TotalOwnedPostsCommentCount,
        SUM(PDE.FavoriteCount) AS TotalOwnedPostsFavoriteCount,
        AVG(CASE WHEN PDE.PostTypeId = 1 THEN PDE.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN PDE.PostTypeId = 2 THEN PDE.Score END) AS AvgAnswerScore,
        SUM(CASE WHEN PDE.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        COUNT(DISTINCT CASE WHEN PDE.IsHotQuestion THEN PDE.PostId END) AS HotQuestionsOwned,
        STRING_AGG(DISTINCT PDE.PrimaryTag, ';') AS AllPrimaryTagsSummary,
        SUM(PDE.LinkedPostCount) AS TotalQuestionLinksOut,
        SUM(PDE.DuplicatedByCount) AS TotalQuestionDuplicatesIn,
        SUM(CASE WHEN PDE.WasReopenedAfterClosed = 1 THEN 1 ELSE 0 END) AS ReopenedPostsCount
    FROM
        PostDetailsExtended PDE
    GROUP BY
        PDE.OwnerUserId
),
UserCommentActivity AS (
    -- Summarizes a user's commenting activity specifically on other users' posts.
    SELECT
        C.UserId,
        COUNT(C.Id) AS CommentsOnOthersPosts,
        SUM(C.Score) AS TotalCommentScore
    FROM Comments C
    INNER JOIN Posts P ON C.PostId = P.Id
    WHERE C.UserId IS NOT NULL AND C.UserId <> P.OwnerUserId
    GROUP BY C.UserId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ProfileViews,
    UAS.UserUpVotesCast,
    UAS.UserDownVotesCast,
    UAS.TotalBadges,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.QuestionsAsked,
    UAS.AnswersProvided,
    AUP.TotalOwnedPostsScore,
    AUP.TotalOwnedPostsViewCount,
    AUP.AvgQuestionScore,
    AUP.AvgAnswerScore,
    AUP.AcceptedAnswersCount,
    UCA.CommentsOnOthersPosts,
    UCA.TotalCommentScore,
    UAS.TotalPostFavoritesReceived,
    UAS.TotalBountyPosted,
    UAS.PostEditCount,
    AUP.HotQuestionsOwned,
    AUP.AllPrimaryTagsSummary,
    AUP.TotalQuestionLinksOut,
    AUP.TotalQuestionDuplicatesIn,
    AUP.ReopenedPostsCount,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - UAS.UserCreationDate)) AS AccountAgeDays, -- Date arithmetic
    NULLIF(UAS.Reputation, 0) / NULLIF(EXTRACT(DAY FROM (CURRENT_TIMESTAMP - UAS.UserCreationDate)), 0) AS RepPerDay, -- NULL logic, division by zero
    COALESCE(AUP.AcceptedAnswersCount * 10.0 / NULLIF(UAS.AnswersProvided, 0), 0.0) AS AnswerAcceptanceRate, -- NULL logic, division by zero
    (UAS.TotalPostScoreReceived + COALESCE(UCA.TotalCommentScore, 0)) AS OverallContentScore,
    -- Complex Influence Score Calculation involving multiple metrics and weights
    (
        UAS.Reputation * 0.5 +
        UAS.ProfileViews * 0.01 +
        UAS.TotalBadges * 0.2 +
        UAS.GoldBadges * 1.5 +
        COALESCE(AUP.TotalOwnedPostsScore, 0) * 0.05 +
        COALESCE(AUP.TotalOwnedPostsViewCount, 0) * 0.001 +
        COALESCE(AUP.AcceptedAnswersCount, 0) * 5 +
        COALESCE(UCA.CommentsOnOthersPosts, 0) * 0.1 +
        COALESCE(UAS.PostEditCount, 0) * 0.5 +
        COALESCE(AUP.ReopenedPostsCount, 0) * 3
    ) AS InfluenceScoreRaw,
    RANK() OVER (ORDER BY
        (UAS.Reputation * 0.6 + (UAS.TotalBadges * 0.1) + (COALESCE(AUP.TotalOwnedPostsScore,0) * 0.05) + (COALESCE(AUP.TotalOwnedPostsViewCount,0) * 0.001) + (COALESCE(AUP.AcceptedAnswersCount,0) * 0.5) + (COALESCE(UCA.CommentsOnOthersPosts,0) * 0.01))
        DESC, UAS.UserId) AS OverallInfluenceRank, -- Ranking using a composite score with window function
    PERCENT_RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.TotalBadges DESC) AS ReputationPercentile, -- Percentile rank
    COALESCE(UAS.DisplayName, 'Anonymous User') AS EffectiveDisplayName, -- NULL logic for display name
    CASE
        WHEN UAS.Reputation > 75000 AND UAS.GoldBadges >= 5 THEN 'Legendary Contributor'
        WHEN UAS.Reputation > 25000 AND UAS.SilverBadges >= 10 THEN 'Senior Expert'
        WHEN UAS.Reputation > 5000 AND UAS.BronzeBadges >= 20 THEN 'Active Contributor'
        WHEN UAS.Reputation > 1000 THEN 'Engaged Participant'
        ELSE 'Casual User'
    END AS UserTier, -- Complicated predicate/expression with CASE WHEN
    (
        -- Correlated subquery to find the count of recent answers by others to the user's latest question.
        -- This uses PDE_sub which represents the user's latest post.
        SELECT COUNT(P_sub.Id)
        FROM Posts P_sub
        WHERE P_sub.ParentId = PDE_sub.PostId -- P_sub is an answer to PDE_sub (a question)
        AND P_sub.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '60 days')
        AND P_sub.PostTypeId = 2
        AND P_sub.OwnerUserId IS NOT NULL
        AND P_sub.OwnerUserId <> UAS.UserId -- Answers by others
    ) AS RecentAnswersToLatestQuestion
FROM
    UserActivitySummary UAS
LEFT JOIN AggregatedUserPosts AUP ON UAS.UserId = AUP.UserId
LEFT JOIN UserCommentActivity UCA ON UAS.UserId = UCA.UserId
LEFT JOIN PostDetailsExtended PDE_sub ON UAS.UserId = PDE_sub.OwnerUserId AND PDE_sub.rn_latest_post_by_user = 1 -- Details for the user's latest post, using ROW_NUMBER
WHERE
    UAS.Reputation > 500 -- Minimum reputation threshold for inclusion
    AND UAS.LatestPostDate IS NOT NULL
    AND UAS.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '180 days') -- Filter for relatively active users
    AND (
        (COALESCE(AUP.TotalOwnedPostsScore, 0) > 100 AND UAS.AnswersProvided > 5) -- Users with good answers
        OR
        (UAS.QuestionsAsked > 3 AND COALESCE(AUP.AvgQuestionScore, 0) > 5) -- Users with good questions
        OR
        (COALESCE(UCA.CommentsOnOthersPosts, 0) > 20 AND COALESCE(UCA.TotalCommentScore, 0) > 10) -- Users active in commenting
    )
ORDER BY
    OverallInfluenceRank, UAS.Reputation DESC, UAS.UserId
LIMIT 250;
