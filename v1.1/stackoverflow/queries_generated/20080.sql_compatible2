WITH UserActivitySummary AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AverageAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        CAST(SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS DOUBLE PRECISION) / COUNT(p.Id) AS AcceptedRatio,
        MAX(p.LastActivityDate) AS LastAnswerActivity
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 10
),
UserCurationStats AS (
    SELECT
        UserId,
        SUM(EditCount) AS TotalEdits,
        SUM(CommentCount) AS TotalComments,
        SUM(UpVotes) AS TotalUpVotesGiven,
        SUM(DownVotes) AS TotalDownVotesGiven
    FROM (
        SELECT UserId, COUNT(Id) AS EditCount, 0 AS CommentCount, 0 AS UpVotes, 0 AS DownVotes
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6) AND UserId IS NOT NULL
        GROUP BY UserId
        UNION ALL
        SELECT UserId, 0, COUNT(Id), 0, 0
        FROM Comments
        WHERE UserId IS NOT NULL
        GROUP BY UserId
        UNION ALL
        SELECT UserId, 0, 0,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END),
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END)
        FROM Votes
        WHERE VoteTypeId IN (2, 3) AND UserId IS NOT NULL
        GROUP BY UserId
    ) AS CurationActivities
    GROUP BY UserId
),
UserBadgeRanks AS (
    SELECT
        UserId,
        Name,
        Date,
        LAG(Date, 1) OVER (PARTITION BY UserId ORDER BY Date) AS PreviousBadgeDate,
        EXTRACT(EPOCH FROM (Date - LAG(Date, 1) OVER (PARTITION BY UserId ORDER BY Date))) / 86400.0 AS DaysBetweenBadges
    FROM Badges
    WHERE Class = 1
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    -- compute account age in days from CreationDate to now (standard SQL)
    CAST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / 86400.0 AS DOUBLE PRECISION) AS UserAccountAgeInDays,
    uas.TotalAnswers,
    uas.AcceptedRatio,
    ucs.TotalEdits,
    ucs.TotalComments,
    (
        SELECT AVG(q_sub.ViewCount)
        FROM Posts p_sub
        JOIN Posts q_sub ON p_sub.ParentId = q_sub.Id
        WHERE p_sub.OwnerUserId = u.Id AND p_sub.PostTypeId = 2
    ) AS AvgViewCountOfAnsweredQuestions,
    COALESCE(
        REPLACE(
            SUBSTRING(u.WebsiteUrl FROM '://(?:www\.)?([^/]+)'),
            '.com', ''
        ),
        'NO_WEBSITE'
    ) AS CleanedWebsiteDomain,
    (
        LOG(u.Reputation + 1) * 2
        + COALESCE(uas.AverageAnswerScore, 0) * 1.5
        + COALESCE(uas.AcceptedRatio, 0) * 100
        + LOG(COALESCE(ucs.TotalEdits, 0) + 1) * 1.2
        + LOG(COALESCE(ucs.TotalUpVotesGiven, 0) - COALESCE(ucs.TotalDownVotesGiven, 0) + 1)
    ) AS EngagementScore,
    ubr.Name AS FirstGoldBadgeName,
    ubr.DaysBetweenBadges AS DaysToFirstGoldBadge,
    CASE
        WHEN u.Reputation > 100000 AND uas.AcceptedRatio > 0.5 THEN 'Community Pillar'
        WHEN u.Reputation > 20000 AND COALESCE(ucs.TotalEdits,0) > 500 THEN 'Dedicated Curator'
        WHEN uas.TotalAnswers > 100 THEN 'Prolific Answerer'
        ELSE 'Active Contributor'
    END AS UserTier,
    DENSE_RANK() OVER (ORDER BY
        (LOG(u.Reputation + 1) * 2
        + COALESCE(uas.AverageAnswerScore, 0) * 1.5
        + COALESCE(uas.AcceptedRatio, 0) * 100
        + LOG(COALESCE(ucs.TotalEdits, 0) + 1) * 1.2
        + LOG(COALESCE(ucs.TotalUpVotesGiven, 0) - COALESCE(ucs.TotalDownVotesGiven, 0) + 1)
        ) DESC
    ) AS OverallRank
FROM Users u
JOIN UserActivitySummary uas ON u.Id = uas.OwnerUserId
LEFT JOIN UserCurationStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserBadgeRanks ubr ON u.Id = ubr.UserId AND ubr.PreviousBadgeDate IS NULL
WHERE u.Reputation > (
        SELECT AVG(Reputation) + STDDEV_POP(Reputation) FROM Users
    )
  AND u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
  AND u.AboutMe IS NOT NULL
  AND u.Id > 0
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    uas.TotalAnswers,
    uas.AcceptedRatio,
    ucs.TotalEdits,
    ucs.TotalComments,
    u.WebsiteUrl,
    uas.AverageAnswerScore,
    ucs.TotalUpVotesGiven,
    ucs.TotalDownVotesGiven,
    ubr.Name,
    ubr.DaysBetweenBadges
ORDER BY OverallRank, EngagementScore DESC, u.Reputation DESC
LIMIT 500;