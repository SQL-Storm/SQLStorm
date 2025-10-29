-- {"query": "2009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1530} 

WITH RecentBadgeUsers AS (
    SELECT
        b.UserId,
        u.DisplayName,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    JOIN Users u ON u.Id = b.UserId
    WHERE b.Date >= CURRENT_DATE - INTERVAL '365 days'
    GROUP BY b.UserId, u.DisplayName
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        COALESCE(p.ViewCount, 0) AS Views,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RN
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
      AND p.Score > 0
),
TopQuestionsByUser AS (
    SELECT
        rq.Id AS QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.Score,
        rq.Views,
        rq.CreationDate
    FROM PopularQuestions rq
    WHERE rq.RN <= 3
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerExists,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, q.AcceptedAnswerId
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(c.Id) AS CommentsMade,
        COUNT(b.Id) AS BadgesEarned,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) OVER (PARTITION BY u.Id) AS AvgPostScore,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) OVER (PARTITION BY u.Id) AS LastPostDate,
        MIN(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) OVER (PARTITION BY u.Id) AS FirstPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicatesWithAnswers AS (
    SELECT DISTINCT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId,
        pq.Title AS OriginalTitle,
        pq.Score AS OriginalScore,
        pq.ViewCount AS OriginalViews,
        pa.AnswerCount,
        pa.AvgAnswerScore,
        pa.AcceptedAnswerExists
    FROM PostLinks pl
    LEFT JOIN Posts pq ON pq.Id = pl.RelatedPostId AND pq.PostTypeId = 1
    LEFT JOIN AnswerStats pa ON pa.QuestionId = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
UserLastEditActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS ContentEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT 
    uaw.UserId,
    uaw.DisplayName,
    uaw.Reputation,
    uaw.QuestionsPosted,
    uaw.AnswersPosted,
    uaw.CommentsMade,
    uaw.BadgesEarned,
    uaw.AvgPostScore,
    uaw.FirstPostDate,
    uaw.LastPostDate,
    rb.GoldBadges,
    rb.SilverBadges,
    rb.BronzeBadges,
    ts.QuestionId AS TopQuestionId,
    ts.Title AS TopQuestionTitle,
    ts.Score AS TopQuestionScore,
    ts.Views AS TopQuestionViews,
    ts.CreationDate AS TopQuestionCreationDate,
    ds.DuplicateQuestionId,
    ds.OriginalQuestionId,
    ds.OriginalTitle AS DuplicatedOriginalTitle,
    ds.OriginalScore AS DuplicatedOriginalScore,
    ds.AnswerCount AS DuplicatedAnswerCount,
    ds.AvgAnswerScore AS DuplicatedAvgAnswerScore,
    ds.AcceptedAnswerExists AS DuplicatedAcceptedAnswerExists,
    ula.LastEditDate,
    ula.PostsEdited,
    ula.ContentEdits,
    ula.CloseVotes,
    ula.ReopenVotes,
    CASE 
        WHEN uaw.LastPostDate IS NULL THEN 'No Posts'
        WHEN uaw.LastPostDate < CURRENT_DATE - INTERVAL '90 days' THEN 'Inactive'
        ELSE 'Active'
    END AS UserActivityStatus,
    CONCAT_WS(' | ',
        'Rep: ' || uaw.Reputation,
        'Badges: ' || uaw.BadgesEarned,
        COALESCE('Top Q: ' || ts.Title, 'No Top Question'),
        COALESCE('Duplicate Of: ' || ds.OriginalTitle, 'No Duplicates'),
        'Last Edit: ' || TO_CHAR(ula.LastEditDate, 'YYYY-MM-DD')
    ) AS SummaryInfo
FROM UserActivityWindows uaw
LEFT JOIN RecentBadgeUsers rb ON rb.UserId = uaw.UserId
LEFT JOIN TopQuestionsByUser ts ON ts.OwnerUserId = uaw.UserId
LEFT JOIN DuplicatesWithAnswers ds ON ds.DuplicateQuestionId = ts.QuestionId
LEFT JOIN UserLastEditActivity ula ON ula.UserId = uaw.UserId
WHERE 
    uaw.Reputation > 1000
    AND uaw.QuestionsPosted > 0
    AND (ds.DuplicateQuestionId IS NOT NULL OR rb.GoldBadges >= 1)
ORDER BY uaw.Reputation DESC, uaw.BadgesEarned DESC, ts.Score DESC
LIMIT 100;
