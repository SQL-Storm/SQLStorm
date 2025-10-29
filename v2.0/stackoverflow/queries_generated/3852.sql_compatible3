WITH TagPosts AS (
    SELECT
        p.Id,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        regexp_split_to_array(trim(both '<>' FROM p.Tags), '><') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
ExplodedTags AS (
    SELECT
        pt.Id,
        UNNEST(pt.TagArray) AS TagName,
        pt.OwnerUserId,
        pt.CreationDate,
        pt.Score,
        pt.ViewCount
    FROM TagPosts pt
),
UserStats AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END), 0) AS TotalScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
TagUserAgg AS (
    SELECT
        et.TagName,
        us.UserId,
        us.TotalScore,
        ROW_NUMBER() OVER (PARTITION BY et.TagName ORDER BY us.TotalScore DESC NULLS LAST) AS rn,
        COUNT(*) OVER (PARTITION BY et.TagName) AS tag_user_cnt
    FROM ExplodedTags et
    JOIN UserStats us ON us.UserId = et.OwnerUserId
),
TopTagContributors AS (
    SELECT TagName, UserId, TotalScore, rn
    FROM TagUserAgg
    WHERE rn <= 5
),
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        ph.CreationDate AS ClosedDate,
        ph.Comment AS CloseReasonId,
        COALESCE(NULLIF(ph.Comment, '' ), '0')::text AS CloseReasonText,
        CASE WHEN COALESCE(NULLIF(ph.Comment, '' ), '0') ~ '^[0-9]+$' THEN CAST(COALESCE(NULLIF(ph.Comment, '' ), '0') AS INTEGER) ELSE 0 END AS CloseReasonInt,
        ROW_NUMBER() OVER (ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
                     AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
),
DuplicatedPairs AS (
    SELECT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId,
        pl.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate) AS dup_rn
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
)
SELECT
    t.TagName,
    t.UserId,
    u.DisplayName,
    t.TotalScore,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    rc.Id AS RecentClosedQuestionId,
    rc.Title AS RecentClosedQuestionTitle,
    rc.ClosedDate,
    CASE
        WHEN rc.CloseReasonInt BETWEEN 101 AND 105 THEN cr.Name
        ELSE 'Other'
    END AS CloseReasonName,
    dp.DuplicatePostId,
    dp.OriginalPostId,
    dp.CreationDate AS DuplicateLinkDate
FROM TopTagContributors t
LEFT JOIN Users u ON u.Id = t.UserId
LEFT JOIN BadgeCounts bc ON bc.UserId = t.UserId
LEFT JOIN RecentClosedQuestions rc ON rc.rn = t.rn
LEFT JOIN CloseReasonTypes cr ON cr.Id = rc.CloseReasonInt
LEFT JOIN DuplicatedPairs dp ON dp.DuplicatePostId = rc.Id
                         AND dp.dup_rn = 1
WHERE t.TagName IS NOT NULL

UNION ALL

SELECT
    'AllTags' AS TagName,
    CAST(NULL AS INTEGER) AS UserId,
    CAST(NULL AS TEXT) AS DisplayName,
    CAST(NULL AS NUMERIC) AS TotalScore,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges,
    CAST(NULL AS INTEGER) AS RecentClosedQuestionId,
    CAST(NULL AS TEXT) AS RecentClosedQuestionTitle,
    CAST(NULL AS TIMESTAMP) AS ClosedDate,
    CAST(NULL AS TEXT) AS CloseReasonName,
    CAST(NULL AS INTEGER) AS DuplicatePostId,
    CAST(NULL AS INTEGER) AS OriginalPostId,
    CAST(NULL AS TIMESTAMP) AS DuplicateLinkDate
FROM (SELECT 1) AS dummy
ORDER BY TagName, TotalScore DESC
LIMIT 100;