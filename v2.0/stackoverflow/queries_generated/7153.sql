-- {"query": "7153.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1757} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        COALESCE(p.ParentId, 0) AS ParentId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with Answers'
            ELSE 'Other'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RankByScore,
        RANK() OVER (ORDER BY p.Score DESC) AS RankOverall,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS RankByViews,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser,
        SUM(p.ViewCount) OVER (ORDER BY p.CreationDate) AS CumulativeViews
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TopQuestions AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.OwnerUserId,
        ps.Tags,
        ps.PostStatus,
        ps.RankByScore,
        ps.RankOverall,
        ps.AvgScorePerUser
    FROM PostStats ps
    WHERE ps.PostTypeId = 1 AND ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
    AND ps.RankOverall <= 100
),
AnswerStats AS (
    SELECT 
        ps.PostId,
        ps.Score,
        ps.ViewCount,
        ps.OwnerUserId,
        ps.ParentId,
        ps.RankByScore,
        ps.RankOverall,
        ps.AvgScorePerUser,
        ps.CreationDate,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount
    FROM PostStats ps
    LEFT JOIN Comments c ON ps.PostId = c.PostId
    LEFT JOIN Votes v ON ps.PostId = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE ps.PostTypeId = 2
    GROUP BY ps.PostId, ps.Score, ps.ViewCount, ps.OwnerUserId, ps.ParentId, ps.RankByScore, ps.RankOverall, ps.AvgScorePerUser, ps.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 1
            ELSE 0
        END AS HasAnswers,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS RankByTag
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.Id) AS HistoryCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        CASE 
            WHEN COUNT(DISTINCT ph.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT ph.Id) > 50 THEN 'Active'
            ELSE 'Regular'
        END AS ActivityLevel
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    tq.PostId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount,
    tq.PostStatus,
    tq.OwnerUserId,
    COALESCE(us.DisplayName, 'Unknown') AS OwnerDisplayName,
    COALESCE(us.Reputation, 0) AS OwnerReputation,
    COALESCE(AS1.VoteCount, 0) AS AnswerVoteCount,
    COALESCE(AS1.CommentCount, 0) AS AnswerCommentCount,
    (SELECT COUNT(*) FROM Tags t WHERE t.TagName = ANY(string_to_array(tq.Tags, '><'))) AS TagCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = tq.PostId AND pl.LinkTypeId = 3) AS DuplicateCount,
    (SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE t.TagName = ANY(string_to_array(tq.Tags, '><'))) AS TagList,
    CASE 
        WHEN tq.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
        WHEN tq.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.7 THEN 'Average'
        ELSE 'Below Average'
    END AS ScoreCategory,
    CASE 
        WHEN tq.PostStatus LIKE '%Closed%' THEN 'Closed'
        WHEN tq.PostStatus LIKE '%Community%' THEN 'Community'
        WHEN tq.PostStatus LIKE '%Question%' THEN 'Question'
        ELSE 'Other'
    END AS StatusCategory,
    DATEDIFF('DAY', tq.CreationDate, CURRENT_TIMESTAMP) AS DaysSinceCreation,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.PostId) AS CommentCount2,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = tq.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) AS HistoryCount
FROM TopQuestions tq
INNER JOIN UserStats us ON tq.OwnerUserId = us.UserId
LEFT JOIN AnswerStats AS1 ON AS1.ParentId = tq.PostId
WHERE (tq.ViewCount IS NULL OR tq.ViewCount > 0)
AND (tq.Score >= 10 OR tq.AnswerCount >= 1)
AND tq.PostStatus IN ('Question with Answers', 'Closed', 'Community Owned')
AND COALESCE(AS1.VoteCount, 0) > 0
AND tq.RankOverall BETWEEN 1 AND 50
ORDER BY tq.Score DESC, tq.ViewCount DESC
LIMIT 1000;