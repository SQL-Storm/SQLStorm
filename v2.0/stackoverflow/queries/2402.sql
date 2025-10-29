-- {"query": "2402.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1530}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CAST(t.TagName AS VARCHAR(1000)) AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        CAST(rh.TagPath || '>' || child.TagName AS VARCHAR(1000)) AS TagPath,
        rh.Level + 1 AS Level
    FROM Tags child
    JOIN RecursiveTagHierarchy rh ON child.Id <> rh.Id AND child.Count < rh.Count AND POSITION(child.TagName IN rh.TagPath) = 0
    WHERE child.IsRequired = FALSE
),
TopUsersByBadgeScore AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE(SUM(COALESCE(vs.VoteScore, 0)), 0) AS TotalVoteScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(b.Id) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN LATERAL (
        SELECT SUM(CASE v.VoteTypeId WHEN 2 THEN 1 WHEN 3 THEN -1 ELSE 0 END) AS VoteScore
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId AND p.OwnerUserId = u.Id
        WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ) vs ON TRUE
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentHotQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ph.Comment AS CloseReason,
        RANK() OVER (PARTITION BY ph.Comment ORDER BY p.Score DESC, p.ViewCount DESC) AS RankWithinCloseReason
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 52
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
),
CommentStats AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(CHAR_LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.UserId) FILTER (WHERE c.UserId IS NOT NULL) AS UniqueCommenters
    FROM Comments c
    GROUP BY c.PostId
),
AnswersPerQuestion AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY p.ParentId
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    COALESCE(a.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(a.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(c.CommentCount, 0) AS NumberOfComments,
    ROUND(COALESCE(c.AvgCommentLength, 0)) AS AvgCommentLength,
    COALESCE(c.UniqueCommenters, 0) AS UniqueCommenters,
    SUBSTRING(q.Tags FROM 2) AS TagsRaw,
    SUBSTRING(q.Tags FROM 2 FOR (POSITION('>' IN SUBSTRING(q.Tags FROM 2)) - 1)) AS FirstTag,
    rh.Level AS TagLevel,
    rh.TagPath,
    q.ClosedDate,
    CASE WHEN q.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
    q.AcceptedAnswerId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.Location,
    u.CreationDate AS OwnerCreationDate,
    RANK() OVER (PARTITION BY SUBSTRING(q.Tags FROM 2 FOR (POSITION('>' IN SUBSTRING(q.Tags FROM 2)) - 1)) ORDER BY q.Score DESC) AS RankByTagScore,
    (
      SELECT COUNT(*)
      FROM Badges b2
      WHERE b2.UserId = q.OwnerUserId
        AND b2.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ) AS OwnerRecentBadgeCount,
    (
      SELECT COUNT(*)
      FROM PostLinks pl
      WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
    )
    +
    (
      SELECT COUNT(*)
      FROM PostLinks pl2
      WHERE pl2.RelatedPostId = q.Id AND pl2.LinkTypeId = 3
    ) AS DuplicateLinkCount,
    CONCAT_WS(' - ',
      COALESCE(u.DisplayName, 'Unknown User'),
      COALESCE(NULLIF(u.Location, ''), 'No Location'),
      'Reputation: ' || COALESCE(CAST(u.Reputation AS TEXT), '0')
    ) AS UserSummary,
    CASE 
      WHEN ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS INTEGER) IN (101, 1) THEN 'Duplicate'
      WHEN ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS INTEGER) IN (102, 2) THEN 'Off-topic'
      WHEN ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS INTEGER) IN (103, 3) THEN 'Needs details or clarity'
      WHEN ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS INTEGER) IN (104, 4) THEN 'Needs more focus'
      WHEN ph.Comment ~ '^[0-9]+$' AND CAST(ph.Comment AS INTEGER) IN (105, 5) THEN 'Opinion-based'
      ELSE 'Not closed or unknown reason'
    END AS CloseReasonName
FROM Posts q
LEFT JOIN AnswersPerQuestion a ON a.QuestionId = q.Id
LEFT JOIN CommentStats c ON c.PostId = q.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = SUBSTRING(q.Tags FROM 2 FOR (POSITION('>' IN SUBSTRING(q.Tags FROM 2)) - 1))
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
WHERE q.PostTypeId = 1
GROUP BY
    q.Id,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    a.TotalAnswers,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    c.CommentCount,
    c.AvgCommentLength,
    c.UniqueCommenters,
    q.Tags,
    rh.Level,
    rh.TagPath,
    q.ClosedDate,
    q.AcceptedAnswerId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.CreationDate,
    u.Id,
    ph.Comment,
    ph.PostId,
    ph.PostHistoryTypeId
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100;