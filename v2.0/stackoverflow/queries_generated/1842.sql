-- {"query": "1842.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2973} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesReceivedByOthers,
        U.DownVotes AS UserDownVotesReceivedByOthers,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS TotalUpVotesCastByMe, -- Votes I have cast
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS TotalDownVotesCastByMe, -- Votes I have cast
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MAX(C.CreationDate) AS LastCommentCreationDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Votes CAST BY THE USER
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation >= 100 -- Focus on more established users
      AND U.CreationDate >= '2015-01-01' -- Consider users from a reasonable time frame
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS FirstCloseDate,
        COALESCE(
            (SELECT PH_sub.UserId FROM PostHistory PH_sub
             WHERE PH_sub.PostId = P.Id AND PH_sub.PostHistoryTypeId IN (4,5,6) AND PH_sub.UserId IS NOT NULL
             ORDER BY PH_sub.CreationDate DESC
             LIMIT 1), P.OwnerUserId -- If no editor, default to owner
        ) AS LastEditorOfPostId,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT CRT.Name, ' | ') FROM PostHistory PH_close
             JOIN CloseReasonTypes CRT ON PH_close.Comment::smallint = CRT.Id
             WHERE PH_close.PostId = P.Id AND PH_close.PostHistoryTypeId = 10
             AND PH_close.Comment ~ '^[0-9]+$' -- Ensure comment is a valid integer for close reason ID
            ), 'Not Closed'
        ) AS TopCloseReasons,
        COUNT(DISTINCT PL_dup.RelatedPostId) AS DuplicateLinksCount,
        COUNT(DISTINCT PL_linked.RelatedPostId) AS LinkedPostsCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks PL_dup ON P.Id = PL_dup.PostId AND PL_dup.LinkTypeId = 3 -- Duplicate links
    LEFT JOIN PostLinks PL_linked ON P.Id = PL_linked.PostId AND PL_linked.LinkTypeId = 1 -- General linked posts
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
      AND P.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate,
             P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags
),
ModeratorActionsSummary AS (
    SELECT
        PH.UserId AS ModeratorUserId,
        U.DisplayName AS ModeratorDisplayName,
        COUNT(DISTINCT PH.PostId) AS TotalModeratedActions,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostsClosedByMod,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostsReopenedByMod,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS PostsDeletedByMod,
        SUM(CASE WHEN PH.PostHistoryTypeId = 14 THEN 1 ELSE 0 END) AS PostsLockedByMod
    FROM PostHistory PH
    JOIN Users U ON PH.UserId = U.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Relevant moderator actions
      AND PH.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    GROUP BY PH.UserId, U.DisplayName
)
SELECT
    UE.UserId,
    COALESCE(UE.DisplayName, 'Anonymous User #' || UE.UserId) AS UserDisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.LastAccessDate,
    UE.UserProfileViews,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.GoldBadges,
    UE.SilverBadges,
    UE.BronzeBadges,
    UE.LastPostCreationDate,
    UE.LastCommentCreationDate,
    COALESCE(UE.AvgPostScore, 0.0) AS AverageOwnedPostScore,
    -- Complex calculation with NULL handling
    CAST(UE.UserUpVotesReceivedByOthers AS NUMERIC) / NULLIF(UE.UserUpVotesReceivedByOthers + UE.UserDownVotesReceivedByOthers, 0) AS UserUpVoteRatioReceived,
    -- Window function: Rank users by reputation within their activity level (defined by total posts)
    RANK() OVER (PARTITION BY (CASE WHEN UE.TotalPosts > 50 THEN 'HighActivity' WHEN UE.TotalPosts > 10 THEN 'MediumActivity' ELSE 'LowActivity' END) ORDER BY UE.Reputation DESC, UE.LastAccessDate DESC) AS RankInActivityClass,
    -- Aggregated post metrics from PostHistoricalMetrics
    SUM(PHM.PostScore) FILTER (WHERE PHM.PostTypeId = 1) AS TotalQuestionScore,
    SUM(PHM.PostScore) FILTER (WHERE PHM.PostTypeId = 2) AS TotalAnswerScore,
    AVG(PHM.ViewCount) FILTER (WHERE PHM.PostTypeId = 1) AS AvgQuestionViewCount,
    MAX(PHM.EditCount) AS MaxEditsOnAnyPost,
    SUM(CASE WHEN PHM.PostTypeId = 1 AND PHM.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsClosed,
    STRING_AGG(DISTINCT PHM.TopCloseReasons, '; ') AS AllUniqueCloseReasonsForUserPosts,
    SUM(PHM.DuplicateLinksCount) AS TotalDuplicateQuestionsLinked,
    -- Average time in hours from creation to last edit (NULL if no edit or missing dates)
    AVG(EXTRACT(EPOCH FROM (PHM.LastEditDate - PHM.PostCreationDate))) / 3600.0 AS AvgHoursToLastEdit,
    -- Correlated subquery to check for 'Autobiographer' badge achievement within the past year
    (SELECT COUNT(B_sub.Id) FROM Badges B_sub WHERE B_sub.UserId = UE.UserId AND B_sub.Name = 'Autobiographer' AND B_sub.Date >= (NOW() - INTERVAL '1 year')) AS AutobiographerBadgesLastYear,
    -- Identifying users who are potentially moderators based on actions, or highly engaged users
    CASE
        WHEN EXISTS (SELECT 1 FROM ModeratorActionsSummary MAS WHERE MAS.ModeratorUserId = UE.UserId AND MAS.PostsClosedByMod > 0) THEN 'ModeratorCandidate'
        WHEN UE.TotalQuestions > 20 AND UE.TotalAnswers > 50 AND UE.AvgPostScore > 10 THEN 'PowerUser'
        ELSE 'Contributor'
    END AS UserRoleHeuristic,
    -- String expression: Extracting top 3 most frequent specific tags from user's posts, handling NULLs
    COALESCE(
        (SELECT STRING_AGG(DISTINCT tag_val, ', ')
         FROM (
             SELECT TRIM(UNNEST(string_to_array(SUBSTRING(P_sub.Tags, 2, LENGTH(P_sub.Tags)-2), '><'))) AS tag_val
             FROM Posts P_sub
             WHERE P_sub.OwnerUserId = UE.UserId AND P_sub.PostTypeId = 1 AND P_sub.Tags IS NOT NULL
             ORDER BY P_sub.CreationDate DESC
             LIMIT 10 -- Consider top 10 most recent questions for tag analysis
         ) AS RecentTags
         WHERE RecentTags.tag_val IN ('sql', 'python', 'javascript', 'c#', 'java', 'go', 'rust', 'php', '.net', 'html', 'css', 'reactjs', 'angular', 'vuejs', 'node.js')
         GROUP BY 1 -- Grouping by 1 here ensures STRING_AGG works correctly for the subquery
        ), 'No specific tags in recent questions'
    ) AS TopRecentSpecificTagsInQuestions,
    -- NULL logic and date calculation
    NULLIF(DATE_PART('day', NOW() - UE.LastAccessDate), 0) AS DaysSinceLastActivity,
    -- Correlated subquery: Average time (in days) it took for user's highly viewed questions (over 1000 views) to receive at least one answer
    (
        SELECT AVG(DATE_PART('day', A.CreationDate - Q.CreationDate))
        FROM Posts Q
        JOIN Posts A ON Q.AcceptedAnswerId = A.Id -- Assuming AcceptedAnswerId implies an answer exists
        WHERE Q.OwnerUserId = UE.UserId
          AND Q.PostTypeId = 1
          AND Q.ViewCount > 1000
          AND Q.AcceptedAnswerId IS NOT NULL
    ) AS AvgDaysToAcceptedAnswerForPopularQuestions,
    -- Join with ModeratorActionsSummary for posts that were edited/closed by a moderator, linking via LastEditorOfPostId
    STRING_AGG(DISTINCT MAS.ModeratorDisplayName, '; ') FILTER (WHERE PHM.LastEditorOfPostId = MAS.ModeratorUserId AND PHM.EditCount > 0) AS EditorsOfUsersPosts,
    COUNT(DISTINCT MAS.ModeratorUserId) FILTER (WHERE PHM.LastEditorOfPostId = MAS.ModeratorUserId AND PHM.EditCount > 0) AS NumberOfEditorsOfUsersPosts
FROM UserEngagement UE
LEFT JOIN PostHistoricalMetrics PHM ON UE.UserId = PHM.OwnerUserId
LEFT JOIN ModeratorActionsSummary MAS ON PHM.LastEditorOfPostId = MAS.ModeratorUserId
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.LastAccessDate, UE.UserProfileViews,
    UE.TotalPosts, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments, UE.GoldBadges, UE.SilverBadges,
    UE.BronzeBadges, UE.LastPostCreationDate, UE.LastCommentCreationDate, UE.AvgPostScore,
    UE.UserUpVotesReceivedByOthers, UE.UserDownVotesReceivedByOthers
ORDER BY
    UE.Reputation DESC, UE.TotalPosts DESC, DaysSinceLastActivity ASC NULLS LAST
LIMIT 500;
