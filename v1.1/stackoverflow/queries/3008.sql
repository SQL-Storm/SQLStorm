WITH UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS ReputationRank,
        COUNT(*) OVER () AS TotalUsers
    FROM Users u
    WHERE u.Reputation IS NOT NULL AND u.Location IS NOT NULL
),
PostStatistics AS (
    SELECT
        p.PostTypeId,
        COUNT(*) AS TotalPosts,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.LastActivityDate) AS LastActive,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY p.PostTypeId
),
LatestComments AS (
    SELECT
        c.PostId,
        c.Text,
        c.CreationDate,
        c.UserId,
        US.Id AS CommentUserId,
        US.Reputation AS CommenterReputation,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments c
    LEFT JOIN Users US ON c.UserId = US.Id
),
QuestionAnswerLinks AS (
    SELECT
        p1.Id AS QuestionId,
        p2.Id AS AnswerId,
        p2.Score AS AnswerScore,
        p2.CreationDate AS AnswerCreated,
        p2.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p1.Id ORDER BY p2.Score DESC, p2.CreationDate DESC) AS rank
    FROM Posts p1
    LEFT JOIN Posts p2 ON p2.ParentId = p1.Id AND p2.PostTypeId = 2
),
HistoricalCounts AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS TotalBodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66) THEN 1 END) AS TotalHistoryEntries
    FROM PostHistory ph
    GROUP BY ph.PostId
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
),
ResponseTimeStats AS (
    SELECT
        q.Id AS QuestionId,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgResponseTimeSeconds,
        COUNT(a.Id) AS TotalAnswers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1 AND a.CreationDate IS NOT NULL
    GROUP BY q.Id
)
SELECT
    UR.UserId,
    UR.Reputation,
    UR.ReputationRank,
    UR.TotalUsers,
    PS.PostTypeId,
    PS.TotalPosts,
    PS.AvgScore,
    PS.TotalViews,
    PS.LastActive,
    PS.UniqueAuthors,
    LC.PostId,
    LC.Text AS LatestCommentText,
    LC.CreationDate AS CommentDate,
    LC.UserId AS CommentUserIdOfComment,
    LC.CommenterReputation,
    LC.rn AS LatestCommentRowNumber,
    QAL.QuestionId,
    QAL.AnswerId,
    QAL.AnswerScore,
    QAL.AnswerCreated,
    QAL.OwnerUserId AS AnswerOwnerUserId,
    QAL.rank AS AnswerRank,
    HC.PostId AS HistoryPostId,
    HC.TotalBodyEdits,
    HC.TotalHistoryEntries,
    TT.TagName,
    TT.Count AS TagCount,
    TT.TagRank,
    RT.QuestionId AS ResponseQuestionId,
    RT.AvgResponseTimeSeconds,
    RT.TotalAnswers
FROM PostStatistics PS
LEFT JOIN UserReputation UR ON 1=1
LEFT JOIN LatestComments LC ON LC.PostId = PS.PostTypeId
LEFT JOIN QuestionAnswerLinks QAL ON QAL.QuestionId = PS.PostTypeId
LEFT JOIN HistoricalCounts HC ON HC.PostId = PS.PostTypeId
LEFT JOIN TopTags TT ON TT.TagRank <= 10
LEFT JOIN ResponseTimeStats RT ON RT.QuestionId = PS.PostTypeId
WHERE
    (UR.Reputation IS NULL OR UR.Reputation > 1000)
    AND (PS.PostTypeId IS NULL OR PS.PostTypeId IN (1,2))
    AND (LC.rn = 1 OR LC.rn IS NULL)
GROUP BY
    UR.UserId,
    UR.Reputation,
    UR.ReputationRank,
    UR.TotalUsers,
    PS.PostTypeId,
    PS.TotalPosts,
    PS.AvgScore,
    PS.TotalViews,
    PS.LastActive,
    PS.UniqueAuthors,
    LC.PostId,
    LC.Text,
    LC.CreationDate,
    LC.UserId,
    LC.CommenterReputation,
    LC.rn,
    QAL.QuestionId,
    QAL.AnswerId,
    QAL.AnswerScore,
    QAL.AnswerCreated,
    QAL.OwnerUserId,
    QAL.rank,
    HC.PostId,
    HC.TotalBodyEdits,
    HC.TotalHistoryEntries,
    TT.TagName,
    TT.Count,
    TT.TagRank,
    RT.QuestionId,
    RT.AvgResponseTimeSeconds,
    RT.TotalAnswers
ORDER BY
    UR.Reputation DESC,
    PS.PostTypeId,
    TT.TagRank
LIMIT 100;