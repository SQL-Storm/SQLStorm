WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        (EXTRACT(YEAR FROM u.LastAccessDate) - EXTRACT(YEAR FROM u.CreationDate)) * 12
            + (EXTRACT(MONTH FROM u.LastAccessDate) - EXTRACT(MONTH FROM u.CreationDate)) AS TenureMonths,
        CASE 
            WHEN u.Location IS NOT NULL AND LENGTH(TRIM(u.Location)) > 0 THEN 1
            ELSE 0
        END AS HasLocation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY u.Views) AS ViewPercentile
    FROM Users u
    WHERE u.Reputation > 100
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        (EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600.0) AS ActivitySpanHours,
        -- convert tag string like '<tag1><tag2>' into array using more portable functions: trim leading/trailing '<' '>' then split on '><'
        CASE
            WHEN p.Tags IS NULL THEN ARRAY[]::text[]
            ELSE (
                SELECT regexp_split
                FROM (
                    SELECT regexp_split_to_array(
                        CASE 
                            WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))
                            ELSE p.Tags
                        END,
                        '><'
                    ) AS regexp_split
                ) s
            )
        END AS TagArray,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '2' YEAR)
),
TagInfluence AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(*), 0) AS AcceptanceRate
    FROM Tags t
    INNER JOIN Posts p ON POSITION(t.TagName IN (
            CASE 
                WHEN p.Tags IS NULL THEN ''
                WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))
                ELSE p.Tags
            END
        )) > 0
    WHERE p.PostTypeId = 1
        AND t.Count > 50
    GROUP BY t.TagName, t.Count
),
VotingPatterns AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
        MAX(v.CreationDate) AS LastVoteDate,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.PostId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.TenureMonths,
    ROUND(CAST(uem.ViewPercentile AS NUMERIC), 4) AS ViewPercentile,
    pp.PostId,
    pp.Score AS PostScore,
    pp.ViewCount,
    COALESCE(vp.UpvoteCount, 0) - COALESCE(vp.DownvoteCount, 0) AS NetVotesOnPost,
    pp.HasAcceptedAnswer,
    ROUND(CAST(pp.RollingAvgScore AS NUMERIC), 2) AS UserRollingAvgScore,
    COALESCE(
        CARDINALITY(pp.TagArray),
        0
    ) AS TagCount,
    COALESCE(
        (SELECT ti.AvgPostScore FROM TagInfluence ti WHERE ti.TagName = (
            CASE WHEN CARDINALITY(pp.TagArray) >= 1 THEN pp.TagArray[1] ELSE NULL END
        )),
        0
    ) AS PrimaryTagAvgScore,
    CASE 
        WHEN pp.PreviousPostScore IS NULL THEN 'FIRST_POST'
        WHEN pp.Score > pp.PreviousPostScore THEN 'IMPROVING'
        WHEN pp.Score < pp.PreviousPostScore THEN 'DECLINING'
        ELSE 'STABLE'
    END AS PerformanceTrend,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = pp.PostId
            AND c.Score > 0
            AND c.Text LIKE '%thank%'
    ) AS PositiveCommentCount,
    (
        SELECT STRING_AGG(DISTINCT b.Name, ', ')
        FROM Badges b
        WHERE b.UserId = uem.Id
            AND b.Class = 1
            AND b.Date >= (DATE '2024-10-01' - INTERVAL '1' YEAR)
    ) AS RecentGoldBadges,
    ROUND(
        (
            pp.Score * 1.0 + COALESCE(pp.ViewCount, 0) * 1.0 / 100 + pp.AnswerCount * 5.0
        ) / NULLIF(
            EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - (pp.ActivitySpanHours * INTERVAL '1' HOUR))) / 86400.0,
            0
        ),
        3
    ) AS EngagementVelocity,
    EXISTS(
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId = pp.PostId
            AND pl.LinkTypeId = 3
    ) AS IsDuplicate
FROM UserEngagementMetrics uem
LEFT JOIN PostPerformance pp ON uem.Id = pp.OwnerUserId
LEFT JOIN VotingPatterns vp ON pp.PostId = vp.PostId
WHERE uem.ReputationRank <= 10000
    AND pp.PostId IS NOT NULL
    AND (pp.Score > 5 OR pp.ViewCount > 1000)
    AND COALESCE(CARDINALITY(pp.TagArray), 0) BETWEEN 1 AND 5
GROUP BY
    uem.DisplayName,
    uem.Reputation,
    uem.TenureMonths,
    uem.ViewPercentile,
    pp.PostId,
    pp.Score,
    pp.ViewCount,
    vp.UpvoteCount,
    vp.DownvoteCount,
    pp.HasAcceptedAnswer,
    pp.RollingAvgScore,
    pp.TagArray,
    pp.PreviousPostScore,
    pp.AnswerCount,
    pp.ActivitySpanHours,
    uem.Id,
    pp.OwnerUserId
ORDER BY 
    CASE 
        WHEN pp.HasAcceptedAnswer = 1 THEN pp.Score * 1.5
        ELSE pp.Score
    END DESC,
    uem.Reputation DESC,
    pp.ViewCount DESC
LIMIT 500;