-- {"query": "2560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1383}
WITH RecursiveUserBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        row_number() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IS NOT NULL
),
TopBadgeUsers AS (
    SELECT UserId, DisplayName, BadgeName, Class FROM RecursiveUserBadges WHERE BadgeRank <= 3
),
PostRelations AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        pt.Name AS PostTypeName,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        COALESCE(p.Score, 0) AS Score
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
AnswerScores AS (
    SELECT 
        p.ParentId AS QuestionId,
        avg(p.Score) AS AvgAnswerScore,
        max(p.Score) AS MaxAnswerScore,
        count(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        count(DISTINCT p.Id) AS NumPosts,
        sum(p.Score) AS TotalPostScore,
        max(p.CreationDate) AS LastPostDate,
        avg(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
CloseReasonsCount AS (
    SELECT 
        p.OwnerUserId AS UserId,
        count(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS NumClosedPosts,
        count(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 11) AS NumReopenedPosts
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.OwnerUserId
),
CTE_QuestionsWithHotness AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        ascore.AvgAnswerScore,
        ascore.MaxAnswerScore,
        rank() OVER (ORDER BY q.ViewCount DESC, q.Score DESC) AS ViewRank,
        dense_rank() OVER (PARTITION BY substring(q.Tags FROM 2 FOR (length(q.Tags) - 2)) ORDER BY q.Score DESC) AS ScoreRankPerTag
    FROM Posts q
    LEFT JOIN AnswerScores ascore ON q.Id = ascore.QuestionId
    WHERE q.PostTypeId = 1
),
ComplexQuery AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        ua.NumPosts,
        ua.TotalPostScore,
        cr.NumClosedPosts,
        cr.NumReopenedPosts,
        tb.BadgeName,
        tb.Class AS BadgeClass,
        q.QuestionId,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        COALESCE(q.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(q.MaxAnswerScore, 0) AS MaxAnswerScore,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        count(DISTINCT c.Id) AS CommentCountOnQuestions,
        string_agg(DISTINCT COALESCE(lt.Name, 'NoLink'), ',') AS LinkTypesForUserPosts,
        row_number() OVER (PARTITION BY u.Id ORDER BY q.Score DESC, q.ViewCount DESC) AS UserTopQuestionRank
    FROM Users u
    LEFT JOIN UserActivity ua ON u.Id = ua.Id
    LEFT JOIN CloseReasonsCount cr ON u.Id = cr.UserId
    LEFT JOIN TopBadgeUsers tb ON u.Id = tb.UserId
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN CTE_QuestionsWithHotness q ON q.QuestionId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE u.Reputation > 1000 
      AND (tb.Class IS NULL OR tb.Class <= 2)
      AND q.ViewCount > 1000
    GROUP BY
        u.Id, u.DisplayName, ua.NumPosts, ua.TotalPostScore, cr.NumClosedPosts, cr.NumReopenedPosts,
        tb.BadgeName, tb.Class, q.QuestionId, q.Title, q.Score, q.ViewCount, q.AvgAnswerScore, q.MaxAnswerScore, q.AcceptedAnswerId
)
SELECT 
    UserId,
    DisplayName,
    NumPosts,
    TotalPostScore,
    NumClosedPosts,
    NumReopenedPosts,
    BadgeName,
    BadgeClass,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViews,
    AvgAnswerScore,
    MaxAnswerScore,
    HasAcceptedAnswer,
    CommentCountOnQuestions,
    LinkTypesForUserPosts
FROM ComplexQuery
WHERE UserTopQuestionRank <= 5

UNION ALL

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    ua.NumPosts,
    ua.TotalPostScore,
    cr.NumClosedPosts,
    cr.NumReopenedPosts,
    NULL AS BadgeName,
    NULL AS BadgeClass,
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS QuestionScore,
    NULL AS QuestionViews,
    NULL AS AvgAnswerScore,
    NULL AS MaxAnswerScore,
    NULL AS HasAcceptedAnswer,
    0 AS CommentCountOnQuestions,
    '' AS LinkTypesForUserPosts
FROM Users u
LEFT JOIN UserActivity ua ON u.Id = ua.Id
LEFT JOIN CloseReasonsCount cr ON u.Id = cr.UserId
WHERE u.Reputation > 1000
  AND u.Id NOT IN (SELECT DISTINCT UserId FROM ComplexQuery)
ORDER BY TotalPostScore DESC, QuestionViews DESC, UserId
LIMIT 20;