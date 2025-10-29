-- {"query": "7320.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2571} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COUNT(DISTINCT p.Id) as PostCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN p.Id END) as OwnAnswers,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    AVG(p.Score) as AvgPostScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as EarliestPostDate,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) as UpDownVoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13) THEN ph.Id END) as ClosedReopenedCount,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,12) THEN ph.Id END) > 0 
        THEN 'Closed/Deleted'
        WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (11,13) THEN ph.Id END) > 0 
        THEN 'Reopened/Undeleted'
        ELSE 'Active'
    END as UserStatus,
    COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as HighViewPosts,
    COUNT(DISTINCT CASE WHEN p.AnswerCount > 10 THEN p.Id END) as HighAnswerQuestions,
    COUNT(DISTINCT CASE WHEN p.CommentCount > 10 THEN p.Id END) as HighCommentPosts,
    COALESCE(AVG(p.CommentCount), 0) as AvgCommentsPerPost,
    STRING_AGG(
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' 
        THEN LEFT(p.Tags, 100) || '...' 
        ELSE 'No Tags' 
        END, 
        '; '
    ) as SampleTags,
    COUNT(DISTINCT CASE WHEN p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days' THEN p.Id END) as RecentPosts,
    COUNT(DISTINCT CASE WHEN p.Score > 100 THEN p.Id END) as HighScorePosts,
    COUNT(DISTINCT CASE WHEN p.Score < -50 THEN p.Id END) as LowScorePosts,
    COUNT(DISTINCT CASE WHEN u.Reputation > 10000 THEN u.Id END) as HighRepUser,
    COUNT(DISTINCT CASE WHEN u.Reputation < 100 THEN u.Id END) as LowRepUser,
    COUNT(DISTINCT CASE WHEN p.LastActivityDate >= CURRENT_TIMESTAMP - INTERVAL '7 days' THEN p.Id END) as RecentlyActivePosts,
    COUNT(DISTINCT CASE WHEN p.LastActivityDate < CURRENT_TIMESTAMP - INTERVAL '30 days' THEN p.Id END) as InactivePosts,
    COUNT(DISTINCT CASE WHEN u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN u.Id END) as ActiveToday,
    COUNT(DISTINCT CASE WHEN u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '7 days' THEN u.Id END) as ActiveWeek,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) > 0 THEN 'Popular'
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 'Regular'
        ELSE 'Inactive'
    END as PostingFrequency,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (8,9) THEN v.Id END) as BountyVotes,
    COUNT(DISTINCT CASE WHEN p.HasAcceptedAnswer = 1 THEN p.Id END) as QWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.IsCommunityOwned = 1 THEN p.Id END) as CommunityOwnedPosts,
    ROUND(COUNT(DISTINCT v.Id) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) as VotePerPostRatio,
    ROUND(
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) * 100.0 / 
        NULLIF(COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END), 0), 
        2
    ) as UpVotePercentage,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostCountRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
    NTILE(10) OVER (ORDER BY COALESCE(SUM(p.Score), 0)) as ScoreQuartile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as PrevUserRep,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as NextUserRep,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.ParentId IS NOT NULL 
         AND p2.PostTypeId = 2
         AND p2.Score > 10), 
        0
    ) as HighScoreAnswers,
    (SELECT COUNT(*) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
     AND p3.PostTypeId = 1 
     AND p3.AcceptedAnswerId IS NOT NULL
     AND p3.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '365 days'
    ) as RecentAcceptedAnswers,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) > 0 
        THEN 'HasClosedPosts'
        WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END) > 0 
        THEN 'HasDeletedPosts'
        WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) > 0 
        THEN 'HasUndeletedPosts'
        ELSE 'NoHistory'
    END as PostHistoryStatus,
    (SELECT AVG(CommentCount) 
     FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id
    ) as AvgCommentsPerPostByUser,
    (SELECT COUNT(*) 
     FROM Tags t 
     WHERE t.TagName IN (
         SELECT TRIM(SUBSTRING(p5.Tags, POSITION('>' IN p5.Tags) + 1, LENGTH(p5.Tags) - POSITION('>' IN p5.Tags) - 1))
         FROM Posts p5 
         WHERE p5.OwnerUserId = u.Id 
         AND p5.Tags IS NOT NULL
         AND p5.Tags != ''
         AND p5.PostTypeId = 1
     )
    ) as CommonTags,
    (SELECT COUNT(*) 
     FROM Posts p6 
     WHERE p6.OwnerUserId = u.Id 
     AND p6.CreationDate >= '2022-01-01'
    ) as PostsSince2022,
    (SELECT COUNT(*) 
     FROM Posts p7 
     WHERE p7.ParentId IN (
         SELECT p8.Id 
         FROM Posts p8 
         WHERE p8.OwnerUserId = u.Id 
         AND p8.PostTypeId = 2
     )
     AND p7.PostTypeId = 1
    ) as AnswersToOwnQuestions,
    (SELECT COUNT(DISTINCT ph2.PostId) 
     FROM PostHistory ph2 
     WHERE ph2.UserId = u.Id 
     AND ph2.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days'
    ) as RecentHistoryEntries,
    (SELECT COUNT(DISTINCT p9.Id) 
     FROM Posts p9 
     WHERE p9.OwnerUserId = u.Id 
     AND p9.PostTypeId = 1
     AND (p9.AnswerCount > 0 OR p9.CommentCount > 0)
    ) as EngagingQuestions,
    (SELECT COUNT(DISTINCT p10.Id) 
     FROM Posts p10 
     WHERE p10.OwnerUserId = u.Id 
     AND p10.PostTypeId = 2
     AND p10.Score > 10
    ) as HighScoreAnswersCount,
    (SELECT AVG(LENGTH(p11.Body)) 
     FROM Posts p11 
     WHERE p11.OwnerUserId = u.Id 
     AND p11.PostTypeId IN (1,2)
    ) as AvgPostLength,
    (SELECT COUNT(DISTINCT ph3.PostId) 
     FROM PostHistory ph3 
     JOIN PostHistoryTypes pht ON ph3.PostHistoryTypeId = pht.Id
     WHERE ph3.UserId = u.Id 
     AND pht.Name IN ('Edit Title', 'Edit Body', 'Edit Tags')
    ) as EditHistoryCount,
    (SELECT STRING_AGG(DISTINCT pht2.Name, ', ') 
     FROM PostHistory ph4 
     JOIN PostHistoryTypes pht2 ON ph4.PostHistoryTypeId = pht2.Id
     WHERE ph4.UserId = u.Id 
     AND DATE(ph4.CreationDate) = CURRENT_DATE
    ) as TodayActions,
    (SELECT COUNT(DISTINCT p12.Id) 
     FROM Posts p12 
     WHERE p12.OwnerUserId = u.Id 
     AND p12.PostTypeId = 1
     AND p12.AnswerCount > 0
     AND p12.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '180 days'
    ) as RecentQuestionWithAnswers,
    (SELECT COUNT(DISTINCT b2.Id) 
     FROM Badges b2 
     WHERE b2.UserId = u.Id 
     AND b2.Date >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    ) as RecentBadges,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(p13.Tags, 1, 30), ', ') 
     FROM Posts p13 
     WHERE p13.OwnerUserId = u.Id 
     AND p13.PostTypeId = 1
     AND p13.Tags IS NOT NULL
    ) as TagExamples
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Posts p14 ON u.Id = p14.OwnerUserId AND p14.ParentId IS NOT NULL
LEFT JOIN PostHistory ph2 ON u.Id = ph2.UserId
LEFT JOIN PostHistoryTypes pht ON ph2.PostHistoryTypeId = pht.Id
WHERE u.Id >= 1
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;