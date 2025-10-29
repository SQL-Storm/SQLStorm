-- {"query": "2516.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1627} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName AS OwnerName,
        u.Reputation,
        u.Location,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS RankInType,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY p.Id) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY p.Id) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserRecentPostNum
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.CreationDate > CURRENT_DATE - INTERVAL '365 days'
),
PostHistoryEdits AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEdit,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        BOOL_OR(ph.PostHistoryTypeId = 10) AS IsClosed,
        BOOL_OR(ph.PostHistoryTypeId = 11) AS IsReopened,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Comment END) AS CloseReasonId
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6,10,11)
    GROUP BY
        ph.PostId
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        ARRAY_AGG(rp.Title) FILTER (WHERE rp.Title IS NOT NULL) AS DuplicateTitles
    FROM
        PostLinks pl
        JOIN RankedPosts rp ON pl.RelatedPostId = rp.Id
    WHERE
        pl.LinkTypeId = 3 -- Duplicate
    GROUP BY
        pl.PostId
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
FilteredPosts AS (
    SELECT
        rp.*,
        COALESCE(phe.EditCount, 0) AS EditCount,
        phe.LastEdit,
        phe.IsClosed,
        phe.IsReopened,
        phe.CloseReasonId,
        dbo.DuplicateTitles,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.LastBadgeDate
    FROM
        RankedPosts rp
        LEFT JOIN PostHistoryEdits phe ON rp.Id = phe.PostId
        LEFT JOIN DuplicateLinks dbo ON rp.Id = dbo.PostId
        LEFT JOIN UserBadges ub ON rp.OwnerUserId = ub.UserId
    WHERE
        rp.RankInType <= 100
        AND (rp.Tags IS NOT NULL AND rp.Tags <> '')
),
TagExploded AS (
    SELECT
        fp.*,
        TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(fp.Tags FROM 2 FOR LENGTH(fp.Tags) - 2), '><'))) AS Tag
    FROM
        FilteredPosts fp
),
ScorePercentiles AS (
    SELECT
        fp.Id,
        fp.PostTypeId,
        fp.Score,
        PERCENT_RANK() OVER (PARTITION BY fp.PostTypeId ORDER BY fp.Score) AS ScorePercentile
    FROM
        FilteredPosts fp
),
ComplexStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedPostsCount,
        MAX(ub.GoldBadges) AS MaxGoldBadges,
        MAX(ub.SilverBadges) AS MaxSilverBadges,
        MAX(ub.BronzeBadges) AS MaxBronzeBadges
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        LEFT JOIN PostHistory ph ON ph.UserId = u.Id
        LEFT JOIN UserBadges ub ON ub.UserId = u.Id
    WHERE
        u.Reputation > 1000
        AND u.CreationDate < CURRENT_DATE - INTERVAL '180 days'
    GROUP BY
        u.Id, u.DisplayName
)
SELECT
    cs.UserId,
    cs.DisplayName,
    cs.TotalPosts,
    cs.QuestionCount,
    cs.AnswerCount,
    ROUND(cs.AvgQuestionScore, 2) AS AvgQuestionScore,
    ROUND(cs.AvgAnswerScore, 2) AS AvgAnswerScore,
    cs.MaxQuestionViews,
    cs.TotalComments,
    cs.ClosedPostsCount,
    cs.MaxGoldBadges,
    cs.MaxSilverBadges,
    cs.MaxBronzeBadges,
    COUNT(DISTINCT te.Tag) FILTER (WHERE te.PostTypeId = 1) AS UniqueQuestionTags,
    STRING_AGG(DISTINCT te.Tag, ', ') FILTER (WHERE te.PostTypeId = 1) AS QuestionTags,
    STRING_AGG(DISTINCT te.Tag, ', ') FILTER (WHERE te.PostTypeId = 2) AS AnswerTags,
    MAX(fp.ScorePercentile) FILTER (WHERE fp.PostTypeId = 1) AS MaxQuestionScorePercentile,
    MAX(fp.ScorePercentile) FILTER (WHERE fp.PostTypeId = 2) AS MaxAnswerScorePercentile,
    MAX(fp.ScorePercentile) - MIN(fp.ScorePercentile) AS ScorePercentileRange
FROM
    ComplexStats cs
    LEFT JOIN FilteredPosts fp ON cs.UserId = fp.OwnerUserId
    LEFT JOIN TagExploded te ON te.Id = fp.Id
WHERE
    cs.TotalPosts > 10
GROUP BY
    cs.UserId, cs.DisplayName, cs.TotalPosts, cs.QuestionCount, cs.AnswerCount,
    cs.AvgQuestionScore, cs.AvgAnswerScore, cs.MaxQuestionViews, cs.TotalComments,
    cs.ClosedPostsCount, cs.MaxGoldBadges, cs.MaxSilverBadges, cs.MaxBronzeBadges
HAVING
    MAX(fp.ScorePercentile) > 0.8
ORDER BY
    cs.TotalPosts DESC,
    cs.MaxGoldBadges DESC NULLS LAST,
    cs.AvgAnswerScore DESC NULLS LAST
LIMIT 50;
