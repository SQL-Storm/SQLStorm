WITH UserEngagement AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
        LAG(u.Reputation, 1) OVER (ORDER BY u.CreationDate) AS PrevUserReputation,
        LEAD(u.Reputation, 1) OVER (ORDER BY u.CreationDate) AS NextUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= DATE '2020-01-01'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionAnalysis AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        q.Tags,
        q.CreationDate,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.CreationDate) AS FirstAnswerTime,
        (SELECT STRING_AGG(x.ownername, ', ')
         FROM (
            SELECT DISTINCT a2.OwnerDisplayName AS ownername, a2.Score, a2.OwnerDisplayName AS od
            FROM Posts a2
            WHERE a2.ParentId = q.Id AND a2.PostTypeId = 2 AND a2.Score > 5
            ORDER BY a2.Score DESC, a2.OwnerDisplayName
         ) x
        ) AS TopAnswerers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN COUNT(a.Id) > 10 THEN 'Popular'
            WHEN COUNT(a.Id) = 0 THEN 'Unanswered'
            ELSE 'Active'
        END AS QuestionStatus,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS UserQuestionRank
    FROM Posts q
    LEFT OUTER JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= DATE '2022-01-01'
        AND (q.Tags LIKE '%<python>%' OR q.Tags LIKE '%<javascript>%' OR q.Tags LIKE '%<sql>%')
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.OwnerUserId, q.Tags, q.CreationDate, q.AcceptedAnswerId, q.ClosedDate
),
BadgeProgression AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        b.Class,
        FIRST_VALUE(b.Name) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS FirstBadge,
        LAST_VALUE(b.Name) OVER (PARTITION BY b.UserId ORDER BY b.Date ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastBadge,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class ORDER BY b.Date) AS ClassBadgeCount,
        EXTRACT(DAY FROM (b.Date - LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date))) AS DaysSincePrevBadge
    FROM Badges b
    WHERE b.Class IN (1, 2)
),
VotePatterns AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        COUNT(DISTINCT CAST(v.CreationDate AS DATE)) AS VotingDays,
        STDDEV(EXTRACT(HOUR FROM v.CreationDate)) FILTER (WHERE v.VoteTypeId IN (2,3)) AS VoteHourStdDev
    FROM Votes v
    WHERE v.CreationDate >= DATE '2022-01-01'
    GROUP BY v.PostId
    HAVING COUNT(*) >= 5
)
SELECT 
    COALESCE(ue.DisplayName, 'Anonymous') AS UserName,
    ue.Reputation,
    ue.ReputationRank,
    qa.QuestionId,
    CASE WHEN LENGTH(qa.Title) > 50 THEN SUBSTRING(qa.Title FROM 1 FOR 50) || '...' ELSE qa.Title END AS TruncatedTitle,
    qa.QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    qa.MaxAnswerScore,
    COALESCE(qa.MedianAnswerScore, 0) AS MedianAnswerScore,
    qa.QuestionStatus,
    qa.UserQuestionRank,
    EXTRACT(EPOCH FROM (qa.FirstAnswerTime - qa.CreationDate)) / 3600.0 AS HoursToFirstAnswer,
    COALESCE(vp.UpVotes, 0) - COALESCE(vp.DownVotes, 0) AS NetVotes,
    COALESCE(vp.UniqueVoters, 0) AS UniqueVoters,
    CASE 
        WHEN vp.UpVotes IS NULL OR vp.DownVotes IS NULL THEN NULL
        WHEN vp.DownVotes = 0 THEN 999.99
        ELSE ROUND(CAST(vp.UpVotes AS NUMERIC) / NULLIF(vp.DownVotes, 0), 2)
    END AS VoteRatio,
    bp.BadgeName AS LatestBadge,
    bp.ClassBadgeCount AS BadgesInClass,
    bp.DaysSincePrevBadge,
    CASE 
        WHEN ue.Reputation >= 10000 THEN 'Expert'
        WHEN ue.Reputation >= 5000 THEN 'Advanced'
        WHEN ue.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    (
        SELECT COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        WHERE ph.PostId = qa.QuestionId
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.UserId != qa.OwnerUserId
    ) AS UniqueEditors,
    CASE WHEN EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE (pl.PostId = qa.QuestionId OR pl.RelatedPostId = qa.QuestionId)
            AND pl.LinkTypeId = 3
    ) THEN TRUE ELSE FALSE END AS IsDuplicateRelated,
    COALESCE(
        (
            SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.Count DESC)
            FROM Tags t
            WHERE qa.Tags LIKE '%<' || t.TagName || '>%'
                AND t.Count > 1000
        ), 
        'No popular tags'
    ) AS PopularTags,
    GREATEST(
        ue.Reputation * 0.1,
        qa.QuestionScore * 10,
        COALESCE((COALESCE(vp.UpVotes,0) - COALESCE(vp.DownVotes,0)) * 5, 0),
        qa.ViewCount * 0.01
    ) AS CompositeScore,
    NTILE(10) OVER (ORDER BY qa.ViewCount * COALESCE(qa.QuestionScore, 1)) AS PopularityDecile
FROM QuestionAnalysis qa
LEFT OUTER JOIN UserEngagement ue ON qa.OwnerUserId = ue.Id
LEFT OUTER JOIN VotePatterns vp ON qa.QuestionId = vp.PostId
LEFT OUTER JOIN LATERAL (
    SELECT bp2.UserId, bp2.BadgeName, bp2.BadgeDate, bp2.Class, bp2.FirstBadge, bp2.LastBadge, bp2.ClassBadgeCount, bp2.DaysSincePrevBadge
    FROM BadgeProgression bp2
    WHERE bp2.UserId = qa.OwnerUserId
    ORDER BY bp2.BadgeDate DESC
    LIMIT 1
) bp ON TRUE
WHERE qa.AnswerCount > 0
    OR qa.QuestionStatus = 'Unanswered'
    OR (qa.ViewCount > 1000 AND qa.QuestionScore > 5)

UNION ALL

SELECT 
    'SYSTEM AVERAGE' AS UserName,
    CAST(AVG(u.Reputation) AS INTEGER) AS Reputation,
    NULL AS ReputationRank,
    NULL AS QuestionId,
    'Statistical Summary Row' AS TruncatedTitle,
    CAST(AVG(p.Score) AS INTEGER) AS QuestionScore,
    CAST(AVG(p.ViewCount) AS INTEGER) AS ViewCount,
    CAST(AVG(p.AnswerCount) AS INTEGER) AS AnswerCount,
    NULL AS MaxAnswerScore,
    NULL AS MedianAnswerScore,
    'Summary' AS QuestionStatus,
    NULL AS UserQuestionRank,
    NULL AS HoursToFirstAnswer,
    NULL AS NetVotes,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    NULL AS VoteRatio,
    NULL AS LatestBadge,
    NULL AS BadgesInClass,
    NULL AS DaysSincePrevBadge,
    'System' AS UserLevel,
    NULL AS UniqueEditors,
    NULL AS IsDuplicateRelated,
    NULL AS PopularTags,
    NULL AS CompositeScore,
    NULL AS PopularityDecile
FROM Users u
CROSS JOIN Posts p
CROSS JOIN Votes v
WHERE u.CreationDate >= DATE '2020-01-01'
    AND p.PostTypeId = 1
    AND v.VoteTypeId IN (2, 3)

ORDER BY CompositeScore DESC NULLS LAST, PopularityDecile ASC NULLS LAST
LIMIT 100;