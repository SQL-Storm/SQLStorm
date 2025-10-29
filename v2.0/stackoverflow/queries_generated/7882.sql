-- {"query": "7882.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1576} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(AVG(p.Score) OVER (PARTITION BY u.Id), 0) as AvgPostScore,
    COALESCE(MAX(p.CreationDate) OVER (PARTITION BY u.Id), u.CreationDate) as LastPostDate,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id), 0) as QuestionsPosted,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id), 0) as AnswersPosted,
    COALESCE(CONCAT('Score: ', 
        CASE WHEN SUM(p.Score) OVER (PARTITION BY u.Id) > 1000 THEN 'High' 
             WHEN SUM(p.Score) OVER (PARTITION BY u.Id) > 500 THEN 'Medium' 
             ELSE 'Low' END,
        ', Posts: ', 
        COUNT(DISTINCT p.Id) OVER (PARTITION BY u.Id),
        ', Badges: ', 
        COUNT(DISTINCT b.Id) OVER (PARTITION BY u.Id)
    ), 'No activity') as UserPerformanceSummary,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as PrevUserRep,
    CASE 
        WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN u.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationCategory,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.CreationDate > DATEADD(MONTH, -6, GETDATE())), 
        0
    ) as RecentPosts,
    COALESCE(
        (SELECT STRING_AGG(t.TagName, ', ') 
         FROM Posts p3 
         JOIN STRING_SPLIT(p3.Tags, '><') AS tag ON tag.value != ''
         JOIN Tags t ON t.TagName = TRIM(tag.value, '<>')
         WHERE p3.OwnerUserId = u.Id 
         AND p3.PostTypeId = 1
         GROUP BY u.Id), 
        'No tags'
    ) as UserTags,
    COALESCE(
        (SELECT TOP 1 pt.Name 
         FROM Posts p4 
         JOIN PostTypes pt ON pt.Id = p4.PostTypeId
         WHERE p4.OwnerUserId = u.Id 
         ORDER BY p4.CreationDate DESC), 
        'No posts'
    ) as LatestPostType,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = u.Id) as CommentCount,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.Score < -5) 
        THEN 'Flagged for low quality'
        WHEN EXISTS (SELECT 1 FROM Posts p6 WHERE p6.OwnerUserId = u.Id AND p6.Score > 100) 
        THEN 'Flagged for high quality'
        ELSE 'Standard user'
    END as QualityIndicator,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as Ranking,
    NTILE(4) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as Quartile,
    COALESCE(
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         WHERE v.UserId = u.Id), 
        u.CreationDate
    ) as LastVoteDate,
    CASE 
        WHEN u.Views = 0 THEN 'No profile views'
        WHEN u.Views > 1000 THEN 'High visibility'
        WHEN u.Views > 500 THEN 'Medium visibility'
        ELSE 'Low visibility'
    END as VisibilityLevel,
    (
        SELECT COUNT(DISTINCT ph.Id) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id
        AND ph.CreationDate > DATEADD(YEAR, -1, GETDATE())
    ) as RecentEdits,
    NULLIF(
        COALESCE(
            (SELECT AVG(p7.Score) 
             FROM Posts p7 
             WHERE p7.OwnerUserId = u.Id 
             AND p7.PostTypeId = 1), 
            0
        ), 
        0
    ) as QuestionAvgScore,
    COALESCE(
        (SELECT COUNT(DISTINCT bh.Id) 
         FROM Badges bh 
         WHERE bh.UserId = u.Id 
         AND bh.Date > DATEADD(MONTH, -3, GETDATE())), 
        0
    ) as RecentBadges,
    CASE 
        WHEN u.EmailHash IS NOT NULL THEN 'Email verified'
        ELSE 'Email unverified'
    END as EmailStatus
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
WHERE u.CreationDate > DATEADD(YEAR, -2, GETDATE())
  AND (
    (u.Reputation > 1000 AND u.Views > 100) 
    OR EXISTS (SELECT 1 FROM Badges bg WHERE bg.UserId = u.Id AND bg.Class = 1)
    OR EXISTS (SELECT 1 FROM Posts po WHERE po.OwnerUserId = u.Id AND po.Score > 50)
  )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.EmailHash
HAVING 
    COUNT(DISTINCT p.Id) >= 1
    OR COUNT(DISTINCT b.Id) >= 1
    OR EXISTS (
        SELECT 1 FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.CreationDate > DATEADD(MONTH, -12, GETDATE())
    )
ORDER BY 
    COALESCE(SUM(p.Score), 0) DESC,
    COUNT(DISTINCT p.Id) DESC,
    u.CreationDate ASC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;