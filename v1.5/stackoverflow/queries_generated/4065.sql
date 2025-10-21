-- {"query": "4065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1425} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.TagName] AS Ancestry
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        c.IsModeratorOnly,
        c.IsRequired,
        p.Level + 1,
        p.Ancestry || c.TagName
    FROM Tags c
    JOIN PostLinks pl ON pl.PostId = c.ExcerptPostId OR pl.PostId = c.WikiPostId
    JOIN RecursiveTagHierarchy p ON pl.RelatedPostId = p.ExcerptPostId OR pl.RelatedPostId = p.WikiPostId
    WHERE c.IsRequired = 0 -- assume related tags not required
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(COALESCE(p.Score,0)) AS TotalPostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RepRankByLocation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Location IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostWithAcceptedAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.ViewCount,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        a.Id AS AcceptedAnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        COALESCE(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600, NULL) AS HoursToAccept,
        COALESCE(a.Body, '') AS AcceptedAnswerBody
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
UserBadgesRanked AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM Badges b
),
RecentClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        crt.Name AS CloseReasonName,
        ph.Comment AS CloseReasonId,
        q.Title
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id
    JOIN Posts q ON q.Id = ph.PostId
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.CreationDate > NOW() - INTERVAL '30 days'
),
CommentsOnHotQuestions AS (
    SELECT
        c.Id AS CommentId,
        c.PostId,
        c.CreationDate,
        c.UserId,
        c.UserDisplayName,
        c.Text AS CommentText,
        q.Title AS QuestionTitle,
        q.Score AS QuestionScore,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC NULLS LAST) AS CommentScoreRank
    FROM Comments c
    JOIN Posts q ON q.Id = c.PostId
    WHERE q.PostTypeId = 1 AND q.Score > 50
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Location,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalPostScore,
    COALESCE(uab.BadgeName, 'No Badge') AS TopBadge,
    pb.PostCountWithAcceptedAnswer,
    pwas.HoursToAccept,
    pwas.QuestionScore,
    pwas.AnswerScore,
    rqc.CloseReasonName,
    cqh.CommentText,
    STRING_AGG(DISTINCT rth.TagName, ', ') AS RelatedTagsInHierarchy,
    CASE
        WHEN ua.Reputation > 10000 THEN 'Elite'
        WHEN ua.Reputation BETWEEN 1000 AND 10000 THEN 'Experienced'
        ELSE 'Newbie'
    END AS UserLevel,
    ua.RepRankByLocation,
    (LENGTH(COALESCE(uab.BadgeName, '')) - LENGTH(REPLACE(COALESCE(uab.BadgeName, ''), 'a', ''))) AS BadgeName_a_count
FROM UserActivityWindow ua
LEFT JOIN UserBadgesRanked uab ON ua.UserId = uab.UserId AND uab.BadgeRank = 1
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*) AS PostCountWithAcceptedAnswer
    FROM Posts
    WHERE AcceptedAnswerId IS NOT NULL
    GROUP BY OwnerUserId
) pb ON pb.OwnerUserId = ua.UserId
LEFT JOIN PostWithAcceptedAnswerStats pwas ON pwas.QuestionId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId AND AcceptedAnswerId IS NOT NULL LIMIT 1
)
LEFT JOIN RecentClosedQuestionsWithReasons rqc ON rqc.PostId IN (
    SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId AND PostTypeId = 1
)
LEFT JOIN CommentsOnHotQuestions cqh ON cqh.UserId = ua.UserId
LEFT JOIN RecursiveTagHierarchy rth ON rth.ExcerptPostId IN (
    SELECT WikiPostId FROM Tags WHERE Count > 1000
)
WHERE (ua.QuestionCount + ua.AnswerCount) > 10
  AND (
    pwas.HoursToAccept IS NULL OR pwas.HoursToAccept < 72
  )
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Location,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalPostScore,
    uab.BadgeName,
    pb.PostCountWithAcceptedAnswer,
    pwas.HoursToAccept,
    pwas.QuestionScore,
    pwas.AnswerScore,
    rqc.CloseReasonName,
    cqh.CommentText,
    ua.RepRankByLocation
ORDER BY ua.Reputation DESC NULLS LAST, ua.Location, ua.UserId
LIMIT 100
;
