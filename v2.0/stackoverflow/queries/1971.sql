-- {"query": "1971.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3261}
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsContributed,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersProvided,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViewsReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LatestOverallActivity,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        (U.Reputation * 0.4 + COUNT(DISTINCT P.Id) * 0.1 + COUNT(DISTINCT C.Id) * 0.05 + COALESCE(SUM(P.Score), 0) * 0.01) AS UserActivityScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.ParentId,
        P.AcceptedAnswerId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount AS PostDirectCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT PH.UserId) AS DistinctEditorsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 AND PL.PostId = P.Id THEN 1 ELSE 0 END) AS DuplicatedByOtherPosts,
        SUM(CASE WHEN PL.LinkTypeId = 3 AND PL.RelatedPostId = P.Id THEN 1 ELSE 0 END) AS DuplicatesOtherPosts,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id) AS ActualTotalComments
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    GROUP BY
        P.Id, P.PostTypeId, P.ParentId, P.AcceptedAnswerId, P.OwnerUserId, P.CreationDate, P.Score,
        P.ViewCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastActivityDate, P.Title, P.Tags, P.AnswerCount
),
BadgeAchievement AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeEarnedDate,
        (SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) > 0) AS HasGoldBadge
    FROM Badges B
    GROUP BY B.UserId
),
RankedUsers AS (
    SELECT
        UES.UserId,
        UES.UserName,
        UES.Reputation,
        UES.TotalQuestionsAsked,
        UES.TotalAnswersProvided,
        UES.TotalPostScoreReceived,
        UES.LatestOverallActivity,
        COALESCE(BA.GoldBadges, 0) AS UserGoldBadges,
        UES.UserActivityScore,
        RANK() OVER (ORDER BY UES.UserActivityScore DESC, UES.Reputation DESC) AS OverallUserRank,
        NTILE(10) OVER (ORDER BY UES.Reputation DESC) AS ReputationDecile
    FROM UserEngagementSummary UES
    LEFT JOIN BadgeAchievement BA ON UES.UserId = BA.UserId
    WHERE UES.Reputation >= 1000
),
PostTagAnalysis AS (
    SELECT
        PHM.PostId,
        PHM.OwnerUserId,
        PHM.PostCreationDate,
        CASE
            WHEN PHM.Tags IS NOT NULL AND LENGTH(PHM.Tags) > 2 THEN string_to_array(substring(PHM.Tags FROM 2 FOR (LENGTH(PHM.Tags) - 2)), '><')
            ELSE NULL
        END AS TagArray
    FROM PostHistoricalMetrics PHM
    WHERE PHM.PostTypeId = 1 AND PHM.Tags IS NOT NULL
)
SELECT
    RU.UserName,
    RU.Reputation,
    RU.OverallUserRank,
    RU.ReputationDecile,
    RU.UserGoldBadges,
    PHM.PostId,
    PHM.PostTypeId,
    CASE PHM.PostTypeId
        WHEN 1 THEN 'Question'
        WHEN 2 THEN 'Answer'
        WHEN 4 THEN 'TagWikiExcerpt'
        WHEN 5 THEN 'TagWiki'
        ELSE PT.Name
    END AS PostTypeName,
    PHM.PostScore,
    PHM.ViewCount,
    PHM.Title,
    PHM.PostCreationDate,
    PHM.LastActivityDate,
    PHM.ActualTotalComments,
    PHM.ContentEditCount,
    PHM.DistinctEditorsCount,
    PHM.CloseVoteCount,
    PHM.ReopenVoteCount,
    PHM.DuplicatedByOtherPosts,
    PHM.DuplicatesOtherPosts,
    CASE
        WHEN PHM.CloseVoteCount > 0 AND PHM.ReopenVoteCount > 0 THEN 'Closed & Reopened'
        WHEN PHM.DuplicatedByOtherPosts > 0 THEN 'Has Duplicates Referring To It'
        WHEN PHM.DuplicatesOtherPosts > 0 THEN 'Refers To Duplicates'
        WHEN PHM.ContentEditCount >= 5 AND PHM.DistinctEditorsCount >= 2 THEN 'Heavily Edited by Multiple Authors'
        WHEN PHM.ActualTotalComments >= 25 AND PHM.PostScore < 0 THEN 'High Comments, Low Score'
        ELSE 'Standard Engagement'
    END AS PostControversyStatus,
    CASE
        WHEN PHM.PostTypeId = 2 AND PHM.AcceptedAnswerId IS NOT NULL AND PHM.ParentId IS NOT NULL
             AND PHM.PostId = (SELECT AcceptedAnswerId FROM Posts WHERE Id = PHM.ParentId)
             AND (SELECT OwnerUserId FROM Posts WHERE Id = PHM.ParentId) = PHM.OwnerUserId
             THEN 'Self-Accepted Answer'
        WHEN PHM.PostTypeId = 2 AND PHM.AcceptedAnswerId IS NOT NULL AND PHM.ParentId IS NOT NULL
             AND PHM.PostId = (SELECT AcceptedAnswerId FROM Posts WHERE Id = PHM.ParentId)
             THEN 'Accepted Answer (Other User)'
        ELSE 'Not Accepted Answer'
    END AS AnswerAcceptanceStatus,
    GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PHM.PostCreationDate)) / (60 * 60 * 24))) AS DaysSinceCreation,
    COALESCE(PTA.TagArray[1], 'N/A') AS PrimaryTag,
    CAST(COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NUMERIC) /
    NULLIF(COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0), 0) AS DownvoteUpvoteRatio,
    CASE
        WHEN LOWER(PHM.Title) LIKE '%performance%' OR LOWER(PHM.Title) LIKE '%benchmark%' THEN 'Title Keyword Match'
        WHEN EXISTS (
            SELECT 1
            FROM PostTagAnalysis InnerPTA
            WHERE InnerPTA.PostId = PHM.PostId
              AND InnerPTA.TagArray IS NOT NULL
              AND (
                  'performance' = ANY(InnerPTA.TagArray)
                  OR 'benchmark' = ANY(InnerPTA.TagArray)
                  OR 'optimization' = ANY(InnerPTA.TagArray)
              )
        ) THEN 'Tag Keyword Match'
        ELSE 'Other Topic'
    END AS PostTopicCategory,
    AVG(PHM.PostScore) OVER (PARTITION BY RU.UserId) AS UserAveragePostScore,
    EXTRACT(EPOCH FROM (PHM.PostCreationDate - LAG(PHM.PostCreationDate, 1, PHM.PostCreationDate) OVER (PARTITION BY RU.UserId ORDER BY PHM.PostCreationDate))) / (60 * 60 * 24) AS DaysSincePreviousPost
