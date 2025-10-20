-- {"query": "17050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 119085, "output_tokens": 117422} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Name) AS BadgeList,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) AS MedianScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2)
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND (u.Location IS NULL OR UPPER(u.Location) LIKE '%UNITED%' OR UPPER(u.Location) LIKE '%USA%')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.Score) AS MaxTagScore,
        LAG(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY t.Count DESC) AS PrevTagPostCount,
        LEAD(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY t.Count DESC) AS NextTagPostCount,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(t.TagName, 1, 1) ORDER BY t.Count DESC) AS AlphaRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE t.Count > 100
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.Score > 0
    GROUP BY t.TagName, t.Count
),
ComplexPostHistory AS (
    SELECT 
        ph.PostId,
        p.Title,
        COUNT(DISTINCT ph.UserId) AS EditorCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 END) AS RollbackCount,
        STRING_AGG(
            CASE 
                WHEN ph.PostHistoryTypeId = 10 THEN 'Closed:' || COALESCE(ph.Comment, 'Unknown')
                WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
                WHEN ph.PostHistoryTypeId IN (12, 13) THEN 'Deleted/Undeleted'
                ELSE NULL
            END, ' -> ' ORDER BY ph.CreationDate
        ) AS PostLifecycle,
        FIRST_VALUE(ph.UserId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS OriginalAuthorId,
        LAST_VALUE(ph.UserId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastEditorId
    FROM PostHistory ph
    INNER JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId NOT IN (25, 31, 50, 52, 53)
    GROUP BY ph.PostId, p.Title
),
RecursiveAnswerChain AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.Score,
        p.OwnerUserId,
        1 AS Level,
        CAST(p.Id AS VARCHAR(1000)) AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AnswerCount > 5
    
    UNION ALL
    
    SELECT 
        a.Id,
        a.ParentId,
        a.Score,
        a.OwnerUserId,
        r.Level + 1,
        r.Path || '->' || CAST(a.Id AS VARCHAR(10))
    FROM Posts a
    INNER JOIN RecursiveAnswerChain r ON a.ParentId = r.Id
    WHERE a.PostTypeId = 2 AND r.Level < 3
)
SELECT 
    um.DisplayName,
    um.Location,
    um.Reputation,
    um.ReputationRank,
    um.QuestionCount + um.AnswerCount AS TotalPosts,
    ROUND(um.AvgPostScore::NUMERIC, 2) AS AvgScore,
    um.MedianScore,
    LEFT(um.BadgeList, 100) AS TopBadges,
    ta.TagName AS MostUsedTag,
    ta.AvgTagScore,
    ta.AlphaRank AS TagAlphaRank,
    COALESCE(cph.EditCount, 0) AS UserEditCount,
    COALESCE(cph.RollbackCount, 0) AS UserRollbackCount,
    CASE 
        WHEN um.Reputation > 10000 THEN 'Expert'
        WHEN um.Reputation > 1000 THEN 'Advanced'
        WHEN um.Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    (
        SELECT COUNT(DISTINCT v.PostId)
        FROM Votes v
        INNER JOIN Posts vp ON v.PostId = vp.Id
        WHERE v.UserId = um.Id
            AND v.VoteTypeId IN (2, 3)
            AND vp.OwnerUserId != um.Id
    ) AS VotesOnOthersPosts,
    COALESCE(
        (
            SELECT STRING_AGG(DISTINCT c.Text, ' | ' ORDER BY c.Score DESC)
            FROM Comments c
            WHERE c.UserId = um.Id
                AND c.Score > 5
                AND LENGTH(c.Text) > 50
                AND c.Text NOT LIKE '%thank%'
                AND c.Text NOT LIKE '%please%'
            LIMIT 3
        ), 
        'No high-scoring comments'
    ) AS TopComments,
    EXISTS (
        SELECT 1
        FROM RecursiveAnswerChain rac
        WHERE rac.OwnerUserId = um.Id
            AND rac.Score > 10
    ) AS HasHighScoringAnswers,
    CASE 
        WHEN ta.PrevTagPostCount > ta.NextTagPostCount * 2 THEN 'Declining Tag'
        WHEN ta.NextTagPostCount > ta.PrevTagPostCount * 2 THEN 'Growing Tag'
        ELSE 'Stable Tag'
    END AS TagTrend,
    NULLIF(
        REGEXP_REPLACE(
            LOWER(COALESCE(um.Location, '')),
            '[^a-z0-9 ]',
            '',
            'g'
        ),
        ''
    ) AS CleanedLocation
FROM UserMetrics um
LEFT JOIN LATERAL (
    SELECT ta2.*
    FROM TagAnalysis ta2
    INNER JOIN Posts p2 ON p2.Tags LIKE '%<' || ta2.TagName || '>%'
    WHERE p2.OwnerUserId = um.Id
    ORDER BY ta2.TagUsageCount DESC
    LIMIT 1
) ta ON TRUE
LEFT JOIN LATERAL (
    SELECT cph2.*
    FROM ComplexPostHistory cph2
    WHERE cph2.OriginalAuthorId = um.Id OR cph2.LastEditorId = um.Id
    ORDER BY cph2.EditCount DESC
    LIMIT 1
) cph ON TRUE
WHERE um.PostCount > 0
    AND um.Reputation > 50
    AND (ta.TagName IS NOT NULL OR um.QuestionCount > 0)
    
UNION ALL

SELECT 
    'SYSTEM_AGGREGATE' AS DisplayName,
    'Global' AS Location,
    AVG(u2.Reputation) AS Reputation,
    NULL AS ReputationRank,
    COUNT(DISTINCT p2.Id) AS TotalPosts,
    AVG(p2.Score) AS AvgScore,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p2.Score) AS MedianScore,
    NULL AS TopBadges,
    NULL AS MostUsedTag,
    NULL AS AvgTagScore,
    NULL AS TagAlphaRank,
    NULL AS UserEditCount,
    NULL AS UserRollbackCount,
    'System' AS UserLevel,
    COUNT(DISTINCT v2.Id) AS VotesOnOthersPosts,
    'System aggregate row' AS TopComments,
    NULL AS HasHighScoringAnswers,
    NULL AS TagTrend,
    NULL AS CleanedLocation
FROM Users u2
CROSS JOIN Posts p2
CROSS JOIN Votes v2
WHERE u2.Id IN (SELECT Id FROM Users ORDER BY Reputation DESC LIMIT 100)

ORDER BY 
    CASE WHEN DisplayName = 'SYSTEM_AGGREGATE' THEN 1 ELSE 0 END,
    Reputation DESC NULLS LAST,
    TotalPosts DESC NULLS LAST
LIMIT 50;
