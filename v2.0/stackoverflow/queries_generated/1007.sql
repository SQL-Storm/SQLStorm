-- {"query": "1007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3002} 

WITH UserAggregates AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMadeByAuthor,
        SUM(P.Score) AS SumPostScoresOwned,
        SUM(P.ViewCount) AS SumPostViewsOwned,
        SUM(COALESCE(P.FavoriteCount, 0)) AS SumPostFavoriteCountsOwned,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntriesOwned,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id ELSE NULL END) AS GoldBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId AND P.Id = PH.PostId -- Link post history to posts owned by the user
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        COALESCE(P.LastEditorDisplayName, (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = P.LastEditorUserId), 'Community') AS LastEditorInfo,
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / 86400 AS DaysSinceCreation, -- Days as a float
        (P.Score * 5 + P.ViewCount * 0.1 + COALESCE(P.AnswerCount, 0) * 10 + P.CommentCount * 3 + COALESCE(P.FavoriteCount, 0) * 15) AS PostEngagementMetric,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCountOnPost, -- Non-correlated subquery
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS LatestCommentDate, -- Non-correlated subquery
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore, -- Window function
        LEAD(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostScore, -- Window function
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRankByUserRecency
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND P.OwnerUserId IS NOT NULL -- Exclude community owned posts (e.g., OwnerUserId = -1)
),
UserPostTagAggregates AS (
    SELECT
        PD.OwnerUserId AS UserId,
        UNNEST(string_to_array(SUBSTRING(PD.Tags FROM 2 FOR LENGTH(PD.Tags)-2), '><')) AS TagName, -- String expression: parsing tags
        SUM(PD.PostScore) AS TagScoreByUser
    FROM PostDetailedMetrics PD
    WHERE PD.PostTypeId = 1 AND PD.Tags IS NOT NULL AND LENGTH(TRIM(PD.Tags)) > 2 -- Ensure tags string is not empty or just "<>"
    GROUP BY PD.OwnerUserId, UNNEST(string_to_array(SUBSTRING(PD.Tags FROM 2 FOR LENGTH(PD.Tags)-2), '><'))
),
UserTopTagRank AS (
    SELECT
        UPTA.UserId,
        UPTA.TagName,
        UPTA.TagScoreByUser,
        RANK() OVER (PARTITION BY UPTA.UserId ORDER BY UPTA.TagScoreByUser DESC, UPTA.TagName ASC) AS RankWithinUserTags
    FROM UserPostTagAggregates UPTA
),
RecentClosedQuestions AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        CR.Name AS CloseReason,
        PH.CreationDate AS CloseHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY PH.CreationDate DESC) AS rn
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CR ON PH.Comment = CR.Id::varchar(20) -- CloseReasonId is in PostHistory.Comment for type 10
    WHERE PHT.Id = 10 -- Post Closed
    AND PH.CreationDate >= NOW() - INTERVAL '90 days'
)
SELECT
    UA.UserId,
    COALESCE(UA.DisplayName, 'Anonymous User #' || UA.UserId) AS DisplayName, -- NULL logic, string expression
    UA.Reputation,
    UA.TotalPostsOwned,
    UA.TotalQuestionsOwned,
    UA.TotalAnswersOwned,
    UA.TotalCommentsMadeByAuthor,
    UA.GoldBadges,
    PD.PostId,
    PD.PostTypeId,
    PD.PostCreationDate,
    PD.PostScore,
    PD.ViewCount,
    PD.Title,
    PD.LastEditorInfo,
    PD.DaysSinceCreation,
    PD.PostEngagementMetric,
    PD.UpvoteCountOnPost,
    PD.LatestCommentDate,
    PD.PreviousPostScore,
    PD.NextPostScore,
    PD.PostRankByUserRecency,
    (
        SELECT AVG(PD2.PostScore)
        FROM PostDetailedMetrics PD2
        WHERE PD2.OwnerUserId = UA.UserId
          AND PD2.PostCreationDate < PD.PostCreationDate
          AND PD2.PostRankByUserRecency <= 5 -- Correlated subquery: average score of user's 5 most recent previous posts
    ) AS AvgPrevious5PostScores,
    (
        SELECT MAX(PH.CreationDate)
        FROM PostHistory PH
        WHERE PH.PostId = PD.PostId
          AND PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
          AND PH.CreationDate > PD.PostCreationDate -- Only edits after initial creation
    ) AS LastContentEditDate, -- Correlated subquery
    UTTR.TagName AS TopTagNameForUser,
    UTTR.TagScoreByUser AS TopTagScoreForUser,
    CASE -- Complicated predicate/expression
        WHEN UA.Reputation >= 10000 AND UA.TotalPostsOwned >= 50 AND UA.GoldBadges >= 5 THEN 'High-Impact Veteran'
        WHEN UA.Reputation >= 5000 AND UA.TotalCommentsMadeByAuthor >= 100 AND UA.SumPostScoresOwned >= 500 THEN 'Experienced Leader'
        WHEN UA.TotalPostsOwned >= 20 AND PD.PostEngagementMetric > 500 AND PD.DaysSinceCreation < 365 THEN 'Active Contributor'
        ELSE 'Emerging User'
    END AS UserEngagementTier,
    NTILE(5) OVER (ORDER BY UA.Reputation DESC, UA.SumPostScoresOwned DESC) AS ReputationQuintile, -- Window function
    RANK() OVER (ORDER BY PD.PostEngagementMetric DESC, PD.PostCreationDate DESC) AS GlobalPostEngagementRank, -- Window function
    CONCAT(COALESCE(UA.DisplayName, 'Anon'), ' (Location: ', COALESCE(UA.Location, 'Unknown'), ')') AS UserDisplayLocation, -- String expression, NULL logic
    UPPER(SUBSTRING(PD.Title FROM 1 FOR 15)) AS UpperTitlePrefix, -- String expression
    LQC.CloseReason AS LastQuestionCloseReason,
    LQC.CloseHistoryDate AS LastQuestionCloseDate,
    AGE(NOW(), UA.UserCreationDate) AS UserAccountAge -- Complicated calculation (date function)
