WITH
RecentActivity AS (
    SELECT
        u.Id                     AS UserId,
        u.DisplayName,
        p.Id                     AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
        AND p.PostTypeId IN (1, 2)
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*)                               AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ')      AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count                                   AS TagUseCount,
        COALESCE(e.AnswerCount, 0)                AS ExcerptAnswers,
        COALESCE(w.AnswerCount, 0)                AS WikiAnswers,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts e
        ON e.Id = t.ExcerptPostId
        AND e.PostTypeId = 4
    LEFT JOIN Posts w
        ON w.Id = t.WikiPostId
        AND w.PostTypeId = 5
    WHERE t.IsModeratorOnly = FALSE
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(CASE WHEN vt.Id = 5 THEN v.UserId END) AS FavoriteByUser,
        MAX(v.CreationDate)                        AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
CloseReason AS (
    SELECT
        ph.PostId,
        (SELECT ph_inner.Comment
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = ph.PostId
           AND ph_inner.PostHistoryTypeId = 10
         ORDER BY ph_inner.CreationDate DESC
         LIMIT 1) AS CloseReasonCode
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
)
SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(uba.TotalBadges, 0)           AS TotalBadges,
    COALESCE(uba.GoldBadges, 0)            AS GoldBadges,
    COALESCE(uba.SilverBadges, 0)          AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0)          AS BronzeBadges,
    COALESCE(uba.BadgeList, '')            AS BadgeList,
    ra.PostId                              AS RecentPostId,
    ra.PostTypeId,
    ra.Title,
    CASE
        WHEN ra.Tags IS NULL THEN 'NoTags'
        ELSE REPLACE(SUBSTRING(ra.Tags FROM 2 FOR CHAR_LENGTH(ra.Tags)-2), '><', ',')
    END                                    AS TagList,
    pv.UpVotes,
    pv.DownVotes,
    CASE WHEN pv.FavoriteByUser IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsFavorited,
    cr.CloseReasonCode,
    tp.TagName,
    tp.TagUseCount,
    tp.TagRank
FROM Users u
LEFT JOIN UserBadgeAgg uba
    ON uba.UserId = u.Id
LEFT JOIN RecentActivity ra
    ON ra.UserId = u.Id AND ra.rn = 1
LEFT JOIN PostVoteSummary pv
    ON pv.PostId = ra.PostId
LEFT JOIN CloseReason cr
    ON cr.PostId = ra.PostId
LEFT JOIN LATERAL (
    SELECT
        t.TagName,
        t.TagUseCount,
        t.TagRank
    FROM TagPopularity t
    WHERE t.TagName = ANY (
        CASE
            WHEN ra.Tags IS NULL THEN (SELECT ARRAY[]::text[] FROM (SELECT 1) AS x WHERE false)
            ELSE regexp_split_to_array(
                    SUBSTRING(ra.Tags FROM 2 FOR CHAR_LENGTH(ra.Tags)-2),
                    '><'
                )
        END
    )
    ORDER BY t.TagRank
    LIMIT 1
) tp ON true
WHERE u.Reputation > 1000
  AND (uba.TotalBadges IS NULL OR uba.TotalBadges >= 5)
  AND (pv.UpVotes IS NULL OR pv.UpVotes + pv.DownVotes > 0)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    uba.TotalBadges,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    uba.BadgeList,
    ra.PostId,
    ra.PostTypeId,
    ra.Title,
    ra.Tags,
    pv.UpVotes,
    pv.DownVotes,
    pv.FavoriteByUser,
    cr.CloseReasonCode,
    tp.TagName,
    tp.TagUseCount,
    tp.TagRank
ORDER BY u.Reputation DESC, tp.TagRank NULLS LAST
LIMIT 100;