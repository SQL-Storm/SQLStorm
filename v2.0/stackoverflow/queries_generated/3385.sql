-- {"query": "3385.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2180} 

WITH
    user_activity AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpVoteGiven,
            COUNT(DISTINCT v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownVoteGiven,
            MAX(p.CreationDate) AS LastPostDate,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Users u
        LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v          ON v.UserId = u.Id
        LEFT JOIN VoteTypes vt    ON vt.Id = v.VoteTypeId
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    recent_badges AS (
        SELECT
            b.UserId,
            STRING_AGG(b.Name || ' (' || b.Class || ')', ', ') AS BadgesList,
            MAX(b.Date) AS LatestBadgeDate
        FROM Badges b
        GROUP BY b.UserId
    ),
    tag_popularity AS (
        SELECT
            t.TagName,
            t.Count AS TagUseCount,
            COALESCE(e.AnswerCount,0) AS ExcerptAnswerCount
        FROM Tags t
        LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    ),
    top_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.CreationDate,
            u.DisplayName AS OwnerName,
            ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore
        FROM Posts p
        JOIN Users u ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1
          AND p.Score IS NOT NULL
    ),
    recent_closed AS (
        SELECT
            ph.PostId,
            ph.CreationDate AS ClosedDate,
            ph.Comment AS CloseReason,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
    ),
    closed_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            rc.ClosedDate,
            rc.CloseReason
        FROM Posts p
        LEFT JOIN recent_closed rc ON rc.PostId = p.Id AND rc.rn = 1
        WHERE p.PostTypeId = 1
    ),
    combined AS (
        SELECT *
        FROM top_questions
        UNION ALL
        SELECT
            cq.Id,
            cq.Title,
            cq.Score,
            cq.ClosedDate,
            cq.CloseReason
        FROM closed_questions cq
        WHERE cq.Score < 0
    )
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpVoteGiven,
    ua.DownVoteGiven,
    COALESCE(rb.BadgesList, 'No badges') AS Badges,
    rb.LatestBadgeDate,
    ua.LastPostDate,
    ua.LastVoteDate,
    tp.TagName,
    tp.TagUseCount,
    tp.ExcerptAnswerCount,
    c.RankByScore,
    c.Title AS SampleTitle,
    CASE
        WHEN c.RankByScore IS NOT NULL THEN 'Top Question'
        WHEN c.CloseReason IS NOT NULL THEN 'Closed: ' || COALESCE(c.CloseReason, 'unknown')
        ELSE 'Other'
    END AS Category,
    CONCAT('Score:', COALESCE(c.Score::text,'0'), ' | Owner:', COALESCE(c.OwnerName,'?')) AS Summary
FROM user_activity ua
LEFT JOIN recent_badges rb ON rb.UserId = ua.UserId
LEFT JOIN LATERAL (
    SELECT *
    FROM tag_popularity tp
    WHERE tp.TagUseCount > 1000
    ORDER BY tp.TagUseCount DESC
    LIMIT 1
) tp ON TRUE
LEFT JOIN combined c ON c.RankByScore = 1
ORDER BY ua.Reputation DESC NULLS LAST
LIMIT 100;
