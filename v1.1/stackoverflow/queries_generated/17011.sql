-- {"query": "17011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 28020, "output_tokens": 27318} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        EXTRACT(YEAR FROM u.CreationDate) as JoinYear,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) as YearlyRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) as MedianPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
        AND p.CreationDate BETWEEN u.CreationDate AND COALESCE(u.LastAccessDate, CURRENT_TIMESTAMP)
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
        AND u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '365 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopAnswerers AS (
    SELECT 
        p.OwnerUserId,
        q.Id as QuestionId,
        q.Tags,
        p.Score as AnswerScore,
        p.Id as AnswerId,
        DENSE_RANK() OVER (PARTITION BY q.Id ORDER BY p.Score DESC, p.CreationDate ASC) as AnswerRank,
        CASE 
            WHEN p.Id = q.AcceptedAnswerId THEN 1 
            ELSE 0 
        END as IsAccepted,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevAnswerScore,
        FIRST_VALUE(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as FirstAnswerScore
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2 
        AND p.Score > 0
        AND p.OwnerUserId IS NOT NULL
        AND q.ClosedDate IS NULL
        AND LENGTH(COALESCE(q.Tags, '')) > 0
),
TagExperts AS (
    SELECT DISTINCT
        ta.OwnerUserId,
        TRIM(BOTH '<>' FROM tag_name.tag) as Tag,
        COUNT(*) OVER (PARTITION BY ta.OwnerUserId, TRIM(BOTH '<>' FROM tag_name.tag)) as TagAnswerCount,
        SUM(ta.AnswerScore) OVER (PARTITION BY ta.OwnerUserId, TRIM(BOTH '<>' FROM tag_name.tag)) as TagTotalScore,
        AVG(ta.AnswerScore) OVER (PARTITION BY ta.OwnerUserId, TRIM(BOTH '<>' FROM tag_name.tag)) as TagAvgScore,
        SUM(ta.IsAccepted) OVER (PARTITION BY ta.OwnerUserId, TRIM(BOTH '<>' FROM tag_name.tag)) as TagAcceptedCount
    FROM TopAnswerers ta
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(ta.Tags, 2, length(ta.Tags)-2), '><')) as tag
    ) tag_name
    WHERE ta.AnswerRank <= 3
),
EditHistory AS (
    SELECT 
        ph.PostId,
        ph.UserId as EditorId,
        COUNT(*) as EditCount,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as EditTypes,
        MIN(ph.CreationDate) as FirstEdit,
        MAX(ph.CreationDate) as LastEdit,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (7,8,9)) as RollbackCount
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
        AND ph.UserId IS NOT NULL
    GROUP BY ph.PostId, ph.UserId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.JoinYear,
    um.PostCount,
    um.QuestionCount,
    um.AnswerCount,
    ROUND(um.TotalPostScore::numeric / NULLIF(um.PostCount, 0), 2) as AvgScorePerPost,
    um.BadgeCount,
    um.GoldBadges,
    um.YearlyRank,
    COALESCE(um.MedianPostScore, 0) as MedianPostScore,
    COUNT(DISTINCT te.Tag) as ExpertTagCount,
    STRING_AGG(DISTINCT 
        CASE 
            WHEN te.TagAvgScore >= 10 AND te.TagAnswerCount >= 5 
            THEN te.Tag || ' (' || te.TagTotalScore::text || ')'
            ELSE NULL
        END, ', ' ORDER BY te.Tag
    ) FILTER (WHERE te.TagAvgScore >= 10 AND te.TagAnswerCount >= 5) as TopExpertiseTags,
    COALESCE(MAX(te.TagTotalScore), 0) as MaxTagScore,
    COUNT(DISTINCT eh.PostId) as EditedPostCount,
    COALESCE(SUM(eh.EditCount), 0) as TotalEdits,
    COALESCE(SUM(eh.RollbackCount), 0) as TotalRollbacks,
    CASE 
        WHEN um.Reputation > 10000 AND um.GoldBadges > 0 THEN 'Expert'
        WHEN um.Reputation > 5000 OR um.BadgeCount > 20 THEN 'Advanced'
        WHEN um.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END as UserLevel,
    EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.UserId = um.Id 
            AND c.Score > 5
            AND c.Text ILIKE '%welcome%to%stack%'
    ) as IsWelcomer,
    (
        SELECT COUNT(DISTINCT v.PostId)
        FROM Votes v
        INNER JOIN Posts vp ON v.PostId = vp.Id
        WHERE v.UserId = um.Id
            AND v.VoteTypeId = 2
            AND vp.OwnerUserId != um.Id
            AND vp.Score < 0
    ) as UpvotedStruggling,
    SUBSTRING(
        STRING_AGG(
            DISTINCT COALESCE(b.Name, 'Unknown'),
            ', ' ORDER BY b.Class, b.Name
        ) FROM 1 FOR 100
    ) as SampleBadges
FROM UserMetrics um
LEFT JOIN TagExperts te ON um.Id = te.OwnerUserId
LEFT JOIN EditHistory eh ON um.Id = eh.EditorId
LEFT JOIN Badges b ON um.Id = b.UserId AND b.Class <= 2
WHERE um.PostCount > 0
    AND (um.QuestionCount > 0 OR um.AnswerCount > 0)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph2
        WHERE ph2.UserId = um.Id
            AND ph2.PostHistoryTypeId = 12
            AND ph2.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
    )
GROUP BY 
    um.Id, um.DisplayName, um.Reputation, um.JoinYear, 
    um.PostCount, um.QuestionCount, um.AnswerCount,
    um.TotalPostScore, um.BadgeCount, um.GoldBadges,
    um.YearlyRank, um.MedianPostScore
HAVING COUNT(DISTINCT te.Tag) > 0 
    OR um.Reputation > 5000
ORDER BY 
    um.Reputation DESC NULLS LAST,
    COALESCE(MAX(te.TagTotalScore), 0) DESC,
    um.PostCount DESC
LIMIT 100;
