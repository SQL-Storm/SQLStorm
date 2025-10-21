-- {"query": "53077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1020} 

WITH TagQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
        p.ViewCount,
        p.Score,
        p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
QuestionStats AS (
    SELECT 
        tq.TagName,
        COUNT(DISTINCT tq.QuestionId) AS QuestionCount,
        SUM(tq.ViewCount) AS TotalViews,
        AVG(tq.Score) AS AvgQuestionScore,
        SUM(tq.AnswerCount) AS TotalAnswers
    FROM TagQuestions tq
    JOIN Tags t ON tq.TagName = t.TagName
    GROUP BY tq.TagName
),
AnswerStats AS (
    SELECT 
        tq.TagName,
        COUNT(DISTINCT a.Id) AS UniqueAnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM TagQuestions tq
    JOIN Posts a ON a.ParentId = tq.QuestionId AND a.PostTypeId = 2
    GROUP BY tq.TagName
),
EditStats AS (
    SELECT 
        tq.TagName,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) AS CloseReopenCount
    FROM TagQuestions tq
    JOIN PostHistory ph ON ph.PostId = tq.QuestionId AND ph.PostHistoryTypeId BETWEEN 4 AND 9
    GROUP BY tq.TagName
),
CommentStats AS (
    SELECT 
        tq.TagName,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM TagQuestions tq
    JOIN Comments c ON c.PostId = tq.QuestionId
    GROUP BY tq.TagName
),
VoteStats AS (
    SELECT 
        tq.TagName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM TagQuestions tq
    JOIN Votes v ON v.PostId = tq.QuestionId
    GROUP BY tq.TagName
),
BadgeStats AS (
    SELECT 
        b.Name AS TagName,
        COUNT(b.Id) AS TagBadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldTagBadges
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.Name
),
LinkStats AS (
    SELECT 
        tq.TagName,
        COUNT(pl.Id) AS LinkCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateCount
    FROM TagQuestions tq
    JOIN PostLinks pl ON pl.PostId = tq.QuestionId OR pl.RelatedPostId = tq.QuestionId
    GROUP BY tq.TagName
)
SELECT 
    qs.TagName,
    qs.QuestionCount,
    qs.TotalViews,
    qs.AvgQuestionScore,
    qs.TotalAnswers,
    COALESCE(ass.UniqueAnswerCount, 0) AS UniqueAnswerCount,
    COALESCE(ass.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ass.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(es.EditCount, 0) AS EditCount,
    COALESCE(es.CloseReopenCount, 0) AS CloseReopenCount,
    COALESCE(cs.CommentCount, 0) AS CommentCount,
    COALESCE(cs.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(vs.Upvotes, 0) AS Upvotes,
    COALESCE(vs.Downvotes, 0) AS Downvotes,
    COALESCE(bs.TagBadgeCount, 0) AS TagBadgeCount,
    COALESCE(bs.GoldTagBadges, 0) AS GoldTagBadges,
    COALESCE(ls.LinkCount, 0) AS LinkCount,
    COALESCE(ls.DuplicateCount, 0) AS DuplicateCount,
    ROW_NUMBER() OVER (ORDER BY qs.QuestionCount DESC) AS RankByQuestions
FROM QuestionStats qs
LEFT JOIN AnswerStats ass ON qs.TagName = ass.TagName
LEFT JOIN EditStats es ON qs.TagName = es.TagName
LEFT JOIN CommentStats cs ON qs.TagName = cs.TagName
LEFT JOIN VoteStats vs ON qs.TagName = vs.TagName
LEFT JOIN BadgeStats bs ON qs.TagName = bs.TagName
LEFT JOIN LinkStats ls ON qs.TagName = ls.TagName
ORDER BY qs.QuestionCount DESC
LIMIT 500;
