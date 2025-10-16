WITH RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RN,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPosts
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
),
PostAnswers AS (
    SELECT
        a.OwnerUserId,
        a.PostTypeId,
        a.Score,
        a.ViewCount,
        a.CreationDate,
        a.Tags,
        a.Title,
        a.Id AS AnswerId,
        a.ParentId AS QuestionId
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
),
QuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Tags,
        q.OwnerUserId AS QuestionOwnerId,
        COUNT(ans.AnswerId) AS AnswerCount,
        AVG(ans.Score) AS AvgAnswerScore,
        SUM(CASE WHEN ans.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers,
        MAX(ans.Score) AS MaxAnswerScore
    FROM
        Posts q
        LEFT JOIN PostAnswers ans ON q.Id = ans.QuestionId
    WHERE
        q.PostTypeId = 1
    GROUP BY
        q.Id, q.Title, q.CreationDate, q.Tags, q.OwnerUserId
),
VeteranUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        u.LastAccessDate
    FROM
        Users u
    WHERE
        u.Reputation >= 10000
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Id IN (SELECT Id FROM VeteranUsers)
    GROUP BY
        u.Id
),
RecentEdits AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ht.Name AS EditType
    FROM
        PostHistory ph
        JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
    WHERE
        ht.Name ILIKE '%Edit%'
        AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
PostsWithComments AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        STRING_AGG(c.Text, ' || ' ORDER BY c.CreationDate) AS CommentsText
    FROM
        Posts p
        LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id
),
SummarizedData AS (
    SELECT
        r.PostId,
        r.EditDate,
        r.EditType,
        pc.CommentCount,
        pc.AvgCommentScore,
        pc.CommentsText,
        qb.AnswerCount,
        qb.AvgAnswerScore,
        qb.PositiveAnswers,
        qb.MaxAnswerScore,
        up.QuestionCount,
        up.AnswerCount AS UserAnswerCount,
        up.AvgPostScore,
        up.MaxPostScore,
        (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = r.PostId) AS PostOwnerId
    FROM
        RecentEdits r
        LEFT JOIN PostsWithComments pc ON r.PostId = pc.PostId
        LEFT JOIN QuestionsWithAnswers qb ON r.PostId = qb.QuestionId
        LEFT JOIN UserPostStats up ON up.UserId = (SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = r.PostId)
)
SELECT
    s.PostId,
    s.EditDate,
    s.EditType,
    s.CommentCount,
    s.AvgCommentScore,
    s.CommentsText,
    s.AnswerCount,
    s.AvgAnswerScore,
    s.PositiveAnswers,
    s.MaxAnswerScore,
    (CASE WHEN s.UserAnswerCount IS NULL THEN 0 ELSE s.UserAnswerCount END) AS UserAnswerCount,
    (CASE WHEN s.QuestionCount IS NULL THEN 0 ELSE s.QuestionCount END) AS TotalQuestions,
    (CASE WHEN s.AnswerCount IS NULL THEN 0 ELSE s.AnswerCount END) AS TotalAnswers,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate AS UserCreation,
    u.LastAccessDate
FROM
    SummarizedData s
    LEFT JOIN Users u ON u.Id = s.PostOwnerId
WHERE
    s.EditType IS NOT NULL
    AND s.EditType NOT ILIKE '%Rollback%'
    AND s.CommentCount > 0
ORDER BY
    s.EditDate DESC
LIMIT 50;