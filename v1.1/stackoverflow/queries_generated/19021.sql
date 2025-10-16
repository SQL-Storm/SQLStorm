-- {"query": "19021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3480} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.CreationDate AS UserCreationDate,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesReceived,
        U.DownVotes AS UserDownVotesReceived,
        U.DisplayName,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V_GIVEN_UP.PostId) AS TotalUpvotesGiven, -- Upvotes given by user
        COUNT(DISTINCT V_GIVEN_DOWN.PostId) AS TotalDownvotesGiven, -- Downvotes given by user
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(P.CreationDate) AS LastPostCreationDate,
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1,2)) AS AvgPostScore,
        SUM(P.ViewCount) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionViewCount,
        -- Correlated subquery: count of posts with score > 10 within 30 days of user creation
        (SELECT COUNT(P2.Id)
         FROM Posts P2
         WHERE P2.OwnerUserId = U.Id
           AND P2.CreationDate < U.CreationDate + INTERVAL '30 days'
           AND P2.Score > 10) AS PostsHighScoreEarly,
        -- Another correlated subquery: average score of answers accepted by this user's questions
        (SELECT AVG(A.Score)
         FROM Posts Q
         INNER JOIN Posts A ON Q.AcceptedAnswerId = A.Id
         WHERE Q.OwnerUserId = U.Id AND A.OwnerUserId IS NOT NULL) AS AvgAcceptedAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V_GIVEN_UP ON U.Id = V_GIVEN_UP.UserId AND V_GIVEN_UP.VoteTypeId = 2
    LEFT JOIN Votes V_GIVEN_DOWN ON U.Id = V_GIVEN_DOWN.UserId AND V_GIVEN_DOWN.VoteTypeId = 3
    GROUP BY U.Id, U.CreationDate, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.DisplayName, U.Location
),
PostComplexMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        EXTRACT(DAY FROM (NOW() - P.CreationDate)) AS PostAgeDays,
        (SELECT COUNT(PH.Id)
         FROM PostHistory PH
         WHERE PH.PostId = P.Id
           AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Title, Body, Tags edits
        COALESCE(EXTRACT(DAY FROM (P.LastActivityDate - P.LastEditDate)), 0) AS DaysSinceLastEdit,
        -- Window function: Rank of this post among user's posts by score
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate ASC) AS UserPostScoreRank,
        -- Window function: Average score of posts by the same user created around the same time (e.g., within 30 days)
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate RANGE BETWEEN '15 days' PRECEDING AND '15 days' FOLLOWING) AS AvgUserScoreRolling30Days,
        -- Window function: Lag for previous post's creation date for the same user
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostCreationDate,
        LOWER(SUBSTRING(COALESCE(P.Title, ''), 1, 50)) AS LowerTitlePrefix,
        NULLIF(P.CommentCount, 0) * 1.0 / NULLIF(P.ViewCount, 0) AS CommentViewRatio,
        CASE
            WHEN P.Body LIKE '%<pre><code>%' THEN 'ContainsCode'
            WHEN P.Body LIKE '%<img src=%' THEN 'ContainsImage'
            WHEN P.Body LIKE '%<a href=%' THEN 'ContainsLink'
            ELSE 'NoSpecialContent'
        END AS BodyContentIndicator,
        (SELECT MIN(CAST(PH.Comment AS INT)) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$') AS CloseReasonId_IfClosed,
        -- String array processing for tags, handling potential NULL or empty tags
        CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
             THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')
             ELSE ARRAY[]::VARCHAR[]
        END AS TagsArray
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Only questions and answers
),
RelatedPostActivity AS (
    SELECT
        PC.Id AS PostId,
        COUNT(DISTINCT PL_LINKED.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT PL_DUP.RelatedPostId) AS DuplicateOfCount,
        MAX(PH_CLOSED.CreationDate) AS LastClosedDate,
        MAX(PH_REOPENED.CreationDate) AS LastReopenedDate,
        -- Correlated subquery: check if any related answer has a high score
        EXISTS (SELECT 1 FROM Posts PR WHERE PR.ParentId = PC.Id AND PR.Score > 50 AND PR.PostTypeId = 2) AS HasHighScoreAnswer,
        -- Correlated subquery: sum of bounty amounts on answers related to this question
        (SELECT COALESCE(SUM(V.BountyAmount), 0) FROM Votes V INNER JOIN Posts A ON V.PostId = A.Id WHERE A.ParentId = PC.Id AND V.VoteTypeId = 8) AS TotalBountyOnAnswers,
        -- Correlated subquery: count of unique users who edited related posts
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH INNER JOIN PostLinks PL ON PH.PostId = PL.RelatedPostId WHERE PL.PostId = PC.Id AND PH.UserId IS NOT NULL) AS UniqueEditorCountOnRelatedPosts
    FROM Posts PC
    LEFT JOIN PostLinks PL_LINKED ON PC.Id = PL_LINKED.PostId AND PL_LINKED.LinkTypeId = 1 -- Linked
    LEFT JOIN PostLinks PL_DUP ON PC.Id = PL_DUP.PostId AND PL_DUP.LinkTypeId = 3 -- Duplicate
    LEFT JOIN PostHistory PH_CLOSED ON PC.Id = PH_CLOSED.PostId AND PH_CLOSED.PostHistoryTypeId = 10 -- Closed
    LEFT JOIN PostHistory PH_REOPENED ON PC.Id = PH_REOPENED.PostId AND PH_REOPENED.PostHistoryTypeId = 11 -- Reopened
    GROUP BY PC.Id
)
-- Main query combining all CTEs and other tables
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.GoldBadges,
    UE.UserLocation,
    PM.PostId,
    PM.PostTypeId,
    PM.PostCreationDate,
    PM.PostScore,
    PM.ViewCount,
    PM.PostAgeDays,
    PM.EditCount,
    PM.DaysSinceLastEdit,
    PM.UserPostScoreRank,
    PM.AvgUserScoreRolling30Days,
    PM.LowerTitlePrefix,
    PM.CommentViewRatio,
    PM.BodyContentIndicator,
    PM.CloseReasonId_IfClosed,
    ARRAY_LENGTH(PM.TagsArray, 1) AS NumberOfTags,
    RPA.LinkedPostsCount,
    RPA.DuplicateOfCount,
    RPA.LastClosedDate,
    RPA.HasHighScoreAnswer,
    RPA.TotalBountyOnAnswers,
    RPA.UniqueEditorCountOnRelatedPosts,
    -- NULL logic and complex expressions
    NULLIF(UE.TotalQuestions, 0) AS ValidTotalQuestions, -- Example of NULLIF
    CASE
        WHEN UE.TotalPosts > 100 AND PM.PostScore > 50 AND PM.PostAgeDays < 365 THEN 'HighImpactRecentPost'
        WHEN UE.TotalPosts > 50 AND PM.UserPostScoreRank = 1 THEN 'TopPostByActiveUser'
        WHEN RPA.DuplicateOfCount > 0 AND PM.CloseReasonId_IfClosed IS NOT NULL THEN 'DuplicatedAndClosed'
        WHEN PM.BodyContentIndicator = 'ContainsCode' AND PM.CommentViewRatio < 0.01 THEN 'CodeWithLowEngagement'
        ELSE 'StandardPost'
    END AS PostCategory,
    -- Join with Tags table for primary tag info (using the first tag in the array)
    (SELECT T.TagName FROM Tags T WHERE T.TagName = PM.TagsArray[1] LIMIT 1) AS PrimaryTagName,
    -- Another correlated subquery using aggregated data
    (SELECT COUNT(P3.Id)
     FROM Posts P3
     WHERE P3.OwnerUserId = UE.UserId
       AND P3.CreationDate > PM.PrevPostCreationDate
       AND P3.CreationDate < PM.PostCreationDate
       AND P3.Score > PM.PostScore * 0.5) AS InterveningHigherScoringPostsCount
