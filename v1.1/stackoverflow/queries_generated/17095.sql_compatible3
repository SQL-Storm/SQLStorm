WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        DATE_TRUNC('quarter', u.CreationDate) AS JoinQuarter,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CASE WHEN p.Score > 0 THEN p.Score END), 0) AS AvgPositiveScore,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ' ) AS GoldBadges,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('quarter', u.CreationDate) ORDER BY u.Reputation DESC) AS QuarterlyRank,
        (
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ps.Score)
            FROM Posts ps
            WHERE ps.OwnerUserId = u.Id
        ) AS MedianPostScore
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= u.CreationDate
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 
        AND u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '180 days')
        AND (u.Location IS NULL OR UPPER(u.Location) NOT LIKE '%MOON%')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        SUBSTRING(tag FROM 1 FOR 35) AS Tag,
        COUNT(*) AS TagPostCount,
        SUM(p.Score) AS TagScore,
        MAX(p.Score) AS MaxTagScore,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM (
        SELECT p.*,
               UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), '><')) AS tag
        FROM Posts p
        WHERE p.Tags IS NOT NULL 
          AND p.PostTypeId IN (1, 2)
          AND p.Score > 0
          AND p.OwnerUserId IS NOT NULL
    ) p
    GROUP BY p.OwnerUserId, tag
),
EditPatterns AS (
    SELECT 
        ph.UserId,
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 END) AS RollbackCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
        BOOL_OR(ph.PostHistoryTypeId = 16) AS MadeCommunityWiki,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevEditTime,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEditTime
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, ph.PostId, ph.CreationDate, ph.PostHistoryTypeId
),
VotingBehavior AS (
    SELECT 
        v.UserId,
        vt.Name AS VoteType,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS VotesOnPopularPosts,
        STDDEV(CASE WHEN v.VoteTypeId IN (8, 9) THEN v.BountyAmount END) AS BountyStdDev,
        COALESCE(
            CASE 
                WHEN SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0 
                THEN (SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)::numeric) / NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0)
                ELSE NULL 
            END, 0) AS DownUpVoteRatio
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
    GROUP BY v.UserId, vt.Name
),
CommentEngagement AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(CHAR_LENGTH(c.Text)) AS AvgCommentLength,
        SUM(c.Score) AS TotalCommentScore,
        CASE 
            WHEN COUNT(*) > 100 THEN 'Highly Active'
            WHEN COUNT(*) > 50 THEN 'Active'
            WHEN COUNT(*) > 10 THEN 'Moderate'
            ELSE 'Low'
        END AS EngagementLevel,
        STRING_AGG(
            CASE 
                WHEN c.Score >= 5 THEN SUBSTRING(c.Text FROM 1 FOR 50) || '...'
            END, 
            ' | '
        ) FILTER (WHERE c.Score >= 5) AS TopComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    COALESCE(uam.Location, 'Not Specified') AS Location,
    uam.JoinQuarter,
    uam.QuarterlyRank,
    uam.PostCount,
    CAST(uam.QuestionCount AS TEXT) || '/' || CAST(uam.AnswerCount AS TEXT) AS "Q/A Ratio",
    ROUND(CAST(uam.TotalPostScore AS NUMERIC) / GREATEST(uam.PostCount, 1), 2) AS AvgScorePerPost,
    COALESCE(uam.MedianPostScore, 0) AS MedianScore,
    SUBSTRING(COALESCE(uam.GoldBadges, 'None') FROM 1 FOR 100) AS GoldBadgesSample,
    COALESCE(te.Tag, 'No Specialty') AS TopTag,
    COALESCE(te.TagScore, 0) AS TopTagScore,
    COALESCE(ep.EditCount, 0) AS TotalEdits,
    COALESCE(ep.RollbackCount, 0) AS TotalRollbacks,
    CASE 
        WHEN ep.MadeCommunityWiki THEN 'Yes' 
        ELSE 'No' 
    END AS ContributedToCW,
    COALESCE(vb.VoteType, 'No Recent Votes') AS MostCommonVoteType,
    COALESCE(vb.VoteCount, 0) AS VoteTypeCount,
    ROUND(COALESCE(vb.DownUpVoteRatio, 0)::numeric, 3) AS DownUpRatio,
    COALESCE(ce.EngagementLevel, 'None') AS CommentEngagement,
    CAST(COALESCE(ce.AvgCommentLength, 0) AS INT) AS AvgCommentLen,
    CASE 
        WHEN uam.Reputation > 10000 AND COALESCE(te.TagScore,0) > 1000 AND uam.GoldBadges IS NOT NULL THEN 'Expert'
        WHEN uam.Reputation > 5000 AND COALESCE(te.TagScore,0) > 500 THEN 'Advanced'
        WHEN uam.Reputation > 1000 AND COALESCE(te.TagScore,0) > 100 THEN 'Intermediate'
        ELSE 'Contributor'
    END AS UserTier,
    FIRST_VALUE(uam.DisplayName) OVER (
        PARTITION BY uam.JoinQuarter 
        ORDER BY uam.TotalPostScore DESC 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS QuarterTopContributor,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT CAST(pl.LinkTypeId AS TEXT), ',')
            FROM PostLinks pl
            WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = uam.Id)
            LIMIT 10
        ), 
        'No Links'
    ) AS LinkTypes
FROM UserActivityMetrics uam
LEFT OUTER JOIN TagExpertise te ON uam.Id = te.OwnerUserId AND te.TagRank = 1
LEFT OUTER JOIN (
    SELECT UserId, EditCount, RollbackCount, CloseReason, MadeCommunityWiki
    FROM EditPatterns
    WHERE EditCount IS NOT NULL OR RollbackCount IS NOT NULL
) ep ON uam.Id = ep.UserId
LEFT OUTER JOIN (
    SELECT UserId, VoteType, VoteCount, VotesOnPopularPosts, BountyStdDev, DownUpVoteRatio,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY VoteCount DESC) AS rn
    FROM VotingBehavior
) vb ON uam.Id = vb.UserId AND vb.rn = 1
LEFT OUTER JOIN CommentEngagement ce ON uam.Id = ce.UserId
WHERE uam.PostCount > 0
    OR uam.Reputation > 5000
    OR (uam.GoldBadges IS NOT NULL AND CHAR_LENGTH(uam.GoldBadges) > 0)
ORDER BY 
    uam.TotalPostScore DESC,
    uam.Reputation DESC,
    uam.QuarterlyRank ASC
LIMIT 500;