-- {"query": "1919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2784} 

WITH UserActivitySummary AS (
    -- Aggregates various activity metrics for users, including post and comment counts, and derived interaction scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS ProfileViews,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        COALESCE(SUM(P.Score), 0) AS TotalPostsScoreSum,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostsViewCountSum,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate)) AS LastOverallPostActivityDate,
        MAX(C.CreationDate) AS LastCommentMadeDate,
        (CAST(U.Reputation AS NUMERIC) * 0.1) + (U.UpVotes * 0.5) - (U.DownVotes * 0.3) + (COUNT(DISTINCT P.Id) * 1.5) AS UserInfluenceScore
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostHistorySnapshot AS (
    -- Captures the latest significant post history event for each post.
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS HistoryEventDate,
        PH.UserId AS HistoryInitiatorUserId,
        PH.Comment AS HistoryDetailComment,
        PH.Text AS HistoryDetailText,
        ROW_NUMBER() OVER(PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC, PH.Id DESC) AS rn_latest_history_event
    FROM PostHistory AS PH
    INNER JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 24, 33, 34, 35, 36, 50) -- Closed, Reopened, Deleted, Undeleted, Locked, Unlocked, Protected, Unprotected, Suggested Edit Applied, Post Notice Added/Removed, Migrated, CommunityBump
),
QuestionTagPerformance AS (
    -- Analyzes performance metrics for each tag, specifically for questions.
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS QuestionsWithTagCount,
        AVG(P.Score) AS AvgQuestionScoreWithTag,
        MAX(P.FavoriteCount) AS MaxFavoriteCountForTag,
        SUM(P.ViewCount) AS TotalViewsForTag
    FROM Posts AS P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))
),
PostCommentAggregates AS (
    -- Aggregates comment scores and identifies recent owner comments for posts.
    SELECT
        P.Id AS PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        AVG(C.Score) AS AverageCommentScoreOnPost,
        MAX(C.CreationDate) AS LatestCommentDateOnPost,
        -- Correlated subquery to find the most recent comment text by the post owner
        (
            SELECT T.Text
            FROM Comments AS T
            WHERE T.PostId = P.Id AND T.UserId = P.OwnerUserId
            ORDER BY T.CreationDate DESC
            LIMIT 1
        ) AS LatestOwnerCommentText
    FROM Posts AS P
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    GROUP BY P.Id, P.OwnerUserId
),
UserBadgeSummary AS (
    -- Summarizes badges earned by users, separating them by class.
    SELECT
        B.UserId,
        STRING_AGG(DISTINCT B.Name, ', ') FILTER (WHERE B.Class = 1) AS GoldBadgesList,
        STRING_AGG(DISTINCT B.Name, ', ') FILTER (WHERE B.Class = 2) AS SilverBadgesList,
        STRING_AGG(DISTINCT B.Name, ', ') FILTER (WHERE B.Class = 3) AS BronzeBadgesList,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges AS B
    GROUP BY B.UserId
)
-- Main complex query for performance benchmarking
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.TotalPostsCreated,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.TotalPostsScoreSum,
    UAS.TotalPostsViewCountSum,
    UAS.TotalCommentsMade,
    UAS.UserInfluenceScore,
    UBS.GoldBadgesList,
    UBS.SilverBadgesList,
    UBS.BronzeBadgesList,
    UBS.GoldBadgeCount,
    UBS.SilverBadgeCount,
    UBS.BronzeBadgeCount,
    P.Id AS PostId,
    PT.Name AS PostType,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.LastActivityDate AS PostLastActivityDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.AnswerCount,
    P.CommentCount AS PostEmbeddedCommentCount,
    P.FavoriteCount,
    COALESCE(P.ClosedDate, 'N/A'::timestamp) AS PostClosedDate, -- NULL Logic
    PHS.HistoryTypeName AS LatestPostHistoryAction,
    PHS.HistoryEventDate AS LatestHistoryActionDate,
    PHS.HistoryDetailComment,
    PHS.HistoryDetailText,
    PCA.TotalCommentsOnPost AS ActualTotalCommentsOnPost,
    COALESCE(PCA.AverageCommentScoreOnPost, 0.0) AS AverageCommentScore,
    PCA.LatestOwnerCommentText,
    COALESCE(QTP.TagName, 'NoTagInfo') AS TopRelatedTag,
    COALESCE(QTP.QuestionsWithTagCount, 0) AS TopRelatedTagQuestionCount,
    COALESCE(QTP.AvgQuestionScoreWithTag, 0.0) AS TopRelatedTagAvgScore,
    -- Complicated Predicates/Expressions/Calculations & String Expressions
    CASE
        WHEN P.Score >= 500 AND P.ViewCount >= 10000 THEN 'Highly Engaged'
        WHEN P.Score >= 100 AND P.ViewCount >= 1000 THEN 'Moderately Engaged'
        WHEN P.Score <= 0 AND P.ViewCount >= 500 THEN 'Controversial/Viewed'
        ELSE 'Low Engagement'
    END AS PostEngagementCategory,
    GREATEST(P.Score * 1.2 + P.ViewCount * 0.05 + P.FavoriteCount * 3 + COALESCE(PCA.AverageCommentScoreOnPost, 0.0) * 5, 0) AS CalculatedPostImpactScore,
    UPPER(SUBSTRING(P.Title, 1, 1)) || LPAD(LENGTH(P.Title)::VARCHAR, 3, '0') || '-' || REPLACE(COALESCE(P.Tags, 'notag'), '><', '_') AS TitleTagFingerprint,
    NULLIF(P.OwnerDisplayName, UAS.DisplayName) AS PotentialRenamedUser, -- NULL Logic
    -- Window Functions
    ROW_NUMBER() OVER (PARTITION BY PT.Id ORDER BY P.Score DESC, P.ViewCount DESC) AS RankWithinPostTypeByScore,
    LAG(P.Score, 1, 0) OVER (PARTITION BY UAS.UserId ORDER BY P.CreationDate) AS PreviousPostScoreByOwner,
    AVG(P.Score) OVER (PARTITION BY UAS.UserId ORDER BY P.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS MovingAvgScoreLast4Posts,
    NTILE(10) OVER (ORDER BY UAS.UserInfluenceScore DESC) AS UserInfluenceDecile,
    -- Non-correlated Subquery for global average
    (
        SELECT AVG(P_Inner.Score)
        FROM Posts AS P_Inner
        WHERE P_Inner.PostTypeId = P.PostTypeId
          AND P_Inner.CreationDate BETWEEN P.CreationDate - INTERVAL '6 months' AND P.CreationDate
    ) AS AvgScoreForPostTypePast6Months,
    -- Set Operations concept (via subqueries or CTEs) - example of finding posts with unique history traits
    P.Id IN (SELECT PH_Link.PostId FROM PostHistory PH_Link WHERE PH_Link.PostHistoryTypeId = 35) AS WasMigratedAway,
    P.Id IN (SELECT PH_Link.PostId FROM PostHistory PH_Link WHERE PH_Link.PostHistoryTypeId = 36) AS WasMigratedHere
FROM UserActivitySummary AS UAS
INNER JOIN Users AS U ON UAS.UserId = U.Id
LEFT JOIN UserBadgeSummary AS UBS ON UAS.UserId = UBS.UserId
LEFT JOIN Posts AS P ON UAS.UserId = P.OwnerUserId
LEFT JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
LEFT JOIN PostHistorySnapshot AS PHS ON P.Id = PHS.PostId AND PHS.rn_latest_history_event = 1
LEFT JOIN PostCommentAggregates AS PCA ON P.Id = PCA.PostId
LEFT JOIN LATERAL ( -- Lateral join to find the best performing tag associated with the post
    SELECT
        QTP_Inner.TagName,
        QTP_Inner.QuestionsWithTagCount,
        QTP_Inner.AvgQuestionScoreWithTag
    FROM QuestionTagPerformance AS QTP_Inner
    WHERE P.Tags LIKE '%' || QTP_Inner.TagName || '%'
    ORDER BY QTP_Inner.QuestionsWithTagCount DESC, QTP_Inner.AvgQuestionScoreWithTag DESC
    LIMIT 1
) AS QTP ON TRUE
WHERE
    UAS.Reputation > 2000 -- Filter for more active/established users
    AND P.Id IS NOT NULL -- Exclude users without posts joined
    AND P.CreationDate >= (NOW() - INTERVAL '3 years') -- Focus on recent activity
    AND (
        P.Title ILIKE '%api%' OR P.Body ILIKE '%json%' OR P.Tags LIKE '%<javascript>%' OR P.Tags LIKE '%<python>%'
        OR EXISTS ( -- Correlated EXISTS subquery
            SELECT 1 FROM Comments C_inner WHERE C_inner.PostId = P.Id AND C_inner.Text ILIKE '%solution%' AND C_inner.CreationDate >= (NOW() - INTERVAL '1 year')
        )
    )
    AND (P.ClosedDate IS NULL OR P.ClosedDate > (NOW() - INTERVAL '6 months')) -- Exclude very old closed posts
ORDER BY
    UAS.UserInfluenceScore DESC, P.CreationDate DESC, P.Score DESC
LIMIT 1000;
