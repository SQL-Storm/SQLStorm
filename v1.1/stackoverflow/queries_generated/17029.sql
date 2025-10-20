-- {"query": "17029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 70050, "output_tokens": 68762} 

WITH UserEngagement AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        AVG(p.Score) as AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostCountRank,
        LAG(u.Reputation, 1) OVER (ORDER BY u.CreationDate) as PrevUserReputation,
        LEAD(u.Reputation, 1) OVER (ORDER BY u.CreationDate) as NextUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionAnalysis AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        q.Tags,
        q.CreationDate,
        COUNT(DISTINCT a.Id) as AnswerCount,
        MAX(a.Score) as MaxAnswerScore,
        MIN(a.CreationDate) as FirstAnswerTime,
        STRING_AGG(DISTINCT a.OwnerDisplayName, ', ' ORDER BY a.Score DESC) FILTER (WHERE a.Score > 5) as TopAnswerers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as MedianAnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN COUNT(a.Id) > 10 THEN 'Popular'
            WHEN COUNT(a.Id) = 0 THEN 'Unanswered'
            ELSE 'Active'
        END as QuestionStatus,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) as UserQuestionRank
    FROM Posts q
    LEFT OUTER JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= '2022-01-01'
        AND (q.Tags LIKE '%<python>%' OR q.Tags LIKE '%<javascript>%' OR q.Tags LIKE '%<sql>%')
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.OwnerUserId, q.Tags, q.CreationDate, q.AcceptedAnswerId, q.ClosedDate
),
BadgeProgression AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        b.Class,
        FIRST_VALUE(b.Name) OVER (PARTITION BY b.UserId ORDER BY b.Date) as FirstBadge,
        LAST_VALUE(b.Name) OVER (PARTITION BY b.UserId ORDER BY b.Date RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as LastBadge,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) as ClassBadgeCount,
        EXTRACT(DAY FROM b.Date - LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date)) as DaysSincePrevBadge
    FROM Badges b
    WHERE b.Class IN (1, 2)
),
VotePatterns AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        COUNT(DISTINCT v.UserId) as UniqueVoters,
        COUNT(DISTINCT DATE(v.CreationDate)) as VotingDays,
        STDDEV(CASE WHEN v.VoteTypeId IN (2,3) THEN EXTRACT(HOUR FROM v.CreationDate) END) as VoteHourStdDev
    FROM Votes v
    WHERE v.CreationDate >= '2022-01-01'
    GROUP BY v.PostId
    HAVING COUNT(*) >= 5
)
SELECT 
    COALESCE(ue.DisplayName, 'Anonymous') as UserName,
    ue.Reputation,
    ue.ReputationRank,
    qa.QuestionId,
    SUBSTRING(qa.Title, 1, 50) || CASE WHEN LENGTH(qa.Title) > 50 THEN '...' ELSE '' END as TruncatedTitle,
    qa.QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    qa.MaxAnswerScore,
    COALESCE(qa.MedianAnswerScore, 0) as MedianAnswerScore,
    qa.QuestionStatus,
    qa.UserQuestionRank,
    EXTRACT(EPOCH FROM (qa.FirstAnswerTime - qa.CreationDate)) / 3600.0 as HoursToFirstAnswer,
    COALESCE(vp.UpVotes, 0) - COALESCE(vp.DownVotes, 0) as NetVotes,
    COALESCE(vp.UniqueVoters, 0) as UniqueVoters,
    CASE 
        WHEN vp.UpVotes IS NULL OR vp.DownVotes IS NULL THEN NULL
        WHEN vp.DownVotes = 0 THEN 999.99
        ELSE ROUND(vp.UpVotes::numeric / NULLIF(vp.DownVotes, 0), 2)
    END as VoteRatio,
    bp.BadgeName as LatestBadge,
    bp.ClassBadgeCount as BadgesInClass,
    bp.DaysSincePrevBadge,
    CASE 
        WHEN ue.Reputation >= 10000 THEN 'Expert'
        WHEN ue.Reputation >= 5000 THEN 'Advanced'
        WHEN ue.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as UserLevel,
    (
        SELECT COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        WHERE ph.PostId = qa.QuestionId
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.UserId != qa.OwnerUserId
    ) as UniqueEditors,
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE (pl.PostId = qa.QuestionId OR pl.RelatedPostId = qa.QuestionId)
            AND pl.LinkTypeId = 3
    ) as IsDuplicateRelated,
    COALESCE(
        (
            SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.Count DESC)
            FROM Tags t
            WHERE qa.Tags LIKE '%<' || t.TagName || '>%'
                AND t.Count > 1000
        ), 
        'No popular tags'
    ) as PopularTags,
    GREATEST(
        ue.Reputation * 0.1,
        qa.QuestionScore * 10,
        COALESCE(vp.NetVotes * 5, 0),
        qa.ViewCount * 0.01
    ) as CompositeScore,
    NTILE(10) OVER (ORDER BY qa.ViewCount * COALESCE(qa.QuestionScore, 1)) as PopularityDecile
FROM QuestionAnalysis qa
LEFT OUTER JOIN UserEngagement ue ON qa.OwnerUserId = ue.Id
LEFT OUTER JOIN VotePatterns vp ON qa.QuestionId = vp.PostId
LEFT OUTER JOIN LATERAL (
    SELECT *
    FROM BadgeProgression bp2
    WHERE bp2.UserId = qa.OwnerUserId
    ORDER BY bp2.BadgeDate DESC
    LIMIT 1
) bp ON true
WHERE qa.AnswerCount > 0
    OR qa.QuestionStatus = 'Unanswered'
    OR (qa.ViewCount > 1000 AND qa.QuestionScore > 5)

UNION ALL

SELECT 
    'SYSTEM AVERAGE' as UserName,
    AVG(u.Reputation)::int as Reputation,
    NULL as ReputationRank,
    NULL as QuestionId,
    'Statistical Summary Row' as TruncatedTitle,
    AVG(p.Score)::int as QuestionScore,
    AVG(p.ViewCount)::int as ViewCount,
    AVG(p.AnswerCount)::int as AnswerCount,
    NULL as MaxAnswerScore,
    NULL as MedianAnswerScore,
    'Summary' as QuestionStatus,
    NULL as UserQuestionRank,
    NULL as HoursToFirstAnswer,
    NULL as NetVotes,
    COUNT(DISTINCT v.UserId)::int as UniqueVoters,
    NULL as VoteRatio,
    NULL as LatestBadge,
    NULL as BadgesInClass,
    NULL as DaysSincePrevBadge,
    'System' as UserLevel,
    NULL as UniqueEditors,
    NULL as IsDuplicateRelated,
    NULL as PopularTags,
    NULL as CompositeScore,
    NULL as PopularityDecile
FROM Users u
CROSS JOIN Posts p
CROSS JOIN Votes v
WHERE u.CreationDate >= '2020-01-01'
    AND p.PostTypeId = 1
    AND v.VoteTypeId IN (2, 3)

ORDER BY CompositeScore DESC NULLS LAST, PopularityDecile ASC NULLS LAST
LIMIT 100;
