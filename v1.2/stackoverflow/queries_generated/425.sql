-- {"query": "425.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1983} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        parent.TagPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id <> parent.Id
    WHERE NOT child.TagName = ANY(parent.TagPath)
    AND child.Count < parent.Count
    LIMIT 1000 -- prevent infinite recursion
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostVoteAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END),0) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        MAX(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswersWithOwners,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) OVER (PARTITION BY u.Id) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) OVER (PARTITION BY u.Id) AS AnswerCount,
        COUNT(c.Id) OVER (PARTITION BY u.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC NULLS LAST) AS LastPostRank,
        MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
),
PostLinkDuplicates AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name AS LinkTypeName,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE lt.Name = 'Duplicate'
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        ph.UserId AS ClosedByUserId,
        u.DisplayName AS ClosedByUserName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
QuestionsWithLatestComments AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Id AS CommentId,
        c.Text AS CommentText,
        c.CreationDate AS CommentDate,
        c.UserId AS CommentUserId,
        u.DisplayName AS CommentUserName
    FROM Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
    ORDER BY c.PostId, c.CreationDate DESC
),
QuestionAnswerCombined AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.Tags,
        q.QuestionCreation,
        q.QuestionScore,
        q.QuestionViews,
        q.AnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.AnswersWithOwners,
        q.LastAnswerDate,
        pva.UpVotes AS QuestionUpVotes,
        pva.DownVotes AS QuestionDownVotes,
        pva.TotalBounty AS QuestionBounty,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.LastBadgeDate,
        ca.CloseDate,
        ca.CloseReason,
        ca.ClosedByUserName,
        qc.CommentText AS LatestComment,
        qc.CommentDate AS LatestCommentDate,
        qc.CommentUserName AS LatestCommentUser
    FROM QuestionAnswerStats q
    LEFT JOIN PostVoteAggregates pva ON q.QuestionId = pva.PostId
    LEFT JOIN UserBadgeSummary ubs ON pva.OwnerUserId = ubs.UserId
    LEFT JOIN ClosedQuestionsWithReasons ca ON q.QuestionId = ca.PostId
    LEFT JOIN QuestionsWithLatestComments qc ON q.QuestionId = qc.PostId
)
SELECT
    qac.QuestionId,
    qac.Title,
    COALESCE(NULLIF(qac.Tags, ''), '<no tags>') AS Tags,
    qac.QuestionCreation,
    qac.QuestionScore,
    qac.QuestionViews,
    qac.AnswerCount,
    ROUND(qac.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    qac.MaxAnswerScore,
    qac.AnswersWithOwners,
    qac.LastAnswerDate,
    qac.QuestionUpVotes,
    qac.DownVotes AS QuestionDownVotes,
    qac.QuestionBounty,
    qac.GoldBadges,
    qac.SilverBadges,
    qac.BronzeBadges,
    qac.LastBadgeDate,
    qac.CloseDate,
    qac.CloseReason,
    qac.ClosedByUserName,
    qac.LatestComment,
    qac.LatestCommentDate,
    qac.LatestCommentUser,
    -- Window function: rank questions by score within each tag (explode tags)
    RANK() OVER (
        PARTITION BY unnest(string_to_array(replace(replace(qac.Tags, '<', ''), '>', ' '), ' '))
        ORDER BY qac.QuestionScore DESC NULLS LAST
    ) AS ScoreRankWithinTag,
    -- String manipulation: extract first tag or 'none'
    COALESCE(split_part(trim(both ' ' FROM qac.Tags), '><', 1), 'none') AS FirstTag,
    -- Complex predicate: questions with answers having higher average score than question score and at least one gold badge owner
    CASE
        WHEN qac.AvgAnswerScore > qac.QuestionScore AND qac.GoldBadges > 0 THEN 'High Quality'
        ELSE 'Normal'
    END AS QualityCategory,
    -- Correlated subquery: count of distinct users who answered this question
    (
        SELECT COUNT(DISTINCT a.OwnerUserId)
        FROM Posts a
        WHERE a.ParentId = qac.QuestionId AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    ) AS DistinctAnswerersCount,
    -- NULL logic: days since last answer or since question creation if no answers
    COALESCE(
        EXTRACT(EPOCH FROM (NOW() - qac.LastAnswerDate)) / 86400,
        EXTRACT(EPOCH FROM (NOW() - qac.QuestionCreation)) / 86400
    )::INT AS DaysSinceLastActivity,
    -- EXISTS predicate: has duplicate posts linked
    EXISTS (
        SELECT 1 FROM PostLinkDuplicates pld WHERE pld.PostId = qac.QuestionId
    ) AS HasDuplicates
FROM QuestionAnswerCombined qac
WHERE qac.AnswerCount > 0
ORDER BY qac.QuestionScore DESC NULLS LAST
LIMIT 50;
