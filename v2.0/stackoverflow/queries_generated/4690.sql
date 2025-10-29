-- {"query": "4690.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1095} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
LatestEdits AS (
    SELECT
        PostId,
        UserId,
        EditorDisplayName,
        CreationDate,
        PostHistoryTypeId
    FROM RankedPostEdits
    WHERE rn = 1
),
QuestionAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.CreationDate AS QuestionCreationDate,
        COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 -- Questions
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT ps.Id) AS PostsWithTag
    FROM Tags t
    LEFT JOIN Posts ps ON ps.Tags LIKE '%' || t.TagName || '%' AND ps.PostTypeId = 1
    GROUP BY t.TagName, t.Count
)
SELECT
    qa.QuestionId,
    qa.QuestionTitle,
    qa.QuestionScore,
    qa.QuestionViewCount,
    qa.QuestionCreationDate,
    qa.AnswerCount,
    le.EditorDisplayName AS LastEditorDisplayName,
    le.CreationDate AS LastEditDate,
    COALESCE(uc.UserDisplayName, 'Community') AS OwnerDisplayName,
    uc.QuestionsAsked,
    uc.AnswersGiven,
    uc.TotalAnswerScore,
    uc.CommentsMade,
    tp.TagName,
    tp.TagCount,
    tp.PostsWithTag,
    CASE
        WHEN qa.QuestionScore > 100 THEN 'High Score'
        WHEN qa.QuestionScore BETWEEN 50 AND 100 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    CASE
        WHEN le.PostHistoryTypeId = 4 THEN 'Title Edited'
        WHEN le.PostHistoryTypeId = 5 THEN 'Body Edited'
        WHEN le.PostHistoryTypeId = 6 THEN 'Tags Edited'
        ELSE 'No Recent Edit'
    END AS LastEditType,
    DENSE_RANK() OVER (ORDER BY qa.QuestionViewCount DESC) as ViewRank,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = qa.QuestionId AND v.VoteTypeId = 2) AS UpVoteCountForQuestion
FROM QuestionAnswers qa
LEFT JOIN LatestEdits le ON qa.QuestionId = le.PostId
LEFT JOIN UserContribution uc ON qa.QuestionId = (SELECT OwnerUserId FROM Posts WHERE Id = qa.QuestionId)
LEFT JOIN (
    SELECT
        DISTINCT
        p.Id AS QuestionId,
        t.TagName
    FROM Posts p
    CROSS APPLY string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ') AS tag_list
    JOIN Tags t ON t.TagName = tag_list.value
    WHERE p.PostTypeId = 1
) tp ON qa.QuestionId = tp.QuestionId
WHERE qa.QuestionScore IS NOT NULL
  AND qa.QuestionViewCount > 0
  AND COALESCE(uc.QuestionsAsked, 0) > 5
  AND tp.TagName NOT LIKE '%-' -- Exclude meta-tags
ORDER BY qa.QuestionViewCount DESC, qa.QuestionScore DESC
LIMIT 100;
