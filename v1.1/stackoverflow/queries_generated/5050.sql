-- {"query": "5050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1053} 
WITH
TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT ph.Id) AS EditsCount,
        RANK() OVER (ORDER BY (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) + COUNT(DISTINCT ph.Id)) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4,5,6) -- edits
    WHERE u.Reputation >= 1000
    GROUP BY u.Id, u.DisplayName
),
RecentPopularQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.ViewCount,
        q.Score,
        q.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY q.ViewCount DESC, q.Score DESC) AS qn
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.ViewCount > 1000
      AND q.CreationDate > NOW() - INTERVAL '1 year'
),
LinkedAndDuplicateStats AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY p.Id
),
UserTopTags AS (
    SELECT
        p.OwnerUserId,
        SPLIT_PART(substring(t, 2, length(t)-2), '><', 1) AS FirstTag
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
RecentBadgeWinners AS (
    SELECT
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Class ASC) AS BadgeRank
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '3 months'
),
ClosureReasonSummary AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS NumClosed
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON
        CAST(NULLIF(ph.Comment, '') AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY ph.PostId, crt.Name
)
SELECT
    rau.UserId,
    rau.DisplayName,
    rau.PostsCount,
    rau.CommentsCount,
    rau.EditsCount,
    rpq.QuestionId,
    rpq.Title AS QuestionTitle,
    rpq.CreationDate AS QuestionCreation,
    rpq.ViewCount,
    rpq.Score AS QuestionScore,
    las.LinkedCount,
    las.DuplicateCount,
    ut.FirstTag AS MostUsedTag,
    COALESCE(crs.CloseReason, 'N/A') AS LastCloseReason,
    COALESCE(crs.NumClosed, 0) AS TimesClosed,
    COALESCE(rb.Name, 'None') AS MostRecentBadge,
    COALESCE(rb.Class::text, '') AS BadgeClass
FROM TopActiveUsers rau
LEFT JOIN RecentPopularQuestions rpq
    ON rpq.OwnerUserId = rau.UserId AND rpq.qn <= 5
LEFT JOIN LinkedAndDuplicateStats las
    ON las.PostId = rpq.QuestionId
LEFT JOIN LATERAL (
    SELECT FirstTag
    FROM UserTopTags ut
    WHERE ut.OwnerUserId = rau.UserId
    GROUP BY FirstTag
    ORDER BY COUNT(*) DESC
    LIMIT 1
) ut ON TRUE
LEFT JOIN LATERAL (
    SELECT crs.CloseReason, crs.NumClosed
    FROM ClosureReasonSummary crs
    WHERE crs.PostId = rpq.QuestionId
    ORDER BY NumClosed DESC
    LIMIT 1
) crs ON TRUE
LEFT JOIN LATERAL (
    SELECT rb.Name, rb.Class
    FROM RecentBadgeWinners rb
    WHERE rb.UserId = rau.UserId
    AND rb.BadgeRank = 1
    LIMIT 1
) rb ON TRUE
WHERE rau.ActivityRank <= 50
  AND (rpq.QuestionId IS NOT NULL OR rau.CommentsCount > 20)
ORDER BY rau.ActivityRank, rpq.ViewCount DESC NULLS LAST;