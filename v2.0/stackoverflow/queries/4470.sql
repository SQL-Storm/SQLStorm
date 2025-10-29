WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 4 THEN Id END) AS TitleEdits,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 5 THEN Id END) AS BodyEdits,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 6 THEN Id END) AS TagEdits
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.ViewCount) AS TotalViewsOnOwnedPosts,
        AVG(p.Score) AS AvgScoreOnOwnedPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
TopEditors AS (
    SELECT
        EditorDisplayName,
        COUNT(*) AS EditCount
    FROM RankedPostEdits
    WHERE rn = 1
    GROUP BY EditorDisplayName
    ORDER BY EditCount DESC
    LIMIT 10
),
RecentQuestions AS (
    SELECT
        Id,
        Title,
        CreationDate,
        OwnerUserId,
        Score,
        AnswerCount,
        ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS RecentRank
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days')
),
QuestionDetails AS (
    SELECT
        rq.Id AS QuestionId,
        rq.Title AS QuestionTitle,
        rq.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        rq.Score AS QuestionScore,
        rq.AnswerCount AS NumberOfAnswers,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(CASE WHEN c.PostId IS NOT NULL THEN c.Id END) AS CommentCountOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnQuestion,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
        rq.OwnerUserId
    FROM RecentQuestions rq
    LEFT JOIN Users u ON rq.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON rq.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5)
    LEFT JOIN Comments c ON rq.Id = c.PostId AND c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days')
    LEFT JOIN Votes v ON rq.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Posts p ON rq.Id = p.Id
    GROUP BY
        rq.Id,
        rq.Title,
        rq.CreationDate,
        u.DisplayName,
        rq.Score,
        rq.AnswerCount,
        p.ClosedDate,
        rq.OwnerUserId
    HAVING rq.OwnerUserId IS NOT NULL OR rq.OwnerUserId = -1
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.QuestionCreationDate,
    qd.OwnerDisplayName,
    qd.QuestionScore,
    qd.NumberOfAnswers,
    qd.LastTitleEditDate,
    qd.LastBodyEditDate,
    qd.CommentCountOnQuestion,
    qd.UpVotesOnQuestion,
    qd.DownVotesOnQuestion,
    qd.QuestionStatus,
    COALESCE(pec.TitleEdits, 0) AS TotalTitleEdits,
    COALESCE(pec.BodyEdits, 0) AS TotalBodyEdits,
    COALESCE(pec.TagEdits, 0) AS TotalTagEdits,
    CASE
        WHEN uap.TotalPostsOwned > 1000 THEN 'Prolific'
        WHEN uap.TotalPostsOwned > 100 THEN 'Experienced'
        ELSE 'Newer'
    END AS OwnerExperienceLevel,
    CASE
        WHEN (qd.QuestionScore * 1.0 / NULLIF(qd.NumberOfAnswers, 0)) > 5 THEN 'High Engagement Ratio'
        WHEN qd.QuestionScore > 50 THEN 'High Score Question'
        ELSE 'Standard Question'
    END AS QuestionEngagementMetric,
    te.EditCount AS TopEditorEditCount
FROM QuestionDetails qd
LEFT JOIN PostEditCounts pec ON qd.QuestionId = pec.PostId
LEFT JOIN UserPostActivity uap ON qd.OwnerUserId = uap.OwnerUserId
LEFT JOIN TopEditors te ON qd.OwnerDisplayName = te.EditorDisplayName
WHERE qd.QuestionScore > 0 OR qd.NumberOfAnswers > 0
ORDER BY qd.QuestionCreationDate DESC
LIMIT 100;