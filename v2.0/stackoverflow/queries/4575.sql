-- {"query": "4575.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2094}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS previous_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.PostScore) AS TotalScoreFromPosts,
        AVG(rp.PostScore) AS AvgScorePerPost,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN rp.PostId ELSE NULL END) AS QuestionCount,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN rp.PostId ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
        SUM(rp.PostScore) * 1.0 / NULLIF(COUNT(rp.PostId),0) AS WeightedScore,
        MAX(rp.PostCreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
CommentAggregates AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UnionUserActivity AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.UserCreationDate,
        upa.TotalPosts,
        upa.TotalScoreFromPosts,
        upa.AvgScorePerPost,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.TotalAnswersToQuestions,
        upa.WeightedScore,
        upa.LastPostDate,
        COALESCE(ca.CommentCount, 0) AS UserCommentCount,
        COALESCE(ca.TotalCommentScore, 0) AS UserTotalCommentScore,
        COALESCE(ca.AvgCommentScore, 0) AS UserAvgCommentScore
    FROM UserPostActivity upa
    LEFT JOIN CommentAggregates ca ON upa.UserId = ca.UserId
),
HighReputationUsers AS (
    SELECT UserId
    FROM UnionUserActivity
    WHERE Reputation > 50000
),
RecentQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        Tags,
        Score,
        AnswerCount,
        ViewCount,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
),
RQ_User_Info AS (
    SELECT
        rq.Id AS QuestionId,
        rq.Title,
        rq.Tags,
        rq.Score,
        rq.AnswerCount,
        rq.ViewCount,
        rq.CreationDate AS QuestionCreationDate,
        COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COALESCE(RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC), 0) AS UserRankForQuestion
    FROM RecentQuestions rq
    LEFT JOIN Users u ON rq.OwnerUserId = u.Id
)
SELECT
    COALESCE(rt.Name, 'N/A') AS LinkTypeName,
    COALESCE(rp.PostTypeName, 'N/A') AS PostTypeName,
    rp.PostId,
    rp.PostCreationDate,
    rp.PostScore,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    rp.ViewCount AS PostViewCount,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    rp.previous_score,
    CASE
        WHEN rp.rn_by_type <= 10 THEN 'Top 10 by Type'
        WHEN rp.rn_by_type > 10 AND rp.rn_by_type <= 50 THEN 'Next 40 by Type'
        ELSE 'Beyond Top 50 by Type'
    END AS RankCategory,
    CONCAT(
        COALESCE(CAST(ruu.TotalPosts AS VARCHAR), '0'), ' posts, ',
        COALESCE(CAST(ruu.TotalScoreFromPosts AS VARCHAR), '0'), ' score, ',
        COALESCE(ruu.DisplayName, 'Unknown User')
    ) AS UserContributionSummary,
    (SELECT COUNT(*) FROM Tags t WHERE rp.PostId = t.WikiPostId OR rp.PostId = t.ExcerptPostId) AS RelatedTagWikis,
    CASE
        WHEN EXISTS (SELECT 1 FROM HighReputationUsers hru WHERE hru.UserId = rp.OwnerUserId) THEN 'High Reputation'
        ELSE 'Standard Reputation'
    END AS UserReputationCategory,
    (SELECT MAX(CreationDate) FROM Comments c WHERE c.PostId = rp.PostId) AS LastCommentDate,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous Owner'
        WHEN ruu.UserCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '5 years') THEN 'Established User'
        ELSE 'Newer User'
    END AS UserAgeCategory,
    CASE
        WHEN rp.PostTypeName = 'Question' AND rp.AnswerCount > 100 THEN 'High Answer Volume Question'
        WHEN rp.PostTypeName = 'Answer' AND rp.PostScore > 50 THEN 'Highly Scored Answer'
        ELSE 'Standard Post'
    END AS PostSignificance,
    ROW_NUMBER() OVER (ORDER BY rp.PostScore DESC, rp.ViewCount DESC) AS GlobalRank,
    SUM(rp.PostScore) OVER (PARTITION BY rp.PostTypeId ORDER BY rp.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreTotalByType,
    rq_ui.OwnerDisplayName AS RecentQuestionOwner,
    rq_ui.UserRankForQuestion AS RecentQuestionOwnerRank
FROM RankedPosts rp
LEFT JOIN PostTypes rt ON rt.Id = rp.PostTypeId
LEFT JOIN UnionUserActivity ruu ON rp.OwnerUserId = ruu.UserId
LEFT JOIN RQ_User_Info rq_ui ON rp.PostId = rq_ui.QuestionId AND rp.PostTypeId = 1
WHERE rp.PostScore > 0 AND rp.OwnerUserId IS NOT NULL
UNION ALL
SELECT
    NULL AS LinkTypeName,
    NULL AS PostTypeName,
    NULL AS PostId,
    NULL AS PostCreationDate,
    NULL AS PostScore,
    NULL AS PostAnswerCount,
    NULL AS PostCommentCount,
    NULL AS PostFavoriteCount,
    NULL AS PostViewCount,
    NULL AS PostStatus,
    NULL AS previous_score,
    NULL AS RankCategory,
    CONCAT(
        COALESCE(CAST(ruu.TotalPosts AS VARCHAR), '0'), ' posts, ',
        COALESCE(CAST(ruu.TotalScoreFromPosts AS VARCHAR), '0'), ' score, ',
        COALESCE(ruu.DisplayName, 'Unknown User')
    ) AS UserContributionSummary,
    NULL AS RelatedTagWikis,
    CASE
        WHEN EXISTS (SELECT 1 FROM HighReputationUsers hru WHERE hru.UserId = ruu.UserId) THEN 'High Reputation'
        ELSE 'Standard Reputation'
    END AS UserReputationCategory,
    NULL AS LastCommentDate,
    CASE
        WHEN ruu.UserCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '5 years') THEN 'Established User'
        ELSE 'Newer User'
    END AS UserAgeCategory,
    NULL AS PostSignificance,
    NULL AS GlobalRank,
    NULL AS RunningScoreTotalByType,
    rq_ui.Title AS RecentQuestionOwner,
    rq_ui.UserRankForQuestion AS RecentQuestionOwnerRank
FROM UnionUserActivity ruu
LEFT JOIN RQ_User_Info rq_ui ON ruu.UserId = rq_ui.QuestionId
WHERE ruu.Reputation > 10000;