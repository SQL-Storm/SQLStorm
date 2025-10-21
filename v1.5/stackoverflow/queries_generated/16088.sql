-- {"query": "16088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2040}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COALESCE(AVG(p.Score), 0) as AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) as LocationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= TIMESTAMP '2020-01-01'
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
QuestionAnswerStats AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId as QuestionOwnerId,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = q.Id 
            AND c.Score > 0) as PositiveCommentCount,
        (SELECT STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 15), '|') 
         FROM LATERAL (
             SELECT UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as TagName
         ) t) as TagList,
        COALESCE(a.AvgAnswerScore, 0) as AvgAnswerScore,
        COALESCE(a.MaxAnswerScore, 0) as MaxAnswerScore,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN q.AnswerCount > 0 AND q.AcceptedAnswerId IS NULL THEN 0
            ELSE NULL
        END as HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate))/86400.0 as DaysActive
    FROM Posts q
    LEFT OUTER JOIN (
        SELECT 
            a.ParentId,
            AVG(a.Score) as AvgAnswerScore,
            MAX(a.Score) as MaxAnswerScore,
            COUNT(*) as AnswerCnt
        FROM Posts a
        WHERE a.PostTypeId = 2
            AND a.CreationDate >= TIMESTAMP '2019-01-01'
        GROUP BY a.ParentId
    ) a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= TIMESTAMP '2019-01-01'
        AND q.Score >= 0
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as MaxBounty,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM v.CreationDate)) as MedianVoteTime
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY v.PostId
),
EditActivityRanked AS (
    SELECT 
        ph.PostId,
        ph.UserId as EditorId,
        COUNT(*) as EditCount,
        MAX(ph.CreationDate) as LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY COUNT(*) DESC) as EditorRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.UserId IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
)
SELECT 
    uem.DisplayName as UserName,
    COALESCE(uem.Location, 'N/A') as UserLocation,
    uem.Reputation,
    uem.PostCount,
    uem.BadgeCount,
    uem.LocationRank,
    qas.Title as QuestionTitle,
    qas.QuestionScore,
    qas.ViewCount,
    ROUND(qas.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    qas.TagList,
    CASE 
        WHEN qas.HasAcceptedAnswer = 1 THEN 'Accepted'
        WHEN qas.HasAcceptedAnswer = 0 THEN 'No Acceptance'
        ELSE 'Unanswered'
    END as AnswerStatus,
    COALESCE(vp.UpVotes, 0) - COALESCE(vp.DownVotes, 0) as NetVotes,
    COALESCE(vp.Favorites, 0) as FavoriteCount,
    COALESCE(vp.MaxBounty, 0) as BountyAmount,
    COALESCE(ear.EditCount, 0) as TopEditorEditCount,
    ROUND(qas.DaysActive::numeric, 1) as DaysActive,
    CASE 
        WHEN qas.ViewCount > 10000 THEN 'Viral'
        WHEN qas.ViewCount > 1000 THEN 'Popular'
        WHEN qas.ViewCount > 100 THEN 'Moderate'
        ELSE 'Low Traffic'
    END as TrafficCategory,
    (qas.QuestionScore * 0.4 + qas.AvgAnswerScore * 0.3 + 
     COALESCE(vp.UpVotes, 0) * 0.2 + 
     CASE WHEN qas.HasAcceptedAnswer = 1 THEN 10 ELSE 0 END * 0.1) as EngagementScore
FROM UserEngagementMetrics uem
INNER JOIN QuestionAnswerStats qas ON uem.Id = qas.QuestionOwnerId
LEFT OUTER JOIN VotePatterns vp ON qas.QuestionId = vp.PostId
LEFT OUTER JOIN EditActivityRanked ear ON qas.QuestionId = ear.PostId AND ear.EditorRank = 1
WHERE uem.LocationRank <= 3
    AND qas.AnswerCount IS NOT NULL
    AND (qas.ViewCount > 500 OR qas.QuestionScore > 10)
    AND EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.PostId = qas.QuestionId 
            AND c.UserId != uem.Id
    )
    AND NOT EXISTS (
        SELECT 1
        FROM Posts p2
        WHERE p2.ParentId = qas.QuestionId
            AND p2.OwnerUserId = uem.Id
            AND p2.PostTypeId = 2
    )
ORDER BY 
    CASE WHEN uem.GoldBadges > 0 THEN 1 ELSE 2 END,
    EngagementScore DESC,
    qas.ViewCount DESC NULLS LAST,
    uem.Reputation DESC
LIMIT 500;
