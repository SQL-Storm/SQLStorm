-- {"query": "4439.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1327} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeInfo AS (
    SELECT
        b.UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteAnalysis AS (
    SELECT
        v.UserId,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCast,
        COUNT(DISTINCT pu.Id) AS PostsVotedOn
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Posts pu ON v.PostId = pu.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ups.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(ups.AnswerCount, 0) AS UserAnswerCount,
    ups.AverageScore,
    ups.LastPostDate,
    ups.TotalViews,
    COALESCE(ubi.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(ubi.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ubi.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ubi.BronzeBadges, 0) AS UserBronzeBadges,
    ubi.FirstBadgeDate,
    COALESCE(uva.TotalVotesCast, 0) AS UserTotalVotesCast,
    COALESCE(uva.UpVotesCast, 0) AS UserUpVotesCast,
    COALESCE(uva.DownVotesCast, 0) AS UserDownVotesCast,
    COALESCE(uva.PostsVotedOn, 0) AS UserPostsVotedOn,
    CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
    END AS WebsiteCategory,
    (u.UpVotes - u.DownVotes) AS NetUserVotes,
    CAST(SUBSTR(u.AboutMe, 1, 50) AS VARCHAR(50)) AS AboutMeSnippet,
    CASE
        WHEN u.LastAccessDate < (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN 'Inactive'
        WHEN u.LastAccessDate < (CURRENT_TIMESTAMP - INTERVAL '3 months') THEN 'Less Active'
        ELSE 'Active'
    END AS UserActivityLevel,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (PARTITION BY CASE WHEN u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '5 years') THEN 'Old' ELSE 'New' END ORDER BY u.Views DESC) AS UserViewsRankByAge
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserBadgeInfo ubi ON u.Id = ubi.UserId
LEFT JOIN UserVoteAnalysis uva ON u.Id = uva.UserId
WHERE u.DisplayName IS NOT NULL
  AND u.DisplayName NOT LIKE '% Deleted'
  AND (ups.TotalPosts > 5 OR ubi.TotalBadges > 2 OR uva.TotalVotesCast > 10)
UNION
SELECT
    'Community User' AS DisplayName,
    -1 AS Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(p.Score) AS AverageScore,
    MAX(p.CreationDate) AS LastPostDate,
    SUM(p.ViewCount) AS TotalViews
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.OwnerUserId = -1
GROUP BY p.OwnerUserId
UNION
SELECT
    'System' AS DisplayName,
    0 AS Reputation,
    COUNT(DISTINCT ph.Id) AS TotalPosts,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS AverageScore,
    MAX(ph.CreationDate) AS LastPostDate,
    NULL AS TotalViews
FROM PostHistory ph
WHERE ph.UserId IS NULL AND ph.PostHistoryTypeId IN (16, 50) -- Community Owned, CommunityBump
GROUP BY ph.UserId;
