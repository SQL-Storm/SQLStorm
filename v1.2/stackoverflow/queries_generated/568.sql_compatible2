WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, 1 AS Level, t.ExcerptPostId, t.WikiPostId
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT t.Id, t.TagName, t.Count, r.Level + 1, t.ExcerptPostId, t.WikiPostId
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id > r.Id
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false AND r.Level < 3
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = true THEN 1 ELSE 0 END),0) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        COUNT(a.Id) AS ActualAnswerCount,
        AVG(COALESCE(a.Score,0)) AS AvgAnswerScore,
        MAX(COALESCE(a.Score,0)) AS MaxAnswerScore,
        SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousAnswers
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount
),
QuestionCloseReasons AS (
    SELECT ph.PostId, crt.Name AS CloseReasonName, COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityWindow AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PostRank,
        LAG(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS NextScore,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalPosts
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2)
),
UserPostScoreDiff AS (
    SELECT 
        UserId,
        DisplayName,
        COUNT(CASE WHEN Score > COALESCE(PrevScore, -999999) THEN 1 END) AS PostsWithScoreIncrease,
        COUNT(CASE WHEN Score < COALESCE(PrevScore, 999999) THEN 1 END) AS PostsWithScoreDecrease,
        AVG(Score - COALESCE(PrevScore, Score)) AS AvgScoreDiff
    FROM UserActivityWindow
    GROUP BY UserId, DisplayName
),
CombinedUserStats AS (
    SELECT 
        ubc.UserId,
        ubc.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        ups.PostsWithScoreIncrease,
        ups.PostsWithScoreDecrease,
        ups.AvgScoreDiff,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
            ELSE 'Beginner' 
        END AS ReputationLevel,
        CASE 
            WHEN u.Location IS NULL THEN 'Unknown'
            WHEN LOWER(u.Location) LIKE '%usa%' THEN 'USA'
            WHEN LOWER(u.Location) LIKE '%india%' THEN 'India'
            ELSE 'Other'
        END AS Region
    FROM UserBadgeCounts ubc
    LEFT JOIN UserPostScoreDiff ups ON ups.UserId = ubc.UserId
    JOIN Users u ON u.Id = ubc.UserId
),
QuestionsWithTopAnswerAndClose AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreated,
        p.Score AS QuestionScore,
        p.ViewCount,
        pa.MaxAnswerScore,
        pa.AvgAnswerScore,
        cr.CloseReasonName,
        cr.CloseVotesCount,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        p.AnswerCount
    FROM Posts p
    LEFT JOIN PostAnswerStats pa ON pa.QuestionId = p.Id
    LEFT JOIN (
        SELECT PostId, CloseReasonName, CloseVotesCount,
            ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CloseVotesCount DESC) AS rn
        FROM QuestionCloseReasons
    ) cr ON cr.PostId = p.Id AND cr.rn = 1
    WHERE p.PostTypeId = 1
),
FinalOutput AS (
    SELECT 
        c.UserId,
        c.DisplayName,
        c.ReputationLevel,
        c.Region,
        c.GoldBadges,
        c.SilverBadges,
        c.BronzeBadges,
        c.TagBasedBadges,
        c.PostsWithScoreIncrease,
        c.PostsWithScoreDecrease,
        c.AvgScoreDiff,
        q.QuestionId,
        q.Title AS QuestionTitle,
        q.QuestionCreated,
        q.QuestionScore,
        q.ViewCount,
        q.MaxAnswerScore,
        q.AvgAnswerScore,
        q.CloseReasonName,
        q.CloseVotesCount,
        q.HasAcceptedAnswer,
        q.AnswerCount,
        CONCAT(
            CASE WHEN q.CloseReasonName IS NULL THEN 'Open' ELSE 'Closed: ' || q.CloseReasonName END,
            ' | ',
            'Answers: ',
            COALESCE(CAST(q.AnswerCount AS VARCHAR), '0'),
            ' | Views: ',
            COALESCE(CAST(q.ViewCount AS VARCHAR), '0'),
            ' | Score: ',
            COALESCE(CAST(q.QuestionScore AS VARCHAR), '0')
        ) AS QuestionSummary
    FROM CombinedUserStats c
    LEFT JOIN Posts p ON p.OwnerUserId = c.UserId AND p.PostTypeId = 1
    LEFT JOIN QuestionsWithTopAnswerAndClose q ON q.QuestionId = p.Id
    WHERE (c.GoldBadges + c.SilverBadges + c.BronzeBadges) > 5
)
SELECT *
FROM FinalOutput
WHERE QuestionCreated > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
ORDER BY ReputationLevel DESC, GoldBadges DESC, QuestionScore DESC, QuestionCreated DESC
LIMIT 100;