-- {"query": "19078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2721} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        SUM(P.FavoriteCount) AS TotalPostFavorites,
        MAX(P.LastActivityDate) AS LastPostActivity,
        AVG(CAST(P.AnswerCount AS DECIMAL)) AS AvgQuestionAnswerCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE B.Class
                WHEN 1 THEN 100 -- Gold
                WHEN 2 THEN 50  -- Silver
                WHEN 3 THEN 10  -- Bronze
                ELSE 0
             END) AS WeightedBadgeScore,
        COUNT(CASE WHEN B.TagBased = TRUE THEN 1 ELSE NULL END) AS TagBadgesCount
    FROM Badges B
    GROUP BY B.UserId
),
PostHistoryMetrics AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseDeleteVoteCount,
        MAX(PH.CreationDate) AS LastHistoryActivity
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
TopTagsPerUserRanked AS (
    SELECT
        UserId,
        Tag,
        TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, Tag) AS Rn
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')) AS Tag,
            COUNT(*) AS TagCount
        FROM Posts P
        WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1 -- Only questions have tags this way
        GROUP BY P.OwnerUserId, UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))
    ) AS UserTagCounts
),
TopTagsByPosts AS (
    SELECT UserId, Tag, TagCount
    FROM TopTagsPerUserRanked
    WHERE Rn <= 3
),
UserVoteSummaries AS (
    SELECT
        V.UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesCast, -- Bookmarks
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        MAX(V.CreationDate) AS LastVoteCastDate
    FROM Votes V
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
),
CommunityPostIndicators AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(P.Id) AS TotalCommunityOwnedPosts,
        MAX(P.CommunityOwnedDate) AS LastCommunityOwnedDate
    FROM Posts P
    WHERE P.CommunityOwnedDate IS NOT NULL
    GROUP BY P.OwnerUserId
),
RecentActivityLog AS (
    -- Post Creation Activity
    SELECT
        P.OwnerUserId AS ActorUserId,
        P.CreationDate AS ActivityDate,
        'Post Created: ' || COALESCE(P.Title, 'ID ' || P.Id) AS ActivityDescription,
        P.Id AS RelatedPostId,
        'Post' AS ActivityType
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
    AND P.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')

    UNION ALL

    -- Comment Creation Activity
    SELECT
        C.UserId AS ActorUserId,
        C.CreationDate AS ActivityDate,
        'Comment Posted on Post ' || C.PostId || ': ' || SUBSTRING(C.Text, 1, 50) AS ActivityDescription,
        C.PostId AS RelatedPostId,
        'Comment' AS ActivityType
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    AND C.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')

    UNION ALL

    -- Post Edit Activity
    SELECT
        PH.UserId AS ActorUserId,
        PH.CreationDate AS ActivityDate,
        'Post Edited: ' || COALESCE(P.Title, 'Post ' || PH.PostId) || ' (Type ' || PH.PostHistoryTypeId || ')' AS ActivityDescription,
        PH.PostId AS RelatedPostId,
        'Edit' AS ActivityType
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
      AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
      AND PH.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
),
UserRecentActivity AS (
    SELECT
        RAL.ActorUserId AS UserId,
        COUNT(RAL.ActivityType) AS RecentActivitiesCount,
        MAX(RAL.ActivityDate) AS LastRecentActivityDate,
        COUNT(DISTINCT RAL.RelatedPostId) AS DistinctPostsWithRecentActivity
    FROM RecentActivityLog RAL
    GROUP BY RAL.ActorUserId
)
SELECT
    UE.UserId,
    U.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.UserProfileViews,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    UE.TotalPostViews,
    UE.TotalPostFavorites,
    UE.TotalComments,
    UE.TotalCommentScore,
    BS.TotalBadges,
    BS.WeightedBadgeScore,
    BS.TagBadgesCount,
    PHM.EditCount AS TotalPostEdits,
    PHM.CloseDeleteVoteCount AS TotalCloseDeleteVotes,
    UVS.UpVotesCast AS TotalUpVotesCastByMe,
    UVS.DownVotesCast AS TotalDownVotesCastByMe,
    UVS.FavoritesCast AS TotalFavoritesCastByMe,
    UVS.TotalBountyGiven,
    CPI.TotalCommunityOwnedPosts,
    URA.RecentActivitiesCount,
    URA.LastRecentActivityDate,
    -- Window functions
    RANK() OVER (ORDER BY UE.Reputation DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (ORDER BY UE.TotalPosts DESC) AS GlobalPostCountRank,
    AVG(UE.TotalPostScore) OVER (PARTITION BY EXTRACT(YEAR FROM UE.UserCreationDate)) AS AvgScorePerUserCreationYear,
    -- String expressions and NULL logic
    COALESCE(U.Location, 'Unknown Location') AS UserLocation,
    NULLIF(U.WebsiteUrl, '') AS UserWebsiteUrl,
    -- Complex calculation: Activity Score
    (
        UE.Reputation * 0.1
        + UE.TotalPostScore * 0.5
        + UE.TotalComments * 0.2
        + COALESCE(BS.WeightedBadgeScore, 0) * 0.01
        + COALESCE(PHM.EditCount, 0) * 0.05
        - UE.UserDownVotesGiven * 0.01 -- penalize downvotes given
        + COALESCE(UVS.UpVotesCast, 0) * 0.02 -- reward upvotes cast
    ) AS CalculatedActivityScore,
    -- Example for Correlated Subquery: Avg score of accepted answers to one's own questions
    (
        SELECT AVG(A.Score)
        FROM Posts A
        JOIN Posts Q ON A.ParentId = Q.Id
        WHERE A.PostTypeId = 2 -- Answer
          AND Q.PostTypeId = 1 -- Question
          AND A.OwnerUserId = UE.UserId -- User is the answerer
          AND Q.OwnerUserId = UE.UserId -- User is the questioner
          AND A.AcceptedAnswerId IS NOT NULL -- Only accepted answers are considered 'quality'
    ) AS AvgScoreOwnAcceptedAnswersToOwnQuestions,
    -- Another complex calculation: Post Interaction Ratio
    CAST(COALESCE(UE.TotalPostFavorites, 0) AS DECIMAL) / NULLIF(COALESCE(UE.TotalPostViews, 0), 0) AS FavoriteToViewRatio,
    -- String aggregation for Top Tags
    (
        SELECT STRING_AGG(TT.Tag || ' (' || TT.TagCount || ')', '; ')
        FROM TopTagsByPosts TT
        WHERE TT.UserId = UE.UserId
    ) AS TopTagsString,
    -- Subquery for a specific 'hot' post linked to the user
    (
        SELECT P.Title
        FROM Posts P
        WHERE P.OwnerUserId = UE.UserId
          AND P.PostTypeId = 1 -- Question
          AND P.ViewCount > 10000
          AND P.Score > 500
          AND P.CreationDate > (CURRENT_DATE - INTERVAL '1 year')
        ORDER BY P.Score DESC, P.ViewCount DESC
        LIMIT 1
    ) AS TopRecentQuestionTitle,
    -- Check for overall recent activity based on aggregated log
    CASE
        WHEN URA.LastRecentActivityDate > (CURRENT_DATE - INTERVAL '30 days') THEN 'Highly Active'
        WHEN URA.LastRecentActivityDate > (CURRENT_DATE - INTERVAL '90 days') THEN 'Moderately Active'
        WHEN URA.LastRecentActivityDate IS NOT NULL THEN 'Inactive Recently'
        ELSE 'No Recent Logged Activity'
    END AS RecentActivityStatus
FROM Users U
INNER JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN BadgeSummary BS ON U.Id = BS.UserId
LEFT JOIN PostHistoryMetrics PHM ON U.Id = PHM.UserId
LEFT JOIN UserVoteSummaries UVS ON U.Id = UVS.UserId
LEFT JOIN CommunityPostIndicators CPI ON U.Id = CPI.UserId
LEFT JOIN UserRecentActivity URA ON U.Id = URA.UserId
WHERE
    U.Reputation > 500 -- Filter for sufficiently active users
    AND U.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    AND COALESCE(UE.TotalPosts, 0) + COALESCE(UE.TotalComments, 0) > 10 -- Ensure some minimum content
ORDER BY
    CalculatedActivityScore DESC, UE.Reputation DESC
LIMIT 1000;
