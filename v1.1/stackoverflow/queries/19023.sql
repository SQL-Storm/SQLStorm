WITH RecentPostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months') AS RecentCommentCount,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months') AS RecentUpVoteCount,
        COALESCE(p.LastActivityDate, p.CreationDate) AS EffectiveLastActivityDate
    FROM
        Posts p
    WHERE
        p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
        AND p.PostTypeId IN (1, 2)
),
UserOverallStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.Location,
        u.AboutMe,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6) AND ph.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months') AS RecentEditsCount,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 5) AS TotalFavoritesGiven,
        (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months') AS RecentCommentsMade
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.Location, u.AboutMe
),
TrendingTags AS (
    SELECT
        tag_name_clean AS TagName,
        COUNT(DISTINCT rpa.PostId) AS PostCountInPeriod,
        SUM(rpa.Score) AS TotalTagScore,
        SUM(rpa.ViewCount) AS TotalTagViews,
        RANK() OVER (ORDER BY COUNT(DISTINCT rpa.PostId) DESC, SUM(rpa.Score) DESC) AS TagRank
    FROM
        RecentPostActivity rpa,
        LATERAL unnest(string_to_array(substring(rpa.Tags, 2, length(rpa.Tags)-2), '><')) AS tag_name_clean
    WHERE
        rpa.Tags IS NOT NULL
        AND rpa.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '3 months'
    GROUP BY
        tag_name_clean
    HAVING
        COUNT(DISTINCT rpa.PostId) > 10
),
EliteUserPosts AS (
    SELECT
        uos.UserId,
        uos.DisplayName,
        uos.Reputation,
        rpa.PostId,
        rpa.Title AS PostTitle,
        rpa.Score AS PostScore,
        rpa.ViewCount AS PostViewCount,
        rpa.CreationDate AS PostCreationDate,
        rpa.PostTypeId,
        rpa.Tags,
        rpa.RecentUpVoteCount,
        rpa.RecentCommentCount,
        CASE
            WHEN rpa.PostTypeId = 1 THEN 'Question'
            WHEN rpa.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName,
        rpa.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY uos.UserId ORDER BY rpa.Score DESC, rpa.ViewCount DESC) AS Rn
    FROM
        UserOverallStats uos
    INNER JOIN
        RecentPostActivity rpa ON uos.UserId = rpa.OwnerUserId
    WHERE
        uos.Reputation >= 5000
        AND uos.GoldBadges >= 1
        AND uos.LastAccessDate >= CAST('2024-10-01' AS DATE) - INTERVAL '3 months'
        AND EXISTS (
            SELECT 1
            FROM Badges b
            JOIN TrendingTags tt ON b.Name = tt.TagName
            WHERE b.UserId = uos.UserId AND b.Class = 1 AND tt.TagRank <= 5
        )
),
RisingStarPosts AS (
    SELECT
        uos.UserId,
        uos.DisplayName,
        uos.Reputation,
        rpa.PostId,
        rpa.Title AS PostTitle,
        rpa.Score AS PostScore,
        rpa.ViewCount AS PostViewCount,
        rpa.CreationDate AS PostCreationDate,
        rpa.PostTypeId,
        rpa.Tags,
        rpa.RecentUpVoteCount,
        rpa.RecentCommentCount,
        CASE
            WHEN rpa.PostTypeId = 1 THEN 'Question'
            WHEN rpa.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeName,
        LAG(rpa.CreationDate, 1, rpa.CreationDate) OVER (PARTITION BY uos.UserId ORDER BY rpa.CreationDate) AS PrevPostCreationDate,
        RANK() OVER (PARTITION BY uos.UserId ORDER BY rpa.RecentUpVoteCount DESC, rpa.Score DESC) AS Rn
    FROM
        UserOverallStats uos
    INNER JOIN
        RecentPostActivity rpa ON uos.UserId = rpa.OwnerUserId
    WHERE
        uos.Reputation < 5000
        AND uos.Reputation >= 500
        AND uos.UserCreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '2 year'
        AND uos.LastAccessDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 month'
        AND uos.RecentEditsCount >= 5
        AND rpa.Score > 10
        AND rpa.RecentUpVoteCount > 3
        AND EXISTS (
            SELECT 1
            FROM Badges b
            JOIN TrendingTags tt ON b.Name = tt.TagName
            WHERE b.UserId = uos.UserId AND b.Class IN (1, 2) AND tt.TagRank <= 10
        )
)
SELECT
    'Elite Contributor' AS UserCategory,
    eup.UserId,
    eup.DisplayName,
    eup.Reputation,
    uos.UserCreationDate,
    uos.LastAccessDate,
    uos.Location,
    eup.PostTitle,
    eup.PostTypeName,
    eup.PostScore,
    eup.PostViewCount,
    eup.Tags,
    uos.GoldBadges,
    uos.SilverBadges,
    uos.BronzeBadges,
    uos.RecentEditsCount,
    eup.RecentUpVoteCount,
    eup.RecentCommentCount,
    (SELECT tt.TagName FROM TrendingTags tt WHERE tt.TagRank = 1 FETCH FIRST 1 ROW ONLY) AS OverallTopTrendingTag,
    COALESCE(phs.CloseReasonName, 'N/A') AS PostCloseReason,
    CASE
        WHEN eup.PostTypeId = 1 AND eup.AcceptedAnswerId IS NOT NULL THEN
            (SELECT COUNT(ans.Id) FROM Posts ans WHERE ans.ParentId = eup.PostId AND ans.OwnerUserId <> eup.UserId AND ans.Score >= 5)
        ELSE NULL
    END AS HighQualityAnswerCountByOthers,
    AVG(eup.PostScore) OVER (PARTITION BY eup.UserId) AS AvgPostScoreByUser,
    RANK() OVER (ORDER BY eup.Reputation DESC, eup.PostScore DESC) AS OverallUserRank
