-- {"query": "5040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1170} 
WITH
active_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC) AS rn_posts
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
popular_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers
    FROM
        Posts p
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
        AND p.Score > 5
        AND p.ViewCount > 1000
    GROUP BY
        p.Id, p.OwnerUserId, p.CreationDate, p.Title, p.Tags, p.Score, p.ViewCount
),
recent_badges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        MAX(b.Date) AS LatestBadgeDate,
        ARRAY_AGG(b.Name) FILTER (WHERE b.Class = 1) AS GoldBadges
    FROM
        Badges b
    WHERE
        b.Date > NOW() - INTERVAL '1 year'
    GROUP BY
        b.UserId
),
tag_stats AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(DISTINCT q.Id) AS DistinctQuestions,
        SUM(q.AnswerCount) AS TotalAnswers,
        AVG(q.Score) AS AvgScore
    FROM
        Tags t
        LEFT JOIN LATERAL (
            SELECT
                p.Id,
                p.Score,
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount
            FROM
                Posts p
            WHERE
                p.PostTypeId = 1
                AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
        ) q ON TRUE
    GROUP BY
        t.TagName, t.Count
),
first_posts AS (
    SELECT DISTINCT ON (p.OwnerUserId)
        p.OwnerUserId,
        p.Id AS FirstPostId,
        p.CreationDate AS FirstPostDate,
        p.Score AS FirstPostScore,
        p.PostTypeId
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
    ORDER BY
        p.OwnerUserId, p.CreationDate ASC
)
SELECT
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.PostCount,
    au.CommentCount,
    au.BadgeCount,
    fp.FirstPostDate,
    fp.FirstPostScore,
    fp.PostTypeId AS FirstPostType,
    pbq.QuestionId,
    pbq.Title AS PopularQuestionTitle,
    pbq.Score AS PopularQuestionScore,
    pbq.ViewCount,
    pbq.AnswerCount AS Qa_AnswerCount,
    pbq.PositiveAnswers,
    COALESCE(rb.LatestBadgeDate, NULL) AS LatestRecentBadgeDate,
    COALESCE(Array_TO_STRING(rb.GoldBadges, ', '), '(no gold)') AS GoldBadges,
    ts.TagName as TopTag,
    ts.Count as TagUseCount,
    ts.DistinctQuestions,
    ts.TotalAnswers,
    ts.AvgScore,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = au.UserId AND v.VoteTypeId = 2), 0
    ) AS UpVotesCast,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = au.UserId AND v.VoteTypeId = 3), 0
    ) AS DownVotesCast
FROM
    active_users au
    LEFT JOIN first_posts fp ON fp.OwnerUserId = au.UserId
    LEFT JOIN LATERAL (
        SELECT pq.*
        FROM popular_questions pq
        WHERE pq.OwnerUserId = au.UserId
        ORDER BY pq.Score DESC, pq.ViewCount DESC
        LIMIT 1
    ) pbq ON TRUE
    LEFT JOIN recent_badges rb ON rb.UserId = au.UserId
    LEFT JOIN LATERAL (
        SELECT ts.*
        FROM tag_stats ts
        JOIN popular_questions pq2 ON pq2.QuestionId = pbq.QuestionId
        WHERE pq2.Tags IS NOT NULL
          AND POSITION(CONCAT('<', ts.TagName, '>') IN pq2.Tags) > 0
        ORDER BY ts.Count DESC
        LIMIT 1
    ) ts ON TRUE
WHERE
    au.rn_posts <= 50
    AND (au.PostCount > 10 OR au.CommentCount > 20 OR au.BadgeCount >= 5)
    AND ((pbq.Score IS NULL) OR (pbq.AnswerCount >= 2 AND pbq.Score >= 10))
ORDER BY
    au.PostCount DESC,
    au.Reputation DESC;