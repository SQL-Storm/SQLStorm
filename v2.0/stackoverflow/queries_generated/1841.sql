-- {"query": "1841.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3512} 
WITH QuestionPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.CreationDate
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Questions
),
AnswerPosts AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Score,
        P.ParentId,
        P.CreationDate
    FROM Posts P
    WHERE P.PostTypeId = 2 -- Answers
),
UsersWithOnlyAnswers AS (
    -- Identify users who have posted answers but never a question
    SELECT DISTINCT OwnerUserId FROM AnswerPosts
    EXCEPT
    SELECT DISTINCT OwnerUserId FROM QuestionPosts
),
UserEngagement AS (
    -- Summarizes comprehensive user activity and calculates aggregated metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT Q.PostId) AS TotalQuestions,
        COUNT(DISTINCT A.PostId) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- Votes cast BY the user
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven, -- Votes cast BY the user
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        AVG(P.Score * 1.0) FILTER (WHERE P.PostTypeId IN (1,2)) AS AvgPostScore, -- Average score of their questions/answers
        AVG(C.Score * 1.0) AS AvgCommentScore,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE WHEN UOA.OwnerUserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasOnlyAnswers
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN QuestionPosts Q ON U.Id = Q.OwnerUserId
    LEFT JOIN AnswerPosts A ON U.Id = A.OwnerUserId
    LEFT JOIN UsersWithOnlyAnswers UOA ON U.Id = UOA.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, UOA.OwnerUserId
    HAVING COUNT(DISTINCT P.Id) > 5 -- Only consider users with a significant number of posts
       AND U.Reputation > 100
),
PostContentAnalysis AS (
    -- Analyzes post content, history, and related comments for Questions and Answers
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        LENGTH(P.Body) AS BodyLength,
        SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2) AS RawTagsString, -- Remove leading/trailing '<>' for later parsing
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.Id END) AS TotalEdits, -- Title, Body, Tags edits
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        (SELECT MAX(C_sub.CreationDate) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS LatestCommentDate, -- Correlated subquery for latest comment
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'HasAcceptedAnswer'
            WHEN P.AnswerCount > 0 AND P.Score >= 10 THEN 'PopularQuestionWithAnswers'
            WHEN P.ViewCount > 1000 AND P.Score >= 5 THEN 'HighlyViewedQuestion'
            WHEN P.Score < 0 THEN 'PoorlyReceived'
            ELSE 'Other'
        END AS PostQualityCategory,
        NULLIF(P.LastEditorUserId, P.OwnerUserId) AS EditorDifferentFromOwnerUserId -- NULL if owner is also last editor
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
      AND P.CreationDate >= '2020-01-01' -- Recent posts
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.CreationDate, P.LastEditDate, P.LastActivityDate,
        P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.Body, P.Tags, P.AcceptedAnswerId, P.LastEditorUserId
),
PostCommentActivity AS (
    -- Analyzes comment activity per post and per user on those comments using window functions
    SELECT
        C.PostId,
        C.UserId AS CommenterId,
        C.CreationDate AS CommentCreationDate,
        C.Score AS CommentScore,
        ROW_NUMBER() OVER (PARTITION BY C.PostId ORDER BY C.CreationDate DESC) AS rn_latest_comment,
        LAG(C.CreationDate, 1, C.CreationDate) OVER (PARTITION BY C.PostId ORDER BY C.CreationDate) AS PrevCommentDate,
        (C.CreationDate - LAG(C.CreationDate, 1, C.CreationDate) OVER (PARTITION BY C.PostId ORDER BY C.CreationDate)) AS TimeSincePrevComment
    FROM Comments C
    WHERE C.CreationDate >= '2020-01-01'
),
PostLinkAnalysis AS (
    -- Aggregates linked and duplicate post counts
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 END) AS DuplicatePostsCount,
        ARRAY_AGG(PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicateOfPostIds -- Collects IDs of duplicated posts
    FROM PostLinks PL
    GROUP BY PL.PostId
),
TagPerformance AS (
    -- Aggregates performance metrics by tag for questions
    SELECT
        T.TagName,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.ViewCount * 1.0) AS AvgTagViewCount,
        COUNT(P.Id) AS PostsWithTag,
        COUNT(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN P.Id END) AS AcceptedAnswersWithTag,
        DENSE_RANK() OVER (ORDER BY SUM(P.Score) DESC) AS TagScoreRank
    FROM Tags T
    JOIN Posts P ON P.Tags LIKE '%<' || T.TagName || '>%' -- String matching for tags
    WHERE P.PostTypeId = 1 -- Only questions have tags in this context
    GROUP BY T.TagName
    HAVING COUNT(P.Id) > 10
),
UserPostEvolution AS (
    -- Tracks the evolution of a user's posts, focusing on editing patterns and time intervals between edits
    SELECT
        PH.PostId,
        PH.UserId AS EditorId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate) AS PreviousEditDate,
        (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate)) AS TimeSincePreviousEdit,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate DESC) AS rn_latest_edit -- Latest edit by specific user on this post
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
      AND PH.UserId IS NOT NULL
)
-- Main Query: Combines and analyzes data from all CTEs to identify high-impact user activities and content trends
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserLocation,
    UE.HasOnlyAnswers,
    PCA.PostId,
    PCA.Title,
    PCA.PostQualityCategory,
    PCA.PostScore,
    PCA.ViewCount,
    PCA.TotalEdits,
    TagsExtracted.TagName AS PrimaryTag, -- Primary tag for the post (one of them if multiple)
    TP.TotalTagScore,
    TP.TagScoreRank,
    PLA.LinkedPostsCount,
    PLA.DuplicatePostsCount,
    COALESCE(PLA.DuplicateOfPostIds, '{}') AS DuplicateRelatedPosts, -- Handle NULL array for posts with no duplicates
    MAX(CASE WHEN PCE.rn_latest_comment = 1 THEN PCE.CommentCreationDate END) OVER (PARTITION BY UE.UserId) AS UsersLastCommentDate, -- Latest comment date by a specific user across all their commented posts
    AVG(PCE.CommentScore) OVER (PARTITION BY UE.UserId, PCA.PostId) AS AvgCommentScoreOnPost,
    CASE
        WHEN UE.Reputation > 5000 AND PCA.PostScore > 50 THEN 'HighRepHighImpactPost'
        WHEN UE.TotalBadges >= 10 AND PCA.TotalEdits > 3 THEN 'ExperiencedEditor'
        WHEN UE.AvgPostScore IS NULL THEN 'NoPostsOrScores'
        WHEN UE.HasOnlyAnswers THEN 'DedicatedAnswerer'
        ELSE 'OtherEngagement'
    END AS EngagementProfile,
    EXTRACT(WEEK FROM PCA.PostCreationDate) AS WeekOfPostCreation,
    (SELECT COUNT(DISTINCT UPE_sub.EditorId) FROM UserPostEvolution UPE_sub WHERE UPE_sub.PostId = PCA.PostId AND UPE_sub.EditDate = PCA.LastHistoryEditDate) AS DistinctLastEditors, -- Correlated subquery for distinct editors of the last history event
    (SELECT AVG(UPE_sub.TimeSincePreviousEdit) FROM UserPostEvolution UPE_sub WHERE UPE_sub.PostId = PCA.PostId AND UPE_sub.EditorId = UE.UserId) AS AvgEditIntervalByOwner, -- Avg time between edits for owner
    UPE_owner.TimeSincePreviousEdit AS LatestOwnerEditInterval, -- Time since previous edit for the owner's latest edit
    RNK.UserPostRank AS TopUserPostRank,
    LAG(PCA.PostCreationDate) OVER (PARTITION BY UE.UserId ORDER BY PCA.PostCreationDate) AS PreviousPostCreationDate,
    (PCA.PostCreationDate - LAG(PCA.PostCreationDate) OVER (PARTITION BY UE.UserId ORDER BY PCA.PostCreationDate)) AS TimeBetweenPosts,
    COUNT(CASE WHEN PCA.EditorDifferentFromOwnerUserId IS NOT NULL THEN 1 END) OVER (PARTITION BY UE.UserId) AS PostsEditedByOthersCount
