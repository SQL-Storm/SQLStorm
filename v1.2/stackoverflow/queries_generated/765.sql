-- {"query": "765.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1403} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        rh.Level + 1,
        rh.AncestorPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy rh ON t.Id <> rh.Id AND NOT t.TagName = ANY(rh.AncestorPath)
    WHERE rh.Level < 3
),
UserBadgeAggregates AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(CASE WHEN p.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnswersWithOwners
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
QuestionDetails AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        COALESCE(a.TotalAnswers,0) AS AnswerCount,
        COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(a.MaxAnswerScore,0) AS MaxAnswerScore,
        COALESCE(a.AnswersWithOwners,0) AS AnswersWithOwners
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN AnswerStats a ON q.Id = a.QuestionId
    WHERE q.PostTypeId = 1
),
RankedQuestions AS (
    SELECT
        q.*,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.ViewCount DESC) AS UserTopQuestionRank,
        RANK() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS GlobalRank
    FROM QuestionDetails q
),
ClosedQuestions AS (
    SELECT DISTINCT ph.PostId, ph.Comment AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
CloseReasonText AS (
    SELECT crt.Id, crt.Name
    FROM CloseReasonTypes crt
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(ph.CreationDate) AS LastPostHistoryEdit
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    rq.Id AS QuestionId,
    rq.Title,
    rq.Tags,
    rq.Score,
    rq.ViewCount,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.Reputation,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AnswersWithOwners,
    rq.UserTopQuestionRank,
    rq.GlobalRank,
    cb.PostId IS NOT NULL AS IsClosed,
    crt.Name AS CloseReason,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.DistinctBadges,
    uba.LastBadgeDate,
    ura.LastPostActivity,
    ura.LastCommentDate,
    ura.LastPostHistoryEdit,
    -- Complex string manipulation: Extract first tag from Tags string assuming format '<tag1><tag2><tag3>'
    CASE 
        WHEN rq.Tags IS NOT NULL AND LENGTH(rq.Tags) > 2 THEN
            substring(rq.Tags FROM 2 FOR POSITION('>' IN substring(rq.Tags FROM 2)) - 1)
        ELSE NULL
    END AS FirstTag,
    -- Calculate days since question creation to last activity
    EXTRACT(EPOCH FROM (COALESCE(ura.LastPostActivity, rq.CreationDate) - rq.CreationDate))/86400 AS DaysToLastActivity,
    -- Correlated subquery to get number of distinct users who commented on the question
    (
        SELECT COUNT(DISTINCT c.UserId)
        FROM Comments c
        WHERE c.PostId = rq.Id AND c.UserId IS NOT NULL
    ) AS DistinctCommenters,
    -- Window function to get moving average of question scores over creation dates per user
    AVG(rq.Score) OVER (PARTITION BY rq.OwnerUserId ORDER BY rq.CreationDate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS MovingAvgScoreLast5,
    -- NULL logic example: if user has no badges, default to zero
    COALESCE(uba.GoldBadges, 0) + COALESCE(uba.SilverBadges, 0) + COALESCE(uba.BronzeBadges, 0) AS TotalBadges,
    -- Outer join with recursive tag hierarchy to see if first tag is in top 3 levels
    CASE 
        WHEN rth.Level IS NOT NULL THEN rth.Level
        ELSE NULL
    END AS FirstTagHierarchyLevel
FROM RankedQuestions rq
LEFT JOIN ClosedQuestions cb ON rq.Id = cb.PostId
LEFT JOIN CloseReasonText crt ON cb.CloseReasonId::smallint = crt.Id
LEFT JOIN UserBadgeAggregates uba ON rq.OwnerUserId = uba.UserId
LEFT JOIN UserRecentActivity ura ON rq.OwnerUserId = ura.UserId
LEFT JOIN RecursiveTagHierarchy rth ON
    rth.TagName = (
        CASE 
            WHEN rq.Tags IS NOT NULL AND LENGTH(rq.Tags) > 2 THEN
                substring(rq.Tags FROM 2 FOR POSITION('>' IN substring(rq.Tags FROM 2)) - 1)
            ELSE NULL
        END
    )
WHERE rq.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
ORDER BY rq.GlobalRank
FETCH FIRST 100 ROWS ONLY;
