WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditTypeName,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
PostEditSummaries AS (
    SELECT
        re.PostId,
        re.UserId,
        re.EditorDisplayName,
        re.EditDate,
        STRING_AGG(re.EditTypeName, ', ') AS EditedFields,
        COUNT(re.PostHistoryTypeId) AS NumberOfEditsOfType,
        MAX(re.EditComment) AS LastEditComment
    FROM RankedPostEdits re
    WHERE re.rn = 1
    GROUP BY re.PostId, re.UserId, re.EditorDisplayName, re.EditDate
),
TopUsersByEdits AS (
    SELECT
        ph.UserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS DistinctPostsEdited,
        COUNT(*) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.UserId
    HAVING COUNT(*) > 50
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
QuestionStats AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        u.DisplayName AS QuestionOwnerDisplayName,
        rq.CreationDate AS QuestionCreationDate,
        rq.Score AS QuestionScore,
        rq.AnswerCount,
        rq.FavoriteCount,
        rq.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId AND c.Score > 5) AS HighScoreCommentCount,
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = rq.QuestionId AND v.VoteTypeId = 2) AS UpVoteCount,
        CASE WHEN rq.OwnerUserId IS NULL THEN 'Unknown' ELSE (SELECT us.DisplayName FROM Users us WHERE us.Id = rq.OwnerUserId) END AS OriginalOwnerName,
        CASE WHEN rq.OwnerUserId IS NULL THEN 'Community' ELSE 'User' END AS OwnerType,
        rq.OwnerUserId
    FROM RecentQuestions rq
    LEFT JOIN Users u ON rq.OwnerUserId = u.Id
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.QuestionOwnerDisplayName,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.Tags,
    qs.HighScoreCommentCount,
    qs.UpVoteCount,
    qs.OwnerType,
    tue.TotalEdits AS TotalEditsByOwner,
    tue.TitleEdits AS TitleEditsByOwner,
    tue.BodyEdits AS BodyEditsByOwner,
    tue.TagEdits AS TagEditsByOwner,
    CASE
        WHEN qs.QuestionScore < 0 THEN 'Negative Score'
        WHEN qs.QuestionScore BETWEEN 0 AND 10 THEN 'Low Score'
        WHEN qs.QuestionScore BETWEEN 11 AND 50 THEN 'Medium Score'
        ELSE 'High Score'
    END AS ScoreCategory,
    CASE
        WHEN qs.AnswerCount = 0 THEN 'No Answers'
        WHEN qs.AnswerCount BETWEEN 1 AND 5 THEN 'Few Answers'
        ELSE 'Many Answers'
    END AS AnswerCountCategory,
    CASE
        WHEN qs.FavoriteCount IS NULL OR qs.FavoriteCount = 0 THEN 'Not Favorited'
        ELSE 'Favorited'
    END AS FavoritedStatus,
    (
        SELECT pl.RelatedPostId
        FROM PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
        WHERE pl.PostId = qs.QuestionId AND lt.Name = 'Duplicate'
        ORDER BY pl.CreationDate DESC
        LIMIT 1
    ) AS DuplicateOfPostId,
    p.EditorDisplayName AS LastEditorDisplayName,
    p.EditDate AS LastEditDate,
    p.EditedFields AS LastEditedFields,
    p.NumberOfEditsOfType AS LastNumberOfEditsOfType,
    p.LastEditComment
FROM QuestionStats qs
LEFT JOIN PostEditSummaries p ON qs.QuestionId = p.PostId
LEFT JOIN TopUsersByEdits tue ON qs.OwnerUserId = tue.UserId
WHERE qs.QuestionScore > -10 AND qs.AnswerCount < 100
ORDER BY qs.QuestionCreationDate DESC, qs.QuestionScore DESC
LIMIT 100;