FROM UserEngagement UE
INNER JOIN PostComplexMetrics PM ON UE.UserId = PM.OwnerUserId
LEFT JOIN RelatedPostActivity RPA ON PM.PostId = RPA.PostId
WHERE
    UE.Reputation > 5000
    AND PM.PostScore >= 10
    AND PM.PostAgeDays <= 1095 -- Posts within 3 years
    AND PM.PostTypeId = 1 -- Only questions for the main result set
    AND PM.EditCount > 0 -- Has been edited at least once
    AND (PM.CommentViewRatio IS NULL OR PM.CommentViewRatio < 0.05) -- Low comment-to-view ratio or no comments/views
    AND PM.LowerTitlePrefix LIKE 'how to %'
    AND EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UE.UserId AND B.Name = 'Enthusiast') -- User has a specific badge
    -- Complex predicate with OR and AND, involving NULL logic
    AND (
        (UE.TotalQuestions > 20 AND UE.AvgPostScore > 15 AND UE.LastPostCreationDate > NOW() - INTERVAL '6 months')
        OR
        (RPA.DuplicateOfCount > 0 AND RPA.LastClosedDate IS NOT NULL AND RPA.LastReopenedDate IS NULL AND RPA.HasHighScoreAnswer = FALSE)
    )
    -- Additional NULL logic check, ensuring no closed code questions without a reason
    AND NOT (PM.CloseReasonId_IfClosed IS NULL AND PM.BodyContentIndicator = 'ContainsCode' AND PM.PostScore < 20)
    -- Exclude posts from users with very high downvote activity
    AND UE.TotalDownvotesGiven < UE.TotalUpvotesGiven * 0.2
    AND ARRAY_LENGTH(PM.TagsArray, 1) > 0 -- Ensure there's at least one tag
