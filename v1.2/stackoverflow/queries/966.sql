WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation,
        u.Location,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAvgScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
),
AcceptedAnswerScores AS (
    SELECT
        rp.Id AS QuestionId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore
    FROM RankedPosts rp
    LEFT JOIN Posts a ON rp.AcceptedAnswerId = a.Id
    WHERE rp.PostTypeId = 1
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateLinks,
        COUNT(CASE WHEN lt.Name = 'Linked' THEN 1 END) AS LinkedPosts
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
CorrelatedCommentsCount AS (
    SELECT
        p.Id AS PostId,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id AND c.Score > 0
        ) AS PositiveCommentCount,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id AND c.Text IS NULL
        ) AS NullTextComments
    FROM Posts p
    WHERE p.PostTypeId = 1
),
FilteredPosts AS (
    SELECT
        rp.Id,
        rp.PostTypeId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.AcceptedAnswerId,
        rp.Title,
        rp.Tags,
        rp.OwnerDisplayName,
        rp.Reputation,
        rp.Location,
        rp.ScoreRank,
        rp.UserPostCount,
        rp.UserAvgScore,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.UniqueBadges, 0) AS UniqueBadges,
        COALESCE(pls.DuplicateLinks, 0) AS DuplicateLinks,
        COALESCE(pls.LinkedPosts, 0) AS LinkedPosts,
        COALESCE(ccc.PositiveCommentCount, 0) AS PositiveCommentCount,
        COALESCE(ccc.NullTextComments, 0) AS NullTextComments,
        COALESCE(aas.AcceptedAnswerScore, 0) AS AcceptedAnswerScore
    FROM RankedPosts rp
    LEFT JOIN UserBadgeStats ubs ON rp.OwnerUserId = ubs.UserId
    LEFT JOIN PostLinkSummary pls ON rp.Id = pls.PostId
    LEFT JOIN CorrelatedCommentsCount ccc ON rp.Id = ccc.PostId
    LEFT JOIN AcceptedAnswerScores aas ON rp.Id = aas.QuestionId
    WHERE rp.ScoreRank <= 50 AND rp.UserPostCount > 5
),
FinalAggregates AS (
    SELECT
        OwnerUserId,
        OwnerDisplayName,
        COUNT(*) AS TotalPosts,
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViews,
        MAX(Score) AS MaxScore,
        SUM(GoldBadges) AS TotalGoldBadges,
        SUM(SilverBadges) AS TotalSilverBadges,
        SUM(BronzeBadges) AS TotalBronzeBadges,
        SUM(DuplicateLinks) AS TotalDuplicateLinks,
        SUM(LinkedPosts) AS TotalLinkedPosts,
        SUM(PositiveCommentCount) AS TotalPositiveComments,
        SUM(NullTextComments) AS TotalNullTextComments,
        AVG(AcceptedAnswerScore) AS AvgAcceptedAnswerScore,
        STRING_AGG(DISTINCT COALESCE(NULLIF(Title, ''), '[No Title]'), ' || ') AS RecentTitles,
        MAX(CASE WHEN Location IS NOT NULL AND LENGTH(TRIM(Location)) > 0 THEN 1 ELSE 0 END) = 1 AS HasLocationInfo,
        MIN(CreationDate) AS MinCreationDate,
        MAX(CreationDate) AS MaxCreationDate
    FROM FilteredPosts
    GROUP BY OwnerUserId, OwnerDisplayName
),
UserReputationWindow AS (
    SELECT
        fa.OwnerUserId,
        fa.OwnerDisplayName,
        fa.TotalPosts,
        fa.AvgScore,
        fa.AvgViews,
        fa.MaxScore,
        fa.TotalGoldBadges,
        fa.TotalSilverBadges,
        fa.TotalBronzeBadges,
        fa.TotalDuplicateLinks,
        fa.TotalLinkedPosts,
        fa.TotalPositiveComments,
        fa.TotalNullTextComments,
        fa.AvgAcceptedAnswerScore,
        fa.RecentTitles,
        fa.HasLocationInfo,
        fa.MinCreationDate,
        fa.MaxCreationDate,
        NTILE(10) OVER (ORDER BY fa.AvgScore DESC) AS ScoreDecile,
        NTILE(10) OVER (ORDER BY fa.TotalPosts DESC) AS PostsDecile,
        NTILE(5) OVER (ORDER BY fa.TotalGoldBadges DESC) AS GoldBadgeQuintile
    FROM FinalAggregates fa
)
SELECT
    urw.OwnerUserId,
    urw.OwnerDisplayName,
    urw.TotalPosts,
    urw.AvgScore,
    urw.AvgViews,
    urw.MaxScore,
    urw.TotalGoldBadges,
    urw.TotalSilverBadges,
    urw.TotalBronzeBadges,
    urw.TotalDuplicateLinks,
    urw.TotalLinkedPosts,
    urw.TotalPositiveComments,
    urw.TotalNullTextComments,
    urw.AvgAcceptedAnswerScore,
    SUBSTRING(urw.RecentTitles FROM 1 FOR 1000) AS RecentTitlesSnippet,
    urw.HasLocationInfo,
    urw.ScoreDecile,
    urw.PostsDecile,
    urw.GoldBadgeQuintile,
    CASE
        WHEN urw.TotalPosts > 100 THEN 'High Activity'
        WHEN urw.TotalPosts BETWEEN 50 AND 100 THEN 'Medium Activity'
        ELSE 'Low Activity'
    END AS ActivityLevel,
    CASE
        WHEN urw.AvgScore >= 10 THEN urw.AvgScore * 1.2
        WHEN urw.AvgScore >= 5 AND urw.AvgScore < 10 THEN urw.AvgScore * 1.1
        ELSE urw.AvgScore
    END AS AdjustedAvgScore,
    CONCAT(
        'User ', COALESCE(urw.OwnerDisplayName, '[No Name]'),
        ' with reputation ', COALESCE(CAST(u.Reputation AS varchar), '0'),
        ' has ', CAST(urw.TotalPosts AS varchar), ' posts and earned ',
        CAST(urw.TotalGoldBadges AS varchar), '/', CAST(urw.TotalSilverBadges AS varchar), '/', CAST(urw.TotalBronzeBadges AS varchar),
        ' badges respectively.'
    ) AS SummaryDescription
FROM UserReputationWindow urw
LEFT JOIN Users u ON urw.OwnerUserId = u.Id
WHERE urw.GoldBadgeQuintile >= 3
ORDER BY AdjustedAvgScore DESC, urw.TotalPosts DESC
LIMIT 100;