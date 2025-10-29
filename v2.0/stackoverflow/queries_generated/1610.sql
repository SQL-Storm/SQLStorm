-- {"query": "1610.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4002} 

WITH UserEngagement AS (
    -- Summarizes key engagement metrics for users, including badge counts and aggregated post/comment scores.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    -- Extracts temporal and event-based metrics from Posts and PostHistory for questions.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.OwnerUserId,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Tags,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS FirstClosedDate, -- Post Closed
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate, -- Post Reopened
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate, -- Edit Title, Body, Tags
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS EditCount, -- Edit/Rollback events
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseEvents,
        -- Correlated subquery: Count long comments made within 24 hours of post creation
        (SELECT COUNT(DISTINCT Cmt.Id) FROM Comments AS Cmt WHERE Cmt.PostId = P.Id AND Cmt.CreationDate < P.CreationDate + INTERVAL '1 day' AND LENGTH(Cmt.Text) > 50) AS InitialDayLongComments
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.PostTypeId = 1 -- Focus on questions only
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.AcceptedAnswerId, P.ParentId, P.Score, P.ViewCount, P.OwnerUserId, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Tags
),
TagAnalysis AS (
    -- Analyzes tags associated with each question, counting tags and identifying specific categories.
    SELECT
        PHM.PostId,
        COALESCE(ARRAY_LENGTH(string_to_array(NULLIF(SUBSTRING(PHM.Tags, 2, LENGTH(PHM.Tags)-2), ''), '><'), 1), 0) AS NumberOfTags,
        SUM(CASE WHEN T.TagName IS NOT NULL THEN T.Count ELSE 0 END) AS TotalTagUsageCount, -- Sum of global counts of individual tags
        MAX(CASE WHEN T.TagName ILIKE '%sql%' OR T.TagName ILIKE '%database%' OR T.TagName ILIKE '%nosql%' THEN 1 ELSE 0 END) AS HasDatabaseTag,
        MAX(CASE WHEN T.TagName ILIKE '%python%' OR T.TagName ILIKE '%java%' OR T.TagName ILIKE '%javascript%' THEN 1 ELSE 0 END) AS HasProgrammingTag
    FROM PostHistoricalMetrics AS PHM
    LEFT JOIN Tags AS T ON T.TagName = ANY(string_to_array(NULLIF(SUBSTRING(PHM.Tags, 2, LENGTH(PHM.Tags)-2), ''), '><'))
    GROUP BY PHM.PostId, PHM.Tags
),
QuestionPerformance AS (
    -- Combines post metrics and tag analysis for questions using a UNION ALL operator to select posts based on two distinct criteria.
    -- First set: High-scoring, well-answered, or highly favorited questions.
    SELECT
        PHM.PostId,
        PHM.PostTypeId,
        PHM.OwnerUserId,
        PHM.PostCreationDate,
        PHM.PostScore,
        PHM.PostViewCount,
        PHM.AnswerCount,
        PHM.FavoriteCount,
        PHM.FirstClosedDate,
        PHM.LastReopenedDate,
        PHM.FirstEditDate,
        PHM.EditCount,
        PHM.InitialDayLongComments,
        TA.NumberOfTags,
        TA.HasDatabaseTag,
        TA.HasProgrammingTag,
        EXTRACT(EPOCH FROM (COALESCE(PHM.LastEditDate, PHM.PostCreationDate) - PHM.PostCreationDate)) / 3600 AS TimeToFirstEditHours,
        (COALESCE(PHM.PostScore, 0) * 1.5 + COALESCE(PHM.PostViewCount, 0) / 10.0 + COALESCE(PHM.AnswerCount, 0) * 5 + COALESCE(PHM.FavoriteCount, 0) * 2) AS RawEngagementScore,
        'HighValue' AS SelectionType,
        CASE
            WHEN PHM.PostScore > 50 AND PHM.AnswerCount >= 5 THEN 'High Impact'
            WHEN PHM.PostScore > 10 AND PHM.AnswerCount >= 1 THEN 'Medium Impact'
            ELSE 'Low Impact'
            ELSE 'Unknown Impact'
        END AS PostImpactCategory
    FROM PostHistoricalMetrics AS PHM
    LEFT JOIN TagAnalysis AS TA ON PHM.PostId = TA.PostId
    WHERE (PHM.PostScore > 100 AND PHM.AnswerCount >= 3) -- High score and answers
       OR (PHM.FavoriteCount > 20)                     -- Many favorites
       OR (PHM.PostViewCount > 10000 AND PHM.AnswerCount > 0) -- High views with answers
    UNION ALL
    -- Second set: Recently active, possibly controversial (closed/reopened) or with many initial comments, excluding duplicates.
    SELECT
        PHM.PostId,
        PHM.PostTypeId,
        PHM.OwnerUserId,
        PHM.PostCreationDate,
        PHM.PostScore,
        PHM.PostViewCount,
        PHM.AnswerCount,
        PHM.FavoriteCount,
        PHM.FirstClosedDate,
        PHM.LastReopenedDate,
        PHM.FirstEditDate,
        PHM.EditCount,
        PHM.InitialDayLongComments,
        TA.NumberOfTags,
        TA.HasDatabaseTag,
        TA.HasProgrammingTag,
        EXTRACT(EPOCH FROM (COALESCE(PHM.LastEditDate, PHM.PostCreationDate) - PHM.PostCreationDate)) / 3600 AS TimeToFirstEditHours,
        (COALESCE(PHM.PostScore, 0) * 1.5 + COALESCE(PHM.PostViewCount, 0) / 10.0 + COALESCE(PHM.AnswerCount, 0) * 5 + COALESCE(PHM.FavoriteCount, 0) * 2) AS RawEngagementScore,
        'ActiveOrControversial' AS SelectionType,
        CASE
            WHEN PHM.PostScore > 50 AND PHM.AnswerCount >= 5 THEN 'High Impact'
            WHEN PHM.PostScore > 10 AND PHM.AnswerCount >= 1 THEN 'Medium Impact'
            ELSE 'Low Impact'
            ELSE 'Unknown Impact'
        END AS PostImpactCategory
    FROM PostHistoricalMetrics AS PHM
    LEFT JOIN TagAnalysis AS TA ON PHM.PostId = TA.PostId
    WHERE PHM.LastEditDate > CURRENT_DATE - INTERVAL '6 months' -- Recently active
      AND (PHM.CloseEvents > 0 OR PHM.CommentCount > 15 OR PHM.InitialDayLongComments > 0) -- Potentially controversial or high discussion
      AND NOT EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.RelatedPostId = PHM.PostId AND PL.LinkTypeId = 3) -- Not a duplicate *source*
),
UserQuestionStats AS (
    -- Aggregates question-related statistics for each user, including a rank based on engagement within their geographical location.
    SELECT
        QE.OwnerUserId AS UserId,
        COUNT(DISTINCT QE.PostId) AS UserTotalQuestionsConsidered,
        SUM(QE.RawEngagementScore) AS UserTotalEngagementScore,
        AVG(QE.PostScore) AS UserAvgQuestionScore,
        MAX(QE.PostViewCount) AS UserMaxQuestionViews,
        MIN(QE.TimeToFirstEditHours) AS UserMinTimeToFirstEditHours,
        COUNT(CASE WHEN QE.HasDatabaseTag = 1 THEN QE.PostId END) AS UserDatabaseQuestions,
        COUNT(CASE WHEN QE.HasProgrammingTag = 1 THEN QE.PostId END) AS UserProgrammingQuestions,
        -- Window function: Rank users by engagement within defined geographical location groups
        RANK() OVER (PARTITION BY UE_Loc.UserLocationGroup ORDER BY SUM(QE.RawEngagementScore) DESC, COUNT(DISTINCT QE.PostId) DESC) AS RankByEngagementInLocation
    FROM QuestionPerformance AS QE
    JOIN Users AS U ON QE.OwnerUserId = U.Id
    JOIN (
        -- Subquery to categorize users into broad geographical groups based on their 'Location' string.
        SELECT Id,
               CASE
                   WHEN Location IS NULL OR Location = '' THEN 'Unknown'
                   WHEN LOWER(Location) LIKE '%us%' OR LOWER(Location) LIKE '%usa%' OR LOWER(Location) LIKE '%america%' THEN 'USA'
                   WHEN LOWER(Location) LIKE '%india%' THEN 'India'
                   WHEN LOWER(Location) LIKE '%europe%' OR LOWER(Location) LIKE '%uk%' OR LOWER(Location) LIKE '%germany%' OR LOWER(Location) LIKE '%france%' OR LOWER(Location) LIKE '%spain%' THEN 'Europe'
                   WHEN LOWER(Location) LIKE '%canada%' THEN 'Canada'
                   WHEN LOWER(Location) LIKE '%australia%' THEN 'Australia'
                   ELSE 'Other'
               END AS UserLocationGroup
        FROM Users
    ) AS UE_Loc ON U.Id = UE_Loc.Id
    GROUP BY QE.OwnerUserId, UE_Loc.UserLocationGroup
)
SELECT
    UE.Id AS UserId,
    UE.DisplayName,
    UES.Reputation,
    UES.GoldBadges,
    UES.TotalPosts,
    UES.QuestionsPosted,
    UES.AnswersPosted,
    UES.TotalPostScore,
    UES.TotalCommentScore,
    UQS.UserTotalQuestionsConsidered,
    UQS.UserTotalEngagementScore,
    UQS.UserAvgQuestionScore,
    UQS.UserMaxQuestionViews,
    UQS.UserMinTimeToFirstEditHours,
    UQS.UserDatabaseQuestions,
    UQS.UserProgrammingQuestions,
    UQS.RankByEngagementInLocation,
    QP.PostId,
    QP.PostCreationDate,
    QP.PostScore,
    QP.PostViewCount,
    QP.AnswerCount,
    QP.FavoriteCount,
    QP.FirstClosedDate,
    QP.LastReopenedDate,
    QP.EditCount,
    QP.TimeToFirstEditHours,
    QP.InitialDayLongComments,
    QP.NumberOfTags,
    QP.HasDatabaseTag,
    QP.HasProgrammingTag,
    QP.PostImpactCategory,
    QP.SelectionType,
    PH_CR.Text AS LastCloseVoteUsers, -- Contains JSON string of users who voted to close if PostHistoryTypeId = 10
    COALESCE(CLT.Name, 'NoCloseReason') AS DominantCloseReasonName,
    -- Window functions: Compare a question's engagement score with the previous and next questions by the same user.
    LAG(QP.RawEngagementScore, 1, 0) OVER (PARTITION BY UE.Id ORDER BY QP.PostCreationDate) AS PreviousQuestionEngagementScore,
    LEAD(QP.RawEngagementScore, 1, 0) OVER (PARTITION BY UE.Id ORDER BY QP.PostCreationDate) AS NextQuestionEngagementScore,
    -- Complex CASE expression for classifying post lifecycle status.
    CASE
        WHEN QP.FirstClosedDate IS NOT NULL AND QP.LastReopenedDate IS NULL
             AND (EXTRACT(DAY FROM (CURRENT_DATE - QP.FirstClosedDate)) < 90) THEN 'RecentlyClosed_NotReopened'
        WHEN QP.FirstClosedDate IS NOT NULL AND QP.LastReopenedDate IS NOT NULL
             AND QP.FirstClosedDate < QP.LastReopenedDate
             AND (EXTRACT(DAY FROM (QP.LastReopenedDate - QP.FirstClosedDate)) < 7) THEN 'QuicklyReopened'
        WHEN QP.PostCreationDate < CURRENT_DATE - INTERVAL '2 year'
             AND QP.AnswerCount = 0 AND QP.PostViewCount > 5000 THEN 'OldUnansweredHighViews'
        WHEN EXISTS (
            -- Correlated subquery: Check if this post is a duplicate of a higher-scoring post by a different user.
            SELECT 1 FROM PostLinks PL WHERE PL.PostId = QP.PostId AND PL.LinkTypeId = 3 -- Duplicate link type
            AND PL.RelatedPostId IN (SELECT Q2.PostId FROM QuestionPerformance Q2 WHERE Q2.PostScore > QP.PostScore AND Q2.OwnerUserId <> QP.OwnerUserId)
        ) THEN 'DuplicateOfHigherScoringOtherUserPost'
        ELSE 'Normal'
    END AS PostLifecycleStatus
