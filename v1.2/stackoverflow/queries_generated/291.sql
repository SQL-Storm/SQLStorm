-- {"query": "291.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1703} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> ALL(r.TagPath::int[])
    WHERE t.IsModeratorOnly = 0
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.Tags,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(COALESCE(vt.UpVotes,0)) AS TotalAnswerUpVotes
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN (
        SELECT 
            v.PostId,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes
        FROM Votes v
        GROUP BY v.PostId
    ) vt ON vt.PostId = a.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
TopCommentersPerQuestion AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.UserId,
        u.DisplayName,
        COUNT(c.Id) OVER (PARTITION BY c.PostId, c.UserId) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY COUNT(c.Id) OVER (PARTITION BY c.PostId, c.UserId) DESC, c.UserId) AS rn
    FROM Comments c
    JOIN Users u ON u.Id = c.UserId
    WHERE c.UserId IS NOT NULL
),
PostHistoryCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10
),
QuestionWithCloseInfo AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        phcr.CloseReason,
        phcr.CloseDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY phcr.CloseDate DESC NULLS LAST) AS CloseRank
    FROM Posts p
    LEFT JOIN PostHistoryCloseReasons phcr ON phcr.PostId = p.Id
    WHERE p.PostTypeId = 1
),
RankedQuestions AS (
    SELECT
        q.*,
        uas.GoldBadges,
        uas.SilverBadges,
        uas.BronzeBadges,
        uas.TagBasedBadges,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.TotalAnswerUpVotes,
        tcu.UserId AS TopCommenterUserId,
        tcu.DisplayName AS TopCommenterName,
        tcu.CommentCount AS TopCommenterComments
    FROM QuestionWithCloseInfo q
    LEFT JOIN UserBadgeStats uas ON uas.UserId = q.Id
    LEFT JOIN PostAnswerStats pas ON pas.QuestionId = q.Id
    LEFT JOIN TopCommentersPerQuestion tcu ON tcu.PostId = q.Id AND tcu.rn = 1
    WHERE q.CloseRank = 1 OR q.CloseRank IS NULL
),
FilteredQuestions AS (
    SELECT *
    FROM RankedQuestions
    WHERE 
        (AnswerCount > 5 OR Score > 10)
        AND (CloseReason IS NULL OR CloseReason NOT IN ('Duplicate', 'Off-topic'))
        AND (Tags IS NOT NULL AND Tags <> '')
),
ExplodedTags AS (
    SELECT
        fq.Id AS QuestionId,
        unnest(string_to_array(substring(fq.Tags from 2 for length(fq.Tags) - 2), '><')) AS Tag
    FROM FilteredQuestions fq
),
TagAggregates AS (
    SELECT
        et.Tag,
        COUNT(DISTINCT et.QuestionId) AS QuestionCount,
        AVG(fq.Score) AS AvgQuestionScore,
        MAX(fq.ViewCount) AS MaxViewCount
    FROM ExplodedTags et
    JOIN FilteredQuestions fq ON fq.Id = et.QuestionId
    GROUP BY et.Tag
),
FinalResult AS (
    SELECT
        fq.Id AS QuestionId,
        fq.Title,
        fq.CreationDate,
        fq.Score,
        fq.ViewCount,
        fq.CloseReason,
        fq.GoldBadges,
        fq.SilverBadges,
        fq.BronzeBadges,
        fq.TagBasedBadges,
        fq.AnswerCount,
        fq.AvgAnswerScore,
        fq.MaxAnswerScore,
        fq.TotalAnswerUpVotes,
        fq.TopCommenterUserId,
        fq.TopCommenterName,
        fq.TopCommenterComments,
        STRING_AGG(DISTINCT ta.Tag || ' (QCount: ' || ta.QuestionCount || ', AvgScore: ' || ROUND(ta.AvgQuestionScore::numeric,2) || ')', ', ') AS TagSummary,
        ROW_NUMBER() OVER (PARTITION BY fq.TopCommenterUserId ORDER BY fq.Score DESC NULLS LAST) AS RankByTopCommenter
    FROM FilteredQuestions fq
    LEFT JOIN ExplodedTags et ON et.QuestionId = fq.Id
    LEFT JOIN TagAggregates ta ON ta.Tag = et.Tag
    GROUP BY
        fq.Id, fq.Title, fq.CreationDate, fq.Score, fq.ViewCount, fq.CloseReason,
        fq.GoldBadges, fq.SilverBadges, fq.BronzeBadges, fq.TagBasedBadges,
        fq.AnswerCount, fq.AvgAnswerScore, fq.MaxAnswerScore, fq.TotalAnswerUpVotes,
        fq.TopCommenterUserId, fq.TopCommenterName, fq.TopCommenterComments
)
SELECT
    fr.QuestionId,
    fr.Title,
    fr.CreationDate,
    fr.Score,
    fr.ViewCount,
    COALESCE(fr.CloseReason, 'Open') AS CloseStatus,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.TagBasedBadges,
    fr.AnswerCount,
    ROUND(fr.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    fr.MaxAnswerScore,
    fr.TotalAnswerUpVotes,
    fr.TopCommenterUserId,
    fr.TopCommenterName,
    fr.TopCommenterComments,
    fr.TagSummary,
    fr.RankByTopCommenter,
    CASE 
        WHEN fr.Score > 50 AND fr.AnswerCount > 10 THEN 'Hot Question'
        WHEN fr.Score BETWEEN 20 AND 50 THEN 'Popular Question'
        ELSE 'Normal Question'
    END AS PopularityCategory
FROM FinalResult fr
WHERE fr.RankByTopCommenter <= 5
ORDER BY fr.Score DESC NULLS LAST, fr.ViewCount DESC NULLS LAST, fr.CreationDate DESC
LIMIT 100;
