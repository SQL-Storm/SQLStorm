-- {"query": "16073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 172790, "output_tokens": 159782} 

WITH RECURSIVE user_engagement_metrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 AND p.ViewCount IS NOT NULL THEN p.ViewCount END) as AvgQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
        AND (u.Reputation > 100 OR u.UpVotes > 10)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
badge_rankings AS (
    SELECT 
        b.UserId,
        COUNT(*) as TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') as GoldBadgeNames,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as BadgeRank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM b.Date) ORDER BY COUNT(*) DESC) as YearlyBadgeRank
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2019-01-01'
    GROUP BY b.UserId
),
post_interaction_depth AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId,
        p.Score as PostScore,
        p.ViewCount,
        p.Title,
        COALESCE(p.AnswerCount, 0) as DirectAnswers,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownvoteCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as OutgoingLinks,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id) as IncomingLinks,
        (SELECT MAX(CreationDate) FROM Comments c WHERE c.PostId = p.Id) as LastCommentDate,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Unanswered'
        END as PostStatus,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostScore,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostDate,
        SUM(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as CumulativeUserScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= TIMESTAMP '2021-01-01'
        AND (p.Score IS NULL OR p.Score >= -5)
),
tag_performance AS (
    SELECT 
        UNNEST(string_to_array(NULLIF(substring(p.Tags, 2, length(p.Tags)-2), ''), '><')) as TagName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) as MedianViews,
        MAX(p.ViewCount) as MaxViews,
        COUNT(DISTINCT p.OwnerUserId) as UniqueAskers
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 0
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
answer_acceptance_analysis AS (
    SELECT 
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwner,
        q.AcceptedAnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer,
        EXTRACT(EPOCH FROM (COALESCE(q.LastEditDate, q.CreationDate) - q.CreationDate))/86400 as DaysActive,
        COUNT(*) OVER (PARTITION BY q.Id) as TotalAnswersForQuestion,
        RANK() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRankByScore
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.CreationDate >= TIMESTAMP '2020-06-01'
)
SELECT 
    uem.UserId,
    uem.DisplayName,
    COALESCE(uem.Reputation, 0) as Reputation,
    ROUND(uem.TotalPostScore::numeric / NULLIF(uem.TotalPosts, 0), 2) as AvgScorePerPost,
    CASE 
        WHEN br.TotalBadges >= 100 THEN 'Elite'
        WHEN br.TotalBadges >= 50 THEN 'Expert'
        WHEN br.TotalBadges >= 20 THEN 'Intermediate'
        WHEN br.TotalBadges >= 5 THEN 'Beginner'
        ELSE 'Novice'
    END as UserTier,
    br.GoldBadges || 'G/' || br.SilverBadges || 'S/' || br.BronzeBadges || 'B' as BadgeBreakdown,
    COALESCE(br.GoldBadgeNames, 'None') as GoldBadges,
    pid.PostStatus,
    ROUND(AVG(pid.ViewCount)::numeric, 0) as AvgViews,
    ROUND(AVG(pid.CommentCount)::numeric, 1) as AvgCommentsPerPost,
    SUM(pid.UpvoteCount) - SUM(pid.DownvoteCount) as NetVotes,
    COUNT(DISTINCT CASE WHEN pid.PostScore > pid.PreviousPostScore THEN pid.PostId END)::float / 
        NULLIF(COUNT(DISTINCT pid.PostId), 0) as ImprovementRate,
    MAX(pid.CumulativeUserScore) as MaxCumulativeScore,
    STRING_AGG(DISTINCT SUBSTRING(pid.Title, 1, 50), ' | ' ORDER BY SUBSTRING(pid.Title, 1, 50)) FILTER (WHERE pid.PostScore >= 10) as TopPostTitles,
    (SELECT COUNT(*) 
     FROM answer_acceptance_analysis aaa 
     WHERE aaa.AnswerOwner = uem.UserId 
       AND aaa.AcceptedAnswerId IS NOT NULL 
       AND aaa.AnswerRankByScore = 1) as AcceptedAnswersCount,
    ROUND(AVG(CASE WHEN aaa.AnswerRankByScore = 1 THEN aaa.HoursToAnswer END)::numeric, 2) as AvgHoursToTopAnswer,
    EXTRACT(DAYS FROM (MAX(pid.LastCommentDate) - uem.UserCreationDate)) as DaysSinceLastActivity,
    br.BadgeRank,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM post_interaction_depth pid2 
            WHERE pid2.OwnerUserId = uem.UserId 
              AND pid2.IncomingLinks > 5
        ) THEN 'Influential'
        ELSE 'Regular'
    END as InfluenceStatus
FROM user_engagement_metrics uem
LEFT JOIN badge_rankings br ON uem.UserId = br.UserId
LEFT JOIN post_interaction_depth pid ON uem.UserId = pid.OwnerUserId
LEFT JOIN answer_acceptance_analysis aaa ON uem.UserId = aaa.AnswerOwner
WHERE uem.TotalPosts > 0
    AND (br.TotalBadges IS NULL OR br.TotalBadges >= 1)
    AND EXISTS (
        SELECT 1 FROM Posts p2
        WHERE p2.OwnerUserId = uem.UserId
            AND p2.Score > 0
    )
GROUP BY 
    uem.UserId, uem.DisplayName, uem.Reputation, uem.TotalPostScore, uem.TotalPosts,
    br.TotalBadges, br.GoldBadges, br.SilverBadges, br.BronzeBadges, 
    br.GoldBadgeNames, br.BadgeRank, pid.PostStatus, uem.UserCreationDate
HAVING COUNT(DISTINCT pid.PostId) >= 2
    AND SUM(pid.UpvoteCount) > SUM(pid.DownvoteCount)
ORDER BY 
    MaxCumulativeScore DESC NULLS LAST,
    br.BadgeRank ASC NULLS LAST,
    NetVotes DESC
LIMIT 500;
