-- {"query": "46032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 73408, "output_tokens": 58943} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(p.Score) as AvgPostScore,
        SUM(p.ViewCount) as TotalViews,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
TopAnswerers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) as AcceptedAnswers,
        AVG(p.Score) as AvgAcceptedScore,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as AnswererRank
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 
        AND q.AcceptedAnswerId = p.Id
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        AVG(p.Score) as AvgTagScore,
        COUNT(*) as TagPostCount
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.OwnerUserId, p.Tags
),
VotingPatterns AS (
    SELECT 
        v.UserId,
        v.VoteTypeId,
        vt.Name as VoteTypeName,
        COUNT(*) as VoteCount,
        MIN(v.CreationDate) as FirstVote,
        MAX(v.CreationDate) as LastVote
    FROM Votes v
    INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY v.UserId, v.VoteTypeId, vt.Name
),
PostEvolutionMetrics AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) as EditCount,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as PostLifespan,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as HistoryTypes
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY ph.PostId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(uem.AvgPostScore::numeric, 2) as AvgPostScore,
    uem.TotalViews,
    uem.CommentCount,
    uem.BadgeCount,
    CONCAT(uem.GoldBadges, 'G/', uem.SilverBadges, 'S/', uem.BronzeBadges, 'B') as BadgeBreakdown,
    COALESCE(ta.AcceptedAnswers, 0) as AcceptedAnswerCount,
    COALESCE(ROUND(ta.AvgAcceptedScore::numeric, 2), 0) as AvgAcceptedScore,
    COALESCE(ta.AnswererRank, 999999) as AnswererRank,
    COUNT(DISTINCT te.tag_array) as UniqueTagCount,
    ROUND(AVG(te.AvgTagScore)::numeric, 2) as AvgTagExpertiseScore,
    SUM(CASE WHEN vp.VoteTypeName = 'UpMod' THEN vp.VoteCount ELSE 0 END) as UpvotesGiven,
    SUM(CASE WHEN vp.VoteTypeName = 'DownMod' THEN vp.VoteCount ELSE 0 END) as DownvotesGiven,
    SUM(CASE WHEN vp.VoteTypeName = 'Favorite' THEN vp.VoteCount ELSE 0 END) as FavoritesGiven,
    ROUND(AVG(pem.EditCount)::numeric, 2) as AvgEditsPerPost,
    ROUND(AVG(EXTRACT(EPOCH FROM pem.PostLifespan)/86400.0)::numeric, 2) as AvgPostLifespanDays,
    CASE 
        WHEN uem.Reputation > 10000 AND COALESCE(ta.AcceptedAnswers, 0) > 50 THEN 'Elite'
        WHEN uem.Reputation > 5000 AND COALESCE(ta.AcceptedAnswers, 0) > 20 THEN 'Expert'
        WHEN uem.Reputation > 1000 THEN 'Advanced'
        ELSE 'Intermediate'
    END as UserTier
FROM UserEngagementMetrics uem
LEFT JOIN TopAnswerers ta ON uem.UserId = ta.OwnerUserId
LEFT JOIN TagExpertise te ON uem.UserId = te.OwnerUserId
LEFT JOIN VotingPatterns vp ON uem.UserId = vp.UserId
LEFT JOIN Posts p ON uem.UserId = p.OwnerUserId
LEFT JOIN PostEvolutionMetrics pem ON p.Id = pem.PostId
WHERE uem.TotalPosts >= 10
GROUP BY 
    uem.UserId,
    uem.DisplayName,
    uem.Reputation,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.AvgPostScore,
    uem.TotalViews,
    uem.CommentCount,
    uem.BadgeCount,
    uem.GoldBadges,
    uem.SilverBadges,
    uem.BronzeBadges,
    ta.AcceptedAnswers,
    ta.AvgAcceptedScore,
    ta.AnswererRank
HAVING COUNT(DISTINCT te.tag_array) > 3
ORDER BY 
    uem.Reputation DESC,
    COALESCE(ta.AcceptedAnswers, 0) DESC,
    uem.TotalViews DESC
LIMIT 500;
