-- {"query": "4297.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1734} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY COALESCE(ph.CreationDate, u.CreationDate) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, ph.CreationDate
),
UserPostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        p.Score,
        p.FavoriteCount,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.Title IS NOT NULL AND p.Title <> '' AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.Score, p.FavoriteCount, p.LastActivityDate
),
QuestionMetrics AS (
    SELECT
        upg.OwnerUserId,
        AVG(upg.Score) AS AvgQuestionScore,
        SUM(CASE WHEN upg.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        COUNT(DISTINCT upg.PostId) AS DistinctQuestions
    FROM UserPostEngagement upg
    WHERE upg.PostTypeId = 1
    GROUP BY upg.OwnerUserId
),
AnswerMetrics AS (
    SELECT
        upg.OwnerUserId,
        AVG(upg.Score) AS AvgAnswerScore,
        SUM(CASE WHEN upg.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT upg.PostId) AS DistinctAnswers,
        SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts accepted_answers WHERE accepted_answers.Id = upg.PostId AND accepted_answers.AcceptedAnswerId = upg.PostId) THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM UserPostEngagement upg
    WHERE upg.PostTypeId = 2
    GROUP BY upg.OwnerUserId
),
HighReputationUsers AS (
    SELECT UserId
    FROM RankedUserActivity
    WHERE ReputationRank <= 1000
),
TopPostsByEngagement AS (
    SELECT
        upg.PostId,
        upg.Title,
        upg.OwnerUserId,
        (upg.CommentCount * 5 + upg.UpVoteCount * 2 + upg.FavoriteCount) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY upg.OwnerUserId ORDER BY (upg.CommentCount * 5 + upg.UpVoteCount * 2 + upg.FavoriteCount) DESC, upg.LastActivityDate DESC) AS PostEngagementRank
    FROM UserPostEngagement upg
    WHERE upg.OwnerUserId IN (SELECT UserId FROM HighReputationUsers)
)
SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.UserCreationDate,
    rua.ReputationRank,
    COALESCE(qm.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(qm.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(am.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(am.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(am.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
    CASE
        WHEN tpe.Name = 'Question' THEN 'Q'
        WHEN tpe.Name = 'Answer' THEN 'A'
        ELSE 'Other'
    END AS PrimaryPostType,
    CASE
        WHEN hru.UserId IS NOT NULL THEN 'HighRep'
        ELSE 'Regular'
    END AS UserTier,
    pl.RelatedPostId,
    CASE WHEN pl.LinkTypeId = 1 THEN 'Linked' WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE 'OtherLink' END AS LinkType,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (19, 20)) THEN 'Protected'
        ELSE 'NotProtected'
    END AS ProtectionStatus,
    CASE
        WHEN LOWER(p.Tags) LIKE '%<sql>%' THEN 'HasSQLTag'
        ELSE 'NoSQLTag'
    END AS TagPresence,
    COALESCE(tpeu.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(tpte.Title, 'N/A') AS TopPostTitle,
    COALESCE(tpte.EngagementScore, 0) AS TopPostEngagementScore
FROM RankedUserActivity rua
LEFT JOIN QuestionMetrics qm ON rua.UserId = qm.OwnerUserId
LEFT JOIN AnswerMetrics am ON rua.UserId = am.OwnerUserId
LEFT JOIN PostTypes tpe ON 1 = tpe.Id -- Assuming we are interested in posts of type 'Question' for this join
LEFT JOIN HighReputationUsers hru ON rua.UserId = hru.UserId
LEFT JOIN Posts p ON rua.UserId = p.OwnerUserId AND p.PostTypeId = 1 -- Joining to get Post related info for User Tier and Status
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3 -- Focusing on duplicate links
LEFT JOIN TopPostsByEngagement tpte ON rua.UserId = tpte.OwnerUserId AND tpte.PostEngagementRank = 1
LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS TotalQuestions FROM UserPostEngagement WHERE PostTypeId = 1 GROUP BY OwnerUserId) tpeu ON rua.UserId = tpeu.OwnerUserId
WHERE LOWER(rua.DisplayName) LIKE '%john%' OR LOWER(rua.DisplayName) LIKE '%doe%'
GROUP BY
    rua.UserId, rua.DisplayName, rua.Reputation, rua.UserCreationDate, rua.ReputationRank,
    qm.TotalQuestions, qm.AvgQuestionScore, am.TotalAnswers, am.AvgAnswerScore, am.AcceptedAnswerCount,
    tpe.Name, hru.UserId, pl.RelatedPostId, pl.LinkTypeId, p.ClosedDate, p.Tags, tpeu.TotalQuestions,
    tpte.Title, tpte.EngagementScore
ORDER BY rua.Reputation DESC, rua.UserCreationDate ASC
LIMIT 1000;
