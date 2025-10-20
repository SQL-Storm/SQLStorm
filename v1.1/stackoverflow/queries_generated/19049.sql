-- {"query": "19049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4658} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpvotesGivenByUsers,
        U.DownVotes AS TotalDownvotesGivenByUsers,
        COUNT(DISTINCT P.Id) AS UserTotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionsCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswersCount,
        COUNT(DISTINCT C.Id) AS UserTotalComments,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6,7,8,9,14,15,19,20,33,34)) AS UserTotalEditOrModerationActions,
        SUM(P.ViewCount) AS UserTotalPostViews,
        SUM(P.Score) AS UserTotalPostScore,
        COALESCE(SUM(P.FavoriteCount), 0) AS UserTotalPostFavorites,
        COUNT(DISTINCT B.Id) AS UserTotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS UserGoldBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS UserTagBadges,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        MAX(B.Date) AS LastBadgeAwardDate,
        (SELECT COUNT(DISTINCT V_POST_USER.PostId) FROM Votes V_POST_USER WHERE V_POST_USER.UserId = U.Id AND V_POST_USER.VoteTypeId = 1) AS AcceptedAnswersSelectedCount,
        AVG(P_ANS.Score) AS AvgAnswerScoreForOwnQuestions
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P_ANS ON P_ANS.OwnerUserId = U.Id AND P_ANS.PostTypeId = 2
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostComprehensiveMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Body,
        P.OwnerUserId,
        U_OWNER.DisplayName AS OwnerDisplayName,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.AcceptedAnswerId,
        COALESCE(P.ContentLicense, 'CC BY-SA 4.0') AS ContentLicense,
        LENGTH(P.Body) AS BodyCharacterLength,
        CHAR_LENGTH(P.Body) - CHAR_LENGTH(REPLACE(P.Body, '`', '')) AS BacktickCountInBody, -- Simple heuristic for code snippets
        CHAR_LENGTH(P.Body) - CHAR_LENGTH(REPLACE(REPLACE(P.Body, '<pre>', ''), '</pre>', '')) AS PreTagCharacterCount, -- Heuristic for larger code blocks
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')
            ELSE ARRAY[]::VARCHAR[]
        END AS ParsedTagsArray,
        (SELECT COUNT(PH_EDIT.Id) FROM PostHistory PH_EDIT WHERE PH_EDIT.PostId = P.Id AND PH_EDIT.PostHistoryTypeId IN (4, 5, 6)) AS TotalMinorEdits,
        (SELECT COUNT(DISTINCT PH_EDITOR.UserId) FROM PostHistory PH_EDITOR WHERE PH_EDITOR.PostId = P.Id AND PH_EDITOR.PostHistoryTypeId IN (4, 5, 6) AND PH_EDITOR.UserId IS NOT NULL) AS UniqueEditorCount,
        (SELECT MAX(PH_LAST.CreationDate) FROM PostHistory PH_LAST WHERE PH_LAST.PostId = P.Id AND PH_LAST.PostHistoryTypeId IN (4,5,6,7,8,9)) AS LastContentEditDate,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId IN (4, 12)) AS FlagVoteCount, -- Offensive/Spam
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS LinkedPostsOutCount,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id AND PL.LinkTypeId = 1) AS LinkedPostsInCount,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicatePostsOutCount,
        (SELECT COUNT(V_CLOSE.Id) FROM Votes V_CLOSE WHERE V_CLOSE.PostId = P.Id AND V_CLOSE.VoteTypeId = 6) AS LegacyCloseVoteCount,
        (SELECT COUNT(DISTINCT PH_CLOSERS.UserId) FROM PostHistory PH_CLOSERS WHERE PH_CLOSERS.PostId = P.Id AND PH_CLOSERS.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)) AS UniqueCloseVotersCount,
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = P.Id AND C.UserId IS NULL) AS AnonymousCommentsCount
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Users U_OWNER ON P.OwnerUserId = U_OWNER.Id
),
TagHealthMetrics AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        COUNT(DISTINCT P.Id) AS TaggedPostsCount,
        SUM(P.ViewCount) AS TagTotalViews,
        AVG(P.Score) AS TagAverageScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TaggedQuestionsCount,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS TaggedAcceptedAnswersCount,
        (SELECT COUNT(DISTINCT U_TOP.Id) FROM Users U_TOP JOIN Badges B_TOP ON U_TOP.Id = B_TOP.UserId WHERE B_TOP.Name = T.TagName AND B_TOP.TagBased = TRUE) AS TagBadgeHolders,
        (SELECT STRING_AGG(DISTINCT U_CONTRIB.DisplayName, '; ') FROM Users U_CONTRIB JOIN Posts P_CONTRIB ON U_CONTRIB.Id = P_CONTRIB.OwnerUserId WHERE P_CONTRIB.Tags LIKE '%<' || T.TagName || '>%' GROUP BY T.TagName ORDER BY COUNT(P_CONTRIB.Id) DESC LIMIT 3) AS TopTagContributors
    FROM Tags T
    JOIN Posts P ON P.Tags LIKE '%<' || T.TagName || '>%'
    GROUP BY T.TagName, T.Id
),
UserPostPerformance AS (
    SELECT
        PCM.PostId,
        PCM.OwnerUserId,
        PCM.PostCreationDate,
        PCM.PostTypeId,
        PCM.Score,
        PCM.ViewCount,
        PCM.AnswerCount,
        PCM.FavoriteCount,
        PCM.TotalMinorEdits,
        PCM.UniqueEditorCount,
        PCM.FlagVoteCount,
        PCM.ClosedDate,
        PCM.AcceptedAnswerId,
        COALESCE(PCM.Score, 0) * 1.0 / GREATEST(1, DATE_PART('day', NOW() - PCM.PostCreationDate) + 1) AS ScorePerDay,
        ROW_NUMBER() OVER (PARTITION BY PCM.OwnerUserId ORDER BY PCM.Score DESC, PCM.CreationDate DESC) AS RankByUserScore,
        RANK() OVER (PARTITION BY PCM.PostTypeId ORDER BY PCM.ViewCount DESC) AS RankByViewCountPostType,
        NTILE(10) OVER (PARTITION BY PCM.PostTypeId ORDER BY PCM.Score DESC) AS ScoreDecileByPostType,
        LAG(PCM.Score, 1, 0) OVER (PARTITION BY PCM.OwnerUserId ORDER BY PCM.PostCreationDate) AS PreviousPostScore,
        LEAD(PCM.Score, 1, 0) OVER (PARTITION BY PCM.OwnerUserId ORDER BY PCM.PostCreationDate) AS NextPostScore,
        NTH_VALUE(PCM.Title, 1) OVER (PARTITION BY PCM.OwnerUserId ORDER BY PCM.CreationDate DESC) AS LatestPostTitleByOwner
    FROM PostComprehensiveMetrics PCM
    WHERE PCM.PostTypeId IN (1, 2)
),
ProblematicPostCandidates AS (
    -- Posts with very low score, many edits, but no accepted answer (for questions) or low impact (for answers)
    SELECT
        UPP.PostId,
        UPP.PostCreationDate,
        UPP.PostTypeId,
        UPP.Score,
        UPP.TotalMinorEdits,
        'LowScore_HighEdits_NoAcceptedAnswer' AS ProblemCategory
    FROM UserPostPerformance UPP
    WHERE UPP.PostTypeId = 1 AND UPP.Score < -2 AND UPP.TotalMinorEdits > 3 AND UPP.AcceptedAnswerId IS NULL
    UNION ALL
    -- Posts that were closed and received significant flag votes
    SELECT
        UPP.PostId,
        UPP.PostCreationDate,
        UPP.PostTypeId,
        UPP.Score,
        UPP.TotalMinorEdits,
        'Closed_Flagged' AS ProblemCategory
    FROM UserPostPerformance UPP
    WHERE UPP.ClosedDate IS NOT NULL AND UPP.FlagVoteCount >= 2
    UNION ALL
    -- Answers to very old questions that never got an accepted answer, and the answer itself is old/low score
    SELECT
        PA.Id AS PostId,
        PA.CreationDate AS PostCreationDate,
        PA.PostTypeId,
        PA.Score,
        PCM.TotalMinorEdits,
        'OldUnacceptedAnswer' AS ProblemCategory
    FROM Posts PA
    JOIN Posts PQ ON PA.ParentId = PQ.Id
    JOIN PostComprehensiveMetrics PCM ON PA.Id = PCM.PostId
    WHERE PA.PostTypeId = 2
      AND PQ.PostTypeId = 1
      AND PQ.AcceptedAnswerId IS NULL
      AND PA.CreationDate < NOW() - INTERVAL '5 year'
      AND PA.Score <= 0
      AND DATE_PART('day', NOW() - PQ.CreationDate) > 365 * 3
    UNION ALL
    -- Posts with excessive backticks (potential malformed code blocks or irrelevant code)
    SELECT
        PCM.PostId,
        PCM.PostCreationDate,
        PCM.PostTypeId,
        PCM.Score,
        PCM.TotalMinorEdits,
        'ExcessiveBackticks' AS ProblemCategory
    FROM PostComprehensiveMetrics PCM
    WHERE PCM.BacktickCountInBody > 50 AND PCM.BodyCharacterLength < 500
),
ModeratorActionAudit AS (
    SELECT
        PH.PostId,
        PH.UserId AS ModeratorId,
        PH.UserDisplayName AS ModeratorDisplayName,
        PHT.Name AS ActionType,
        PH.CreationDate AS ActionDate,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate) AS PreviousActionDate,
        NTH_VALUE(PH.UserId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LastModeratorId,
        NTH_VALUE(PH.UserDisplayName, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LastModeratorDisplayName
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) -- Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect, Migrated
    AND PH.UserId IS NOT NULL -- Assuming moderators have a UserId
)
SELECT
    UAS.UserId,
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.UserTotalPosts,
    UAS.UserQuestionsCount,
    UAS.UserAnswersCount,
    UAS.UserTotalComments,
    UAS.UserTotalEditOrModerationActions,
    UAS.UserGoldBadges,
    UAS.UserTagBadges,
    UAS.AvgAnswerScoreForOwnQuestions,
    (UAS.UserTotalPostScore * 1.0 / GREATEST(1, DATE_PART('day', NOW() - UAS.UserCreationDate))) AS AvgDailyPostScore,
    PCM.PostId,
    PCM.PostTypeName,
    PCM.Title AS PostTitle,
    PCM.PostCreationDate,
    PCM.Score AS PostScore,
    PCM.ViewCount AS PostViewCount,
    PCM.AnswerCount AS PostAnswerCount,
    PCM.CommentCount AS PostCommentCount,
    PCM.FavoriteCount AS PostFavoriteCount,
    PCM.BodyCharacterLength,
    PCM.BacktickCountInBody,
    PCM.PreTagCharacterCount,
    PCM.TotalMinorEdits,
    PCM.UniqueEditorCount,
    PCM.FlagVoteCount,
    PCM.ClosedDate,
    PCM.CommunityOwnedDate,
    PCM.LastContentEditDate,
    PCM.LinkedPostsOutCount,
    PCM.LinkedPostsInCount,
    PCM.DuplicatePostsOutCount,
    PCM.UniqueCloseVotersCount,
    PCM.AnonymousCommentsCount,
    UPP.ScorePerDay,
    UPP.RankByUserScore,
    UPP.RankByViewCountPostType,
    UPP.ScoreDecileByPostType,
    UPP.PreviousPostScore,
    UPP.NextPostScore,
    UPP.LatestPostTitleByOwner,
    COALESCE(PPC.ProblemCategory, 'NotProblematic') AS PostProblemCategory,
    MAA.ActionType AS LastModeratorActionType,
    MAA.ActionDate AS LastModeratorActionDate,
    MAA.LastModeratorDisplayName AS LastModerator,
    THM.TagName AS TopAssociatedTagName,
    THM.TaggedPostsCount AS TagPostsCount,
    THM.TagTotalViews,
    THM.TagAverageScore,
    THM.TagBadgeHolders,
    THM.TopTagContributors,
    (SELECT AVG(V_ANSWER.Score) FROM Posts P_Q_ANSWER JOIN Posts V_ANSWER ON P_Q_ANSWER.Id = V_ANSWER.ParentId WHERE P_Q_ANSWER.Id = PCM.PostId AND V_ANSWER.PostTypeId = 2) AS AvgAnswerScoreForQuestion,
    (SELECT COUNT(DISTINCT V_ANSWER.OwnerUserId) FROM Posts P_Q_ANSWER JOIN Posts V_ANSWER ON P_Q_ANSWER.Id = V_ANSWER.ParentId WHERE P_Q_ANSWER.Id = PCM.PostId AND V_ANSWER.PostTypeId = 2 AND V_ANSWER.OwnerUserId = PCM.OwnerUserId) AS SelfAnswerCount,
    CASE
        WHEN PCM.PostTypeId = 1 AND PCM.AcceptedAnswerId IS NOT NULL THEN (
            SELECT DATE_PART('day', PA.CreationDate - PCM.PostCreationDate)
            FROM Posts PA WHERE PA.Id = PCM.AcceptedAnswerId
        )
        ELSE NULL
    END AS DaysToAcceptedAnswer,
    ARRAY_TO_STRING(PCM.ParsedTagsArray, ', ') AS PostTagsString,
    -- Calculate a complex "content health" score
    (DATE_PART('day', NOW() - GREATEST(COALESCE(PCM.LastContentEditDate, '1970-01-01'::timestamp), COALESCE(PCM.PostCreationDate, '1970-01-01'::timestamp), COALESCE(PCM.LastActivityDate, '1970-01-01'::timestamp))) * 0.1 + -- Age penalty
     (CASE WHEN PCM.AcceptedAnswerId IS NULL AND PCM.PostTypeId = 1 THEN 50 ELSE 0 END) + -- Unaccepted question penalty
     (CASE WHEN PCM.ClosedDate IS NOT NULL THEN 30 ELSE 0 END) + -- Closed post penalty
     (PCM.FlagVoteCount * 15) + -- Flag penalty
     (PCM.TotalMinorEdits * 2) + -- Edit churn penalty
     (PCM.LegacyCloseVoteCount * 5) + -- Old close votes penalty
     (COALESCE(PCM.Score,0) * -0.5)) AS ContentHealthScore, -- Low score penalty, high score bonus
    AVG(PCM.Score) OVER (PARTITION BY UAS.UserId ORDER BY PCM.PostCreationDate) AS UserCumulativeAvgPostScore,
    (SELECT MIN(PH_INITIAL.CreationDate) FROM PostHistory PH_INITIAL WHERE PH_INITIAL.PostId = PCM.PostId AND PH_INITIAL.PostHistoryTypeId IN (1, 2, 3)) AS InitialPostHistoryDate,
    (SELECT PH_BODY_FIRST.Text FROM PostHistory PH_BODY_FIRST WHERE PH_BODY_FIRST.PostId = PCM.PostId AND PH_BODY_FIRST.PostHistoryTypeId = 2 ORDER BY PH_BODY_FIRST.CreationDate ASC LIMIT 1) AS InitialPostBodySnippet -- Get initial body for comparison
