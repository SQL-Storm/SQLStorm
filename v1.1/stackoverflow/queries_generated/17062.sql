-- {"query": "17062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 147105, "output_tokens": 146609} 

WITH RECURSIVE user_activity_metrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Legendary'
            WHEN u.Reputation > 50000 THEN 'Epic'
            WHEN u.Reputation > 10000 THEN 'Trusted'
            WHEN u.Reputation > 1000 THEN 'Established'
            ELSE 'Novice'
        END AS UserTier,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class, b.Name) FILTER (WHERE b.Class = 1) AS GoldBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
post_engagement AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS UserPostRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS ViewPercentile,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, DATE_TRUNC('month', p.CreationDate)) AS MonthlyPosts,
        FIRST_VALUE(p.Title) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC NULLS LAST
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS BestPostTitle
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
        AND p.PostTypeId IN (1, 2)
        AND p.OwnerUserId IS NOT NULL
),
comment_analysis AS (
    SELECT 
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.Score > 5 THEN 1 ELSE 0 END) AS HighScoredComments,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.Score) AS MedianCommentScore
    FROM Comments c
    WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND c.UserId IS NOT NULL
    GROUP BY c.UserId
),
tag_expertise AS (
    SELECT 
        pe.OwnerUserId,
        SUBSTRING(UNNEST(string_to_array(SUBSTRING(pe.Tags, 2, LENGTH(pe.Tags)-2), '><')), 1, 50) AS Tag,
        COUNT(*) AS TagPostCount,
        AVG(pe.Score)::NUMERIC(10,2) AS AvgTagScore,
        SUM(pe.ViewCount) AS TotalTagViews
    FROM post_engagement pe
    WHERE pe.Tags IS NOT NULL 
        AND pe.Tags != ''
    GROUP BY pe.OwnerUserId, Tag
),
recursive_vote_chain AS (
    SELECT 
        v.PostId,
        v.UserId AS VoterId,
        p.OwnerUserId AS AuthorId,
        1 AS ChainLevel,
        v.VoteTypeId,
        ARRAY[v.PostId] AS PostPath
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId = 2
        AND v.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND v.UserId IS NOT NULL
        
    UNION ALL
    
    SELECT 
        v2.PostId,
        rvc.VoterId,
        p2.OwnerUserId AS AuthorId,
        rvc.ChainLevel + 1,
        v2.VoteTypeId,
        rvc.PostPath || v2.PostId
    FROM recursive_vote_chain rvc
    INNER JOIN Votes v2 ON rvc.AuthorId = v2.UserId
    INNER JOIN Posts p2 ON v2.PostId = p2.Id
    WHERE rvc.ChainLevel < 3
        AND NOT (v2.PostId = ANY(rvc.PostPath))
        AND v2.VoteTypeId = 2
        AND v2.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
)
SELECT DISTINCT ON (uam.UserId)
    uam.UserId,
    uam.DisplayName,
    COALESCE(NULLIF(TRIM(uam.Location), ''), 'Not Specified') AS Location,
    uam.UserTier,
    uam.Reputation,
    uam.JoinYear,
    COALESCE(uam.QuestionCount, 0) + COALESCE(uam.AnswerCount, 0) AS TotalPosts,
    ROUND(uam.AvgPostScore::NUMERIC, 2) AS AvgPostScore,
    CASE 
        WHEN uam.QuestionCount > 0 AND uam.AnswerCount > 0 
        THEN ROUND((uam.AnswerCount::NUMERIC / uam.QuestionCount::NUMERIC), 2)
        WHEN uam.QuestionCount = 0 AND uam.AnswerCount > 0 THEN 999.99
        ELSE 0
    END AS AnswerToQuestionRatio,
    SUBSTRING(COALESCE(uam.GoldBadges, 'None'), 1, 100) AS TopGoldBadges,
    COALESCE(ca.TotalComments, 0) AS CommentCount,
    COALESCE(ca.AvgCommentLength, 0)::INT AS AvgCommentLength,
    COALESCE(ca.MedianCommentScore, 0) AS MedianCommentScore,
    te.Tag AS TopExpertiseTag,
    te.TagPostCount AS TagPosts,
    te.AvgTagScore AS TagAvgScore,
    COUNT(DISTINCT pe.PostId) FILTER (WHERE pe.UserPostRank <= 5) AS Top5Posts,
    MAX(pe.ViewCount) AS MaxPostViews,
    ROUND(AVG(pe.ViewPercentile)::NUMERIC * 100, 1) AS AvgViewPercentile,
    SUM(CASE WHEN pe.Score > pe.PrevPostScore THEN 1 ELSE 0 END) AS ImprovingPosts,
    ROUND(AVG(EXTRACT(EPOCH FROM (pe.NextPostDate - pe.CreationDate)) / 86400)::NUMERIC, 1) AS AvgDaysBetweenPosts,
    MAX(pe.MonthlyPosts) AS MaxMonthlyPosts,
    LEFT(MAX(pe.BestPostTitle), 50) AS BestPostTitle,
    COUNT(DISTINCT rvc.PostId) AS VoteChainPosts,
    EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = uam.UserId 
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13)
            AND ph.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    ) AS HasModeratorActivity,
    CASE 
        WHEN MAX(pl.CreationDate) IS NOT NULL 
        THEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(pl.CreationDate)::DATE))
        ELSE NULL 
    END AS DaysSinceLastLink,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT vt.Name, ', ' ORDER BY vt.Name)
         FROM Votes v3
         INNER JOIN VoteTypes vt ON v3.VoteTypeId = vt.Id
         WHERE v3.UserId = uam.UserId
            AND v3.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
         LIMIT 5),
        'No Recent Votes'
    ) AS RecentVoteTypes
FROM user_activity_metrics uam
LEFT JOIN post_engagement pe ON uam.UserId = pe.OwnerUserId AND pe.UserPostRank <= 10
LEFT JOIN comment_analysis ca ON uam.UserId = ca.UserId
LEFT JOIN LATERAL (
    SELECT * FROM tag_expertise te2 
    WHERE te2.OwnerUserId = uam.UserId 
    ORDER BY te2.TagPostCount DESC, te2.AvgTagScore DESC 
    LIMIT 1
) te ON TRUE
LEFT JOIN recursive_vote_chain rvc ON uam.UserId = rvc.VoterId
LEFT JOIN PostLinks pl ON EXISTS (
    SELECT 1 FROM Posts p3 
    WHERE p3.OwnerUserId = uam.UserId 
        AND (pl.PostId = p3.Id OR pl.RelatedPostId = p3.Id)
)
WHERE uam.Reputation > 500
    OR ca.TotalComments > 100
    OR pe.ViewCount > 10000
GROUP BY 
    uam.UserId, uam.DisplayName, uam.Location, uam.UserTier, uam.Reputation,
    uam.JoinYear, uam.QuestionCount, uam.AnswerCount, uam.AvgPostScore,
    uam.GoldBadges, ca.TotalComments, ca.AvgCommentLength, ca.MedianCommentScore,
    te.Tag, te.TagPostCount, te.AvgTagScore
HAVING COUNT(DISTINCT pe.PostId) > 0 
    OR COALESCE(ca.TotalComments, 0) > 50
ORDER BY uam.UserId, uam.Reputation DESC, te.AvgTagScore DESC NULLS LAST
LIMIT 100;
