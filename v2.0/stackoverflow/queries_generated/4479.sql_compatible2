WITH RECURSIVE PostHierarchy AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        1 AS Level,
        CAST(p.Id AS VARCHAR) AS Path,
        p.Id AS RootPostId,
        CAST(NULL AS INTEGER) AS ParentPostId,
        p.PostTypeId,
        p.ParentId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    SELECT
        a.Id AS PostId,
        a.Title,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.AnswerCount,
        ph.Level + 1 AS Level,
        ph.Path || '/' || CAST(a.Id AS VARCHAR) AS Path,
        ph.RootPostId,
        ph.PostId AS ParentPostId,
        a.PostTypeId,
        a.ParentId
    FROM Posts a
    JOIN PostHierarchy ph ON a.ParentId = ph.PostId
    WHERE a.PostTypeId = 2
),
AnswerQuality AS (
    SELECT
        p.Id AS PostId,
        AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AverageCommentScore,
        COUNT(DISTINCT c.Id) AS NumberOfComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        MAX(CASE WHEN p.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 2
    GROUP BY p.Id
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS TotalPostsOwned,
        SUM(CASE WHEN ph.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
        SUM(CASE WHEN ph.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
        AVG(ph.Score) AS AveragePostScore,
        MAX(u.CreationDate) AS LatestUserCreationDate
    FROM Users u
    LEFT JOIN Posts ph ON u.Id = ph.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostTagsAgg AS (
    -- Generic placeholder: TagNames as NULL-compatible string type
    SELECT
        p.Id AS PostId,
        CAST(NULL AS VARCHAR) AS TagNames
    FROM Posts p
    WHERE p.PostTypeId = 1
),
PostInteraction AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT ph.Id) AS PostHistoryEvents,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT pv.Id) AS TotalVotes,
        SUM(CASE WHEN pht.Name IN ('Post Closed', 'Post Merged') THEN 1 ELSE 0 END) AS ClosureOrMergeEvents,
        STRING_AGG(DISTINCT pt.TagName, ', ') AS PostTagNames
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes pv ON p.Id = pv.PostId
    LEFT JOIN PostTagsAgg tagsagg ON p.Id = tagsagg.PostId
    LEFT JOIN Tags pt ON tagsagg.TagNames IS NOT NULL AND tagsagg.TagNames LIKE '%' || pt.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    ph.PostId,
    ph.Title AS QuestionTitle,
    u.DisplayName AS QuestionOwnerDisplayName,
    ph.CreationDate AS QuestionCreationDate,
    ph.Score AS QuestionScore,
    ph.AnswerCount AS QuestionAnswerCount,
    aq.AverageCommentScore,
    aq.NumberOfComments,
    aq.Upvotes AS AnswerUpvotes,
    aq.Downvotes AS AnswerDownvotes,
    aq.IsAcceptedAnswer,
    uc.Reputation AS QuestionOwnerReputation,
    uc.TotalPostsOwned AS QuestionOwnerTotalPosts,
    uc.QuestionsOwned AS QuestionOwnerQuestions,
    uc.AnswersOwned AS QuestionOwnerAnswers,
    uc.AveragePostScore AS QuestionOwnerAverageScore,
    pi.PostHistoryEvents,
    pi.TotalComments AS QuestionTotalComments,
    pi.TotalVotes AS QuestionTotalVotes,
    pi.ClosureOrMergeEvents,
    pi.PostTagNames,
    COALESCE(u.DisplayName, 'Deleted User') AS SafeOwnerDisplayName,
    CASE
        WHEN ph.Score > 1000 AND ph.AnswerCount > 50 THEN 'High Engagement'
        WHEN ph.Score <= 0 AND ph.AnswerCount = 0 THEN 'Low Engagement'
        ELSE 'Moderate Engagement'
    END AS EngagementLevel,
    ROW_NUMBER() OVER (PARTITION BY ph.RootPostId ORDER BY aq.IsAcceptedAnswer DESC, aq.AverageCommentScore DESC, aq.NumberOfComments DESC) AS AnswerRankForQuestion
FROM PostHierarchy ph
LEFT JOIN Posts p ON ph.PostId = p.Id
LEFT JOIN Users u ON ph.OwnerUserId = u.Id
LEFT JOIN AnswerQuality aq ON ph.PostId = aq.PostId
LEFT JOIN UserContribution uc ON ph.OwnerUserId = uc.UserId
LEFT JOIN PostInteraction pi ON ph.PostId = pi.PostId
WHERE ph.Level = 1
  AND (p.ClosedDate IS NULL OR p.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR))
  AND pi.PostTagNames IS NOT NULL
  AND uc.Reputation BETWEEN 100 AND 10000
ORDER BY ph.CreationDate DESC
LIMIT 100;