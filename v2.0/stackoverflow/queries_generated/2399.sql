-- {"query": "2399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1482} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        c.Id,
        c.TagName,
        c.Count,
        r.TagPath || c.TagName
    FROM Tags c
    JOIN RecursiveTagHierarchy r ON c.Count < r.Count
    WHERE c.IsModeratorOnly = 0 AND c.IsRequired = 0
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(vt1.CountVotes), 0) AS TotalUpVotes,
        COALESCE(SUM(vt2.CountVotes), 0) AS TotalDownVotes,
        COALESCE(MAX(b.BadgeCount), 0) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountVotes
        FROM Votes
        WHERE VoteTypeId = 2 -- UpMod
        GROUP BY PostId
    ) vt1 ON vt1.PostId = p.Id OR vt1.PostId = p2.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CountVotes
        FROM Votes
        WHERE VoteTypeId = 3 -- DownMod
        GROUP BY PostId
    ) vt2 ON vt2.PostId = p.Id OR vt2.PostId = p2.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnsweredQuestionsRanked AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.DisplayName,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerUserId,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
UserCloseReasons AS (
    SELECT
        ph.UserId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON TRY_CAST(ph.Comment AS INT) = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, crt.Name
),
UserBadgeSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalUpVotes,
    u.TotalDownVotes,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    COALESCE(cr.CloseReason, 'No Close Votes') AS FrequentCloseReason,
    q.Id AS TopQuestionId,
    q.Title AS TopQuestionTitle,
    q.Score AS TopQuestionScore,
    q.ViewCount AS TopQuestionViews,
    a.AnswerId AS TopAnswerId,
    a.AnswerScore AS TopAnswerScore,
    STRING_AGG(DISTINCT CONCAT_WS(' > ', rh.TagPath[1], rh.TagPath[array_length(rh.TagPath,1)]), ' | ') FILTER (WHERE rh.TagPath IS NOT NULL) AS SampleTagHierarchies
FROM UserActivity u
LEFT JOIN UserBadgeSummary b ON b.UserId = u.UserId
LEFT JOIN LATERAL (
    SELECT
        CloseReason
    FROM UserCloseReasons
    WHERE UserId = u.UserId
    ORDER BY CloseCount DESC
    LIMIT 1
) cr ON true
LEFT JOIN LATERAL (
    SELECT *
    FROM TopQuestions tq
    WHERE tq.OwnerUserId = u.UserId AND tq.rn = 1
) q ON true
LEFT JOIN LATERAL (
    SELECT *
    FROM AnsweredQuestionsRanked aqr
    WHERE aqr.QuestionId = q.Id AND aqr.AnswerRank = 1
) a ON true
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(replace(replace(q.Tags, '<', ''), '>', ''), ','))
WHERE u.QuestionCount > 5 AND u.Reputation > 1000
GROUP BY
    u.UserId, u.DisplayName, u.Reputation, u.Location,
    u.QuestionCount, u.AnswerCount, u.TotalUpVotes, u.TotalDownVotes,
    b.GoldBadges, b.SilverBadges, b.BronzeBadges,
    cr.CloseReason,
    q.Id, q.Title, q.Score, q.ViewCount,
    a.AnswerId, a.AnswerScore
ORDER BY u.Reputation DESC
LIMIT 25
UNION
SELECT
    NULL, 'Aggregate Totals', NULL, NULL,
    SUM(u.QuestionCount),
    SUM(u.AnswerCount),
    SUM(u.TotalUpVotes),
    SUM(u.TotalDownVotes),
    SUM(b.GoldBadges),
    SUM(b.SilverBadges),
    SUM(b.BronzeBadges),
    NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM UserActivity u
LEFT JOIN UserBadgeSummary b ON b.UserId = u.UserId
WHERE u.QuestionCount > 5 AND u.Reputation > 1000;
