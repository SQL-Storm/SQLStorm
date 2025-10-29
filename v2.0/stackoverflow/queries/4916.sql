-- {"query": "4916.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1278}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.ViewCount AS DECIMAL(10,2))) AS AverageViewCount,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentQuestions AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS RecentQuestionCount
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
    GROUP BY OwnerUserId
),
UserBadgeStats AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostWithCommentsAndVotes AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS NumberOfComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS NumberOfUpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS NumberOfDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyGiven
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalScore,
    upa.AverageViewCount,
    upa.LastPostActivityDate,
    upa.ClosedPostCount,
    upa.CommentCount,
    COALESCE(rq.RecentQuestionCount, 0) AS Recent30DayQuestionCount,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    rp.Title AS MostRecentQuestionTitle,
    pwc.NumberOfComments AS CommentsOnMostRecentQuestion,
    pwc.NumberOfUpVotes AS UpVotesOnMostRecentQuestion,
    pwc.NumberOfDownVotes AS DownVotesOnMostRecentQuestion,
    pwc.TotalBountyGiven AS BountyGivenOnMostRecentQuestion,
    CASE
        WHEN upa.Reputation > 100000 THEN 'High Reputation'
        WHEN upa.Reputation BETWEEN 10000 AND 100000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationTier,
    CASE
        WHEN upa.LastPostActivityDate IS NULL THEN 'Never Active'
        WHEN upa.LastPostActivityDate < (cast('2024-10-01' as date) - INTERVAL '365 days') THEN 'Inactive'
        ELSE 'Active'
    END AS ActivityStatus,
    CASE
        WHEN upa.AnswerCount > (upa.QuestionCount * 2) THEN 'Answer Heavy'
        WHEN upa.QuestionCount > (upa.AnswerCount * 2) THEN 'Question Heavy'
        ELSE 'Balanced'
    END AS ActivityBalance,
    LENGTH(TRIM(upa.DisplayName)) AS DisplayNameLength,
    UPPER(SUBSTR(upa.DisplayName, 1, 1)) AS DisplayNameInitial,
    CASE
        WHEN upa.TotalScore < 0 THEN 'Negative Score User'
        WHEN upa.TotalScore BETWEEN 0 AND 1000 THEN 'Moderate Score User'
        ELSE 'High Score User'
    END AS ScoreCategory
FROM UserPostActivity upa
LEFT JOIN RecentQuestions rq ON upa.UserId = rq.OwnerUserId
LEFT JOIN UserBadgeStats ubs ON upa.UserId = ubs.UserId
LEFT JOIN RankedPosts rp ON upa.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN PostWithCommentsAndVotes pwc ON rp.PostId = pwc.PostId
WHERE upa.Reputation >= 0
ORDER BY upa.Reputation DESC, upa.LastPostActivityDate DESC;