WITH UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE 0 END) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        MAX(ph.CreationDate) AS LastHistoryDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        FIRST_VALUE(crt.Name) OVER (
            PARTITION BY ph.PostId
            ORDER BY CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE CAST('1900-01-01' AS timestamp) END DESC, ph.Id DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS MostRecentCloseReason
    FROM
        PostHistory ph
    LEFT JOIN
        CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = CAST(crt.Id AS text)
    GROUP BY
        ph.PostId, ph.Id, crt.Name, ph.PostHistoryTypeId, ph.CreationDate, ph.Comment
),
TagAnalysis AS (
    SELECT
        p.Id AS PostId,
        LOWER(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        p.Score,
        p.ViewCount,
        p.CreationDate
    FROM
        Posts p
    WHERE
        p.Tags IS NOT NULL AND p.Tags != ''
),
TopTags AS (
    SELECT
        ta.TagName,
        SUM(ta.Score) AS TotalTagScore,
        SUM(ta.ViewCount) AS TotalTagViewCount,
        COUNT(DISTINCT ta.PostId) AS PostCount,
        DENSE_RANK() OVER (ORDER BY SUM(ta.Score) DESC, SUM(ta.ViewCount) DESC) AS TagRank
    FROM
        TagAnalysis ta
    GROUP BY
        ta.TagName
    HAVING
        COUNT(DISTINCT ta.PostId) > 50
),
PostCommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(CASE WHEN c.Text ILIKE '%thanks%' THEN 1 ELSE 0 END) AS HasThanksComment,
        SUM(CASE WHEN c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' THEN 1 ELSE 0 END) AS ProblematicCommentsCount
    FROM
        Comments c
    GROUP BY
        c.PostId
)
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ups.DisplayName AS OwnerDisplayName,
    ups.Reputation AS OwnerReputation,
    COALESCE(ups.GoldBadges, 0) AS OwnerGoldBadges,
    phd.EditCount AS PostEditCount,
    phd.LastClosedDate,
    phd.MostRecentCloseReason,
    pcs.TotalComments,
    pcs.AvgCommentScore,
    pcs.HasThanksComment,
    tt.TotalTagScore AS PrimaryTagTotalScore,
    tt.TagRank AS PrimaryTagOverallRank,
    COALESCE(p.CommunityOwnedDate, p.ClosedDate, CAST('1900-01-01' AS timestamp)) AS LastStatusChangeDate,
    NULLIF(p.LastEditorDisplayName, '') AS EffectiveLastEditorDisplayName,
    EXTRACT(DAY FROM (COALESCE(p.LastActivityDate, CAST('2024-10-01 12:34:56' AS timestamp)) - p.CreationDate)) AS PostAgeInDays,
    LENGTH(COALESCE(p.Body, '')) AS BodyLength,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.CommunityOwnedDate IS NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
        WHEN p.AnswerCount > 0 THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankWithinOwnerPosts,
    AVG(p.Score) OVER (
        PARTITION BY LOWER(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1))
    ) AS AvgScoreForPrimaryTag,
    EXISTS (
        SELECT 1
        FROM Badges b_sub
        WHERE b_sub.UserId = p.OwnerUserId
          AND b_sub.Name = 'Stellar Question'
          AND b_sub.Date BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '1 year'
    ) AS HasStellarBadgeEarly,
    (
        SELECT MAX(dp.Score)
        FROM PostLinks pl
        JOIN Posts dp ON pl.RelatedPostId = dp.Id
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS MaxDuplicatePostScore,
    ans.Score AS AcceptedAnswerScore,
    ans_owner.DisplayName AS AcceptedAnswerOwner,
    (
        p.ViewCount > 5000 AND p.FavoriteCount > 50
        AND (p.Score > 100 OR COALESCE(pcs.ProblematicCommentsCount, 0) > 5)
        AND p.CreationDate >= CAST('2020-01-01' AS timestamp)
        AND p.Title ILIKE '%sql%'
        AND NOT EXISTS (SELECT 1 FROM PostHistory ph_sub WHERE ph_sub.PostId = p.Id AND ph_sub.PostHistoryTypeId = 12)
        AND (phd.LastClosedDate IS NULL OR p.LastActivityDate > phd.LastClosedDate + INTERVAL '30 days')
    ) AS IsHighEngagementComplex,
    COALESCE(
        LOWER(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1)),
        'no-tag'
    ) AS PrimaryTag
FROM
    Posts p