FROM UserActivitySummary UAS
LEFT JOIN PostComprehensiveMetrics PCM ON UAS.UserId = PCM.OwnerUserId
LEFT JOIN UserPostPerformance UPP ON PCM.PostId = UPP.PostId
LEFT JOIN ProblematicPostCandidates PPC ON PCM.PostId = PPC.PostId
LEFT JOIN ModeratorActionAudit MAA ON PCM.PostId = MAA.PostId AND MAA.ActionType NOT LIKE 'Post Un%' AND MAA.ActionType NOT LIKE '%Reopened'
LEFT JOIN TagHealthMetrics THM ON PCM.ParsedTagsArray && ARRAY[THM.TagName] -- Join on any common tag
WHERE
    UAS.Reputation > 750 -- Focus on more established users
    AND (
        PCM.PostId IS NOT NULL -- Include users with posts
        OR (UAS.UserTotalPosts = 0 AND UAS.UserTotalComments > 20 AND UAS.UserCreationDate > NOW() - INTERVAL '3 year') -- Or active commenters
    )
    AND PCM.PostCreationDate > NOW() - INTERVAL '7 year' -- Analyze posts within the last 7 years
    AND (PCM.Title ILIKE '%SQL%' OR PCM.Body ILIKE '%index%' OR PCM.Body ILIKE '%optimize%' OR PCM.ParsedTagsArray && ARRAY['sql', 'database', 'performance', 'indexing']) -- Content specific search for performance-related topics
    AND PCM.ContentLicense IS NOT NULL AND PCM.ContentLicense <> '' -- Ensure license info is explicitly present
    AND (UAS.UserGoldBadges > 0 OR UAS.UserTagBadges > 0 OR UAS.UserQuestionsCount > 10 OR UAS.UserAnswersCount > 15 OR UAS.UserTotalPostScore > 100) -- Filter for truly engaged users
    AND (PCM.PostTypeId = 1 OR (PCM.PostTypeId = 2 AND PCM.Score >= 0)) -- Relevant questions or non-negative answers
ORDER BY
    ContentHealthScore DESC,
    UAS.Reputation DESC,
    PCM.Score DESC
LIMIT 5000;