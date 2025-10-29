WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsPosted,
        SUM(CASE WHEN P.ParentId IS NOT NULL AND P.Id = QuestionPosts.AcceptedAnswerId THEN 1 ELSE 0 END) AS TotalAcceptedAnswers,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.LastAccessDate)) / 86400 AS TimeSinceLastAccessDays,
        CASE
            WHEN (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate) IS NULL OR EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) = 0
            THEN 0.0
            ELSE U.Reputation * 1.0 / (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / 86400.0)
        END AS ReputationPerDay,
        COALESCE(SUM(P.Score) * 1.0 / NULLIF(COUNT(P.Id), 0), 0.0) AS AveragePostScoreReceived,
        (
            SELECT PT.Name
            FROM Posts UserPosts
            JOIN PostTypes PT ON UserPosts.PostTypeId = PT.Id
            WHERE UserPosts.OwnerUserId = U.Id
            GROUP BY PT.Name, UserPosts.PostTypeId
            ORDER BY COUNT(UserPosts.Id) DESC, UserPosts.PostTypeId DESC
            LIMIT 1
        ) AS MostFrequentPostType
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts QuestionPosts ON P.ParentId = QuestionPosts.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
    HAVING U.Reputation > 100
),
PostQualityMetrics AS (
    SELECT
        PQ.Id AS PostId,
        PQ.OwnerUserId,
        PQ.Score AS PostScore,
        PQ.ViewCount,
        PQ.AnswerCount,
        PQ.FavoriteCount,
        PQ.Title,
        PQ.Tags,
        COALESCE(COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)), 0) AS TotalEditEvents,
        COALESCE(COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10), 0) AS CloseVoteEvents,
        COALESCE(COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3), 0) AS DuplicateLinkCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS PostUpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS PostDownVotes
    FROM Posts PQ
    LEFT JOIN PostHistory PH ON PQ.Id = PH.PostId
    LEFT JOIN PostLinks PL ON PQ.Id = PL.PostId
    LEFT JOIN Votes V ON PQ.Id = V.PostId
    WHERE PQ.PostTypeId = 1
    GROUP BY PQ.Id, PQ.OwnerUserId, PQ.Score, PQ.ViewCount, PQ.AnswerCount, PQ.FavoriteCount, PQ.Title, PQ.Tags
),
UserBadgeRanks AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) DESC, B.UserId ASC) AS BadgeRank,
        STRING_AGG(DISTINCT B.Name, ', ' ORDER BY B.Name) AS AllBadgesList
    FROM Badges B
    GROUP BY B.UserId
),
DailyActivityMetrics AS (
    SELECT
        P.OwnerUserId AS UserId,
        DATE_TRUNC('day', P.CreationDate) AS ActivityDay,
        COUNT(P.Id) AS PostsOnDay,
        COUNT(C.Id) AS CommentsOnDay,
        SUM(CASE WHEN V.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS UpVotesOnDay,
        SUM(CASE WHEN V.VoteTypeId IN (3, 10) THEN 1 ELSE 0 END) AS DownVotesOnDay
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId AND DATE_TRUNC('day', P.CreationDate) = DATE_TRUNC('day', C.CreationDate)
    LEFT JOIN Votes V ON P.Id = V.PostId AND DATE_TRUNC('day', P.CreationDate) = DATE_TRUNC('day', V.CreationDate)
    WHERE P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months'
    GROUP BY P.OwnerUserId, DATE_TRUNC('day', P.CreationDate)
),
UserSegment_HighRepAndGoldBadges AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        'High Reputation & Gold Badges' AS SegmentType
    FROM UserActivitySummary UAS
    JOIN UserBadgeRanks UBR ON UAS.UserId = UBR.UserId
    WHERE UAS.Reputation > 50000 AND UBR.GoldBadges >= 5
),
UserSegment_ActiveRecentContributors AS (
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        'Active Contributor (Recent Posts & Comments)' AS SegmentType
    FROM UserActivitySummary UAS
    JOIN (
        SELECT UserId, SUM(PostsOnDay) AS TotalRecentPosts, SUM(CommentsOnDay) AS TotalRecentComments
        FROM DailyActivityMetrics
        GROUP BY UserId
    ) AS DAM_Agg ON UAS.UserId = DAM_Agg.UserId
    WHERE DAM_Agg.TotalRecentPosts >= 20 AND DAM_Agg.TotalRecentComments >= 10
),
UserSegment_SelectedUsers AS (
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_HighRepAndGoldBadges
    UNION ALL
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_ActiveRecentContributors
    UNION ALL
    SELECT UserId, DisplayName, 'Random Active User Sample' AS SegmentType
    FROM UserActivitySummary
    WHERE UserId NOT IN (
        SELECT UserId FROM UserSegment_HighRepAndGoldBadges
        UNION
        SELECT UserId FROM UserSegment_ActiveRecentContributors
    )
),
RandomSample AS (
    SELECT UserId, DisplayName, SegmentType
    FROM UserSegment_SelectedUsers
    WHERE SegmentType = 'Random Active User Sample'
    ORDER BY RANDOM()
    LIMIT 100
),
FinalSelectedUsers AS (
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_HighRepAndGoldBadges
    UNION ALL
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_ActiveRecentContributors
    UNION ALL
    SELECT UserId, DisplayName, SegmentType FROM RandomSample
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.CreationDate,
    UAS.LastAccessDate,
    UAS.TimeSinceLastAccessDays,
    UAS.ReputationPerDay,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.TotalCommentsPosted,
    UAS.TotalAcceptedAnswers,
    UAS.AveragePostScoreReceived,
    UAS.MostFrequentPostType,
    UBR.GoldBadges,
    UBR.SilverBadges,
    UBR.BronzeBadges,
    UBR.BadgeRank,
    UBR.AllBadgesList,
    ROW_NUMBER() OVER (ORDER BY UAS.Reputation DESC, UAS.LastAccessDate DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (ORDER BY UAS.TotalQuestionsPosted DESC, UAS.TotalAnswersPosted DESC) AS ContributionRank,
    AVG(UAS.AveragePostScoreReceived) OVER (PARTITION BY UAS.MostFrequentPostType) AS AvgPostScoreByMainPostType,
    (
        SELECT P_Latest.Title
        FROM Posts P_Latest
        WHERE P_Latest.OwnerUserId = UAS.UserId
        ORDER BY P_Latest.CreationDate DESC
        LIMIT 1
    ) AS LatestPostTitle,
    COALESCE(
        (
            SELECT C_Latest.Text
            FROM Comments C_Latest
            WHERE C_Latest.UserId = UAS.UserId
            ORDER BY C_Latest.CreationDate DESC
            LIMIT 1
        ),
        'No recent comments'
    ) AS LatestCommentText,
    COALESCE(SUM(DAM.PostsOnDay) OVER (PARTITION BY UAS.UserId, DAM.UserId, DAM.ActivityDay), 0) AS RecentTotalPosts,
    COALESCE(SUM(DAM.CommentsOnDay) OVER (PARTITION BY UAS.UserId, DAM.UserId, DAM.ActivityDay), 0) AS RecentTotalComments,
    COALESCE(AVG(DAM.UpVotesOnDay) OVER (PARTITION BY UAS.UserId, DAM.UserId, DAM.ActivityDay), 0.0) AS AvgDailyUpVotesRecent,
    COALESCE(AVG(DAM.DownVotesOnDay) OVER (PARTITION BY UAS.UserId, DAM.UserId, DAM.ActivityDay), 0.0) AS AvgDailyDownVotesRecent,
    STRING_AGG(DISTINCT (PQM.Title || ' (Score: ' || PQM.PostScore || ' Edits: ' || PQM.TotalEditEvents || ')'), '; ')
        FILTER (WHERE PQM.PostScore > 50 AND PQM.TotalEditEvents > 5 AND PQM.DuplicateLinkCount > 0 AND LOWER(PQM.Title) LIKE '%sql%') AS HighlightedProblematicSQLQuestions,
    COALESCE(
        SUM(CASE
                WHEN PQM.TotalEditEvents > 5 AND PQM.CloseVoteEvents > 0 AND PQM.PostDownVotes > PQM.PostUpVotes THEN 1
                ELSE 0
            END),
        0
    ) AS HighlyEditedClosedAndDownvotedQuestionsCount,
    (
        SELECT COUNT(DISTINCT tag)
        FROM (
            SELECT UNNEST(string_to_array(SUBSTRING(P_Tag.Tags FROM 2 FOR CHAR_LENGTH(P_Tag.Tags)-2), '><')) AS tag
            FROM Posts P_Tag
            WHERE P_Tag.OwnerUserId = UAS.UserId AND P_Tag.PostTypeId = 1 AND P_Tag.Tags IS NOT NULL AND CHAR_LENGTH(P_Tag.Tags) > 2
        ) AS UserTags
        WHERE tag IN (SELECT TagName FROM Tags WHERE IsModeratorOnly = TRUE)
    ) AS QuestionsWithModeratorTagsCount,
    COALESCE(
        UAS.DisplayName,
        'Anonymous User ' || CAST(UAS.UserId AS text)
    ) AS EffectiveDisplayName,
    NULLIF(UAS.UserViews, 0) AS UserViewsNonNull,
    COALESCE(SelectedUsers.SegmentType, 'Standard User') AS UserSegmentDescription,
    CASE WHEN UAS.Reputation > 10000 THEN 'HighRepContributor'
         WHEN UAS.Reputation BETWEEN 1000 AND 10000 THEN 'MidRepContributor'
         ELSE 'LowRepContributor'
    END AS ReputationTier,
    CASE WHEN UAS.TotalQuestionsPosted > 0 AND UAS.TotalAnswersPosted > 0 AND UAS.TotalCommentsPosted > 0 THEN 'DiverseContributor'
         WHEN UAS.TotalQuestionsPosted > 0 AND UAS.TotalAnswersPosted = 0 THEN 'Questioner'
         WHEN UAS.TotalAnswersPosted > 0 AND UAS.TotalQuestionsPosted = 0 THEN 'Answerer'
         ELSE 'Passive'
    END AS ContributionStyle
FROM UserActivitySummary UAS
LEFT JOIN UserBadgeRanks UBR ON UAS.UserId = UBR.UserId
LEFT JOIN PostQualityMetrics PQM ON UAS.UserId = PQM.OwnerUserId
LEFT JOIN DailyActivityMetrics DAM ON UAS.UserId = DAM.UserId
LEFT JOIN FinalSelectedUsers SelectedUsers ON UAS.UserId = SelectedUsers.UserId
WHERE
    UAS.Reputation > (SELECT AVG(Reputation) FROM Users)
    AND UAS.TotalQuestionsPosted >= 1
    AND UAS.AveragePostScoreReceived IS NOT NULL
    AND UAS.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    AND UAS.UserId IN (SELECT UserId FROM FinalSelectedUsers)
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.CreationDate, UAS.LastAccessDate, UAS.TimeSinceLastAccessDays,
    UAS.ReputationPerDay, UAS.TotalQuestionsPosted, UAS.TotalAnswersPosted, UAS.TotalCommentsPosted,
    UAS.TotalAcceptedAnswers, UAS.AveragePostScoreReceived, UAS.MostFrequentPostType,
    UBR.GoldBadges, UBR.SilverBadges, UBR.BronzeBadges, UBR.BadgeRank, UBR.AllBadgesList,
    UAS.UserViews, UAS.UserUpVotesGiven, UAS.UserDownVotesGiven, SelectedUsers.SegmentType,
    UAS.UserId, DAM.UserId, DAM.ActivityDay, DAM.PostsOnDay, DAM.CommentsOnDay, DAM.UpVotesOnDay, DAM.DownVotesOnDay,
    PQM.Title, PQM.PostScore, PQM.TotalEditEvents, PQM.DuplicateLinkCount, PQM.CloseVoteEvents, PQM.PostDownVotes, PQM.PostUpVotes
ORDER BY GlobalReputationRank ASC, HighlightedProblematicSQLQuestions DESC NULLS LAST
LIMIT 200;