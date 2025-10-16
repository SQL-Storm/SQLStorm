-- {"query": "16009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 23350, "output_tokens": 21754} 

WITH UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM AGE(u.LastAccessDate, u.CreationDate)) * 12 + 
        EXTRACT(MONTH FROM AGE(u.LastAccessDate, u.CreationDate)) AS MonthsActive,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY u.Reputation) AS ReputationDecile
    FROM Users u
    WHERE u.Reputation > 1000 
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'HasAcceptedAnswer'
            WHEN p.PostTypeId = 2 AND ap.AcceptedAnswerId = p.Id THEN 'IsAcceptedAnswer'
            ELSE 'NoAcceptance'
        END AS AcceptanceStatus,
        COALESCE(LENGTH(p.Body) - LENGTH(REPLACE(p.Body, ' ', '')), 0) AS WordCount,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate))/3600 AS HoursActive,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS DirectCommentCount,
        (SELECT AVG(v.CreationDate - p.CreationDate) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)
        ) AS AvgVoteDelay
    FROM Posts p
    LEFT JOIN Posts ap ON p.ParentId = ap.Id
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
),
TagCoOccurrence AS (
    SELECT 
        t1.tag AS Tag1,
        t2.tag AS Tag2,
        COUNT(*) AS CoOccurrenceCount,
        AVG(p.Score) AS AvgScore
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t1(tag)
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t2(tag)
    WHERE p.PostTypeId = 1 
        AND t1.tag < t2.tag
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY t1.tag, t2.tag
    HAVING COUNT(*) >= 50
),
BadgeProgress AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) AS BadgeNames,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate,
        PERCENT_RANK() OVER (PARTITION BY b.Class ORDER BY COUNT(*)) AS ClassPercentile
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY b.UserId, b.Class
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationRank,
    uam.MonthsActive,
    ROUND(AVG(pp.Score)::numeric, 2) AS AvgPostScore,
    ROUND(AVG(COALESCE(pp.ViewCount, 0))::numeric, 2) AS AvgViews,
    COUNT(DISTINCT CASE WHEN pp.PostTypeId = 1 THEN pp.PostId END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN pp.PostTypeId = 2 THEN pp.PostId END) AS AnswerCount,
    COUNT(DISTINCT CASE WHEN pp.AcceptanceStatus = 'IsAcceptedAnswer' THEN pp.PostId END) AS AcceptedAnswerCount,
    ROUND(AVG(CASE WHEN pp.PostTypeId = 1 THEN pp.AnswerCount END)::numeric, 2) AS AvgAnswersPerQuestion,
    COALESCE(SUM(bp_gold.BadgeCount), 0) AS GoldBadges,
    COALESCE(SUM(bp_silver.BadgeCount), 0) AS SilverBadges,
    COALESCE(SUM(bp_bronze.BadgeCount), 0) AS BronzeBadges,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
    ROUND(AVG(pp.WordCount)::numeric, 2) AS AvgWordCount,
    ROUND(AVG(pp.HoursActive)::numeric, 2) AS AvgPostLifespanHours,
    STRING_AGG(DISTINCT SUBSTRING(tag_data.tag, 1, 20), '|' ORDER BY SUBSTRING(tag_data.tag, 1, 20)) 
        FILTER (WHERE tag_rank <= 5) AS Top5Tags,
    CASE 
        WHEN uam.ReputationDecile >= 9 THEN 'Elite'
        WHEN uam.ReputationDecile >= 7 THEN 'Advanced'
        WHEN uam.ReputationDecile >= 5 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    EXISTS(
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = uam.Id 
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    ) AS HasRecentEdits
FROM UserActivityMetrics uam
INNER JOIN PostPerformance pp ON pp.OwnerUserId = uam.Id
LEFT JOIN BadgeProgress bp_gold ON bp_gold.UserId = uam.Id AND bp_gold.Class = 1
LEFT JOIN BadgeProgress bp_silver ON bp_silver.UserId = uam.Id AND bp_silver.Class = 2
LEFT JOIN BadgeProgress bp_bronze ON bp_bronze.UserId = uam.Id AND bp_bronze.Class = 3
LEFT JOIN PostLinks pl ON pl.PostId = pp.PostId AND pl.LinkTypeId = 1
LEFT JOIN LATERAL (
    SELECT 
        t.tag,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Posts p2
    CROSS JOIN LATERAL unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS t(tag)
    WHERE p2.OwnerUserId = uam.Id AND p2.PostTypeId = 1
    GROUP BY t.tag
) tag_data ON true
WHERE pp.Score IS NOT NULL
    AND uam.MonthsActive > 6
    AND (pp.ViewCount > 100 OR pp.PostTypeId = 2)
GROUP BY 
    uam.Id,
    uam.DisplayName, 
    uam.Reputation, 
    uam.ReputationRank, 
    uam.MonthsActive,
    uam.ReputationDecile
HAVING COUNT(DISTINCT pp.PostId) >= 10
    AND AVG(pp.Score) >= 2.0
ORDER BY 
    uam.Reputation DESC,
    COUNT(DISTINCT pp.PostId) DESC
LIMIT 100;
