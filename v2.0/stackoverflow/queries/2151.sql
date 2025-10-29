-- {"query": "2151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1546}
WITH RecursiveTags AS (
    SELECT 
        p.Id AS PostId,
        p.Tags,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserBadgesCount AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
AnswerScores AS (
    SELECT 
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswersWithUserInfo AS (
    SELECT 
        a.QuestionId,
        a.AnswerId,
        a.AnswerScore,
        u.Id AS AnswerOwnerId,
        u.DisplayName AS AnswerOwnerName,
        u.Reputation AS AnswerOwnerReputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges
    FROM AnswerScores a
    LEFT JOIN Users u ON a.AnswerId = u.Id
    LEFT JOIN UserBadgesCount ubc ON u.Id = ubc.UserId
    WHERE a.AnswerRank <= 3
),
QuestionSummary AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.CreationDate,
        q.OwnerUserId,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS DownVotes,
        (SELECT STRING_AGG(lt.Name, ', ') 
            FROM PostLinks pl 
            JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id 
            WHERE pl.PostId = q.Id) AS LinkTypes
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
QuestionCloseHistory AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TimesClosed,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS TimesReopened,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS LastClosedDate,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 11) AS LastReopenedDate,
        STRING_AGG(DISTINCT crt.Name, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CASE WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS integer) ELSE NULL END = crt.Id AND ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
QuestionTagsRank AS (
    SELECT 
        rt.PostId,
        rt.Tag,
        t.Count AS TagUsageCount,
        RANK() OVER (PARTITION BY rt.PostId ORDER BY t.Count DESC NULLS LAST) AS TagPopularityRank
    FROM RecursiveTags rt
    LEFT JOIN Tags t ON t.TagName = rt.Tag
),
FilteredTags AS (
    SELECT PostId, Tag
    FROM QuestionTagsRank
    WHERE TagPopularityRank <= 3
),
CorrelatedVoteStats AS (
    SELECT 
        q.Id AS QuestionId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2 AND v.CreationDate >= q.CreationDate) AS UpVotesSinceCreation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3 AND v.CreationDate >= q.CreationDate) AS DownVotesSinceCreation
    FROM Posts q
    WHERE q.PostTypeId = 1
),
FinalAggregatedData AS (
    SELECT
        qs.QuestionId,
        qs.Title,
        qs.QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.CreationDate,
        qs.OwnerUserId,
        qs.OwnerName,
        qs.OwnerReputation,
        qs.CommentCount,
        qs.UpVotes,
        qs.DownVotes,
        qch.TimesClosed,
        qch.TimesReopened,
        qch.LastClosedDate,
        qch.LastReopenedDate,
        COALESCE(qch.CloseReasons, 'None') AS CloseReasons,
        fs.Tag AS TopTag,
        tas.AnswerId,
        tas.AnswerScore,
        tas.AnswerOwnerId,
        tas.AnswerOwnerName,
        tas.AnswerOwnerReputation,
        tas.GoldBadges,
        tas.SilverBadges,
        tas.BronzeBadges,
        tas.TotalBadges,
        cvs.UpVotesSinceCreation,
        cvs.DownVotesSinceCreation,
        qs.LinkTypes,
        CASE 
            WHEN (COALESCE(qs.DownVotes,0) + COALESCE(qs.UpVotes,0) + 1) > 0 THEN ROUND(CAST(COALESCE(qs.UpVotes,0) AS numeric) / (COALESCE(qs.DownVotes,0) + COALESCE(qs.UpVotes,0) + 1), 4) 
            ELSE NULL 
        END AS VoteUpRatio
    FROM QuestionSummary qs
    LEFT JOIN QuestionCloseHistory qch ON qs.QuestionId = qch.PostId
    LEFT JOIN FilteredTags fs ON fs.PostId = qs.QuestionId
    LEFT JOIN TopAnswersWithUserInfo tas ON tas.QuestionId = qs.QuestionId
    LEFT JOIN CorrelatedVoteStats cvs ON cvs.QuestionId = qs.QuestionId
)
SELECT DISTINCT ON (QuestionId, TopTag)
    QuestionId,
    Title,
    QuestionScore,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    CreationDate,
    OwnerUserId,
    OwnerName,
    OwnerReputation,
    CommentCount,
    UpVotes,
    DownVotes,
    TimesClosed,
    TimesReopened,
    LastClosedDate,
    LastReopenedDate,
    CloseReasons,
    TopTag,
    AnswerId,
    AnswerScore,
    AnswerOwnerId,
    AnswerOwnerName,
    AnswerOwnerReputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalBadges,
    UpVotesSinceCreation,
    DownVotesSinceCreation,
    LinkTypes,
    VoteUpRatio
FROM FinalAggregatedData
WHERE VoteUpRatio IS NOT NULL
ORDER BY QuestionId, TopTag, AnswerScore DESC;