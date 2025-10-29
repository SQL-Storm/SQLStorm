WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN PostTypeId = 5 THEN 1 ELSE 0 END) AS TagWikiCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
),
UserTagCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT t.Id) AS DistinctTagsCount
    FROM Posts p
    JOIN Tags t ON POSITION(CONCAT(',', t.TagName, ',') IN CONCAT(',', COALESCE(p.Tags, ''), ',')) > 0
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesCast,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesCast,
        SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyAmount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL AND v.UserId > 0
    GROUP BY v.UserId
),
PostEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AverageScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    -- replace DATEDIFF with standard SQL age in days where supported; using (CAST(...) - CAST(...)) / interval '1 day' may vary by dialect.
    CAST((CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate) AS INTERVAL) AS AccountAgeInterval,
    COALESCE(upc.TotalPosts, 0) AS TotalPosts,
    COALESCE(upc.QuestionCount, 0) AS QuestionCount,
    COALESCE(upc.AnswerCount, 0) AS AnswerCount,
    COALESCE(upc.TagWikiCount, 0) AS TagWikiCount,
    COALESCE(utc.DistinctTagsCount, 0) AS DistinctTagsUsed,
    COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uvs.UpVotesCast, 0) AS UpVotesCast,
    COALESCE(uvs.DownVotesCast, 0) AS DownVotesCast,
    COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswers,
    COALESCE(uvs.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(pe.CommentCount, 0) AS TotalComments,
    COALESCE(pe.VoteCount, 0) AS TotalVotesOnPosts,
    COALESCE(pe.AverageScore, 0) AS AveragePostScore,
    COALESCE(pe.ClosedPosts, 0) AS ClosedPosts,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Favorite%') AS FavoriteBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
    CASE
        WHEN u.UpVotes > 0 AND u.DownVotes = 0 THEN 'Net Positive'
        WHEN u.UpVotes = 0 AND u.DownVotes > 0 THEN 'Net Negative'
        WHEN u.UpVotes > u.DownVotes THEN 'Slightly Positive'
        WHEN u.DownVotes > u.UpVotes THEN 'Slightly Negative'
        ELSE 'Neutral'
    END AS VoteBalanceCategory,
    CASE
        WHEN u.Views > 100000 THEN 'High'
        WHEN u.Views > 10000 THEN 'Medium'
        ELSE 'Low'
    END AS ViewCategory,
    SUBSTRING(u.AboutMe FROM 1 FOR 50) AS AboutMeSnippet,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
        ELSE 'No Website'
    END AS WebsiteStatus,
    CASE
        WHEN LOWER(u.Location) LIKE '%london%' THEN 'London User'
        WHEN LOWER(u.Location) LIKE '%new york%' THEN 'New York User'
        ELSE 'Other Location'
    END AS LocationCategory,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY COALESCE(upc.TotalPosts, 0) DESC) AS PostCountRank,
    DENSE_RANK() OVER (PARTITION BY CASE WHEN u.Views > 10000 THEN 1 ELSE 0 END ORDER BY u.Reputation DESC) AS ReputationRankForHighViewUsers
FROM Users u
LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
LEFT JOIN UserTagCounts utc ON u.Id = utc.OwnerUserId
LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
LEFT JOIN PostEngagement pe ON u.Id = pe.OwnerUserId
WHERE u.DisplayName IS NOT NULL
  AND u.CreationDate < CAST('2023-01-01' AS TIMESTAMP)
  AND (upc.TotalPosts IS NULL OR upc.TotalPosts > 10)
  AND (u.Location IS NULL OR u.Location <> 'Unknown');