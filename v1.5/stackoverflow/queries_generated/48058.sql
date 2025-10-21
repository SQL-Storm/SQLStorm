-- {"query": "48058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 934} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
UserActivity AS (
    SELECT
        ph.UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT ph.PostId) AS PostsModified,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS Edits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 END) AS InitialCreations,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 END) AS ModerationActions,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.UserId IS NOT NULL AND ph.UserId > 0
    GROUP BY ph.UserId, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        Views,
        UpVotes,
        DownVotes
    FROM Users
    WHERE Reputation > 10000
),
FrequentEdits AS (
    SELECT
        ph.UserId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.UserId
    HAVING COUNT(*) > 50
)
SELECT
    rp_q.Id AS QuestionId,
    rp_q.PostTypeName AS QuestionType,
    rp_q.OwnerDisplayName AS QuestionOwner,
    rp_q.PostCreationDate AS QuestionCreationDate,
    rp_q.Score AS QuestionScore,
    rp_q.ViewCount AS QuestionViewCount,
    rp_q.CommentCount AS QuestionCommentCount,
    rp_q.FavoriteCount AS QuestionFavoriteCount,
    rp_q.ClosedDate AS QuestionClosedDate,
    rp_a.Id AS AnswerId,
    rp_a.PostTypeName AS AnswerType,
    rp_a.OwnerDisplayName AS AnswerOwner,
    rp_a.PostCreationDate AS AnswerCreationDate,
    rp_a.Score AS AnswerScore,
    ua.PostsModified AS AnswererPostsModified,
    ua.Edits AS AnswererEdits,
    ua.ModerationActions AS AnswererModerationActions,
    hru.DisplayName AS HighReputationUser,
    hru.Reputation AS HighReputation,
    fe.EditCount AS FrequentEditorEditCount
FROM RankedPosts rp_q
LEFT JOIN RankedPosts rp_a ON rp_q.Id = rp_a.ParentId AND rp_a.PostTypeId = 2 -- Join questions with their answers
LEFT JOIN UserActivity ua ON rp_a.OwnerUserId = ua.UserId
LEFT JOIN HighReputationUsers hru ON rp_q.OwnerUserId = hru.Id OR rp_a.OwnerUserId = hru.Id
LEFT JOIN FrequentEdits fe ON rp_a.OwnerUserId = fe.UserId
WHERE rp_q.PostTypeId = 1 -- Select only questions from the ranked list
ORDER BY rp_q.PostCreationDate DESC, rp_a.Score DESC
LIMIT 100;