FROM UserEngagement UE
INNER JOIN PostContentAnalysis PCA ON UE.UserId = PCA.OwnerUserId
LEFT JOIN PostLinkAnalysis PLA ON PCA.PostId = PLA.PostId
LEFT JOIN ( -- Subquery to extract one primary tag per question post, for joining with TagPerformance
    SELECT DISTINCT ON (P.Id) -- Selects one tag per PostId
        P.Id AS PostId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
) AS TagsExtracted ON PCA.PostId = TagsExtracted.PostId
LEFT JOIN Tags T ON TagsExtracted.TagName = T.TagName
LEFT JOIN TagPerformance TP ON T.TagName = TP.TagName
LEFT JOIN PostCommentActivity PCE ON PCA.PostId = PCE.PostId
LEFT JOIN UserPostEvolution UPE_owner ON PCA.PostId = UPE_owner.PostId
    AND UPE_owner.EditorId = UE.UserId
    AND UPE_owner.rn_latest_edit = 1 -- Only the latest edit made by the post owner
LEFT JOIN ( -- Derived table for ranking posts by a user based on score and view count
    SELECT
        PostId,
        OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY PostScore DESC, ViewCount DESC) AS UserPostRank
    FROM PostContentAnalysis
) AS RNK ON PCA.PostId = RNK.PostId AND PCA.OwnerUserId = RNK.OwnerUserId
WHERE UE.LastAccessDate >= '2023-01-01' -- Recently active users
  AND PCA.BodyLength > 100 -- Meaningful post body length
  AND PCA.TotalEdits > 1 -- Posts that have been edited more than once
  AND (TagsExtracted.TagName LIKE 'sql%' OR TagsExtracted.TagName LIKE 'database%' OR TagsExtracted.TagName IS NULL) -- Filter for specific tags or posts without a primary tag extracted
  AND PCA.PostScore > COALESCE(UE.AvgPostScore, 0) -- Post score is higher than user's average post score
  AND (UE.UserLocation IS NOT NULL AND UE.UserLocation NOT LIKE '%Earth%' OR UE.Reputation > 10000) -- Complex NULL/string/numeric predicate
  AND NOT EXISTS ( -- Exclude users who possess a specific 'Disciplined' badge
      SELECT 1 FROM Badges B_sub
      WHERE B_sub.UserId = UE.UserId AND B_sub.Name = 'Disciplined'
  )
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.UserLocation, UE.HasOnlyAnswers,
    PCA.PostId, PCA.Title, PCA.PostQualityCategory, PCA.PostScore, PCA.ViewCount, PCA.TotalEdits,
    TagsExtracted.TagName, TP.TotalTagScore, TP.TagScoreRank, PLA.LinkedPostsCount, PLA.DuplicatePostsCount,
    DuplicateRelatedPosts, UPE_owner.TimeSincePreviousEdit, RNK.UserPostRank, PCA.PostCreationDate,
    PCA.EditorDifferentFromOwnerUserId -- Included for PostsEditedByOthersCount window function
HAVING
    COUNT(DISTINCT PCE.CommenterId) > 1 -- More than one distinct commenter on the post
    AND (SUM(CASE WHEN PCE.CommentCreationDate > PCA.LastEditDate THEN 1 ELSE 0 END) > 0 OR MAX(PCA.PostScore) > 20) -- Post has comments after last edit OR is highly scored
ORDER BY
    UE.Reputation DESC, PCA.PostScore DESC, TopUserPostRank ASC
LIMIT 1000;