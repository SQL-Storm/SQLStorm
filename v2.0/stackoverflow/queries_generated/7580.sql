-- {"query": "7580.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3041} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(MAX(p.CreationDate), u.CreationDate) AS LastActivity,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 
            THEN RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) 
            ELSE NULL 
        END AS PostRank,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
        AVG(t.Count) OVER (PARTITION BY t.IsRequired) AS AvgCountByRequired
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        NTILE(10) OVER (ORDER BY p.Score DESC) AS ScoreQuartile
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
QuestionMetrics AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.CreationDate,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        COALESCE(a.Score, 0) AS AnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Yes'
            ELSE 'No'
        END AS HasAcceptedAnswer,
        DATEDIFF('SECOND', q.CreationDate, q.LastActivityDate) AS AgeInSeconds,
        CASE 
            WHEN q.CreationDate >= '2020-01-01' THEN 'Recent'
            WHEN q.CreationDate >= '2018-01-01' THEN 'Mid'
            ELSE 'Old'
        END AS QuestionAgeGroup
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 AND q.Score IS NOT NULL
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Badges,
    ua.TotalScore,
    ua.LastActivity,
    ua.PostRank,
    ua.ReputationRank,
    CASE 
        WHEN ua.TotalPosts >= 100 THEN 'Veteran'
        WHEN ua.TotalPosts >= 50 THEN 'Experienced'
        WHEN ua.TotalPosts >= 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserExperienceLevel,
    STRING_AGG(DISTINCT SUBSTRING(t.TagName, 2, LENGTH(t.TagName) - 2) FILTER (WHERE t.TagName IS NOT NULL AND t.TagName != ''), ', ') AS TopTags,
    STRING_AGG(DISTINCT CONCAT(ups.PostType, ': ', ups.Score, ' points'), ', ') AS RecentPostActivity,
    COALESCE(
        (SELECT COUNT(*) 
         FROM UserActivityStats uas 
         WHERE uas.UserId = ua.UserId 
         AND uas.LastActivity >= '2023-01-01'), 
        0
    ) AS ActiveIn2023,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.UserId = ua.UserId 
         AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 24)), 
        0
    ) AS EditingActivity,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Votes v 
            WHERE v.UserId = ua.UserId 
            AND v.VoteTypeId IN (1, 2, 3)
        ) THEN 'HasVoted'
        ELSE 'NoVotes'
    END AS VotingStatus,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 2) AS AnswerCount,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN pm.QuestionAgeGroup = 'Recent' THEN pm.QuestionId END) > 0 
        THEN 'ActiveRecentQuestions'
        ELSE 'NoRecentQuestions'
    END AS RecentQuestionStatus,
    (SELECT COUNT(*) FROM UserActivityStats uas WHERE uas.UserId = ua.UserId AND uas.TotalPosts > 0) AS ActivePosts,
    LEAD(ua.Reputation, 1) OVER (ORDER BY ua.Reputation DESC) AS NextTopReputation,
    LAG(ua.Reputation, 1) OVER (ORDER BY ua.Reputation DESC) AS PreviousTopReputation,
    PERCENT_RANK() OVER (ORDER BY ua.Reputation) AS ReputationPercentile,
    CASE 
        WHEN ua.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverage'
        WHEN ua.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'BelowAverage'
        ELSE 'Average'
    END AS ReputationComparison,
    COALESCE((SELECT COUNT(DISTINCT PostId) FROM Comments c WHERE c.UserId = ua.UserId), 0) AS CommentCount,
    COALESCE((SELECT COUNT(DISTINCT Id) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 100), 0) AS HighScorePosts,
    COUNT(*) OVER (PARTITION BY ua.UserId) AS UserPostCount,
    (SELECT COUNT(DISTINCT Id) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(DISTINCT Id) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(DISTINCT Id) FROM Badges b WHERE b.UserId = ua.UserId AND b.Class = 3) AS BronzeBadges,
    COUNT(DISTINCT CASE WHEN pm.QuestionAgeGroup = 'Recent' THEN pm.QuestionId END) AS RecentQuestions,
    COALESCE(
        (SELECT AVG(q.Score) 
         FROM Posts q 
         WHERE q.OwnerUserId = ua.UserId 
         AND q.PostTypeId = 1 
         AND q.CreationDate >= '2023-01-01'), 
        0
    ) AS RecentAvgScore,
    CASE 
        WHEN ua.Answers > ua.Questions THEN 'MoreAnswersThanQuestions'
        WHEN ua.Answers < ua.Questions THEN 'MoreQuestionsThanAnswers'
        ELSE 'EqualQuestionsAndAnswers'
    END AS QuestionAnswerRatio,
    COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId), 0) AS TotalVotes,
    COALESCE(
        (SELECT COUNT(*) 
         FROM VoteTypes vt 
         WHERE vt.Name IN ('UpMod', 'DownMod') 
         AND EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId = vt.Id)), 
        0
    ) AS VotedUpOrDown,
    STRING_AGG(DISTINCT pm.QuestionAgeGroup, ', ') OVER (PARTITION BY ua.UserId) AS QuestionAgeGroups,
    COUNT(DISTINCT CASE WHEN pm.QuestionAgeGroup = 'Old' THEN pm.QuestionId END) AS OldQuestions,
    COUNT(DISTINCT CASE WHEN pm.QuestionAgeGroup = 'Mid' THEN pm.QuestionId END) AS MidQuestions,
    COUNT(DISTINCT CASE WHEN pm.QuestionAgeGroup = 'Recent' THEN pm.QuestionId END) AS RecentQuestionsCount,
    (COUNT(DISTINCT q.Id) FILTER (WHERE q.PostTypeId = 1 AND q.ViewCount > 1000)) AS PopularQuestions,
    (SELECT STRING_AGG(CONCAT(pv.PostTypeId, ':', pv.Score), ', ') 
     FROM Posts pv 
     WHERE pv.OwnerUserId IN (ua.UserId) 
     AND pv.PostTypeId IN (1, 2) 
     AND pv.CreationDate >= '2022-01-01'
    ) AS RecentActivity,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 1 AND p.OwnerUserId = ua.UserId AND p.CreationDate >= '2023-01-01') 
        THEN 'HasRecentQuestion'
        ELSE 'NoRecentQuestion'
    END AS RecentQuestionFlag,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 2 AND p.OwnerUserId = ua.UserId AND p.CreationDate >= '2023-01-01') 
        THEN 'HasRecentAnswer'
        ELSE 'NoRecentAnswer'
    END AS RecentAnswerFlag,
    COALESCE((SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = ua.UserId AND b.Date >= '2023-01-01'), 0) AS RecentBadges,
    COALESCE((SELECT COUNT(DISTINCT Id) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 0), 0) AS PositiveScorePosts,
    COALESCE((SELECT COUNT(DISTINCT Id) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score < 0), 0) AS NegativeScorePosts,
    COALESCE((SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1), 0) AS AvgQuestionScore,
    COALESCE((SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 2), 0) AS AvgAnswerScore,
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory ph WHERE ph.UserId = ua.UserId AND ph.CreationDate >= '2023-01-01') AS RecentEdits,
    CASE WHEN EXISTS (SELECT 1 FROM Users u WHERE u.Id = ua.UserId AND u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '') THEN 'HasWebsite' ELSE 'NoWebsite' END AS WebsiteStatus,
    (SELECT COUNT(DISTINCT Id) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.CreationDate >= '2023-01-01') AS RecentPosts,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId)) AS LinkCount,
    CASE 
        WHEN ua.Badges >= 10 THEN 'BadgeMaster'
        WHEN ua.Badges >= 5 THEN 'BadgeEnthusiast'
        ELSE 'BadgeSeeker'
    END AS BadgeAchievement,
    COALESCE(
        (SELECT COUNT(DISTINCT PostId) 
         FROM PostHistory ph 
         WHERE ph.UserId = ua.UserId 
         AND ph.PostHistoryTypeId = 24), 
        0
    ) AS SuggestedEdits,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId AND c.CreationDate >= '2023-01-01') AS RecentComments,
    CASE 
        WHEN ua.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0) * 1.5 THEN 'HighReputation'
        WHEN ua.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0) * 0.75 THEN 'ModerateReputation'
        ELSE 'LowReputation'
    END AS ReputationTier