FROM UserAggregates UA
JOIN PostDetailedMetrics PD ON UA.UserId = PD.OwnerUserId
LEFT JOIN UserTopTagRank UTTR ON UA.UserId = UTTR.UserId AND UTTR.RankWithinUserTags = 1 -- Outer join for top tag
LEFT JOIN RecentClosedQuestions LQC ON UA.UserId = LQC.OwnerUserId AND LQC.rn = 1 -- Outer join for last closed question
WHERE
    PD.PostScore >= 5
    AND PD.ViewCount > 100
    AND (
        (PD.PostTypeId = 1 AND COALESCE(PD.AnswerCount, 0) >= 1) -- Complicated predicate/NULL logic
        OR (PD.PostTypeId = 2 AND PD.AcceptedAnswerId IS NOT NULL)
    )
    AND UA.Reputation > 100
    AND UA.TotalPostsOwned > 5
    AND PD.PostCreationDate BETWEEN NOW() - INTERVAL '2 years' AND NOW() -- Filter for recent activity
    AND (UA.AboutMe IS NOT NULL OR UA.WebsiteUrl IS NOT NULL) -- NULL logic in WHERE clause
    AND NOT EXISTS ( -- Correlated subquery to exclude posts with recent negative votes
        SELECT 1 FROM Votes V
        WHERE V.PostId = PD.PostId
          AND V.VoteTypeId IN (4, 12) -- Offensive, Spam
          AND V.CreationDate >= NOW() - INTERVAL '1 year'
    )

UNION ALL -- Set operator

-- Second part of the UNION ALL for users with high comment activity but potentially lower direct post engagement
SELECT
    UA.UserId,
    COALESCE(UA.DisplayName, 'Anonymous User #' || UA.UserId) AS DisplayName,
    UA.Reputation,
    UA.TotalPostsOwned,
    UA.TotalQuestionsOwned,
    UA.TotalAnswersOwned,
    UA.TotalCommentsMadeByAuthor,
    UA.GoldBadges,
    NULL AS PostId, -- No specific post for this branch
    NULL AS PostTypeId,
    NULL AS PostCreationDate,
    NULL AS PostScore,
    NULL AS ViewCount,
    'N/A - Top Commenter Summary' AS Title,
    'N/A' AS LastEditorInfo,
    NULL AS DaysSinceCreation,
    (UA.TotalCommentsMadeByAuthor * 5 + UA.UserUpVotesGiven * 0.5 - UA.UserDownVotesGiven * 0.2) AS PostEngagementMetric, -- Reusing column for overall engagement
    NULL AS UpvoteCountOnPost,
    NULL AS LatestCommentDate,
    NULL AS PreviousPostScore,
    NULL AS NextPostScore,
    NULL AS PostRankByUserRecency,
    NULL AS AvgPrevious5PostScores,
    NULL AS LastContentEditDate,
    NULL AS TopTagNameForUser,
    NULL AS TopTagScoreForUser,
    'Comment Elite' AS UserEngagementTier,
    NTILE(5) OVER (ORDER BY UA.TotalCommentsMadeByAuthor DESC, UA.Reputation DESC) AS ReputationQuintile, -- Window function
    NULL AS GlobalPostEngagementRank,
    CONCAT(COALESCE(UA.DisplayName, 'Anon'), ' (Location: ', COALESCE(UA.Location, 'Unknown'), ')') AS UserDisplayLocation,
    NULL AS UpperTitlePrefix,
    NULL AS LastQuestionCloseReason,
    NULL AS LastQuestionCloseDate,
    AGE(NOW(), UA.UserCreationDate) AS UserAccountAge
FROM UserAggregates UA
WHERE
    UA.TotalCommentsMadeByAuthor >= 50
    AND UA.Reputation > 500
    AND UA.TotalPostsOwned < 10 -- Focus on users who comment more than post
    AND NOT EXISTS ( -- Exclude users who own posts that were recently closed (avoiding overlap with first part)
        SELECT 1 FROM RecentClosedQuestions RCQ
        WHERE RCQ.OwnerUserId = UA.UserId
          AND RCQ.rn = 1
    )
ORDER BY Reputation DESC, PostEngagementMetric DESC, PostCreationDate DESC;
