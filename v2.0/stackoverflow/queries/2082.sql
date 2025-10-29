WITH RecursiveBadgeAgg AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS rn,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS TagBasedBadges,
        SUM(CASE WHEN b.TagBased = FALSE THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS NamedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, b.Class, b.Date, b.TagBased, b.Id
), FilteredBadges AS (
    SELECT UserId, DisplayName, Class, BadgeCount, TagBasedBadges, NamedBadges
    FROM RecursiveBadgeAgg
    WHERE rn = 1
), PostScoreRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsOfType,
        LEAD(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS NextScore,
        CASE 
            WHEN p.ViewCount = 0 THEN NULL
            ELSE ROUND(1.0 * p.Score / p.ViewCount, 4)
        END AS ScoreViewRatio
    FROM Posts p
    WHERE p.Score IS NOT NULL
), OuterJoinedComments AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN c.Score >= 5 THEN 1 END) AS HighScoreComments,
        COUNT(c.Id) AS TotalComments,
        STRING_AGG(DISTINCT c.UserDisplayName, ', ') FILTER (WHERE c.UserDisplayName IS NOT NULL) AS Commenters,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
), CorrelatedPostLinksCount AS (
    SELECT
        p.Id AS PostId,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
        ) AS OutgoingLinks,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1
        ) AS IncomingLinks
    FROM Posts p
), ComplexPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        psr.Score,
        psr.ViewCount,
        psr.ScoreRank,
        psr.TotalPostsOfType,
        psr.NextScore,
        psr.ScoreViewRatio,
        oc.HighScoreComments,
        oc.TotalComments,
        oc.Commenters,
        oc.LatestCommentDate,
        cpl.OutgoingLinks,
        cpl.IncomingLinks,
        fb.BadgeCount,
        fb.TagBasedBadges,
        fb.NamedBadges,
        u.Reputation,
        u.CreationDate AS UserCreation,
        p.LastActivityDate,
        CASE 
            WHEN (fb.BadgeCount IS NULL OR fb.BadgeCount < 3) AND (psr.ScoreViewRatio IS NOT NULL AND psr.ScoreViewRatio > 0.05) 
                THEN 'Emerging'
            WHEN psr.ScoreRank <= 10 AND (fb.BadgeCount IS NOT NULL AND fb.BadgeCount >= 10)
                THEN 'TopChampion'
            WHEN p.Tags IS NULL OR p.Tags = ''
                THEN 'Untagged'
            ELSE 'Regular'
        END AS PostCategory,
        COALESCE(
            NULLIF(LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1, 0),
            0
        ) AS TagCount
    FROM Posts p
    LEFT JOIN PostScoreRanks psr ON psr.Id = p.Id
    LEFT JOIN OuterJoinedComments oc ON oc.PostId = p.Id
    LEFT JOIN CorrelatedPostLinksCount cpl ON cpl.PostId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN FilteredBadges fb ON fb.UserId = u.Id
    WHERE p.PostTypeId = 1
), FinalFiltered AS (
    SELECT *
    FROM ComplexPosts
    WHERE PostCategory IN ('Emerging', 'TopChampion')
      AND (HighScoreComments >= 5 OR BadgeCount >= 5)
), UnionedResults AS (
    SELECT 
        Id AS PostId,
        Title,
        PostCategory,
        Score,
        ViewCount,
        BadgeCount,
        HighScoreComments,
        Commenters,
        Reputation,
        TagCount
    FROM FinalFiltered
    UNION
    SELECT
        p.Id,
        p.Title,
        'Unanswered' AS PostCategory,
        p.Score,
        p.ViewCount,
        0 AS BadgeCount,
        0 AS HighScoreComments,
        NULL AS Commenters,
        0 AS Reputation,
        0 AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND NOT EXISTS (
          SELECT 1 
          FROM Posts a 
          WHERE a.ParentId = p.Id
      )
      AND p.Score < 0
), NumberedResults AS (
    SELECT
        ur.*,
        ROW_NUMBER() OVER (PARTITION BY ur.PostCategory ORDER BY ur.Score DESC, ur.ViewCount DESC) AS CategoryRank
    FROM UnionedResults ur
)
SELECT 
    nr.PostId,
    nr.Title,
    nr.PostCategory,
    nr.Score,
    nr.ViewCount,
    nr.BadgeCount,
    nr.HighScoreComments,
    nr.Commenters,
    nr.Reputation,
    nr.TagCount,
    AVG(nr.Score) OVER (PARTITION BY nr.PostCategory ORDER BY nr.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgScore,
    COALESCE(NULLIF(nr.Commenters, ''), 'No commenters') AS SafeCommentersList
FROM NumberedResults nr
WHERE nr.CategoryRank <= 20
ORDER BY nr.PostCategory, nr.CategoryRank;