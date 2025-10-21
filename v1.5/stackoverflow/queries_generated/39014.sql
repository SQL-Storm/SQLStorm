-- {"query": "39014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1770} 

WITH
-- Extract question tags into an array
QuestionTags AS (
    SELECT
        p.Id AS QuestionId,
        string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS TagList
    FROM Posts p
    WHERE p.PostTypeId = 1
),
-- Compute per-question metrics: answers, votes, comments, duplicate links, avg edit interval
QuestionMetrics AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(DISTINCT a.Id)                                     AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                                      AS VoteScore,
        COUNT(DISTINCT c.Id)                                     AS CommentCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinkCount,
        COALESCE(AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) / 3600), 0) AS AvgEditHours
    FROM Posts q
    LEFT JOIN Posts a
        ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v
        ON v.PostId = q.Id AND v.VoteTypeId IN (2,3)
    LEFT JOIN Comments c
        ON c.PostId = q.Id
    LEFT JOIN PostLinks pl
        ON pl.PostId = q.Id
    LEFT JOIN PostHistory ph
        ON ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4,5)
    LEFT JOIN Posts p
        ON p.Id = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
-- Compute per-user badge counts by class
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
-- Compute per-user average question score
UserQuestionScores AS (
    SELECT
        p.OwnerUserId AS UserId,
        AVG(p.Score)            AS AvgQuestionScore,
        COUNT(*)                AS QuestionCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    q.Id                                    AS QuestionId,
    q.Title                                 AS QuestionTitle,
    u.DisplayName                           AS OwnerName,
    u.Reputation                            AS OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    uqs.AvgQuestionScore,
    uqs.QuestionCount,
    qm.AnswerCount,
    qm.CommentCount,
    qm.VoteScore,
    qm.DuplicateLinkCount,
    round(qm.AvgEditHours, 2)               AS AvgEditHours,
    qt.TagList
FROM Posts q
JOIN Users u
    ON u.Id = q.OwnerUserId
LEFT JOIN QuestionMetrics qm
    ON qm.QuestionId = q.Id
LEFT JOIN QuestionTags qt
    ON qt.QuestionId = q.Id
LEFT JOIN UserBadges ub
    ON ub.UserId = u.Id
LEFT JOIN UserQuestionScores uqs
    ON uqs.UserId = u.Id
WHERE q.PostTypeId = 1
  AND qm.AnswerCount >= 3
  AND qm.VoteScore >= 5
  AND u.Reputation >= 1000
ORDER BY qm.VoteScore DESC, qm.CommentCount DESC, qm.AnswerCount DESC
LIMIT 20;
