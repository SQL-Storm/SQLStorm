-- {"query": "1422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2789} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user engagement metrics including badge counts and latest activities
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    WHERE U.Reputation >= 1000 -- Filter for users with a minimum reputation
      AND U.CreationDate >= '2010-01-01' -- Only users created after this date
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 5 OR COUNT(DISTINCT C.Id) > 10 -- Users with at least some posting or commenting activity
),
PostHistoricalMetrics AS (
    -- CTE 2: Analyze post history for edits, close/reopen events, and self-edits, calculating time intervals
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits, -- Edit Title, Edit Body, Edit Tags
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10) THEN 1 ELSE 0 END) AS TotalClosedEvents, -- Post Closed
        SUM(CASE WHEN PH.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS TotalReopenedEvents, -- Post Reopened
        SUM(CASE WHEN PH.UserId = P.OwnerUserId AND PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SelfEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (10) THEN PH.CreationDate ELSE NULL END) AS FirstCloseDate,
        -- Calculate average time difference in hours between consecutive self-edits using LAG window function
        AVG(CASE WHEN PH.UserId = P.OwnerUserId AND PH.PostHistoryTypeId IN (4, 5, 6) THEN
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate))) / 3600.0
            ELSE NULL
        END) AS AvgSelfEditIntervalHours
    FROM PostHistory AS PH
    INNER JOIN Posts AS P ON PH.PostId = P.Id
    WHERE PH.CreationDate >= '2020-01-01' -- Focus on recent history events
    GROUP BY PH.PostId
),
QuestionLinkAndTagAnalysis AS (
    -- CTE 3: Analyze linked questions and extract primary tags, including window functions for tag performance
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.Tags,
        Q.CreationDate AS QuestionCreationDate,
        Q.AnswerCount,
        Q.FavoriteCount,
        COUNT(DISTINCT PL.RelatedPostId) AS OutgoingLinks, -- Questions linking out
        COUNT(DISTINCT PL_REV.PostId) AS IncomingLinks, -- Questions being linked to
        -- Extract the primary tag (first tag) from the Tags string
        SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags) - 2) AS PrimaryTag,
        -- Calculate the average score for questions within the same primary tag using an AVG window function
        AVG(Q.Score) OVER (PARTITION BY SUBSTRING(Q.Tags FROM 2 FOR POSITION('>' IN Q.Tags) - 2)) AS AvgScoreForPrimaryTag,
        MAX(CASE WHEN A.AcceptedAnswerId = Q.Id THEN 1 ELSE 0 END) AS HasAcceptedAnswer -- Check if this question has an accepted answer
    FROM Posts AS Q
    LEFT JOIN PostLinks AS PL ON Q.Id = PL.PostId AND PL.LinkTypeId = 1 -- Outgoing links (PostId links to RelatedPostId)
    LEFT JOIN PostLinks AS PL_REV ON Q.Id = PL_REV.RelatedPostId AND PL_REV.LinkTypeId = 1 -- Incoming links (RelatedPostId links to PostId)
    LEFT JOIN Posts AS A ON Q.Id = A.ParentId AND A.PostTypeId = 2 -- Answers to this question (for AcceptedAnswerId check)
    WHERE Q.PostTypeId = 1 -- Only questions
      AND Q.CreationDate >= '2020-01-01'
      AND Q.Tags IS NOT NULL
      AND LENGTH(Q.Tags) > 2 -- Ensure tags string is not empty or just "<>"
    GROUP BY Q.Id, Q.Title, Q.Tags, Q.CreationDate, Q.AnswerCount, Q.FavoriteCount, Q.Score -- Q.Score needed for AVG window function
),
TopQuestionContributors AS (
    -- CTE 4: Identify and rank top questions based on two different criteria using UNION ALL
    -- Branch 1: Questions ranked by score within their primary tag
    SELECT
        QA.QuestionId,
        QA.Title,
        QA.PrimaryTag,
        U.Id AS OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        QA.AvgScoreForPrimaryTag,
        QA.QuestionCreationDate,
        Q.Score AS ContributionMetricValue, -- Using score for this branch
        'HighScoreRank' AS RankingType,
        RANK() OVER (PARTITION BY QA.PrimaryTag ORDER BY Q.Score DESC, QA.QuestionCreationDate DESC) AS RankInPrimaryTag
    FROM QuestionLinkAndTagAnalysis AS QA
    INNER JOIN Posts AS Q ON QA.QuestionId = Q.Id
    INNER JOIN Users AS U ON Q.OwnerUserId = U.Id
    WHERE Q.Score > 100 -- Only consider high-scoring questions
    
    UNION ALL -- Set operator to combine results

    -- Branch 2: Questions ranked by answer count within their primary tag
    SELECT
        QA.QuestionId,
        QA.Title,
        QA.PrimaryTag,
        U.Id AS OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        QA.AvgScoreForPrimaryTag, -- Still useful context
        QA.QuestionCreationDate,
        Q.AnswerCount AS ContributionMetricValue, -- Using answer count for this branch
        'HighAnswerCountRank' AS RankingType,
        RANK() OVER (PARTITION BY QA.PrimaryTag ORDER BY Q.AnswerCount DESC, QA.CreationDate DESC) AS RankInPrimaryTag
    FROM QuestionLinkAndTagAnalysis AS QA
    INNER JOIN Posts AS Q ON QA.QuestionId = Q.Id
    INNER JOIN Users AS U ON Q.OwnerUserId = U.Id
    WHERE Q.AnswerCount > 5 -- Questions with at least 5 answers
)
-- Final SELECT: Combine all CTEs to find users with complex activity patterns and their posts
SELECT
    UE.UserId,
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    UE.GoldBadges,
    UE.SilverBadges,
    P.Id AS PostId,
    P.Title AS PostTitle,
    PT.Name AS PostTypeName,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount AS QuestionAnswerCount,
    P.FavoriteCount,
    COALESCE(PHM.TotalEdits, 0) AS PostTotalEdits,
    COALESCE(PHM.SelfEdits, 0) AS PostSelfEdits,
    PHM.AvgSelfEditIntervalHours,
    PHM.FirstCloseDate,
    QATA.PrimaryTag,
    QATA.OutgoingLinks,
    QATA.IncomingLinks,
    QATA.HasAcceptedAnswer,
    TQC.RankingType,
    TQC.RankInPrimaryTag AS QuestionRankInPrimaryTag,
    TQC.ContributionMetricValue AS QuestionContributionMetric,
    -- String operations and NULL logic on Post Body
    CASE
        WHEN P.Body LIKE '%<a href="https://%' THEN 'ContainsExternalLink'
        WHEN P.Body IS NULL OR LENGTH(P.Body) < 50 THEN 'ShortOrEmptyBody'
        ELSE 'NormalBody'
    END AS BodyCategory,
    -- Complex calculation: interaction score relative to user's reputation, handling division by zero
    (CAST(P.Score AS NUMERIC) + COALESCE(P.AnswerCount, 0) * 2 + COALESCE(P.CommentCount, 0) * 0.5) / NULLIF(UE.Reputation, 0) AS InteractionReputationRatio,
    -- Correlated subquery example: get the latest comment text on this specific post by any user
    (SELECT C.Text
     FROM Comments AS C
     WHERE C.PostId = P.Id
     ORDER BY C.CreationDate DESC
     LIMIT 1) AS LatestCommentText,
    -- Another correlated subquery to check if any linked post is also highly scored, using EXISTS
    (SELECT EXISTS (
        SELECT 1
        FROM PostLinks AS PL_Inner
        INNER JOIN Posts AS P_Linked ON PL_Inner.RelatedPostId = P_Linked.Id
        WHERE PL_Inner.PostId = P.Id
          AND P_Linked.Score > 500
          AND P_Linked.PostTypeId = 1
    )) AS HasHighScoringLinkedQuestion,
    -- Use a ROW_NUMBER window function for ranking posts within a user's activity
    ROW_NUMBER() OVER (PARTITION BY UE.UserId ORDER BY P.Score DESC, P.CreationDate DESC) AS UserPostRank