INNER JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    UserPostSummary ups ON p.OwnerUserId = ups.UserId
LEFT JOIN
    PostHistoryDetails phd ON p.Id = phd.PostId
LEFT JOIN
    PostCommentSentiment pcs ON p.Id = pcs.PostId
LEFT JOIN
    TagAnalysis ta_primary ON p.Id = ta_primary.PostId AND ta_primary.TagName = COALESCE(LOWER(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1)), 'no-tag')
LEFT JOIN
    TopTags tt ON ta_primary.TagName = tt.TagName
LEFT JOIN
    Posts ans ON p.AcceptedAnswerId = ans.Id
LEFT JOIN
    Users ans_owner ON ans.OwnerUserId = ans_owner.Id
WHERE
    p.PostTypeId IN (1, 2)
    AND p.CreationDate >= CAST('2018-01-01' AS timestamp)
    AND p.Score >= 0
    AND (p.ViewCount IS NULL OR p.ViewCount > 10)
    AND (
        p.OwnerUserId IS NOT NULL
        OR p.OwnerDisplayName IS NOT NULL
    )

UNION ALL

SELECT
    p.Id AS PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u_editor.DisplayName AS OwnerDisplayName,
    u_editor.Reputation AS OwnerReputation,
    (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u_editor.Id AND b.Class = 1) AS OwnerGoldBadges,
    phd.EditCount AS PostEditCount,
    phd.LastClosedDate,
    phd.MostRecentCloseReason,
    pcs.TotalComments,
    pcs.AvgCommentScore,
    pcs.HasThanksComment,
    tt.TotalTagScore AS PrimaryTagTotalScore,
    tt.TagRank AS PrimaryTagOverallRank,
    COALESCE(p.CommunityOwnedDate, p.ClosedDate, CAST('1900-01-01' AS timestamp)) AS LastStatusChangeDate,
    NULLIF(p.LastEditorDisplayName, '') AS EffectiveLastEditorDisplayName,
    EXTRACT(DAY FROM (COALESCE(p.LastEditDate, p.LastActivityDate, CAST('2024-10-01 12:34:56' AS timestamp)) - p.CreationDate)) AS PostAgeInDays,
    LENGTH(COALESCE(p.Body, '')) AS BodyLength,
    CASE
        WHEN phd.LastReopenedDate IS NOT NULL AND p.LastActivityDate > phd.LastReopenedDate THEN 'Reopened & Active'
        WHEN p.LastEditDate IS NOT NULL AND p.LastEditorUserId IS NOT NULL THEN 'Edited by High-Rep User'
        ELSE 'Other Post Activity'
    END AS PostStatus,
    CAST(NULL AS INT) AS RankWithinOwnerPosts,
    CAST(NULL AS NUMERIC) AS AvgScoreForPrimaryTag,
    FALSE AS HasStellarBadgeEarly,
    (
        SELECT MAX(dp.Score)
        FROM PostLinks pl
        JOIN Posts dp ON pl.RelatedPostId = dp.Id
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS MaxDuplicatePostScore,
    CAST(NULL AS INT) AS AcceptedAnswerScore,
    CAST(NULL AS VARCHAR(4000)) AS AcceptedAnswerOwner,
    TRUE AS IsHighEngagementComplex,
    COALESCE(
        LOWER(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1)),
        'no-tag'
    ) AS PrimaryTag
FROM
    Posts p
INNER JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Users u_editor ON p.LastEditorUserId = u_editor.Id
LEFT JOIN
    PostHistoryDetails phd ON p.Id = phd.PostId
LEFT JOIN
    PostCommentSentiment pcs ON p.Id = pcs.PostId
LEFT JOIN
    TagAnalysis ta_primary ON p.Id = ta_primary.PostId AND ta_primary.TagName = COALESCE(LOWER(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1)), 'no-tag')
LEFT JOIN
    TopTags tt ON ta_primary.TagName = tt.TagName
WHERE
    p.LastEditorUserId IS NOT NULL
    AND p.LastEditDate IS NOT NULL
    AND p.CreationDate >= CAST('2019-01-01' AS timestamp)
    AND (
        (phd.LastReopenedDate IS NOT NULL AND p.LastActivityDate > phd.LastReopenedDate)
        OR (
            u_editor.Reputation > 50000
            AND p.LastEditDate > p.CreationDate + INTERVAL '90 days'
        )
    )
ORDER BY
    PostCreationDate DESC, PostId DESC
LIMIT 1000;