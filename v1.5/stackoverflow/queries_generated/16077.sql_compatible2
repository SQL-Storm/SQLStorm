WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
        AND u.CreationDate >= TIMESTAMP '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeDistribution AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, '|' ORDER BY b.Name) FILTER (WHERE b.Class = 1) AS GoldBadgeNames,
        MAX(b.Date) AS MostRecentBadgeDate
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2015-01-01'
    GROUP BY b.UserId
),
PostQualityMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS (
                SELECT 1 FROM Posts parent 
                WHERE parent.Id = p.ParentId 
                AND parent.AcceptedAnswerId = p.Id
            ) THEN 2
            ELSE 0
        END AS AcceptanceStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS PostRank,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2015-01-01'
        AND p.OwnerUserId IS NOT NULL
        AND (p.Body IS NOT NULL AND LENGTH(p.Body) > 100)
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStarts,
        COALESCE(SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8), 0) AS TotalBountyAmount,
        AVG(EXTRACT(EPOCH FROM (v.CreationDate - (SELECT MIN(v2.CreationDate) FROM Votes v2 WHERE v2.PostId = v.PostId)))) AS AvgVoteTimeDiff
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2015-01-01'
    GROUP BY v.PostId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        AVG(p.Score) AS AvgScoreForTag,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.ViewCount) AS ViewCount75thPercentile
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE t.Count > 1000
        AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
)
SELECT 
    uem.UserId,
    COALESCE(NULLIF(SUBSTRING(uem.DisplayName, 1, 20), ''), 'Anonymous') AS DisplayName,
    uem.Reputation,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(CAST(uem.AvgPostScore AS NUMERIC) , 2) AS AvgPostScore,
    COALESCE(bd.GoldBadges, 0) AS GoldBadges,
    COALESCE(bd.SilverBadges, 0) AS SilverBadges,
    COALESCE(bd.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bd.GoldBadgeNames, 'None') AS TopBadges,
    pqm.PostRank AS BestPostRank,
    pqm.Score AS BestPostScore,
    COALESCE(vp.UpVotes, 0) AS BestPostUpVotes,
    COALESCE(vp.DownVotes, 0) AS BestPostDownVotes,
    COALESCE(vp.TotalBountyAmount, 0) AS BestPostBountyValue,
    CASE 
        WHEN pqm.AcceptanceStatus = 1 THEN 'Question with Accepted Answer'
        WHEN pqm.AcceptanceStatus = 2 THEN 'Accepted Answer'
        ELSE 'Not Accepted'
    END AS AcceptanceLabel,
    EXTRACT(DAY FROM (CAST(pqm.PostId AS TEXT) || ' days')::INTERVAL) AS DaysSinceEpoch,
    ROUND((CAST(uem.Reputation AS NUMERIC) / NULLIF(uem.TotalPosts, 0)) * 
          (1 + COALESCE(bd.GoldBadges, 0) * 0.1), 2) AS EngagementScore,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.PostId = pqm.PostId 
       AND c.Score > 0) AS HighScoredComments,
    (SELECT STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName)
     FROM TagPopularity tp
     WHERE tp.PostsWithTag > 5000
       AND EXISTS (
           SELECT 1 FROM Posts p2 
           WHERE p2.OwnerUserId = uem.UserId 
             AND p2.Tags LIKE '%<' || tp.TagName || '>%'
       )
     LIMIT 3) AS TopTagsUsed,
    DENSE_RANK() OVER (ORDER BY uem.Reputation DESC, uem.AvgPostScore DESC) AS OverallRank,
    NTILE(10) OVER (ORDER BY uem.Reputation) AS ReputationDecile
FROM UserEngagementMetrics uem
INNER JOIN PostQualityMetrics pqm ON uem.UserId = pqm.OwnerUserId AND pqm.PostRank = 1
LEFT OUTER JOIN BadgeDistribution bd ON uem.UserId = bd.UserId
LEFT OUTER JOIN VotePatterns vp ON pqm.PostId = vp.PostId
WHERE uem.Reputation > 500
    AND (bd.GoldBadges > 0 OR bd.SilverBadges > 2 OR bd.BronzeBadges > 5)
    AND pqm.Score >= (SELECT AVG(Score) FROM Posts WHERE Score > 0) * 0.5
    AND NOT EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = pqm.PostId 
          AND v.VoteTypeId IN (4, 12)
    )
ORDER BY 
    OverallRank,
    uem.Reputation DESC,
    COALESCE(vp.UpVotes, 0) DESC
LIMIT 100;