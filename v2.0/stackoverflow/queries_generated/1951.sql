-- {"query": "1951.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3153} 

WITH UserCoreStats AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60*60*24) AS UserTenureDays,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
PostDetailedStats AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score AS PostScore,
        P.ViewCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate AS PostLastEditDate,
        P.ClosedDate AS PostClosedDate,
        P.FavoriteCount,
        COALESCE(P.Tags, '') AS TagsString,
        (SELECT COUNT(DISTINCT PH.UserId)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6, 9, 24) -- Edit types
        ) AS DistinctEditors,
        (SELECT COUNT(PH.Id)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6, 9, 24, 50) -- Edit and CommunityBump types
        ) AS TotalRevisionsAndBumps,
        (SELECT AVG(C.Score)
         FROM Comments C
         WHERE C.PostId = P.Id AND C.CreationDate > P.CreationDate AND C.UserId IS NOT NULL
        ) AS AvgCommentScoreForPost,
        EXISTS (SELECT 1 FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS HasCloseHistory,
        EXISTS (SELECT 1 FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 11) AS HasReopenHistory,
        (SELECT CR.Name
         FROM PostHistory PH
         JOIN CloseReasonTypes CR ON CAST(PH.Comment AS smallint) = CR.Id
         WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10
         ORDER BY PH.CreationDate DESC LIMIT 1
        ) AS LastCloseReason,
        CASE
            WHEN P.PostTypeId = 2 THEN EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = P.ParentId AND Q.AcceptedAnswerId = P.Id)
            ELSE FALSE
        END AS IsAcceptedAnswer
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community user (-1) or deleted users
),
UserReceivedVotes AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceivedOnPosts
    FROM Posts P
    JOIN Votes V ON P.Id = V.PostId
    WHERE P.OwnerUserId IS NOT NULL AND V.VoteTypeId IN (2,3)
    GROUP BY P.OwnerUserId
),
UserPostAggregates AS (
    SELECT
        PDS.OwnerUserId AS UserId,
        AVG(PDS.PostScore) FILTER (WHERE PDS.PostScore IS NOT NULL) AS UserAvgPostScore,
        SUM(PDS.FavoriteCount) AS TotalFavoriteCountReceived,
        MAX(PDS.TotalRevisionsAndBumps) AS MaxPostRevisionsAndBumps,
        SUM(PDS.DistinctEditors) AS TotalDistinctEditorsAcrossPosts,
        AVG(PDS.AvgCommentScoreForPost) FILTER (WHERE PDS.AvgCommentScoreForPost IS NOT NULL) AS UserAvgCommentScoreOnOwnPosts,
        COUNT(PDS.PostId) FILTER (WHERE PDS.HasCloseHistory) AS PostsWithCloseHistoryCount,
        COUNT(PDS.PostId) FILTER (WHERE PDS.HasReopenHistory) AS PostsWithReopenHistoryCount,
        MAX(PDS.PostCreationDate) AS LatestPostDate,
        COUNT(PDS.PostId) FILTER (WHERE PDS.IsAcceptedAnswer) AS AcceptedAnswersCount
    FROM PostDetailedStats PDS
    GROUP BY PDS.OwnerUserId
),
TagPerformance AS (
    SELECT
        PDS.OwnerUserId,
        TRIM(unnest(string_to_array(substring(PDS.TagsString, 2, length(PDS.TagsString)-2), '><'))) AS TagName,
        COUNT(PDS.PostId) AS PostsInTag,
        SUM(PDS.PostScore) AS TotalTagScore,
        AVG(PDS.PostScore) AS AvgTagPostScore
    FROM PostDetailedStats PDS
    WHERE PDS.TagsString IS NOT NULL AND PDS.TagsString != '' AND PDS.PostTypeId = 1 -- Only questions have tags
    GROUP BY PDS.OwnerUserId, TRIM(unnest(string_to_array(substring(PDS.TagsString, 2, length(PDS.TagsString)-2), '><')))
),
TopUserTagPerformance AS (
    SELECT
        tp.OwnerUserId AS UserId,
        ARRAY_AGG(tp.TagName ORDER BY tp.TotalTagScore DESC, tp.PostsInTag DESC) FILTER (WHERE tp.TagName IS NOT NULL AND tp.rn <= 3) AS Top3Tags,
        SUM(CASE WHEN tp.rn = 1 THEN tp.TotalTagScore ELSE 0 END) AS Top1TagTotalScore
    FROM (
        SELECT
            tp_inner.OwnerUserId,
            tp_inner.TagName,
            tp_inner.PostsInTag,
            tp_inner.TotalTagScore,
            ROW_NUMBER() OVER(PARTITION BY tp_inner.OwnerUserId ORDER BY tp_inner.TotalTagScore DESC, tp_inner.PostsInTag DESC) AS rn
        FROM TagPerformance tp_inner
    ) tp
    GROUP BY tp.OwnerUserId
)
SELECT
    U.DisplayName,
    UCS.UserId,
    UCS.Reputation,
    UCS.UserTenureDays,
    COALESCE(UCS.TotalPostsCreated, 0) AS TotalPostsCreated,
    COALESCE(UCS.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UCS.AnswersProvided, 0) AS AnswersProvided,
    COALESCE(UCS.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(UCS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UCS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UCS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(URV.TotalUpVotesReceivedOnPosts, 0) AS TotalUpVotesReceivedOnPosts,
    COALESCE(URV.TotalDownVotesReceivedOnPosts, 0) AS TotalDownVotesReceivedOnPosts,
    COALESCE(UPA.UserAvgPostScore, 0.0) AS UserAvgOverallPostScore,
    COALESCE(UPA.TotalFavoriteCountReceived, 0) AS TotalFavoriteCountReceived,
    COALESCE(UPA.UserAvgCommentScoreOnOwnPosts, 0.0) AS UserAvgCommentScoreOnOwnPosts,
    COALESCE(UPA.MaxPostRevisionsAndBumps, 0) AS MaxRevisionsForSinglePost,
    COALESCE(UPA.TotalDistinctEditorsAcrossPosts, 0) AS TotalDistinctEditorsAcrossPosts,
    COALESCE(UPA.PostsWithCloseHistoryCount, 0) AS PostsWithCloseHistoryCount,
    COALESCE(UPA.PostsWithReopenHistoryCount, 0) AS PostsWithReopenHistoryCount,
    COALESCE(TUTP.Top3Tags, ARRAY[]::varchar[]) AS Top3EngagedTags,
    COALESCE(TUTP.Top1TagTotalScore, 0) AS TopEngagedTagScore,
    COALESCE(UPA.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    -- Calculate a complex weighted performance metric
    (UCS.Reputation * 0.1
     + COALESCE(UCS.TotalPostsCreated, 0) * 0.5
     + COALESCE(UCS.TotalCommentsMade, 0) * 0.2
     + COALESCE(UCS.GoldBadges, 0) * 10
     + COALESCE(UCS.SilverBadges, 0) * 5
     + COALESCE(UCS.BronzeBadges, 0) * 1
     + COALESCE(UPA.UserAvgPostScore, 0) * 0.75
     + COALESCE(TUTP.Top1TagTotalScore, 0) * 0.01
     + COALESCE(UPA.AcceptedAnswersCount, 0) * 2.5
     - COALESCE(URV.TotalDownVotesReceivedOnPosts, 0) * 0.05
    ) AS WeightedPerformanceScore,
    -- Correlated subquery example: average score of answers provided by this user to questions that have been closed
    (SELECT AVG(P.Score)
     FROM Posts P
     WHERE P.OwnerUserId = U.Id
       AND P.PostTypeId = 2 -- Is an answer
       AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = P.ParentId AND Q.ClosedDate IS NOT NULL)
    ) AS AvgAnswerScoreToClosedQuestions,
    -- Window function: Rank users by their WeightedPerformanceScore
    RANK() OVER (ORDER BY (UCS.Reputation * 0.1 + COALESCE(UCS.TotalPostsCreated, 0) * 0.5 + COALESCE(UCS.TotalCommentsMade, 0) * 0.2 + COALESCE(UCS.GoldBadges, 0) * 10 + COALESCE(UCS.SilverBadges, 0) * 5 + COALESCE(UCS.BronzeBadges, 0) * 1 + COALESCE(UPA.UserAvgPostScore, 0) * 0.75 + COALESCE(TUTP.Top1TagTotalScore, 0) * 0.01 + COALESCE(UPA.AcceptedAnswersCount, 0) * 2.5 - COALESCE(URV.TotalDownVotesReceivedOnPosts, 0) * 0.05) DESC) AS PerformanceRank,
    -- Window function: NTILE for Post counts
    NTILE(10) OVER (ORDER BY COALESCE(UCS.TotalPostsCreated, 0) DESC) AS PostCountDecile,
    -- String expression and NULL logic for AboutMe
    CASE
        WHEN U.AboutMe IS NOT NULL AND LENGTH(TRIM(U.AboutMe)) > 100 THEN SUBSTRING(U.AboutMe, 1, 100) || '...'
        WHEN U.AboutMe IS NOT NULL AND LENGTH(TRIM(U.AboutMe)) > 0 THEN TRIM(U.AboutMe)
        ELSE 'No "About Me" provided.'
    END AS AboutMeSnippet,
    -- More complex calculation / expression for ratio
    (COALESCE(UCS.QuestionsAsked, 0) * 100.0 / NULLIF(COALESCE(UCS.TotalPostsCreated, 0), 0)) AS QuestionToPostRatioPct,
    -- Date difference for activity lag in days
    EXTRACT(EPOCH FROM (NOW() - UPA.LatestPostDate)) / (60*60*24) AS DaysSinceLastPostActivity
FROM Users U
LEFT JOIN UserCoreStats UCS ON U.Id = UCS.UserId
LEFT JOIN UserReceivedVotes URV ON U.Id = URV.UserId
LEFT JOIN UserPostAggregates UPA ON U.Id = UPA.UserId
LEFT JOIN TopUserTagPerformance TUTP ON U.Id = TUTP.UserId
WHERE U.Id > 0 -- Exclude community user with Id -1
  AND UCS.Reputation > 1000 -- Filter for users with significant reputation
  AND (U.Location ILIKE '%United States%' OR U.Location IS NULL OR U.Location = '') -- Example complex predicate with NULL logic and string matching (ILIKE for case-insensitivity)
  AND (UCS.TotalPostsCreated IS NULL OR UCS.TotalPostsCreated > 5 OR UCS.TotalCommentsMade > 10) -- Another predicate with NULL logic and OR condition
ORDER BY WeightedPerformanceScore DESC, U.Reputation DESC
LIMIT 100;