FROM UserEngagement AS UE
INNER JOIN Posts AS P ON UE.UserId = P.OwnerUserId
INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
LEFT JOIN PostHistoricalMetrics AS PHM ON P.Id = PHM.PostId
LEFT JOIN QuestionLinkAndTagAnalysis AS QATA ON P.Id = QATA.QuestionId
LEFT JOIN TopQuestionContributors AS TQC ON P.Id = TQC.QuestionId AND UE.UserId = TQC.OwnerUserId
WHERE P.CreationDate >= '2021-01-01' -- Focus on recent posts
  AND P.PostTypeId IN (1, 2) -- Only Questions and Answers
  AND (COALESCE(PHM.SelfEdits, 0) > 0 OR COALESCE(QATA.IncomingLinks, 0) > 1) -- Posts that were self-edited or have multiple incoming links
  AND (UE.GoldBadges > 0 OR UE.SilverBadges > 2) -- Users with significant badge achievements
  AND P.ViewCount > 1000 -- Only popular posts
  AND P.Body IS NOT NULL -- Exclude posts with no body
  AND NOT (P.ClosedDate IS NOT NULL AND P.CommunityOwnedDate IS NOT NULL) -- Exclude posts that are both closed AND community-owned
ORDER BY UE.Reputation DESC, UserPostRank ASC, PHM.AvgSelfEditIntervalHours ASC NULLS LAST;
