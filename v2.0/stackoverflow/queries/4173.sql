-- {"query": "4173.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2172}
WITH RECURSIVE UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes AS TotalUpVotes,
        u.DownVotes AS TotalDownVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 ELSE 0 END AS HasWebsite,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS ActivityDurationDays,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        p.CommunityOwnedDate,
        p.Tags,
        (
            SELECT COUNT(c.Id)
            FROM Comments c
            WHERE c.PostId = p.Id
            AND c.Score > 0
        ) AS PositiveCommentCount,
        (
            SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
            FROM Votes v
            WHERE v.PostId = p.Id
        ) AS UpVoteCount,
        (
            SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
            FROM Votes v
            WHERE v.PostId = p.Id
        ) AS DownVoteCount,
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS LatestPostByUser
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
UserPostSummary AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.Views,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.BadgeCount,
        ua.HasWebsite,
        COUNT(pe.PostId) AS TotalPosts,
        SUM(CASE WHEN pe.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pe.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(pe.Score) AS AverageScore,
        SUM(pe.ViewCount) AS TotalViewCount,
        SUM(pe.FavoriteCount) AS TotalFavoriteCount,
        SUM(pe.PositiveCommentCount) AS TotalPositiveComments,
        SUM(pe.EditCount) AS TotalPostEdits,
        MAX(pe.LastActivityDate) AS LastPostActivity
    FROM UserActivity ua
    LEFT JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId
    GROUP BY
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.Views,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.BadgeCount,
        ua.HasWebsite
),
TopUsers AS (
    SELECT UserId
    FROM UserPostSummary
    ORDER BY Reputation DESC
    LIMIT 1000
),
RecentQuestions AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.OwnerUserId,
        pe.CreationDate,
        pe.Score,
        pe.ViewCount,
        pe.AnswerCount,
        pe.FavoriteCount,
        pe.Tags,
        pe.ActivityDurationDays,
        pe.IsClosed,
        ROW_NUMBER() OVER (ORDER BY pe.CreationDate DESC) AS RecentQuestionRank
    FROM PostEngagement pe
    WHERE pe.PostTypeId = 1
    AND pe.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND pe.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
),
HighEngagementAnswers AS (
    SELECT
        pe.PostId,
        pe.OwnerUserId,
        pe.CreationDate,
        pe.Score,
        pe.UpVoteCount,
        pe.DownVoteCount,
        pe.PositiveCommentCount,
        pe.ActivityDurationDays,
        ROW_NUMBER() OVER (ORDER BY (pe.Score + COALESCE(pe.UpVoteCount, 0) - COALESCE(pe.DownVoteCount, 0)) DESC) AS EngagementScoreRank
    FROM PostEngagement pe
    WHERE pe.PostTypeId = 2
    AND pe.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND pe.Score > 5
),
QuestionAnswerRatio AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        CAST(ups.AnswerCount AS DOUBLE PRECISION) / NULLIF(ups.QuestionCount, 0) AS AnswerToQuestionRatio,
        CASE
            WHEN CAST(ups.AnswerCount AS DOUBLE PRECISION) / NULLIF(ups.QuestionCount, 0) IS NULL THEN 0
            WHEN CAST(ups.AnswerCount AS DOUBLE PRECISION) / NULLIF(ups.QuestionCount, 0) > 5 THEN 5
            ELSE CAST(ups.AnswerCount AS DOUBLE PRECISION) / NULLIF(ups.QuestionCount, 0)
        END AS NormalizedAnswerToQuestionRatio,
        ups.TotalPosts,
        ups.TotalViewCount,
        ups.TotalPostEdits,
        ups.LastPostActivity
    FROM UserPostSummary ups
    WHERE ups.QuestionCount > 0
),
UserPerformanceMetrics AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AverageScore,
        ups.TotalViewCount,
        ups.TotalFavoriteCount,
        ups.TotalPositiveComments,
        ups.TotalPostEdits,
        ups.LastPostActivity,
        q.RecentQuestionRank,
        a.EngagementScoreRank,
        qar.NormalizedAnswerToQuestionRatio,
        CASE
            WHEN (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ups.LastPostActivity)) / 86400) < 7 THEN 1
            WHEN (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ups.LastPostActivity)) / 86400) < 30 THEN 0.7
            WHEN (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ups.LastPostActivity)) / 86400) < 90 THEN 0.4
            ELSE 0.1
        END AS ActivityRecencyScore,
        RANK() OVER (ORDER BY ups.Reputation DESC) AS ReputationGlobalRank,
        RANK() OVER (ORDER BY ups.TotalPosts DESC) AS PostCountGlobalRank,
        RANK() OVER (ORDER BY ups.TotalViewCount DESC) AS ViewCountGlobalRank
    FROM UserPostSummary ups
    LEFT JOIN RecentQuestions q ON ups.UserId = q.OwnerUserId AND q.RecentQuestionRank <= 5
    LEFT JOIN HighEngagementAnswers a ON ups.UserId = a.OwnerUserId AND a.EngagementScoreRank <= 10
    LEFT JOIN QuestionAnswerRatio qar ON ups.UserId = qar.UserId
    WHERE ups.TotalPosts > 10
)
SELECT
    'PerformanceBenchmark' AS BenchmarkName,
    upm.UserId,
    upm.DisplayName,
    upm.Reputation,
    upm.TotalPosts,
    upm.QuestionCount,
    upm.AnswerCount,
    upm.AverageScore,
    upm.TotalViewCount,
    upm.TotalFavoriteCount,
    upm.TotalPositiveComments,
    upm.TotalPostEdits,
    upm.LastPostActivity,
    COALESCE(q.Title, 'N/A') AS TopRecentQuestionTitle,
    COALESCE(a.Score, 0) AS TopEngagementAnswerScore,
    upm.NormalizedAnswerToQuestionRatio,
    upm.ActivityRecencyScore,
    upm.ReputationGlobalRank,
    upm.PostCountGlobalRank,
    upm.ViewCountGlobalRank,
    (
        upm.ReputationGlobalRank * 0.4 +
        upm.PostCountGlobalRank * 0.2 +
        upm.ViewCountGlobalRank * 0.2 +
        (SELECT MAX(rk) FROM (SELECT RANK() OVER (ORDER BY ActivityRecencyScore DESC) AS rk FROM UserPerformanceMetrics) sub1) * 0.1 +
        (SELECT MAX(rk) FROM (SELECT RANK() OVER (ORDER BY NormalizedAnswerToQuestionRatio DESC) AS rk FROM UserPerformanceMetrics) sub2) * 0.1
    ) AS CompositeScore
FROM UserPerformanceMetrics upm
LEFT JOIN RecentQuestions q ON upm.UserId = q.OwnerUserId AND q.RecentQuestionRank = 1
LEFT JOIN HighEngagementAnswers a ON upm.UserId = a.OwnerUserId AND a.EngagementScoreRank = 1
WHERE upm.TotalPosts > 50
ORDER BY CompositeScore ASC;