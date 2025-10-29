-- {"query": "2439.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1259} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId 
            ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
        ) AS RankWithinType
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2)
),
TopQuestions AS (
    SELECT *
    FROM RankedPosts
    WHERE PostTypeId = 1 AND RankWithinType <= 500
),
TopAnswers AS (
    SELECT *
    FROM RankedPosts
    WHERE PostTypeId = 2 AND RankWithinType <= 1000
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.ViewCount AS AnswerViews,
        a.CreationDate AS AnswerCreationDate,
        u.Id AS AnswerOwnerId,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation,
        b.Name AS BadgeName,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT b.Name, ',') 
            OVER (PARTITION BY a.OwnerUserId ORDER BY b.Date RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS OwnerBadges
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date < a.CreationDate
    LEFT JOIN Comments c ON c.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.Score, a.ViewCount, a.CreationDate, u.Id, u.DisplayName, u.Reputation, b.Name
),
AggregatedQuestionData AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.CreationDate AS QuestionCreationDate,
        q.AcceptedAnswerId,
        q.OwnerUserId,
        u.DisplayName AS QuestionOwnerName,
        u.Reputation AS QuestionOwnerReputation,
        COALESCE(SUM(ad.AnswerScore), 0) AS TotalAnswerScore,
        COALESCE(SUM(ad.CommentCount), 0) AS TotalAnswerComments,
        COUNT(DISTINCT pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinks,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed' 
            ELSE 'Open' 
        END AS QuestionStatus,
        COALESCE(COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,12)), 0) AS CloseOrDeletedEvents
    FROM TopQuestions q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN AnswerDetails ad ON ad.QuestionId = q.Id
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    GROUP BY
        q.Id, q.Title, q.Score, q.ViewCount, q.CreationDate, q.AcceptedAnswerId,
        q.OwnerUserId, u.DisplayName, u.Reputation, q.ClosedDate
),
FinalResult AS (
    SELECT
        aq.QuestionId,
        aq.Title,
        aq.QuestionScore,
        aq.QuestionViews,
        aq.QuestionCreationDate,
        aq.QuestionOwnerName,
        aq.QuestionOwnerReputation,
        aq.TotalAnswerScore,
        aq.TotalAnswerComments,
        aq.DuplicateLinks,
        aq.QuestionStatus,
        aq.CloseOrDeletedEvents,
        psa.AnswerId,
        psa.AnswerScore,
        psa.AnswerViews,
        psa.AnswerOwnerName,
        psa.AnswerOwnerReputation,
        ts.ScoreDiff,
        ts.ViewDiff,
        ts.AgeDays,
        CASE
            WHEN aq.AcceptedAnswerId = psa.AnswerId THEN 'Accepted'
            ELSE 'Not Accepted'
        END AS AcceptStatus,
        -- Complex string operation mixing title and badges and status
        CONCAT(
            SUBSTRING(aq.Title, 1, 30), 
            '... | Answers Badges: ', 
            COALESCE(psa.OwnerBadges, 'None'),
            ' | Status: ', aq.QuestionStatus,
            ' | Score Diff: ', ts.ScoreDiff::text,
            ' | View Diff: ', ts.ViewDiff::text
        ) AS ComplexSummary
    FROM AggregatedQuestionData aq
    LEFT JOIN AnswerDetails psa ON psa.QuestionId = aq.QuestionId
    LEFT JOIN (
        SELECT
            a.ParentId AS QuestionId,
            a.Id AS AnswerId,
            a.Score - q.Score AS ScoreDiff,
            a.ViewCount - q.ViewCount AS ViewDiff,
            EXTRACT(DAY FROM (CURRENT_TIMESTAMP - a.CreationDate)) AS AgeDays
        FROM Posts a
        JOIN Posts q ON a.ParentId = q.Id
        WHERE a.PostTypeId = 2 AND q.PostTypeId = 1
    ) ts ON ts.QuestionId = aq.QuestionId AND ts.AnswerId = psa.AnswerId
    WHERE psa.AnswerScore > 0
),
FilteredFinal AS (
    SELECT *
    FROM FinalResult
    WHERE QuestionStatus = 'Open'
      AND TotalAnswerScore > 100
      AND (DuplicateLinks = 0 OR DuplicateLinks IS NULL)
)
SELECT *
FROM FilteredFinal
ORDER BY QuestionScore DESC, TotalAnswerScore DESC, AnswerScore DESC
LIMIT 100;
