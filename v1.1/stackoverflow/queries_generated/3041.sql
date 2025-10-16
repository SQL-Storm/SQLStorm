-- {"query": "3041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 983} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
), PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 12) AS DeletedCount
    FROM PostHistory ph
    GROUP BY ph.PostId
), PostLinksAggregated AS (
    SELECT 
        pl.PostId,
        COUNT(*) AS LinkCount,
        COUNT(*) FILTER (WHERE lt.Name ILIKE '%duplicate%') AS DuplicateLinks,
        COUNT(*) FILTER (WHERE lt.Name ILIKE '%related%') AS RelatedLinks
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
), TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    ORDER BY p.ViewCount DESC
    LIMIT 5
), QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        STRING_AGG(DISTINCT a.OwnerDisplayName, ', ') AS AnswerOwners
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.AnswerCount
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.LastAccessDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    COALESCE(ps.EditCount, 0) AS TotalEdits,
    COALESCE(ps.ClosedCount, 0) AS TotalClosed,
    COALESCE(ps.DeletedCount, 0) AS TotalDeleted,
    COALESCE(pa.AnswerCount, 0) AS TopQuestionAnswers,
    COALESCE(pa.UpVotes, 0) AS TotalUpVotes,
    COALESCE(pa.DownVotes, 0) AS TotalDownVotes,
    pa.AnswerOwners,
    tl.LinkCount,
    tl.DuplicateLinks,
    tl.RelatedLinks,
    TOPQ.Id AS QuestionId,
    TOPQ.Title AS QuestionTitle,
    TOPQ.Tags AS QuestionTags,
    TOPQ.Score AS QuestionScore,
    TOPQ.ViewCount AS QuestionViews,
    TOPQ.CreationDate AS QuestionCreationDate,
    TOPQ.AnswerCount AS QuestionAnswerCount
FROM UserActivity ua
LEFT JOIN PostHistorySummary ps ON ps.PostId = ua.UserId /* assuming mapping for user's questions and edits */
LEFT JOIN PostLinksAggregated tl ON tl.PostId = ua.UserId
LEFT JOIN QuestionAnswerStats pa ON pa.QuestionId = TOPQ.Id
LEFT JOIN TopQuestions TOPQ ON TOPQ.OwnerUserId = ua.UserId
ORDER BY ua.Reputation DESC
LIMIT 100;