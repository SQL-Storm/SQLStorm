-- {"query": "1255.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2766} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user engagement metrics and calculate some ratios
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous') AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        U.Views AS ProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewCount,
        SUM(COALESCE(P.AnswerCount, 0)) AS TotalAnswersReceived,
        COUNT(DISTINCT C.Id) AS TotalComments,
        -- Calculate a complex engagement score: (TotalPostScore * 2 + TotalUpVotesGiven - TotalDownVotesGiven + ProfileViews / 10) * (1 + TotalAnswersReceived / 10.0)
        (SUM(COALESCE(P.Score, 0)) * 2.0 + U.UpVotes - U.DownVotes + COALESCE(U.Views, 0) / 10.0) * (1 + SUM(COALESCE(P.AnswerCount, 0)) / 10.0) AS RawEngagementScore,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS UserRankByReputation,
        AVG(P.Score) OVER (PARTITION BY COALESCE(U.Location, '')) AS AvgScorePerLocation
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views, U.Location
    HAVING COUNT(DISTINCT P.Id) > 5 -- Only consider users with a significant number of posts
),
PostHistoricalAnalysisSummary AS (
    -- CTE 2: Summarize post history actions by user, including the latest relevant comment by them
    SELECT
        PH.UserId AS HistoryActorUserId,
        COUNT(DISTINCT PH.Id) AS TotalUserHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalUserEditActions, -- Edit Title, Body, Tags
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalUserCloseVotes,
        MAX(PH.CreationDate) AS LatestUserHistoryDate,
        (SELECT PH_Inner.Comment
         FROM PostHistory PH_Inner
         WHERE PH_Inner.UserId = PH.UserId
           AND PH_Inner.Comment IS NOT NULL
           AND PH_Inner.PostHistoryTypeId IN (4, 5, 6, 10, 11) -- Edit, Close, Reopen
         ORDER BY PH_Inner.CreationDate DESC
         LIMIT 1) AS LatestUserRelevantHistoryComment
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
TagSpecificPostsMetrics AS (
    -- CTE 3: Identify posts related to specific technologies and their general metrics, per post
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        CASE
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<postgresql>%' THEN 'DatabaseRelated'
            WHEN P.Tags LIKE '%<javascript>%' OR P.Tags LIKE '%<frontend>%' OR P.Tags LIKE '%<react>%' THEN 'FrontendRelated'
            WHEN P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<machine-learning>%' THEN 'PythonMLRelated'
            ELSE 'OtherTech'
        END AS TechnologyCategory,
        COUNT(DISTINCT C.UserId) AS UniqueCommenters,
        AVG(C.Score) AS AvgCommentScore
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.PostTypeId IN (1, 2) -- Questions or Answers
      AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Title, P.Tags, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.AcceptedAnswerId
),
CorePostAggregation AS (
    -- CTE 4: Aggregate post metrics for a user across different technology categories
    SELECT
        TSPM.OwnerUserId,
        TSPM.TechnologyCategory,
        COUNT(TSPM.PostId) AS CategoryPostCount,
        SUM(TSPM.Score) AS CategoryTotalScore,
        SUM(TSPM.ViewCount) AS CategoryTotalViewCount,
        AVG(TSPM.Score) AS CategoryAvgScore,
        MAX(TSPM.FavoriteCount) AS MaxFavoriteCountInCategory,
        MAX(TSPM.UniqueCommenters) AS MaxUniqueCommentersInCategory,
        -- Correlated subquery: Find the creation date of the accepted answer for the user's highest scored question in this category
        (SELECT MAX(A_Inner.CreationDate)
         FROM Posts Q_Inner
         JOIN Posts A_Inner ON Q_Inner.AcceptedAnswerId = A_Inner.Id
         WHERE Q_Inner.OwnerUserId = TSPM.OwnerUserId
           AND Q_Inner.PostTypeId = 1
           AND (CASE
                WHEN Q_Inner.Tags LIKE '%<sql>%' OR Q_Inner.Tags LIKE '%<database>%' OR Q_Inner.Tags LIKE '%<postgresql>%' THEN 'DatabaseRelated'
                WHEN Q_Inner.Tags LIKE '%<javascript>%' OR Q_Inner.Tags LIKE '%<frontend>%' OR Q_Inner.Tags LIKE '%<react>%' THEN 'FrontendRelated'
                WHEN Q_Inner.Tags LIKE '%<python>%' OR Q_Inner.Tags LIKE '%<machine-learning>%' THEN 'PythonMLRelated'
                ELSE 'OtherTech'
               END) = TSPM.TechnologyCategory
           AND Q_Inner.Score = (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = TSPM.OwnerUserId AND PostTypeId = 1
                                    AND (CASE
                                         WHEN Tags LIKE '%<sql>%' OR Tags LIKE '%<database>%' OR Tags LIKE '%<postgresql>%' THEN 'DatabaseRelated'
                                         WHEN Tags LIKE '%<javascript>%' OR Tags LIKE '%<frontend>%' OR Tags LIKE '%<react>%' THEN 'FrontendRelated'
                                         WHEN Tags LIKE '%<python>%' OR Tags LIKE '%<machine-learning>%' THEN 'PythonMLRelated'
                                         ELSE 'OtherTech'
                                        END) = TSPM.TechnologyCategory
                                    )
        ) AS AcceptedAnswerForTopQuestionDate
    FROM TagSpecificPostsMetrics TSPM
    GROUP BY TSPM.OwnerUserId, TSPM.TechnologyCategory
),
UserBadgeSummary AS (
    -- CTE 5: Aggregate badge information per user
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
UserLinkAndMigrationSummary AS (
    -- CTE 6: Summarize post links and migration events for a user
    SELECT
        P.OwnerUserId AS LinkOwnerUserId,
        COUNT(DISTINCT PL.Id) AS TotalPostLinks,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostCount,
        SUM(CASE WHEN PH_Mig.PostHistoryTypeId IN (35, 36) THEN 1 ELSE 0 END) AS MigratedPostCount,
        SUM(CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedPosts
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    LEFT JOIN PostHistory PH_Mig ON P.Id = PH_Mig.PostId AND PH_Mig.PostHistoryTypeId IN (35, 36)
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserLatestCommentInfo AS (
    -- Get comment text and creation date for each user's comments on *any* post
    SELECT
        C.UserId,
        C.Text AS CommentText,
        C.CreationDate AS CommentCreationDate
    FROM Comments C
    WHERE C.UserId IS NOT NULL AND C.Text IS NOT NULL
),
UserCumulativeCommentLength AS (
    -- CTE 7: Calculate cumulative average comment length for each user based on their comment history
    SELECT
        ULCI.UserId,
        ULCI.CommentCreationDate,
        AVG(LENGTH(ULCI.CommentText)) OVER (PARTITION BY ULCI.UserId ORDER BY ULCI.CommentCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAvgCommentLength,
        ROW_NUMBER() OVER (PARTITION BY ULCI.UserId ORDER BY ULCI.CommentCreationDate DESC) AS rn_latest_comment
    FROM UserLatestCommentInfo ULCI
),
EligibleUsersPreFilter AS (
    -- CTE 8: Filter users based on initial complex criteria using UNION
    -- Criteria 1: Highly engaged users with good reputation and recent activity
    SELECT UE.UserId
    FROM UserEngagement UE
    WHERE UE.RawEngagementScore > 1000
      AND UE.Reputation > 5000
      AND UE.LastAccessDate >= (NOW() - INTERVAL '3 months')
      AND UE.TotalQuestions >= 3
    UNION
    -- Criteria 2: Users with significant badge achievements and answer contributions
    SELECT U.Id AS UserId
    FROM Users U
    JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
    WHERE (UBS.GoldBadges >= 1 OR UBS.SilverBadges >= 3)
      AND U.UpVotes > 100
      AND U.LastAccessDate >= (NOW() - INTERVAL '6 months')
)
SELECT
    UE.UserId,
    UE.UserDisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.LastAccessDate,
    UE.RawEngagementScore,
    UE.UserRankByReputation,
    COALESCE(UE.AvgScorePerLocation, 0.0) AS AvgScoreInTheirLocation,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    UE.TotalPostViewCount,
    UE.TotalComments,
    UHS.TotalUserEditActions AS UserSignificantEditActions,
    UHS.TotalUserCloseVotes AS UserCloseVoteActions,
    UHS.LatestUserRelevantHistoryComment,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    CO