-- {"query": "1028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4333} 
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(B.Id) AS TotalBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        MIN(P.CreationDate) AS FirstPostDate,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (2, 3, 5)) AS LastVoteDate, -- UpMod, DownMod, Favorite
        (SELECT MAX(PH.CreationDate) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS LastHistoryEditDate -- Edited Title/Body/Tags
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS CurrentScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        -- Get the initial body content if available from PostHistory, otherwise use current Body
        COALESCE(
            (SELECT PH_B.Text FROM PostHistory PH_B WHERE PH_B.PostId = P.Id AND PH_B.PostHistoryTypeId = 2 ORDER BY PH_B.CreationDate ASC LIMIT 1),
            P.Body
        ) AS InitialBodyContent,
        -- Count edits on Title (4), Body (5), Tags (6)
        COUNT(PH_Edits.Id) FILTER (WHERE PH_Edits.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        -- Count close (10) and reopen (11) events
        COUNT(PH_ReopenClose.Id) FILTER (WHERE PH_ReopenClose.PostHistoryTypeId = 10) AS CloseCount,
        COUNT(PH_ReopenClose.Id) FILTER (WHERE PH_ReopenClose.PostHistoryTypeId = 11) AS ReopenCount,
        -- Aggregate distinct close reasons, limited to 20 chars
        STRING_AGG(DISTINCT SUBSTRING(CR.Name, 1, 20), ', ') FILTER (WHERE PH_CloseReason.Comment IS NOT NULL AND CR.Name IS NOT NULL) AS CloseReasons,
        -- Complicated predicate: check for specific keywords in initial body or title
        CASE
            WHEN COALESCE(
                (SELECT PH_B.Text FROM PostHistory PH_B WHERE PH_B.PostId = P.Id AND PH_B.PostHistoryTypeId = 2 ORDER BY PH_B.CreationDate ASC LIMIT 1),
                P.Body
            ) ILIKE '%performance%' OR P.Title ILIKE '%benchmark%' THEN 'Performance-Related'
            WHEN COALESCE(
                (SELECT PH_B.Text FROM PostHistory PH_B WHERE PH_B.PostId = P.Id AND PH_B.PostHistoryTypeId = 2 ORDER BY PH_B.CreationDate ASC LIMIT 1),
                P.Body
            ) ILIKE '%security%' OR P.Title ILIKE '%exploit%' THEN 'Security-Related'
            ELSE 'General'
        END AS ContentCategory,
        NULLIF(P.AnswerCount, 0) AS NonZeroAnswerCount,
        -- Correlated subquery to count specific tags (e.g., 'sql') within a post's tags
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN
                (SELECT COUNT(DISTINCT tag) FROM unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag WHERE tag ILIKE '%sql%')
            ELSE 0
        END AS SqlTagMentions,
        (SELECT MAX(V.CreationDate) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 1) AS AcceptedAnswerDate -- AcceptedByOriginator
    FROM Posts P
    LEFT JOIN PostHistory PH_Edits ON P.Id = PH_Edits.PostId
    LEFT JOIN PostHistory PH_ReopenClose ON P.Id = PH_ReopenClose.PostId
    LEFT JOIN PostHistory PH_CloseReason ON P.Id = PH_CloseReason.PostId AND PH_CloseReason.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON PH_CloseReason.Comment = CR.Id::text -- Assuming Comment stores CloseReasonId as text
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate, P.Body, P.Title, P.Tags
),
PostRevisionDetails AS (
    SELECT
        PH.PostId,
        PH.Id AS HistoryId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryUserId,
        PH.Text AS HistoryText,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousRevisionDate,
        PH.Comment AS HistoryComment,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) AS rn_latest_history_type
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (2, 5, 10, 11) -- Initial Body, Edit Body, Post Closed, Post Reopened
),
LatestPostRevisions AS (
    SELECT
        PRD.PostId,
        SUM(CASE WHEN PRD.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
        MAX(PRD.HistoryDate) FILTER (WHERE PRD.PostHistoryTypeId = 5) AS LastBodyEditDate,
        MIN(PRD.HistoryDate) FILTER (WHERE PRD.PostHistoryTypeId = 2) AS FirstBodyCreationDate,
        MAX(PRD.HistoryDate) FILTER (WHERE PRD.PostHistoryTypeId = 10) AS LastClosedDate,
        MAX(PRD.HistoryDate) FILTER (WHERE PRD.PostHistoryTypeId = 11) AS LastReopenedDate,
        MAX(CASE WHEN PRD.PostHistoryTypeId = 10 AND PRD.rn_latest_history_type = 1 THEN PRD.HistoryComment END) AS LatestCloseReasonId
    FROM PostRevisionDetails PRD
    GROUP BY PRD.PostId
),
TagAnalysis AS (
    SELECT
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName,
        P.Id AS PostId,
        P.OwnerUserId,
        'PostTag' AS SourceType
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    UNION ALL
    SELECT
        T.TagName,
        COALESCE(T.ExcerptPostId, T.WikiPostId) AS PostId,
        NULL AS OwnerUserId,
        'OfficialTag' AS SourceType
    FROM Tags T
    WHERE T.ExcerptPostId IS NOT NULL OR T.WikiPostId IS NOT NULL
)
-- Main Query Part 1: High-Engagement Questions and Users
SELECT
    'HighEngagement_Questions' AS AnalysisType,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.TotalBadges,
    UE.GoldBadges,
    (UE.UpVotes - UE.DownVotes) AS NetUserVotes,
    COALESCE(UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastVoteDate, UE.LastHistoryEditDate, UE.LastAccessDate) AS UserMostRecentActivity,
    CASE
        WHEN UE.Reputation >= 10000 THEN 'Legendary'
        WHEN UE.Reputation >= 5000 THEN 'Veteran'
        WHEN UE.Reputation >= 1000 THEN 'Expert'
        WHEN UE.Reputation >= 200 THEN 'Active'
        ELSE 'Novice'
    END AS ReputationTier,
    AVG(PCA.CurrentScore) OVER (PARTITION BY UE.UserId) AS AvgPostScoreByUser, -- Window function
    RANK() OVER (ORDER BY UE.Reputation DESC, UE.UserCreationDate ASC) AS ReputationRank, -- Window function
    P.Id AS Post_Id,
    P.Title AS PostTitle,
    PCA.PostCreationDate,
    PCA.CurrentScore,
    PCA.ViewCount,
    PCA.AnswerCount,
    PCA.FavoriteCount,
    PCA.ContentCategory,
    PCA.EditCount AS TotalPostEditCount,
    LPR.BodyEditCount,
    AGE(CURRENT_TIMESTAMP, PCA.PostCreationDate) AS PostAge,
    EXTRACT(EPOCH FROM (LPR.LastBodyEditDate - PCA.PostCreationDate)) / 3600 AS HoursToLastBodyEdit, -- Calculation
    COALESCE(PCA.NonZeroAnswerCount, 0) AS AnswerCountForRatio,
    NULLIF(PCA.CurrentScore, 0) / NULLIF(PCA.ViewCount, 0)::numeric AS ScorePerViewRatio, -- NULL logic, division
    NULLIF(PCA.CommentCount, 0) / NULLIF(PCA.AnswerCount, 0)::numeric AS CommentsPerAnswerRatio, -- NULL logic
    -- Correlated Subquery: Find the most popular tag for posts owned by this user (only 'PostTag' source)
    (
        SELECT TA.TagName
        FROM TagAnalysis TA
        WHERE TA.OwnerUserId = UE.UserId AND TA.SourceType = 'PostTag'
        GROUP BY TA.TagName
        ORDER BY COUNT(TA.PostId) DESC, TA.TagName ASC
        LIMIT 1
    ) AS MostFrequentTagByOwner,
    LPR.LatestCloseReasonId,
    CR.Name AS LatestCloseReasonName,
    COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostsCount, -- Links to others
    COUNT(PL_Dup.RelatedPostId) FILTER (WHERE PL_Dup.LinkTypeId = 3) AS DuplicatePostsCount -- Duplicates of this post
FROM UserEngagement UE
INNER JOIN Posts P ON UE.UserId = P.OwnerUserId -- INNER JOIN to focus on posts with owners for this branch
LEFT JOIN PostContentAnalysis PCA ON P.Id = PCA.PostId
LEFT JOIN LatestPostRevisions LPR ON P.Id = LPR.PostId
LEFT JOIN CloseReasonTypes CR ON LPR.LatestCloseReasonId = CR.Id::text
LEFT JOIN PostLinks PL ON P.Id = PL.PostId
LEFT JOIN PostLinks PL_Dup ON P.Id = PL_Dup.PostId AND PL_Dup.LinkTypeId = 3
WHERE
    UE.Reputation >= 1000 -- Higher reputation threshold
    AND P.PostTypeId = 1 -- Only questions
    AND P.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
    AND P.Score > 50 AND P.ViewCount > 500
    AND P.Body IS NOT NULL AND LENGTH(P.Body) > 200 -- More substantial posts
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments, UE.TotalBadges, UE.GoldBadges, UE.UpVotes, UE.DownVotes, UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastVoteDate, UE.LastHistoryEditDate, UE.LastAccessDate,
    P.Id, P.Title, PCA.PostCreationDate, PCA.CurrentScore, PCA.ViewCount, PCA.AnswerCount, PCA.FavoriteCount, PCA.ContentCategory, PCA.EditCount, LPR.BodyEditCount, LPR.LastBodyEditDate, LPR.LatestCloseReasonId, CR.Name,
    PCA.NonZeroAnswerCount, P.Body, P.PostTypeId, P.Score, P.ViewCount, P.CommentCount


UNION ALL


-- Main Query Part 2: Low-Engagement/Problematic Answers and Newer Users
SELECT
    'LowEngagement_Problematic_Answers' AS AnalysisType,
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.TotalBadges,
    UE.GoldBadges,
    (UE.UpVotes - UE.DownVotes) AS NetUserVotes,
    COALESCE(UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastVoteDate, UE.LastHistoryEditDate, UE.LastAccessDate) AS UserMostRecentActivity,
    CASE
        WHEN UE.Reputation >= 10000 THEN 'Legendary'
        WHEN UE.Reputation >= 5000 THEN 'Veteran'
        WHEN UE.Reputation >= 1000 THEN 'Expert'
        WHEN UE.Reputation >= 200 THEN 'Active'
        ELSE 'Novice'
    END AS ReputationTier,
    AVG(PCA.CurrentScore) OVER (PARTITION BY UE.UserId) AS AvgPostScoreByUser,
    RANK() OVER (ORDER BY UE.Reputation DESC, UE.UserCreationDate ASC) AS ReputationRank,
    P.Id AS Post_Id,
    P.Title AS PostTitle, -- Title is NULL for answers, but column needed for UNION ALL
    PCA.PostCreationDate,
    PCA.CurrentScore,
    PCA.ViewCount,
    PCA.AnswerCount,
    PCA.FavoriteCount,
    PCA.ContentCategory,
    PCA.EditCount AS TotalPostEditCount,
    LPR.BodyEditCount,
    AGE(CURRENT_TIMESTAMP, PCA.PostCreationDate) AS PostAge,
    EXTRACT(EPOCH FROM (LPR.LastBodyEditDate - PCA.PostCreationDate)) / 3600 AS HoursToLastBodyEdit,
    COALESCE(PCA.NonZeroAnswerCount, 0) AS AnswerCountForRatio,
    NULLIF(PCA.CurrentScore, 0) / NULLIF(PCA.ViewCount, 0)::numeric AS ScorePerViewRatio,
    NULLIF(PCA.CommentCount, 0) / NULLIF(PCA.AnswerCount, 0)::numeric AS CommentsPerAnswerRatio,
    (
        SELECT TA.TagName
        FROM TagAnalysis TA
        WHERE TA.OwnerUserId = UE.UserId AND TA.SourceType = 'PostTag'
        GROUP BY TA.TagName
        ORDER BY COUNT(TA.PostId) DESC, TA.TagName ASC
        LIMIT 1
    ) AS MostFrequentTagByOwner,
    LPR.LatestCloseReasonId,
    CR.Name AS LatestCloseReasonName,
    COUNT(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostsCount,
    COUNT(PL_Dup.RelatedPostId) FILTER (WHERE PL_Dup.LinkTypeId = 3) AS DuplicatePostsCount
FROM UserEngagement UE
INNER JOIN Posts P ON UE.UserId = P.OwnerUserId
LEFT JOIN PostContentAnalysis PCA ON P.Id = PCA.PostId
LEFT JOIN LatestPostRevisions LPR ON P.Id = LPR.PostId
LEFT JOIN CloseReasonTypes CR ON LPR.LatestCloseReasonId = CR.Id::text
LEFT JOIN PostLinks PL ON P.Id = PL.PostId
LEFT JOIN PostLinks PL_Dup ON P.Id = PL_Dup.PostId AND PL_Dup.LinkTypeId = 3
WHERE
    UE.Reputation < 500 -- Lower reputation threshold
    AND P.PostTypeId = 2 -- Only answers
    AND P.CreationDate BETWEEN '2022-01-01' AND '2024-12-31'
    AND (
        (P.Score < 0 AND P.CommentCount > 5) OR -- Negative score but active discussion
        (P.ClosedDate IS NOT NULL AND LPR.LatestCloseReasonId IN ('101', '102')) -- Closed due to duplicate or off-topic (assuming CloseReasonId is string '101'/'102')
    )
    AND P.Body IS NOT NULL AND LENGTH(P.Body) < 150 -- Shorter or less substantial posts
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.TotalQuestions, UE.TotalAnswers, UE.TotalComments, UE.TotalBadges, UE.GoldBadges, UE.UpVotes, UE.DownVotes, UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastVoteDate, UE.LastHistoryEditDate, UE.LastAccessDate,
    P.Id, P.Title, PCA.PostCreationDate, PCA.CurrentScore, PCA.ViewCount, PCA.AnswerCount, PCA.FavoriteCount, PCA.ContentCategory, PCA.EditCount, LPR.BodyEditCount, LPR.LastBodyEditDate, LPR.LatestCloseReasonId, CR.Name,
    PCA.NonZeroAnswerCount, P.Body, P.PostTypeId, P.Score, P.ViewCount, P.CommentCount
ORDER BY
    ReputationRank ASC, UserMostRecentActivity DESC, Post_Id ASC
LIMIT 2000;