-- Set operator to combine with highly favorited and accepted answers
UNION ALL
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.GoldBadges,
    UE.UserLocation,
    PM.PostId,
    PM.PostTypeId,
    PM.PostCreationDate,
    PM.PostScore,
    PM.ViewCount,
    PM.PostAgeDays,
    PM.EditCount,
    PM.DaysSinceLastEdit,
    PM.UserPostScoreRank,
    PM.AvgUserScoreRolling30Days,
    PM.LowerTitlePrefix,
    PM.CommentViewRatio,
    PM.BodyContentIndicator,
    PM.CloseReasonId_IfClosed,
    ARRAY_LENGTH(PM.TagsArray, 1) AS NumberOfTags,
    RPA.LinkedPostsCount,
    RPA.DuplicateOfCount,
    RPA.LastClosedDate,
    RPA.HasHighScoreAnswer,
    RPA.TotalBountyOnAnswers,
    RPA.UniqueEditorCountOnRelatedPosts,
    NULLIF(UE.TotalQuestions, 0) AS ValidTotalQuestions,
    'HighlyFavoritedAnswer' AS PostCategory,
    (SELECT T.TagName FROM Tags T WHERE T.TagName = PM.TagsArray[1] LIMIT 1) AS PrimaryTagName,
    (SELECT COUNT(P3.Id)
     FROM Posts P3
     WHERE P3.OwnerUserId = UE.UserId
       AND P3.CreationDate > PM.PrevPostCreationDate
       AND P3.CreationDate < PM.PostCreationDate
       AND P3.Score > PM.PostScore * 0.5) AS InterveningHigherScoringPostsCount
FROM UserEngagement UE
INNER JOIN PostComplexMetrics PM ON UE.UserId = PM.OwnerUserId
LEFT JOIN RelatedPostActivity RPA ON PM.PostId = RPA.PostId
WHERE
    PM.PostTypeId = 2 -- Only answers for this part
    AND PM.PostScore > 150 -- Very high score answers
    AND PM.FavoriteCount > 25 -- Many favorites
    AND PM.PostAgeDays > 730 -- Older answers (at least 2 years old)
    AND UE.Reputation > 20000 -- By very high reputation users
    AND PM.OwnerUserId IS NOT NULL
    AND PM.AcceptedAnswerId IS NOT NULL -- The answer was accepted
    AND PM.BodyContentIndicator = 'ContainsCode' -- Specifically answers containing code
    AND RPA.TotalBountyOnAnswers > 0 -- Had bounty on its parent question
ORDER BY Reputation DESC, PostScore DESC, PostCreationDate ASC
LIMIT 2000;
