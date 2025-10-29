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
),
MainUsers AS (
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
        CAST(SUBSTRING(u.AboutMe FROM 1 FOR 50) AS VARCHAR(50)) AS AboutMeSnippet,
        CASE
            WHEN u.LastAccessDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') THEN 'Inactive'
            WHEN u.LastAccessDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 months') THEN 'Less Active'
            ELSE 'Active'
        END AS UserActivityLevel,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY CASE WHEN u.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years') THEN 'Old' ELSE 'New' END ORDER BY u.Views DESC) AS UserViewsRankByAge
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserBadgeInfo ubi ON u.Id = ubi.UserId
    LEFT JOIN UserVoteAnalysis uva ON u.Id = uva.UserId
    WHERE u.DisplayName IS NOT NULL
      AND u.DisplayName NOT LIKE '% Deleted'
      AND (COALESCE(ups.TotalPosts, 0) > 5 OR COALESCE(ubi.TotalBadges, 0) > 2 OR COALESCE(uva.TotalVotesCast, 0) > 10)
)
SELECT
    DisplayName,
    Reputation,
    UserTotalPosts,
    UserQuestionCount,
    UserAnswerCount,
    AverageScore,
    LastPostDate,
    TotalViews,
    UserTotalBadges,
    UserGoldBadges,
    UserSilverBadges,
    UserBronzeBadges,
    FirstBadgeDate,
    UserTotalVotesCast,
    UserUpVotesCast,
    UserDownVotesCast,
    UserPostsVotedOn,
    WebsiteCategory,
    NetUserVotes,
    AboutMeSnippet,
    UserActivityLevel,
    ReputationRank,
    UserViewsRankByAge
FROM MainUsers

UNION ALL

SELECT
    'Community User' AS DisplayName,
    -1 AS Reputation,
    COUNT(DISTINCT p.Id) AS UserTotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS UserQuestionCount,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS UserAnswerCount,
    AVG(p.Score) AS AverageScore,
    MAX(p.CreationDate) AS LastPostDate,
    SUM(p.ViewCount) AS TotalViews,
    0 AS UserTotalBadges,
    0 AS UserGoldBadges,
    0 AS UserSilverBadges,
    0 AS UserBronzeBadges,
    NULL AS FirstBadgeDate,
    0 AS UserTotalVotesCast,
    0 AS UserUpVotesCast,
    0 AS UserDownVotesCast,
    0 AS UserPostsVotedOn,
    'No Website' AS WebsiteCategory,
    0 AS NetUserVotes,
    NULL AS AboutMeSnippet,
    'Active' AS UserActivityLevel,
    NULL AS ReputationRank,
    NULL AS UserViewsRankByAge
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.OwnerUserId = -1
GROUP BY p.OwnerUserId

UNION ALL

SELECT
    'System' AS DisplayName,
    0 AS Reputation,
    COUNT(DISTINCT ph.Id) AS UserTotalPosts,
    NULL AS UserQuestionCount,
    NULL AS UserAnswerCount,
    NULL AS AverageScore,
    MAX(ph.CreationDate) AS LastPostDate,
    NULL AS TotalViews,
    0 AS UserTotalBadges,
    0 AS UserGoldBadges,
    0 AS UserSilverBadges,
    0 AS UserBronzeBadges,
    NULL AS FirstBadgeDate,
    0 AS UserTotalVotesCast,
    0 AS UserUpVotesCast,
    0 AS UserDownVotesCast,
    0 AS UserPostsVotedOn,
    'No Website' AS WebsiteCategory,
    0 AS NetUserVotes,
    NULL AS AboutMeSnippet,
    'Active' AS UserActivityLevel,
    NULL AS ReputationRank,
    NULL AS UserViewsRankByAge
FROM PostHistory ph
WHERE ph.UserId IS NULL AND ph.PostHistoryTypeId IN (16, 50)
GROUP BY ph.UserId;