FROM
    EliteUserPosts eup
JOIN
    UserOverallStats uos ON eup.UserId = uos.UserId
LEFT JOIN LATERAL (
    SELECT crt.Name AS CloseReasonName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostId = eup.PostId
    AND ph.PostHistoryTypeId = 10
    ORDER BY ph.CreationDate DESC
    LIMIT 1
) phs ON TRUE
WHERE
    eup.Rn = 1
    AND (eup.Tags ILIKE '%<sql>%' OR eup.Tags ILIKE '%<database>%')
    AND eup.PostScore > (SELECT AVG(rpa2.Score) FROM RecentPostActivity rpa2 WHERE rpa2.PostTypeId = eup.PostTypeId)
    AND eup.PostTitle IS NOT NULL
    AND LENGTH(eup.PostTitle) > 10
    AND uos.AboutMe IS NOT NULL
    AND uos.AboutMe ILIKE '%engineer%'
    AND COALESCE(eup.PostViewCount, 0) > 1000
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId = eup.PostId AND pl.LinkTypeId = 3
    )
UNION ALL
SELECT
    'Rising Star' AS UserCategory,
    rsp.UserId,
    rsp.DisplayName,
    rsp.Reputation,
    uos.UserCreationDate,
    uos.LastAccessDate,
    uos.Location,
    rsp.PostTitle,
    rsp.PostTypeName,
    rsp.PostScore,
    rsp.PostViewCount,
    rsp.Tags,
    uos.GoldBadges,
    uos.SilverBadges,
    uos.BronzeBadges,
    uos.RecentEditsCount,
    rsp.RecentUpVoteCount,
    rsp.RecentCommentCount,
    (SELECT tt.TagName FROM TrendingTags tt WHERE tt.TagRank = 1 FETCH FIRST 1 ROW ONLY) AS OverallTopTrendingTag,
    COALESCE(phs.CloseReasonName, 'N/A') AS PostCloseReason,
    NULL AS HighQualityAnswerCountByOthers,
    AVG(rsp.PostScore) OVER (PARTITION BY rsp.UserId) AS AvgPostScoreByUser,
    RANK() OVER (ORDER BY rsp.RecentUpVoteCount DESC, rsp.Reputation DESC) AS OverallUserRank
FROM
    RisingStarPosts rsp
JOIN
    UserOverallStats uos ON rsp.UserId = uos.UserId
LEFT JOIN LATERAL (
    SELECT crt.Name AS CloseReasonName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostId = rsp.PostId
    AND ph.PostHistoryTypeId = 10
    ORDER BY ph.CreationDate DESC
    LIMIT 1
) phs ON TRUE
WHERE
    rsp.Rn = 1
    AND (rsp.PostScore >= 20 OR rsp.RecentUpVoteCount >= 5)
    AND rsp.PostTitle IS NOT NULL
    AND rsp.PostTypeId = 2
    AND uos.LastBadgeDate IS NOT NULL
    AND rsp.PostCreationDate - rsp.PrevPostCreationDate < INTERVAL '1 week'
    AND EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.PostId = rsp.PostId
        AND c.UserId = rsp.UserId
        AND c.Text ILIKE '%thank%'
    )
ORDER BY
    OverallUserRank ASC, UserCategory DESC;