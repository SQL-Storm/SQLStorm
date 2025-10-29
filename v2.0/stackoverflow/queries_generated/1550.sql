-- {"query": "1550.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2868} 

WITH UserActivityMetrics AS (
    -- Summarizes user activity, reputation, post counts, comment counts, and badge information.
    -- Includes complex aggregations and a window function for median post score.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Class) AS HighestBadgeClass, -- 1=Gold (Min), 2=Silver, 3=Bronze (Max)
        MIN(B.Class) AS MostPrestigiousBadgeClass,
        MAX(P.LastActivityDate) AS LastPostActivity,
        AVG(P.CommentCount) AS AvgCommentCountPerPost,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY P.Score) OVER (PARTITION BY U.Id) AS MedianPostScore
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5 AND COUNT(DISTINCT B.Id) > 1
),
PostLifecycleEvents AS (
    -- Tracks key dates and metrics for posts, focusing on questions and answers.
    -- Calculates edit counts and uses ROW_NUMBER for ranking posts per user.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Score AS PostScore,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.Body, -- Including Body for string operations in the final SELECT
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDate,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditOrCreationDate, -- NULL handling
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostRankDesc
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Filter for Questions (1) and Answers (2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.ClosedDate, P.AcceptedAnswerId, P.Score, P.ViewCount, P.Title, P.Tags, P.Body, P.LastEditDate
    HAVING COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) >= 1 -- Only posts that have been edited at least once
),
TagPerformance AS (
    -- Analyzes tag popularity, counting posts per tag and calculating average scores.
    -- Uses RANK() window function to identify popular tags.
    SELECT
        T.TagName,
        T.Id AS TagId,
        COUNT(P.Id) AS PostsWithTagCount,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.Score) AS AvgTagScore,
        RANK() OVER (ORDER BY COUNT(P.Id) DESC, SUM(P.Score) DESC) AS TagPopularityRank,
        LAG(COUNT(P.Id), 1, 0) OVER (ORDER BY COUNT(P.Id) DESC) AS PrevTagPostCount -- LAG for comparison with previous rank
    FROM Tags AS T
    JOIN Posts AS P ON P.Tags LIKE '%' || T.TagName || '%' -- Potentially inefficient string matching, but specified
    WHERE P.PostTypeId = 1 AND P.CreationDate >= '2020-01-01'
    GROUP BY T.Id, T.TagName
    HAVING COUNT(P.Id) > 50
),
ModeratorActionAnalysis AS (
    -- Identifies posts that have been closed or reopened, and the timestamps of these actions.
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastCloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenDate
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
    GROUP BY PH.PostId
    HAVING COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) > 0 OR COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) > 0
),
RecentHighImpactPosts AS (
    -- Filters for recently created posts with high scores by highly reputable users.
    -- Includes a correlated subquery for recent comment count.
    SELECT
        P.Id AS PostId,
        P.Title,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        (SELECT COUNT(C.Id) FROM Comments AS C WHERE C.PostId = P.Id AND C.CreationDate > P.LastActivityDate - INTERVAL '60 days') AS RecentCommentCount,
        SUM(V.BountyAmount) AS TotalBountyAmount
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (8,9) -- BountyStart, BountyClose
    WHERE P.CreationDate >= CURRENT_DATE - INTERVAL '2 year'
      AND P.Score > 20
      AND EXISTS (SELECT 1 FROM UserActivityMetrics UAM WHERE UAM.UserId = P.OwnerUserId AND UAM.Reputation > 5000) -- Correlated subquery for user reputation check
    GROUP BY P.Id, P.Title, P.OwnerUserId, P.Score, P.ViewCount, P.CreationDate, P.LastActivityDate
),
AnswerAcceptanceRatio AS (
    -- Calculates the ratio of questions with accepted answers for each user.
    SELECT
        Q.OwnerUserId,
        COUNT(Q.Id) AS TotalQuestionsByOwner,
        COUNT(Q.AcceptedAnswerId) AS AcceptedAnswerCountByOwner,
        CAST(COUNT(Q.AcceptedAnswerId) AS DECIMAL) / NULLIF(COUNT(Q.Id), 0) AS AcceptanceRatio -- NULLIF for division by zero
    FROM Posts AS Q
    WHERE Q.PostTypeId = 1
    GROUP BY Q.OwnerUserId
),
CombinedPostVoteMetrics AS (
    -- Aggregates vote counts and ratios for each post.
    SELECT
        P.Id AS PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
        (CAST(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END),0)) AS UpVoteRatio
    FROM Posts AS P
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    GROUP BY P.Id
),
QuestionAcceptedAnswerInfo AS (
    -- Gathers specific details about the accepted answer for each question.
    -- Includes calculation for time until accepted answer.
    SELECT
        Q.Id AS QuestionId,
        Q.AcceptedAnswerId,
        A.OwnerUserId AS AcceptedAnswerOwnerUserId,
        A.CreationDate AS AcceptedAnswerCreationDate,
        A.Score AS AcceptedAnswerScore,
        LENGTH(A.Body) AS AcceptedAnswerBodyLength,
        (EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate)) / 3600.0) AS TimeToAcceptedAnswerHours -- Date arithmetic
    FROM Posts AS Q
    INNER JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id
    WHERE Q.PostTypeId = 1 AND A.PostTypeId = 2
)
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    UAM.TotalPosts,
    UAM.TotalQuestions,
    UAM.TotalAnswers,
    UAM.TotalBadges,
    UAM.MostPrestigiousBadgeClass,
    PLC.PostId,
    PLC.Title AS PostTitle,
    PLC.PostCreationDate,
    PLC.PostScore,
    PLC.ViewCount,
    PLC.EditCount,
    PLC.FirstEditDate,
    PLC.LastEditDate,
    MAA.CloseEvents,
    MAA.ReopenEvents,
    TP.TagName AS PrimaryTag,
    TP.AvgTagScore,
    RHP.Title AS RecentHighImpactPostTitle,
    RHP.RecentCommentCount,
    RHP.TotalBountyAmount,
    AAR.AcceptanceRatio,
    (SELECT T2.TagName FROM TagPerformance T2 ORDER BY T2.TagPopularityRank LIMIT 1) AS OverallTopTag, -- Non-correlated subquery for a global stat
    COALESCE(PLC.ClosedDate, PLC.LastEditDate, PLC.PostCreationDate) AS LastSignificantDate, -- NULL logic using COALESCE
    CASE
        WHEN PLC.PostScore > 75 AND PLC.ViewCount > 20000 THEN 'Highly Viral'
        WHEN PLC.PostScore > 25 AND PLC.EditCount >= 5 AND LENGTH(PLC.Body) > 1000 THEN 'Thoroughly Refined Long Post'
        WHEN PLC.ClosedDate IS NOT NULL AND MAA.ReopenEvents > 0 AND (EXTRACT(EPOCH FROM (MAA.LastReopenDate - MAA.LastCloseDate)) / 3600) < 24 * 7 THEN 'Quickly Reopened Controversial'
        WHEN QAA.AcceptedAnswerId IS NOT NULL THEN 'Answered Question'
        ELSE 'Standard Activity'
    END AS PostStatusCategory,
    DENSE_RANK() OVER (ORDER BY UAM.Reputation DESC, UAM.TotalPosts DESC, PLC.PostScore DESC) AS UserPostGlobalRank,
    (EXTRACT(EPOCH FROM (NOW() - PLC.PostCreationDate)) / 86400.0) AS DaysSinceCreation, -- Calculate days since creation
    LOWER(REPLACE(REPLACE(REPLACE(SUBSTRING(COALESCE(PLC.Tags, 'no-tag'), 1, 100), '<', ''), '>', ' '), '-', '_')) AS CleanedTagsSnippet, -- String manipulation
    (
        SELECT AVG(SubQ.PostScore)
        FROM PostLifecycleEvents SubQ
        WHERE SubQ.OwnerUserId = UAM.UserId
          AND SubQ.PostCreationDate >= PLC.PostCreationDate - INTERVAL '180 days'
          AND SubQ.PostCreationDate < PLC.PostCreationDate
    ) AS AvgScoreLast180DaysPrior