WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS rn_score,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS dr_viewcount,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        p.Tags,
        p.PostTypeId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.CreationDate > DATE '2023-01-01'
),
UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
FrequentTags AS (
    SELECT
        tag AS TagName,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            p.Id,
            TRIM(t) AS tag
        FROM Posts p,
        LATERAL (
            SELECT regexp_split_to_table(
                CASE
                    WHEN p.Tags LIKE '<%>' THEN ''
                    ELSE SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2))
                END,
                '><'
            ) AS t
        ) s
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) sub
    GROUP BY tag
    HAVING COUNT(*) > 100
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LatestEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 14, 19) THEN 1 ELSE 0 END) AS ModerationActions
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.CreationDate > DATE '2023-01-01' AND p.PostTypeId = 1
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.Score,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.PostCreationDate,
    rp.rn_score,
    rp.dr_viewcount,
    rp.PreviousPostScore,
    COALESCE(ups.DisplayName, 'Unknown User') AS OwnerDisplayName,
    ups.QuestionCount,
    ups.AnswerCount AS UserAnswerCount,
    ups.AveragePostScore,
    ups.TotalViewCount,
    ups.LastPostDate,
    CASE
        WHEN ups.TotalViewCount > 1000000 THEN 'High Traffic User'
        WHEN ups.AveragePostScore > 50 THEN 'High Quality User'
        ELSE 'Standard User'
    END AS UserQualityTier,
    phd.DistinctEditors,
    phd.LatestEditDate,
    phd.EditCount,
    phd.ModerationActions,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score < 0) AS NegativeScoreComments,
    (
        SELECT
            CASE
                WHEN COUNT(*) > 0 THEN 'Has Duplicate Link'
                ELSE 'No Duplicate Link'
            END
        FROM PostLinks pl
        WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3
    ) AS DuplicateStatus,
    COALESCE(f.TagCount, 0) AS FrequentTagCount,
    rp.Tags
FROM RankedPosts rp
LEFT JOIN UserPostSummary ups ON rp.OwnerUserId = ups.UserId
LEFT JOIN PostHistoryDetails phd ON rp.PostId = phd.PostId
LEFT JOIN FrequentTags f ON (rp.Title LIKE '%' || f.TagName || '%' OR rp.Tags LIKE '%' || f.TagName || '%')
WHERE rp.rn_score <= 100 AND rp.ViewCount > 1000
GROUP BY
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.Score,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.PostCreationDate,
    rp.rn_score,
    rp.dr_viewcount,
    rp.PreviousPostScore,
    rp.Tags,
    ups.DisplayName,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AveragePostScore,
    ups.TotalViewCount,
    ups.LastPostDate,
    phd.DistinctEditors,
    phd.LatestEditDate,
    phd.EditCount,
    phd.ModerationActions,
    f.TagCount
ORDER BY rp.dr_viewcount, rp.Score DESC, ups.TotalViewCount DESC
LIMIT 500;