FROM Users AS UE
JOIN UserEngagement AS UES ON UE.Id = UES.UserId
LEFT JOIN UserQuestionStats AS UQS ON UE.Id = UQS.UserId
LEFT JOIN QuestionPerformance AS QP ON UE.Id = QP.OwnerUserId
LEFT JOIN PostHistory AS PH_CR ON QP.PostId = PH_CR.PostId
    AND PH_CR.PostHistoryTypeId = 10 -- Post Closed event
    AND PH_CR.CreationDate = QP.FirstClosedDate -- Link to the first close event for its comment/reason
LEFT JOIN CloseReasonTypes AS CLT ON CAST(PH_CR.Comment AS SMALLINT) = CLT.Id -- Cast string comment to smallint for join
WHERE UES.Reputation > 20000 -- Filter for highly influential users
  AND UES.GoldBadges >= 5
  AND UES.QuestionsPosted >= 10
  AND UQS.UserTotalQuestionsConsidered IS NOT NULL -- Ensure user has at least one question matching criteria in QuestionPerformance CTE
  AND QP.PostId IS NOT NULL -- Ensure we only include questions from QuestionPerformance
  -- Non-correlated subquery: Question score significantly above the average recent question score.
  AND QP.PostScore > (SELECT COALESCE(AVG(PostScore), 0) FROM Posts WHERE PostTypeId = 1 AND CreationDate > CURRENT_DATE - INTERVAL '1 year') * 1.5
  AND QP.TimeToFirstEditHours < 48 -- Questions edited within 48 hours of creation
  AND (QP.HasDatabaseTag = 1 OR QP.HasProgrammingTag = 1) -- Must be a tech-related question
  AND (
        (QP.FirstClosedDate IS NOT NULL AND QP.LastReopenedDate IS NOT NULL AND QP.FirstClosedDate < QP.LastReopenedDate AND QP.EditCount > 2) -- Closed, reopened and multiple edits
        OR
        (QP.FirstClosedDate IS NULL AND QP.PostCreationDate > CURRENT_DATE - INTERVAL '1 year' AND QP.PostViewCount > 1000 AND QP.InitialDayLongComments > 0) -- New, popular, no closure, early comments
        OR
        (QP.PostImpactCategory = 'High Impact' AND QP.NumberOfTags >= 3) -- High impact with complex tagging
      )
ORDER BY UES.Reputation DESC, UQS.RankByEngagementInLocation ASC, QP.RawEngagementScore DESC, QP.PostCreationDate DESC
LIMIT 500;
