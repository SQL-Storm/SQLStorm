-- {"query": "622.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1440} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(p.ViewCount, 0) AS TagExcerptViewCount,
        1 AS Level
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        COALESCE(p2.ViewCount, 0) + r.TagExcerptViewCount AS TagExcerptViewCount,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.WikiPostId = r.Id
    LEFT JOIN Posts p2 ON t2.ExcerptPostId = p2.Id
    WHERE t2.IsModeratorOnly = 0 AND t2.IsRequired = 0 AND r.Level < 3
),
UserBadgesRanked AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.TagBased = 0
),
UserPostsStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS MaxPostScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
PostAnswerRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
PostLinksFiltered AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name IN ('Linked', 'Duplicate')
),
ComplexFilteredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.Comment AS CloseReason,
        ph.CreationDate AS CloseDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS CloseEventRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11) -- Closed or Reopened
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
FinalAggregated AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.OwnerName,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.CloseReason,
        p.CloseDate,
        us.QuestionsCount,
        us.AnswersCount,
        us.AvgPostScore,
        us.MaxPostScore,
        us.TotalQuestionViews,
        us.TotalComments,
        ub.BadgeName,
        ub.Class AS BadgeClass,
        rh.TagName,
        rh.TagExcerptViewCount,
        par.AnswerId,
        par.Score AS AnswerScore,
        par.AnswerRank,
        plf.LinkTypeName,
        -- Complex string expression with NULL logic
        CASE
            WHEN p.CloseReason IS NOT NULL THEN CONCAT('Closed: ', COALESCE(p.CloseReason, 'Unknown'))
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            ELSE 'Open Question'
        END AS QuestionStatus,
        -- Window function over answers per question
        COUNT(par.AnswerId) OVER (PARTITION BY p.Id) AS TotalAnswers,
        -- Correlated subquery to find last comment text per question by owner
        (SELECT c.Text
         FROM Comments c
         WHERE c.PostId = p.Id AND c.UserId = p.OwnerUserId
         ORDER BY c.CreationDate DESC
         LIMIT 1) AS LastOwnerCommentText
    FROM ComplexFilteredPosts p
    LEFT JOIN UserPostsStats us ON us.UserId = p.OwnerUserId
    LEFT JOIN UserBadgesRanked ub ON ub.UserId = p.OwnerUserId AND ub.BadgeRank = 1
    LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' '))
    LEFT JOIN PostAnswerRanks par ON par.QuestionId = p.Id AND par.AnswerRank <= 3
    LEFT JOIN PostLinksFiltered plf ON plf.PostId = p.Id
    WHERE p.CloseEventRank = 1
)
SELECT DISTINCT
    QuestionId,
    Title,
    OwnerUserId,
    OwnerName,
    Score,
    ViewCount,
    Tags,
    AcceptedAnswerId,
    CloseReason,
    CloseDate,
    QuestionsCount,
    AnswersCount,
    ROUND(AvgPostScore::numeric, 2) AS AvgPostScore,
    MaxPostScore,
    TotalQuestionViews,
    TotalComments,
    BadgeName,
    CASE BadgeClass
        WHEN 1 THEN 'Gold'
        WHEN 2 THEN 'Silver'
        WHEN 3 THEN 'Bronze'
        ELSE 'None'
    END AS BadgeClass,
    TagName,
    TagExcerptViewCount,
    AnswerId,
    AnswerScore,
    AnswerRank,
    LinkTypeName,
    QuestionStatus,
    TotalAnswers,
    LastOwnerCommentText
FROM FinalAggregated
WHERE Score > COALESCE((SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1), 0)
  AND (TagExcerptViewCount > 1000 OR TagExcerptViewCount IS NULL)
ORDER BY Score DESC, ViewCount DESC, CloseDate NULLS LAST
LIMIT 100;
