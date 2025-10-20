WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id = r.Id AND r.Level < 2
),
UserBadgeRanks AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) AS GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) AS SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) AS BronzeBadges,
        row_number() OVER (ORDER BY u.Reputation DESC, u.Id) AS UserRank,
        u.Reputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        count(a.Id) AS AnswerCount,
        avg(coalesce(a.Score,0)) AS AvgAnswerScore,
        max(coalesce(a.Score,0)) AS MaxAnswerScore,
        sum(case when a.OwnerUserId IS NOT NULL then 1 else 0 end) AS AnswersWithOwner
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, q.AcceptedAnswerId
),
QuestionCloseInfo AS (
    SELECT ph.PostId, crt.Name AS CloseReason, min(ph.CreationDate) AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id AND ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
TopVoters AS (
    SELECT v.UserId, count(*) AS VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) AS UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
PostLinkSummary AS (
    SELECT pl.PostId, lt.Name AS LinkType, count(*) AS LinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId, lt.Name
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        dense_rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
CorrelatedComments AS (
    SELECT c.PostId, count(*) AS CommentCount, max(c.CreationDate) AS LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    coalesce(qci.CloseReason, 'Open') AS CloseReason,
    qci.CloseDate,
    ub.DisplayName AS QuestionOwner,
    ub.Reputation AS OwnerReputation,
    ubr.GoldBadges,
    ubr.SilverBadges,
    ubr.BronzeBadges,
    tv.VoteCount AS OwnerVoteCount,
    tv.UpVotes AS OwnerUpVotes,
    tv.DownVotes AS OwnerDownVotes,
    pl.LinkType,
    pl.LinkCount,
    rc.CommentCount,
    rc.LastCommentDate,
    rc.Commenters,
    rp.ScoreRank,
    ('Tags: ' ||
        coalesce(qas.Tags, '<none>') ||
        ' | Owner: ' || coalesce(ub.DisplayName, 'unknown') ||
        ' | ScoreRank: ' || CAST(rp.ScoreRank AS varchar)
    ) AS SummaryInfo,
    rank() OVER (PARTITION BY extract(year FROM qas.QuestionCreation) ORDER BY qas.ViewCount DESC) AS YearlyViewRank,
    CASE 
        WHEN qas.AcceptedAnswerId IS NOT NULL THEN 
            (SELECT p2.Score FROM Posts p2 WHERE p2.Id = qas.AcceptedAnswerId)
        ELSE NULL
    END AS AcceptedAnswerScore,
    (SELECT count(distinct a.OwnerUserId) FROM Posts a WHERE a.ParentId = qas.QuestionId AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL) AS DistinctAnswerers,
    (SELECT string_agg(distinct t.TagName, ', ') FROM Tags t WHERE t.Count > 1000) AS PopularTags
FROM QuestionAnswerStats qas
LEFT JOIN QuestionCloseInfo qci ON qas.QuestionId = qci.PostId
LEFT JOIN Users ub ON qas.OwnerUserId = ub.Id
LEFT JOIN UserBadgeRanks ubr ON ub.Id = ubr.UserId
LEFT JOIN TopVoters tv ON ub.Id = tv.UserId
LEFT JOIN PostLinkSummary pl ON qas.QuestionId = pl.PostId AND pl.LinkType = 'Duplicate'
LEFT JOIN CorrelatedComments rc ON qas.QuestionId = rc.PostId
LEFT JOIN RankedPosts rp ON qas.QuestionId = rp.Id
WHERE qas.AnswerCount > 0
  AND (qci.CloseDate IS NULL OR qci.CloseDate > qas.QuestionCreation)
GROUP BY
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qci.CloseReason,
    qci.CloseDate,
    ub.DisplayName,
    ub.Reputation,
    ubr.GoldBadges,
    ubr.SilverBadges,
    ubr.BronzeBadges,
    tv.VoteCount,
    tv.UpVotes,
    tv.DownVotes,
    pl.LinkType,
    pl.LinkCount,
    rc.CommentCount,
    rc.LastCommentDate,
    rc.Commenters,
    rp.ScoreRank,
    qas.Tags,
    qas.AcceptedAnswerId
ORDER BY qas.QuestionScore DESC, qas.ViewCount DESC
LIMIT 50;