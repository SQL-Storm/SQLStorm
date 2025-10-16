-- {"query": "1235.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1636} 

WITH RecursivePostsCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        1 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only

    UNION ALL

    SELECT
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Tags,
        c.AcceptedAnswerId,
        rp.Depth + 1
    FROM Posts c
    INNER JOIN RecursivePostsCTE rp ON c.ParentId = rp.Id
    WHERE c.PostTypeId = 2 -- Answers linked to questions or answers
),
LatestPostHistory AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11) -- Post Closed or Post Reopened
),
UserBadgesSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
QuestionAnalytics AS (
    SELECT 
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        COALESCE(q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.CreationDate >= q.CreationDate) AS CommentCountSinceCreation,
        (SELECT COUNT(DISTINCT vl.RelatedPostId)
         FROM PostLinks vl
         WHERE vl.PostId = q.Id AND vl.LinkTypeId = 3) AS DuplicateCount,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS PopularRank
    FROM Posts q
    WHERE q.PostTypeId = 1
),
AnswerScores AS (
    SELECT
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT v.UserId) AS DistinctVoters,
        COUNT(*) AS VoteCount,
        AVG(COALESCE(a.Score,0)) AS AvgScorePerAnswer
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, a.OwnerUserId
),
UsersWithActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        CASE WHEN u.LastAccessDate > current_date - INTERVAL '30 day' THEN 1 ELSE 0 END AS ActiveLast30Days
    FROM Users u
    LEFT JOIN UserBadgesSummary b ON b.UserId = u.Id
),
TagPostCounts AS (
    SELECT
        tg.TagName,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.DisplayName IS NOT NULL) AS TopOwnersWithTag
    FROM Tags tg
    LEFT JOIN Posts p ON p.PostTypeId = 1 
                        AND POSITION(CONCAT('<', tg.TagName, '>') IN p.Tags) > 0
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    GROUP BY tg.TagName
),
QuestionsWithStatus AS (
    SELECT
        qa.*,
        tph.CreationDate AS ClosedDate,
        tph.UserId AS ClosedByUserId,
        cr.Name AS CloseReason
    FROM QuestionAnalytics qa
    LEFT JOIN LatestPostHistory tph 
        ON tph.PostId = qa.Id AND tph.PostHistoryTypeId = 10 AND tph.rn = 1
    LEFT JOIN CloseReasonTypes cr ON CAST(tph.Comment AS int) = cr.Id
),
UserAnswerRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.ParentId AS QuestionId,
        a.Score,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC NULLS LAST) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
)
SELECT 
    qws.Id AS QuestionId,
    qws.Title,
    qws.Tags,
    qws.Score AS QuestionScore,
    qws.ViewCount,
    qws.CommentCountSinceCreation,
    qws.DuplicateCount,
    qws.PopularRank,
    COALESCE(uar.AnswerRank, -1) AS AcceptedAnswerRank,
    COALESCE(ars.UpVotes, 0) AS AcceptedAnswerUpVotes,
    COALESCE(ars.DownVotes, 0) AS AcceptedAnswerDownVotes,
    COALESCE(ars.DistinctVoters, 0) AS AcceptedAnswerDistinctVoters,
    coi.DisplayName AS QuestionOwner,
    coi.Reputation AS QuestionOwnerReputation,
    coi.GoldBadges AS QuestionOwnerGoldBadges,
    coi.ActiveLast30Days,
    qws.ClosedDate,
    qws.CloseReason,
    COALESCE(trg.PostsWithTag, 0) AS PostsInTopTag,
    COALESCE(trg.AvgScore, 0) AS AvgScoreInTopTag,
    COALESCE(trg.TopOwnersWithTag, '') AS SomeOwnersInTag,
    Extract(epoch from (NOW() - qws.CreationDate))/86400.0 AS AgeDays,
    Extract(epoch from (COALESCE(qws.ClosedDate, NOW()) - qws.CreationDate))/86400.0 AS OpenDurationDays
FROM QuestionsWithStatus qws
LEFT JOIN Posts accepted ON accepted.Id = qws.AcceptedAnswerId
LEFT JOIN UserAnswerRanks uar ON uar.AnswerId = accepted.Id
LEFT JOIN AnswerScores ars ON ars.QuestionId = qws.Id AND ars.OwnerUserId = accepted.OwnerUserId
LEFT JOIN UsersWithActivity coi ON coi.Id = qws.OwnerUserId
LEFT JOIN TagPostCounts trg ON trg.TagName = (
    SELECT split_part(split_part(qws.Tags, '><', 1), '<', 2) -- selects first tag inside <> brackets
)
WHERE 
    qws.Score >= 10
    AND (qws.ClosedDate IS NULL OR qws.ClosedDate > qws.CreationDate + INTERVAL '7 day')
    AND (ars.UpVotes - ars.DownVotes) > 5
ORDER BY qws.Score DESC, qws.ViewCount DESC
LIMIT 50;
