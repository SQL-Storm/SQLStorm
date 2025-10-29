-- {"query": "4855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1290} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.Title,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc_date,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_desc_score,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.Score > 0 OR p.ViewCount > 0 OR p.FavoriteCount > 0 OR p.AnswerCount IS NOT NULL OR p.CommentCount > 0
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostCreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        GROUP_CONCAT(b.Name, ';') AS BadgeNames
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE u.DisplayName IS NOT NULL AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentClosedQuestions AS (
    SELECT
        Id,
        Title,
        ClosedDate,
        OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1 AND ClosedDate >= DATE('now', '-30 day')
),
ClosedQuestionsWithReason AS (
    SELECT
        rcq.Id AS QuestionId,
        rcq.Title AS QuestionTitle,
        rcq.ClosedDate,
        rcq.OwnerUserId,
        crt.Name AS CloseReason
    FROM RecentClosedQuestions AS rcq
    LEFT JOIN PostHistory AS ph ON rcq.Id = ph.PostId
    LEFT JOIN CloseReasonTypes AS crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
),
HighEngagementUsers AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.UserCreationDate,
        upa.TotalPostsOwned,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AveragePostScore,
        upa.LastPostCreationDate,
        upa.BadgeCount,
        upa.BadgeNames
    FROM UserPostActivity AS upa
    WHERE upa.TotalPostsOwned > 50 AND upa.AveragePostScore > 5
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.Title AS PostTitle,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.CommentCountForPost,
    rp.Tags,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(rp.ClosedDate, '1970-01-01') AS NormalizedClosedDate,
    CASE
        WHEN rp.Score < 0 THEN 'Negative Score'
        WHEN rp.ViewCount > 10000 THEN 'High View Count'
        WHEN rp.FavoriteCount > 50 THEN 'Highly Favorited'
        WHEN rp.AnswerCount IS NOT NULL AND rp.AnswerCount > 10 THEN 'Many Answers'
        ELSE 'Standard Engagement'
    END AS EngagementLevel,
    rp.rn_desc_score,
    rp.PreviousPostScore,
    heu.TotalPostsOwned AS OwnerTotalPosts,
    heu.AveragePostScore AS OwnerAveragePostScore,
    cqr.CloseReason
FROM RankedPosts AS rp
LEFT JOIN Users AS u ON rp.OwnerUserId = u.Id
LEFT JOIN HighEngagementUsers AS heu ON rp.OwnerUserId = heu.UserId
LEFT JOIN ClosedQuestionsWithReason AS cqr ON rp.PostId = cqr.QuestionId
WHERE rp.rn_desc_score <= 100 AND rp.rn_desc_date <= 200 AND rp.PostTypeName IN ('Question', 'Answer')
UNION ALL
SELECT
    NULL,
    'Summary',
    NULL,
    SUM(Score),
    SUM(ViewCount),
    SUM(FavoriteCount),
    SUM(CommentCountForPost),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM RankedPosts
WHERE PostTypeName IN ('Question', 'Answer');
