-- {"query": "4289.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1836}
WITH RelevantPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.Title AS PostTitle,
        p.Tags AS PostTags,
        pt.Name AS PostTypeName,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOwned,
        AVG(p.Score) AS AvgScoreOwned,
        MAX(p.CreationDate) AS LastPostCreationDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        Score,
        ViewCount,
        FavoriteCount,
        CreationDate,
        ROW_NUMBER() OVER (ORDER BY Score DESC, FavoriteCount DESC, ViewCount DESC) AS q_rn
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 100
),
RecentAnswers AS (
    SELECT
        Id,
        ParentId AS QuestionId,
        OwnerUserId,
        Score,
        CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ParentId ORDER BY CreationDate DESC) AS a_rn
    FROM Posts
    WHERE PostTypeId = 2 AND ParentId IS NOT NULL AND Score > 0
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE NULL END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserContributionMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upa.TotalPostsOwned, 0) AS TotalPostsOwned,
        COALESCE(upa.TotalScoreOwned, 0) AS TotalScoreOwned,
        COALESCE(upa.AvgScoreOwned, 0) AS AvgScoreOwned,
        COALESCE(upa.QuestionCount, 0) AS UserQuestionCount,
        COALESCE(upa.AnswerCount, 0) AS UserAnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, upa.TotalPostsOwned, upa.TotalScoreOwned, upa.AvgScoreOwned, upa.QuestionCount, upa.AnswerCount
)
SELECT
    rp_q.PostId AS QuestionId,
    rp_q.PostTitle AS QuestionTitle,
    rp_q.PostScore AS QuestionScore,
    rp_q.PostViewCount AS QuestionViewCount,
    rp_q.PostFavoriteCount AS QuestionFavoriteCount,
    rp_q.PostCommentCount AS QuestionCommentCount,
    COALESCE(phs.EditCount, 0) AS QuestionEditCount,
    COALESCE(phs.LastEditDate, rp_q.PostCreationDate) AS LastQuestionActivity,
    u_q.DisplayName AS QuestionOwnerDisplayName,
    u_q.Reputation AS QuestionOwnerReputation,
    u_q.CreationDate AS QuestionOwnerCreationDate,
    ra.Id AS BestAnswerId,
    ra.Score AS BestAnswerScore,
    ra.CreationDate AS BestAnswerCreationDate,
    COALESCE(u_a.DisplayName, rp_a.OwnerDisplayName) AS BestAnswerOwnerDisplayName,
    u_a.Reputation AS BestAnswerOwnerReputation,
    u_a.CreationDate AS BestAnswerOwnerCreationDate,
    CASE
        WHEN rp_q.PostTags LIKE '%<sql>%' THEN 'SQL Focused'
        WHEN rp_q.PostTags LIKE '%<performance>%' THEN 'Performance Related'
        WHEN rp_q.PostTags LIKE '%<optimization>%' THEN 'Optimization Related'
        ELSE 'General'
    END AS TagCategory,
    CASE
        WHEN rp_q.PostCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year') AND rp_q.PostScore < 50 THEN 'Old & Low Engagement'
        WHEN rp_q.PostCreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 month') AND rp_q.PostAnswerCount > 5 THEN 'Recent & Popular'
        ELSE 'Standard'
    END AS EngagementStatus,
    COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentsOnQuestion,
    SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentsOnQuestion,
    MAX(c.CreationDate) AS LastCommentDateOnQuestion,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp_q.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    (SELECT SUM(pl.Id) FROM PostLinks pl WHERE pl.PostId = rp_q.PostId AND pl.LinkTypeId = 1) AS LinkedPostCountSum
FROM RelevantPosts rp_q
LEFT JOIN RelevantPosts rp_a ON rp_q.PostId = rp_a.PostId AND rp_a.PostTypeId = 2 AND rp_a.PostId = rp_q.PostId
LEFT JOIN (
    SELECT * FROM RecentAnswers WHERE a_rn = 1
) AS ra ON rp_q.PostId = ra.QuestionId
LEFT JOIN Users u_q ON rp_q.OwnerUserId = u_q.Id
LEFT JOIN Users u_a ON ra.OwnerUserId = u_a.Id
LEFT JOIN PostHistorySummary phs ON rp_q.PostId = phs.PostId
LEFT JOIN Comments c ON rp_q.PostId = c.PostId
WHERE rp_q.PostTypeId = 1
  AND rp_q.rn <= 1000
GROUP BY
    rp_q.PostId,
    rp_q.PostTitle,
    rp_q.PostScore,
    rp_q.PostViewCount,
    rp_q.PostFavoriteCount,
    rp_q.PostCommentCount,
    phs.EditCount,
    rp_q.PostCreationDate,
    COALESCE(phs.LastEditDate, rp_q.PostCreationDate),
    u_q.DisplayName,
    u_q.Reputation,
    u_q.CreationDate,
    ra.Id,
    ra.Score,
    ra.CreationDate,
    COALESCE(u_a.DisplayName, rp_a.OwnerDisplayName),
    u_a.Reputation,
    u_a.CreationDate,
    CASE
        WHEN rp_q.PostTags LIKE '%<sql>%' THEN 'SQL Focused'
        WHEN rp_q.PostTags LIKE '%<performance>%' THEN 'Performance Related'
        WHEN rp_q.PostTags LIKE '%<optimization>%' THEN 'Optimization Related'
        ELSE 'General'
    END,
    CASE
        WHEN rp_q.PostCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year') AND rp_q.PostScore < 50 THEN 'Old & Low Engagement'
        WHEN rp_q.PostCreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 month') AND rp_q.PostAnswerCount > 5 THEN 'Recent & Popular'
        ELSE 'Standard'
    END
ORDER BY rp_q.PostCreationDate DESC
LIMIT 500;