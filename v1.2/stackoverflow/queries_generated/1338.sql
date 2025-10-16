-- {"query": "1338.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1528} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        1 AS Level,
        CAST(t.TagName AS varchar(350)) AS Path
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.IsModeratorOnly = 0 AND length(t2.TagName) > length(r.TagName)
    WHERE r.Level < 3
),
QuestionAnswersCTE AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerCommentsCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS AnswerUpvotes,
        q.AcceptedAnswerId,
        u.DisplayName AS QuestionOwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    WHERE q.PostTypeId = 1
      AND (q.ClosedDate IS NULL OR q.ClosedDate > NOW() - INTERVAL '180 days')
),
UserActivitySummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
        COALESCE(SUM(votes.CastedUpvotes), 0) AS TotalUpvotesCast,
        COALESCE(SUM(votes.CastedDownvotes), 0) AS TotalDownvotesCast,
        RANK() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.CreationDate) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS CastedUpvotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS CastedDownvotes
        FROM Votes
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) votes ON votes.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionWithLinkStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        COUNT(pl.Id) AS TotalLinkCount,
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            ELSE 'No Accepted Answer'
        END AS AcceptanceStatus
    FROM Posts q
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.AcceptedAnswerId
),
LatestPostHistoryEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId, ph.UserId
)
SELECT
    qac.QuestionId,
    qac.Title,
    qac.QuestionCreation,
    UPPER(TRIM(COALESCE(u.DisplayName, 'Community'))) AS QuestionOwner,
    qac.QuestionScore,
    qac.ViewCount,
    -- Validate if 'python' tag exists inside Tags: search understanding Swagger Angles: NULL-safe substring
    CASE WHEN POSITION('<python>' in COALESCE(qac.Tags, '') || '') > 0 THEN TRUE ELSE FALSE END AS HasPythonTag,
    qac.AcceptedAnswerId IS NOT NULL AS HasAcceptedAnswer,
    uas.DisplayName AS TopUserDisplayName,
    uas.TotalPosts,
    uas.GoldBadgeCount,
    qws.LinkedCount,
    qws.DuplicateCount,
    qws.AcceptanceStatus,
    -- Find Answer with max score and its Upvotes
    MAX(CASE WHEN qa.AnswerRank = 1 THEN qa.AnswerId ELSE NULL END) AS TopAnswerId,
    MAX(CASE WHEN qa.AnswerRank = 1 THEN qa.AnswerUpvotes ELSE 0 END) AS TopAnswerUpvotes,
    -- Calculate elapsed days since question creation
    EXTRACT(EPOCH FROM (NOW() - qac.QuestionCreation))/86400 AS DaysSinceCreation,
    -- Count how many edits have been made recently by a user with at least 50 reputation
    (SELECT COUNT(DISTINCT ph2.Id)
     FROM PostHistory ph2
     JOIN Users u2 ON u2.Id = ph2.UserId
     WHERE ph2.PostId = qac.QuestionId
       AND ph2.CreationDate > NOW() - INTERVAL '30 days'
       AND u2.Reputation >= 50
       AND ph2.PostHistoryTypeId IN (4,5,6)) AS RecentUserEditsCount
FROM QuestionAnswersCTE qac
LEFT JOIN Users u ON u.Id = qac.OwnerUserId
LEFT JOIN UserActivitySummary uas ON uas.Id = qac.AnswerOwnerUserId
LEFT JOIN QuestionWithLinkStats qws ON qws.QuestionId = qac.QuestionId
LEFT JOIN LatestPostHistoryEdits lph ON lph.PostId = qac.QuestionId AND lph.UserId = uas.Id
LEFT JOIN QuestionAnswersCTE qa ON qa.QuestionId = qac.QuestionId AND qa.AnswerRank = 1
WHERE qac.AnswerRank <= 1 OR qac.AnswerRank IS NULL
GROUP BY qac.QuestionId, qac.Title, qac.QuestionCreation, uas.DisplayName, uas.TotalPosts,
         uas.GoldBadgeCount, qws.LinkedCount, qws.DuplicateCount, qws.AcceptanceStatus,
         uas.Id, qac.QuestionScore, qac.ViewCount, uas.DisplayName, u.DisplayName, qac.Tags, qac.AcceptedAnswerId
ORDER BY qac.QuestionScore DESC NULLS LAST, qac.ViewCount DESC NULLS LAST
LIMIT 100;
