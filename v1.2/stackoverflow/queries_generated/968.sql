-- {"query": "968.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2003} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.TagName] AS AncestorTags,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        r.AncestorTags || t.TagName,
        r.Level + 1
    FROM Tags t
    JOIN PostLinks pl ON pl.PostId = t.ExcerptPostId
    JOIN RecursiveTagHierarchy r ON pl.RelatedPostId = r.Id
    WHERE r.Level < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Id END) AS TagBasedBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostScoreWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        LEAD(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
QuestionsWithStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.Score > 0) AS PositiveAnswerCount,
        (SELECT COUNT(DISTINCT u.Id)
         FROM Posts a2 
         JOIN Users u ON u.Id = a2.OwnerUserId
         WHERE a2.ParentId = p.Id AND a2.Score > 0 AND u.Reputation > 1000) AS HighRepAnswerUsers,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        u.Location,
        u.CreationDate AS UserCreationDate
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '2 years'
),
QuestionCloseReasons AS (
    SELECT
        ph.PostId,
        cr.Name AS CloseReason,
        COUNT(*) AS CloseVotes
    FROM PostHistory ph
    JOIN CloseReasonTypes cr ON CAST(ph.Comment AS int) = cr.Id
    WHERE ph.PostHistoryTypeId = 10 AND ph.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY ph.PostId, cr.Name
),
UserActivityWindows AS (
    SELECT
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(ph.CreationDate) AS LastHistoryEdit,
        MAX(v.CreationDate) AS LastVoteDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(ph.CreationDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
        ) AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
ComplexFilteredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        ph.Comment AS EditComment,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed' 
            ELSE 'Open' END AS PostStatus,
        CHAR_LENGTH(p.Body) - CHAR_LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeSnippetCount,
        COALESCE(u.Reputation, 0) AS OwnerReputation
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
FinalAggregatedStats AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.PositiveAnswerCount,
        q.HighRepAnswerUsers,
        q.HasAcceptedAnswer,
        COALESCE(qc.CloseReason, 'Not Closed') AS CloseReason,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        ua.LastActivity,
        SUM(cf.CodeSnippetCount) AS TotalCodeSnippetsInQuestionAndAnswers,
        AVG(cf.OwnerReputation) FILTER (WHERE cf.PostTypeId = 2) AS AvgAnswererReputation
    FROM QuestionsWithStats q
    LEFT JOIN QuestionCloseReasons qc ON qc.PostId = q.QuestionId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN UserActivityWindows ua ON ua.UserId = q.OwnerUserId
    LEFT JOIN Posts a ON a.ParentId = q.QuestionId
    LEFT JOIN ComplexFilteredPosts cf ON cf.Id IN (q.QuestionId, a.Id)
    GROUP BY 
        q.QuestionId, q.Title, q.Score, q.ViewCount, q.PositiveAnswerCount, q.HighRepAnswerUsers, q.HasAcceptedAnswer,
        qc.CloseReason,
        ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TagBasedBadges,
        ua.LastActivity
)
SELECT
    fas.QuestionId,
    fas.Title,
    fas.Score,
    fas.ViewCount,
    fas.PositiveAnswerCount,
    fas.HighRepAnswerUsers,
    fas.HasAcceptedAnswer,
    fas.CloseReason,
    fas.TotalBadges,
    fas.GoldBadges,
    fas.SilverBadges,
    fas.BronzeBadges,
    fas.TagBasedBadges,
    fas.LastActivity,
    fas.TotalCodeSnippetsInQuestionAndAnswers,
    fas.AvgAnswererReputation,
    STRING_AGG(DISTINCT COALESCE(t.TagName, '')) AS RecursiveTags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fas.QuestionId AND v.VoteTypeId = 2) AS UpVotesCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fas.QuestionId AND v.VoteTypeId = 3) AS DownVotesCount,
    CASE 
        WHEN fas.AvgAnswererReputation > 10000 THEN 'Expert Answers'
        WHEN fas.AvgAnswererReputation BETWEEN 1000 AND 10000 THEN 'Intermediate Answers'
        ELSE 'Beginner Answers'
    END AS AnswererLevelCategory
FROM FinalAggregatedStats fas
LEFT JOIN Posts p_main ON p_main.Id = fas.QuestionId
LEFT JOIN LATERAL (
    SELECT DISTINCT t.TagName
    FROM RecursiveTagHierarchy t
    WHERE t.TagName = ANY(string_to_array(replace(replace(fas.Title, '<', ''), '>', ''), ' '))
    OR t.TagName = ANY(string_to_array(COALESCE(p_main.Tags, ''), '><'))
    LIMIT 5
) t ON TRUE
WHERE fas.Score > 50 AND fas.ViewCount > 1000
GROUP BY
    fas.QuestionId, fas.Title, fas.Score, fas.ViewCount, fas.PositiveAnswerCount, fas.HighRepAnswerUsers, fas.HasAcceptedAnswer,
    fas.CloseReason, fas.TotalBadges, fas.GoldBadges, fas.SilverBadges, fas.BronzeBadges, fas.TagBasedBadges, fas.LastActivity,
    fas.TotalCodeSnippetsInQuestionAndAnswers, fas.AvgAnswererReputation
ORDER BY fas.Score DESC, fas.ViewCount DESC
LIMIT 50;
