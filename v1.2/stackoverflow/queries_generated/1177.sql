-- {"query": "1177.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1560} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.TagName] AS TagPath,
        t.Count
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        r.TagPath || t.TagName,
        t.Count
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id > r.Id
    WHERE t.IsModeratorOnly = 0
      AND NOT t.TagName = ANY(r.TagPath)
      AND t.Count > r.Count / 10
),
TopUsersByReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.CreationDate DESC) AS UserTopQuestionRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.Score > 10
      AND p.ClosedDate IS NULL
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(DISTINCT q.OwnerUserId) AS UniqueQuestionersAnswered
    FROM Posts a
    LEFT JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (1,2,3)) AS InitialEdits,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS SubsequentEdits,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
DuplicatePairs AS (
    SELECT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId,
        p1.Title AS DuplicateTitle,
        p2.Title AS OriginalTitle,
        u1.DisplayName AS DuplicateOwner,
        u2.DisplayName AS OriginalOwner,
        pl.CreationDate AS LinkCreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    LEFT JOIN Users u1 ON p1.OwnerUserId = u1.Id
    LEFT JOIN Users u2 ON p2.OwnerUserId = u2.Id
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.Score) AS MaxCommentScore,
        MIN(c.Score) AS MinCommentScore,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommentedOn
    FROM Comments c
    JOIN Users u ON c.UserId = u.Id
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId, u.DisplayName
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount,
        MAX(ph.CreationDate) AS LastCloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = CAST(crt.Id AS varchar)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId, crt.Name
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    us.AnswerCount,
    ROUND(us.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    us.MaxAnswerScore,
    us.MinAnswerScore,
    us.UniqueQuestionersAnswered,
    uc.CommentCount,
    ROUND(uc.AvgCommentScore::numeric, 2) AS AvgCommentScore,
    pqs.Id AS TopQuestionId,
    pqs.Title AS TopQuestionTitle,
    CONCAT(
      SPLIT_PART(pqs.Tags, '><', 1),
      COALESCE(' | ' || SPLIT_PART(pqs.Tags, '><', 2), ''),
      COALESCE(' | ' || SPLIT_PART(pqs.Tags, '><', 3), '')
    ) AS TopQuestionTagsSummary,
    pqs.Score AS TopQuestionScore,
    pqs.ViewCount AS TopQuestionViews,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    dc.DuplicateCount,
    qcr.CloseReason,
    qcr.CloseCount,
    qcr.LastCloseDate,
    phs.InitialEdits,
    phs.SubsequentEdits,
    phs.LastEditDate,
    phs.FirstEditDate
FROM TopUsersByReputation u
LEFT JOIN UserAnswerStats us ON us.OwnerUserId = u.Id
LEFT JOIN UserCommentActivity uc ON uc.UserId = u.Id
LEFT JOIN PopularQuestions pqs ON pqs.OwnerName = u.DisplayName AND pqs.UserTopQuestionRank = 1
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*) AS DuplicateCount
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    GROUP BY OwnerUserId
) dc ON dc.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
    SELECT
        p.Id AS PostId,
        qr.CloseReason,
        qr.CloseCount,
        qr.LastCloseDate
    FROM Posts p
    LEFT JOIN QuestionCloseReasons qr ON p.Id = qr.PostId
    WHERE p.PostTypeId = 1
) qcr ON qcr.PostId = pqs.Id
LEFT JOIN PostHistorySummary phs ON phs.PostId = pqs.Id
WHERE (b.Class = 1 OR b.Class IS NULL)
  AND (uc.CommentCount > 10 OR uc.CommentCount IS NULL)
ORDER BY u.Reputation DESC, pqs.Score DESC NULLS LAST
LIMIT 50;
