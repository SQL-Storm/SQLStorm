-- {"query": "17018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 44365, "output_tokens": 42748} 

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS UniqueTagsUsed,
        MAX(p.CreationDate) AS LastPostDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate))/86400 AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopAnswerers AS (
    SELECT 
        a.OwnerUserId,
        q.Id AS QuestionId,
        a.Score AS AnswerScore,
        RANK() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
        CASE 
            WHEN a.Id = q.AcceptedAnswerId THEN 'ACCEPTED'
            WHEN a.Score > 10 THEN 'HIGH_SCORE'
            WHEN a.Score BETWEEN 1 AND 10 THEN 'POSITIVE'
            ELSE 'NON_POSITIVE'
        END AS AnswerCategory
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1 
        AND q.ClosedDate IS NULL
        AND a.OwnerUserId IS NOT NULL
),
BadgeProgress AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        COUNT(*) FILTER (WHERE b.TagBased = B'1') AS TagBadges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (b.Date - u.CreationDate))/86400) AS MedianDaysToEarnBadge
    FROM Badges b
    INNER JOIN Users u ON b.UserId = u.Id
    GROUP BY b.UserId, b.Class
),
EditActivity AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPosts,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (7,8,9)) AS RollbackCount,
        COALESCE(LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate), ph.CreationDate) AS PrevEditTime,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate)))/3600 AS HoursBetweenEdits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
        AND ph.UserId IS NOT NULL
    GROUP BY ph.UserId, ph.CreationDate
),
VotingPatterns AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0), 999) AS UpDownRatio,
        STDDEV(EXTRACT(HOUR FROM v.CreationDate)) AS VotingHourStdDev
    FROM Votes v
    WHERE v.UserId IS NOT NULL 
        AND v.VoteTypeId IN (2,3)
    GROUP BY v.UserId
)
SELECT 
    uam.DisplayName,
    COALESCE(uam.Reputation, 0) AS Reputation,
    COALESCE(uam.PostCount, 0) AS TotalPosts,
    ROUND(COALESCE(uam.AvgPostScore, 0)::numeric, 2) AS AvgPostScore,
    CASE 
        WHEN uam.AccountAgeDays > 365 THEN 'Veteran'
        WHEN uam.AccountAgeDays > 90 THEN 'Regular'
        ELSE 'Newcomer'
    END AS UserStatus,
    COALESCE(LEFT(uam.UniqueTagsUsed, 100), 'No tags') AS TopTags,
    (
        SELECT COUNT(*)
        FROM TopAnswerers ta 
        WHERE ta.OwnerUserId = uam.Id AND ta.AnswerRank = 1
    ) AS TopAnswerCount,
    COALESCE(
        (
            SELECT STRING_AGG(b.Name || ' (' || b.Class || ')', ', ' ORDER BY b.Date DESC)
            FROM Badges b 
            WHERE b.UserId = uam.Id 
            LIMIT 5
        ), 
        'No badges'
    ) AS RecentBadges,
    COALESCE(bp1.BadgeCount, 0) + COALESCE(bp2.BadgeCount, 0) * 10 + COALESCE(bp3.BadgeCount, 0) * 100 AS WeightedBadgeScore,
    COALESCE((
        SELECT AVG(c.Score)
        FROM Comments c
        WHERE c.UserId = uam.Id AND c.Score > 0
    ), 0) AS AvgCommentScore,
    COALESCE(vp.UpDownRatio, 0) AS VoteRatio,
    CASE 
        WHEN vp.VotingHourStdDev < 3 THEN 'Consistent'
        WHEN vp.VotingHourStdDev BETWEEN 3 AND 6 THEN 'Variable'
        ELSE 'Erratic'
    END AS VotingPattern,
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = uam.Id 
            AND p.CommunityOwnedDate IS NOT NULL
    ) AS HasCommunityWikiPost,
    COALESCE(
        (
            SELECT MAX(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.UserId = uam.Id
                AND ph.PostHistoryTypeId = 10
        ),
        TIMESTAMP '1900-01-01'
    ) AS LastCloseVoteDate,
    ROW_NUMBER() OVER (ORDER BY uam.Reputation DESC, COALESCE(uam.AvgPostScore, 0) DESC) AS OverallRank
FROM UserActivityMetrics uam
LEFT JOIN BadgeProgress bp1 ON uam.Id = bp1.UserId AND bp1.Class = 3
LEFT JOIN BadgeProgress bp2 ON uam.Id = bp2.UserId AND bp2.Class = 2
LEFT JOIN BadgeProgress bp3 ON uam.Id = bp3.UserId AND bp3.Class = 1
LEFT JOIN VotingPatterns vp ON uam.Id = vp.UserId
WHERE uam.PostCount > 0
    OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = uam.Id)
    OR EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = uam.Id)
ORDER BY 
    CASE 
        WHEN uam.LastPostDate > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 1
        WHEN uam.LastPostDate > CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 2
        ELSE 3
    END,
    uam.Reputation DESC,
    COALESCE(uam.AvgPostScore, 0) DESC
LIMIT 100;