FROM RankedUsers RU
INNER JOIN PostHistoricalMetrics PHM ON RU.UserId = PHM.OwnerUserId
LEFT JOIN PostTagAnalysis PTA ON PHM.PostId = PTA.PostId
LEFT JOIN Votes V ON PHM.PostId = V.PostId
LEFT JOIN PostTypes PT ON PHM.PostTypeId = PT.Id
WHERE
    RU.OverallUserRank <= 500
    AND PHM.PostScore >= 5
    AND PHM.PostTypeId IN (1, 2)
    AND (
        PHM.ActualTotalComments > 10 OR PHM.ContentEditCount > 3 OR PHM.CloseVoteCount > 0 OR PHM.ReopenVoteCount > 0
        OR PHM.FavoriteCount > 5 OR RU.UserGoldBadges > 0
    )
GROUP BY
    RU.UserId, RU.UserName, RU.Reputation, RU.OverallUserRank, RU.ReputationDecile, RU.UserGoldBadges,
    PHM.PostId, PHM.PostTypeId, PHM.PostScore, PHM.ViewCount, PHM.Title, PHM.PostCreationDate,
    PHM.LastActivityDate, PHM.ActualTotalComments, PHM.ContentEditCount, PHM.DistinctEditorsCount,
    PHM.CloseVoteCount, PHM.ReopenVoteCount, PHM.DuplicatedByOtherPosts, PHM.DuplicatesOtherPosts,
    PHM.AcceptedAnswerId, PHM.ParentId, PTA.TagArray, PT.Name, PHM.OwnerUserId, PHM.Title, PHM.PostCreationDate
ORDER BY
    RU.OverallUserRank ASC,
    PHM.PostScore DESC,
    PHM.LastActivityDate DESC;