-- {"query": "4696.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 977} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        p.Title AS PostTitle,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
RecentEdits AS (
    SELECT
        PostId,
        PostHistoryTypeId,
        CreationDate,
        EditorDisplayName,
        PostTitle,
        EditComment
    FROM RankedPostEdits
    WHERE rn = 1
),
QuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        a.Id AS AnswerId,
        a.Body AS AnswerBody,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER(PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as rn_answer
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2 AND q.ClosedDate IS NULL AND a.ClosedDate IS NULL
),
TopAnswers AS (
    SELECT
        QuestionId,
        QuestionTitle,
        AnswerId,
        AnswerBody,
        AnswerScore
    FROM QuestionAnswers
    WHERE rn_answer <= 3
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS PostCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
)
SELECT
    TOP 1000
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    COALESCE(upc.PostCount, 0) AS OwnerPostCount,
    re.CreationDate AS LastEditDate,
    re.PostHistoryTypeId AS LastEditTypeId,
    re.EditorDisplayName AS LastEditorDisplayName,
    re.EditComment AS LastEditComment,
    ta.QuestionTitle AS TopAnswerQuestionTitle,
    ta.AnswerScore AS TopAnswerScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN p.FavoriteCount IS NULL THEN 0
        ELSE p.FavoriteCount
    END AS FavoriteCount,
    CASE
        WHEN p.AnswerCount IS NULL THEN 0
        ELSE p.AnswerCount
    END AS UndeletedAnswerCount,
    CASE
        WHEN p.Tags IS NOT NULL THEN REPLACE(REPLACE(p.Tags, '<', ''), '>', ',')
        ELSE NULL
    END AS FormattedTags,
    CASE
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'User Owned'
    END AS OwnershipType
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN RecentEdits re ON p.Id = re.PostId
LEFT JOIN TopAnswers ta ON p.Id = ta.QuestionId
LEFT JOIN UserPostCounts upc ON p.OwnerUserId = upc.OwnerUserId
WHERE pt.Name IN ('Question', 'Answer')
AND p.OwnerUserId IS NOT NULL
AND p.OwnerUserId <> -1
AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) -- Posts with at least one upvote
ORDER BY p.CreationDate DESC, p.Score DESC;
