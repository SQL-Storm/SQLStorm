-- {"query": "1254.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1435} 
WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON strpos(t.TagName, r.TagName) > 0 AND t.Id <> r.Id AND array_length(r.TagPath, 1) < 5
),
LatestUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        COALESCE(
            (SELECT MAX(ph.CreationDate)
             FROM PostHistory ph
             WHERE ph.UserId = u.Id), '1900-01-01') AS LastPostHistoryEdit
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostScoresWithBadges AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.DisplayName AS OwnerName,
        BADGECOUNT.BadgeGold,
        BADGECOUNT.BadgeSilver,
        BADGECOUNT.BadgeBronze,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(CASE WHEN Class = 1 THEN 1 END) AS BadgeGold,
            COUNT(CASE WHEN Class = 2 THEN 1 END) AS BadgeSilver,
            COUNT(CASE WHEN Class = 3 THEN 1 END) AS BadgeBronze
        FROM Badges
        GROUP BY UserId
    ) AS BADGECOUNT ON BADGECOUNT.UserId = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
QuestionDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        a.TotalAnswers,
        a.AvgAnswerScore,
        a.MaxAnswerScore,
        (p.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
        ul.LastPostActivity,
        ul.LastCommentDate,
        ul.LastPostHistoryEdit,
        ul.DisplayName AS OwnerName
    FROM Posts p
    LEFT JOIN AnswerStats a ON a.QuestionId = p.Id
    LEFT JOIN LatestUserActivity ul ON ul.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
QuestionDuplicates AS (
    SELECT DISTINCT
        pl.PostId AS DuplicateQuestionId,
        pl.RelatedPostId AS OriginalQuestionId
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),
RankedComments AS (
    SELECT
        c.Id,
        c.PostId,
        c.UserId,
        c.Score,
        c.CreationDate,
        c.Text,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS CommentRank
    FROM Comments c
),
Summary AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        COALESCE(q.Score, 0) AS Score,
        COALESCE(q.ViewCount, 0) AS Views,
        q.Tags,
        q.TotalAnswers,
        coalesce(q.AvgAnswerScore, 0) AS AvgAnswerScore,
        coalesce(q.MaxAnswerScore, 0) AS MaxAnswerScore,
        q.HasAcceptedAnswer,
        q.LastPostActivity,
        q.LastCommentDate,
        q.LastPostHistoryEdit,
        q.OwnerName,
        CASE WHEN qd.DuplicateQuestionId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsDuplicate,
        (
            SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC)
            FROM Badges b
            WHERE b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = q.Id)
              AND b.Date >= q.CreationDate - INTERVAL '365 days'
        ) AS RecentBadges,
        (
            SELECT STRING_AGG(DISTINCT LOWER(SUBSTRING(trim(t), 1, 10)), ', ')
            FROM unnest(string_to_array(COALESCE(q.Tags,''), '><')) AS t
            WHERE t <> ''
        ) AS TagSummary,
        AVG(COALESCE(c.Score,0)) OVER (PARTITION BY q.Id) AS AverageCommentScore
    FROM QuestionDetails q
    LEFT JOIN QuestionDuplicates qd ON qd.DuplicateQuestionId = q.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
)
SELECT
    s.QuestionId,
    LEFT(s.Title, 100) || CASE WHEN LENGTH(s.Title) > 100 THEN '...' ELSE '' END AS ShortTitle,
    s.Score,
    s.Views,
    s.TotalAnswers,
    s.AvgAnswerScore,
    s.MaxAnswerScore,
    s.HasAcceptedAnswer,
    s.IsDuplicate,
    s.OwnerName,
    s.LastPostActivity,
    s.LastCommentDate,
    s.LastPostHistoryEdit,
    COALESCE(s.RecentBadges, 'None') AS RecentBadgeList,
    s.TagSummary,
    ROUND(s.AverageCommentScore, 2) AS AverageCommentScore,
    CASE
        WHEN s.Score >= 50 AND s.HasAcceptedAnswer THEN 'High Quality'
        WHEN s.Score BETWEEN 20 AND 49 THEN 'Medium Quality'
        ELSE 'Low Quality'
    END AS QualityCategory
FROM Summary s
WHERE s.CreationDate >= NOW() - INTERVAL '2 years'
  AND (s.TotalAnswers > 0 OR s.IsDuplicate = 'Yes')
  AND (s.Score IS NOT NULL)
ORDER BY s.Score DESC, s.TotalAnswers DESC NULLS LAST, s.LastPostActivity DESC NULLS LAST
LIMIT 100;