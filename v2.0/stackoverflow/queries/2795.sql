-- {"query": "2795.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1225}
WITH RECURSIVE RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        reverse(t.TagName) || '-' || CAST(length(t.TagName) AS varchar) AS TagSignature
    FROM Tags t
    WHERE t.IsRequired = true

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count + rtc.Count AS Count,
        reverse(t.TagName) || '-' || CAST(length(t.TagName) AS varchar) AS TagSignature
    FROM Tags t
    JOIN RecursiveTagCounts rtc ON length(t.TagName) > length(rtc.TagName)
    WHERE t.IsModeratorOnly = false
),
PostsWithStats AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        dense_rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        row_number() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC NULLS LAST) AS ViewRank,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.FavoriteCount > 0 THEN 'Favorite'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        count(*) AS TotalBadges,
        count(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        count(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        count(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        max(b.Date) AS LastBadgeDate,
        string_agg(DISTINCT b.Name, ',' ORDER BY b.Name) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostLatestEdit AS (
    SELECT ph.PostId, max(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
PostLinkCount AS (
    SELECT pl.PostId, count(DISTINCT pl.RelatedPostId) AS RelatedPostsCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
    WHERE ph.PostHistoryTypeId = 10
),
ComplexStats AS (
    SELECT 
        ts.Id,
        p.Title,
        p.Tags,
        COALESCE(plc.RelatedPostsCount,0) AS RelatedPostsCount,
        p.Score,
        p.ViewCount,
        u.Reputation,
        uba.TotalBadges,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        COALESCE(qli.CloseReason, 'Not Closed') AS CloseReason,
        ts.ScoreRank,
        ts.ViewRank,
        ts.PostStatus,
        p.CreationDate,
        ple.LastEditDate,
        COALESCE(ple.LastEditDate, p.CreationDate + INTERVAL '7 days') AS EffectiveEditDate,
        COALESCE(u.DisplayName, '(anonymous)') || ' - ' || ts.PostStatus AS OwnerStatus,
        rank() OVER (
          PARTITION BY p.PostTypeId 
          ORDER BY (
            length(COALESCE(p.Tags, '')) - length(replace(COALESCE(p.Tags, ''), '><', '')) + 1
          ) DESC
        ) AS TagRank,
        CASE 
            WHEN p.Tags IS NULL OR length(p.Tags) = 0 OR p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsFlagged
    FROM PostsWithStats ts
    LEFT JOIN Posts p ON p.Id = ts.Id
    LEFT JOIN Users u ON u.Id = ts.OwnerUserId
    LEFT JOIN UserBadgeAgg uba ON uba.UserId = ts.OwnerUserId
    LEFT JOIN PostLatestEdit ple ON ple.PostId = ts.Id
    LEFT JOIN PostLinkCount plc ON plc.PostId = ts.Id
    LEFT JOIN QuestionCloseInfo qli ON qli.PostId = ts.Id
    WHERE ts.PostTypeId = 1
)
SELECT
    cs.Id,
    cs.Title,
    cs.OwnerStatus,
    cs.Score,
    cs.ViewCount,
    cs.Reputation,
    cs.TotalBadges,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.RelatedPostsCount,
    cs.CloseReason,
    cs.ScoreRank,
    cs.ViewRank,
    cs.PostStatus,
    cs.CreationDate,
    cs.EffectiveEditDate,
    cs.TagRank,
    cs.IsFlagged,
    rtc.TagSignature
FROM ComplexStats cs
LEFT JOIN RecursiveTagCounts rtc
    ON rtc.TagName = regexp_replace(cs.Tags, '^.*?><([^>]+)><.*$', '\1') -- extract first tag; fallback to NULL if no match
WHERE cs.IsFlagged = 0
ORDER BY cs.ScoreRank ASC, cs.ViewRank ASC
LIMIT 100;