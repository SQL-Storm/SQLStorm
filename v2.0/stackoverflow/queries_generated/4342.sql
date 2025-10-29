-- {"query": "4342.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1309} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        pht.Name AS EditType,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsPosted,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS AvgAnswersForQuestions,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2 -- UpVotes
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionDetails AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViews,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS QuestionCreationDate,
        p.AcceptedAnswerId,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ua.TotalUpVotesReceived AS OwnerUpvotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinksCount,
        CASE
            WHEN p.OwnerUserId IS NULL THEN 'Community'
            ELSE u.DisplayName
        END AS ActualOwnerDisplayName,
        COALESCE(p.AnswerCount, 0) AS UndeletedAnswerCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN UserActivitySummary ua ON u.Id = ua.UserId
    WHERE p.PostTypeId = 1
),
AnswerDetails AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswererDisplayName,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) as rn_answer_rank,
        CASE WHEN p.Id = qd.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted
    FROM Posts p
    JOIN QuestionDetails qd ON p.ParentId = qd.QuestionId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
)
SELECT
    q.QuestionId,
    q.Title,
    q.QuestionScore,
    q.QuestionViews,
    q.ActualOwnerDisplayName,
    q.OwnerUpvotes,
    q.QuestionCreationDate,
    q.IsClosed,
    q.UndeletedAnswerCount,
    q.DuplicateLinksCount,
    COALESCE(q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId AND c.Score > 0) AS PositiveScoreCommentsCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = q.QuestionId
        AND ph.PostHistoryTypeId = 10 -- Post Closed
        AND ph.Comment LIKE '%101%' -- Specific close reason for Duplicate
    ) AS CloseVoteForDuplicateCount,
    ad.AnswerId AS BestAnswerId,
    ad.AnswerScore AS BestAnswerScore,
    ad.AnswererDisplayName AS BestAnswerer,
    ad.AnswerCreationDate AS BestAnswerDate,
    ad.IsAccepted AS IsBestAnswerAccepted,
    rpe.EditDate AS LastTitleEditDate,
    rpe.EditType AS LastTitleEditType,
    rpe_body.EditDate AS LastBodyEditDate,
    rpe_body.EditType AS LastBodyEditType,
    rpe_tags.EditDate AS LastTagsEditDate,
    rpe_tags.EditType AS LastTagsEditType
FROM QuestionDetails q
LEFT JOIN AnswerDetails ad ON q.QuestionId = ad.QuestionId AND ad.rn_answer_rank = 1
LEFT JOIN RankedPostEdits rpe ON q.QuestionId = rpe.PostId AND rpe.rn = 1 AND rpe.EditType = 'Edit Title'
LEFT JOIN RankedPostEdits rpe_body ON q.QuestionId = rpe_body.PostId AND rpe_body.rn = 1 AND rpe_body.EditType = 'Edit Body'
LEFT JOIN RankedPostEdits rpe_tags ON q.QuestionId = rpe_tags.PostId AND rpe_tags.rn = 1 AND rpe_tags.EditType = 'Edit Tags'
WHERE q.QuestionScore > 10
AND q.UndeletedAnswerCount >= 1
AND q.QuestionViews BETWEEN 1000 AND 100000
ORDER BY q.QuestionScore DESC, q.QuestionViews DESC
LIMIT 100;