FROM UserActivityStats ua
LEFT JOIN UserPostStats ups ON ua.UserId = ups.OwnerUserId
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN Tags t ON t.TagName IS NOT NULL
LEFT JOIN QuestionMetrics pm ON pm.OwnerUserId = ua.UserId
LEFT JOIN PostHistory ph ON ph.UserId = ua.UserId
WHERE ua.UserId IN (
    SELECT DISTINCT OwnerUserId 
    FROM Posts 
    WHERE OwnerUserId IS NOT NULL
)
GROUP BY 
    ua.UserId, 
    ua.DisplayName, 
    ua.Reputation, 
    ua.Views, 
    ua.UpVotes, 
    ua.DownVotes, 
    ua.TotalPosts, 
    ua.Questions, 
    ua.Answers, 
    ua.Comments, 
    ua.Badges, 
    ua.TotalScore, 
    ua.LastActivity, 
    ua.PostRank, 
    ua.ReputationRank,
    CASE 
        WHEN ua.TotalPosts >= 100 THEN 'Veteran'
        WHEN ua.TotalPosts >= 50 THEN 'Experienced'
        WHEN ua.TotalPosts >= 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END
HAVING 
    COUNT(DISTINCT ups.OwnerUserId) > 0 
    OR COUNT(DISTINCT p.Id) > 0
ORDER BY 
    ua.Reputation DESC,
    ua.Views DESC
LIMIT 1000;