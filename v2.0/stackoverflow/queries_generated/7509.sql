-- {"query": "7509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2102} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2008-01-01'
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopQuestioners AS (
    SELECT 
        UserId,
        COUNT(*) as QuestionCount,
        AVG(Score) as AvgScore,
        SUM(ViewCount) as TotalViews
    FROM Posts 
    WHERE PostTypeId = 1 
        AND CreationDate >= '2020-01-01'
        AND Score > 0
    GROUP BY UserId
    HAVING COUNT(*) >= 10
),
PostAnalytics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 10 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VoteCategory,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostSequence,
        NTH_VALUE(p.Score, 3) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as ThirdPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= '2019-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        COALESCE(p.Title, 'No Title') as ExcerptTitle,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Minor'
            ELSE 'Rare'
        END as TagPopularity,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN CONCAT(p.Title, ' (Q)')
                WHEN p.PostTypeId = 2 THEN CONCAT(SUBSTRING(p.Body, 1, 100), '... (A)')
            END, 
            ' | '
        ) as SamplePosts
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Count > 50
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, p.Title
),
ComplexVoteAnalysis AS (
    SELECT 
        v.PostId,
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        CASE 
            WHEN v.VoteTypeId IN (1, 2, 3) THEN 'TraditionalVotes'
            WHEN v.VoteTypeId IN (8, 9) THEN 'BountyVotes'
            WHEN v.VoteTypeId IN (6, 7) THEN 'CloseReopenVotes'
            ELSE 'OtherVotes'
        END as VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as VoteOrder,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) as UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) as DownvoteCount
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= '2020-01-01'
        AND v.VoteTypeId IN (1, 2, 3, 6, 7, 8, 9)
)
SELECT 
    uas.UserId,
    uas.Reputation,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.ReputationRank,
    uas.ReputationTier,
    COALESCE(tq.QuestionCount, 0) as TopQuestionerQuestionCount,
    COALESCE(tq.AvgScore, 0) as TopQuestionerAvgScore,
    COALESCE(tq.TotalViews, 0) as TopQuestionerTotalViews,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.CommentCount,
    pa.CreationDate,
    pa.DaysOpen,
    pa.VoteCategory,
    pa.PreviousScore,
    pa.PostSequence,
    pa.ThirdPostScore,
    ta.TagName,
    ta.Count as TagCount,
    ta.TagPopularity,
    ta.SamplePosts,
    cva.VoteCategory as VoteCategory2,
    cva.VoteOrder,
    cva.UpvoteCount,
    cva.DownvoteCount,
    CASE 
        WHEN uas.Reputation > 100000 THEN 'Elite'
        WHEN uas.Reputation > 50000 THEN 'Veteran'
        WHEN uas.Reputation > 10000 THEN 'Experienced'
        WHEN uas.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as UserTier,
    CAST(POWER(uas.Reputation, 0.5) AS INTEGER) as ReputationSquareRoot,
    MOD(uas.UserId, 100) as UserMod100,
    COALESCE(uas.Views, 0) + COALESCE(uas.UpVotes, 0) - COALESCE(uas.DownVotes, 0) as NetActivityScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = uas.UserId AND ph.CreationDate >= '2020-01-01') as RecentHistoryEvents,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory ph WHERE ph.UserId = uas.UserId AND ph.CreationDate >= '2020-01-01' AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditActivityCount,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p 
            INNER JOIN PostHistory ph ON p.Id = ph.PostId 
            WHERE ph.UserId = uas.UserId 
                AND ph.CreationDate >= '2020-01-01' 
                AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
                AND p.Score > 100 
                AND p.ViewCount > 1000
        ) THEN 1 
        ELSE 0 
    END as FeaturedEditor,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.Score > 10 AND p.ViewCount > 100 AND p.CreationDate >= '2020-01-01') as RecentHighQualityPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.PostTypeId = 2 AND p.Score > 0 AND p.CreationDate >= '2020-01-01') as RecentAnswers
FROM UserActivityStats uas
LEFT JOIN TopQuestioners tq ON uas.UserId = tq.UserId
LEFT JOIN PostAnalytics pa ON uas.UserId = pa.OwnerUserId AND pa.PostSequence <= 3
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT DISTINCT TRIM(SUBSTRING(p.Tags, n.n, CHARINDEX(' ', p.Tags + ' ', n.n) - n.n)) 
    FROM Posts p 
    CROSS JOIN (
        SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
        UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
    ) n
    WHERE p.OwnerUserId = uas.UserId AND p.Tags IS NOT NULL AND p.Tags != ''
)
LEFT JOIN ComplexVoteAnalysis cva ON cva.PostId = pa.PostId
WHERE uas.Reputation > 1000
    AND (uas.TotalPosts > 0 OR uas.BadgeCount > 0)
    AND pa.CreationDate IS NULL OR pa.CreationDate >= '2020-01-01'
ORDER BY uas.Reputation DESC, pa.CreationDate DESC
LIMIT 1000;