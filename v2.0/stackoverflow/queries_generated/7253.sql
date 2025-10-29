-- {"query": "7253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2817} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(p.Score) as MaxPostScore,
        AVG(p.Score) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as HighViewCountPosts,
        COUNT(DISTINCT CASE WHEN p.AnswerCount > 10 THEN p.Id END) as HighlyAnsweredQuestions,
        COUNT(DISTINCT pv.Id) as VotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes pv ON u.Id = pv.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionTagAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') as TagArray,
        CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) ELSE 0 END as TagCount,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        COALESCE(p.ClosedDate, '1900-01-01') as ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        DATEDIFF('day', p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile
    FROM Posts p
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2015-01-01'
    AND p.ViewCount > 0
),
BadgesWithRanking AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        b.Class,
        b.TagBased,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) as BadgeSequence,
        COUNT(*) OVER (PARTITION BY b.UserId) as TotalBadgesPerUser,
        CASE WHEN b.Class = 1 THEN 1 ELSE 0 END as GoldBadge,
        CASE WHEN b.Class = 2 THEN 1 ELSE 0 END as SilverBadge,
        CASE WHEN b.Class = 3 THEN 1 ELSE 0 END as BronzeBadge,
        DENSE_RANK() OVER (ORDER BY b.Class, b.Date) as BadgeRanking,
        DATEDIFF('day', (SELECT MIN(Date) FROM Badges WHERE UserId = b.UserId), b.Date) as DaysSinceFirstBadge
    FROM Badges b
    WHERE b.Date >= '2016-01-01'
),
PostsWithActivityStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.ParentId,
        o.DisplayName as OwnerDisplayName,
        o.Reputation as OwnerReputation,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question' 
            WHEN p.PostTypeId = 2 THEN 'Answer' 
            ELSE 'Other' 
        END as PostTypeDescription,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 10 THEN 'ModeratelyVoted'
            ELSE 'LowVoted'
        END as ScoreCategory,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        CASE WHEN p.ParentId IS NOT NULL THEN 1 ELSE 0 END as IsAnswer,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextPostScore,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousPostScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAverageScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) as PostSequence,
        p.Tags,
        CASE WHEN p.Tags IS NOT NULL THEN LENGTH(p.Tags) ELSE 0 END as TagsLength,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate
    FROM Posts p
    LEFT JOIN Users o ON p.OwnerUserId = o.Id
    WHERE p.CreationDate >= '2018-01-01'
),
FinalUserAnalysis AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Senior'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Novice'
        END as ReputationLevel,
        COALESCE(ua.TotalPosts, 0) as TotalPosts,
        COALESCE(ua.Questions, 0) as Questions,
        COALESCE(ua.Answers, 0) as Answers,
        COALESCE(ua.Comments, 0) as Comments,
        COALESCE(ua.Badges, 0) as Badges,
        CASE 
            WHEN COALESCE(ua.Badges, 0) > 50 THEN 'EliteBadgeHolder'
            WHEN COALESCE(ua.Badges, 0) > 20 THEN 'ActiveBadgeHolder'
            ELSE 'CasualBadgeHolder'
        END as BadgeIntensity,
        CASE 
            WHEN COALESCE(ua.TotalPosts, 0) > 100 THEN 'HeavyPoster'
            WHEN COALESCE(ua.TotalPosts, 0) > 50 THEN 'ModeratePoster'
            ELSE 'LightPoster'
        END as PostingIntensity,
        COALESCE(ua.MaxPostScore, 0) as MaxPostScore,
        COALESCE(ua.AvgPostScore, 0) as AvgPostScore,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as DaysSinceSignUp,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 ELSE 0 END as HasWebsite,
        CASE WHEN u.Location IS NOT NULL AND u.Location != '' THEN 1 ELSE 0 END as HasLocation,
        CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 1 ELSE 0 END as HasDetailedProfile,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        RANK() OVER (ORDER BY COALESCE(ua.TotalPosts, 0) DESC) as ActivityRank
    FROM Users u
    LEFT JOIN UserActivityStats ua ON u.Id = ua.UserId
    WHERE u.Reputation > 0
)
SELECT 
    'User Activity Analysis' as ReportName,
    COUNT(*) as TotalUsers,
    AVG(Reputation) as AvgReputation,
    SUM(CASE WHEN ReputationLevel = 'Elite' THEN 1 ELSE 0 END) as EliteUsers,
    SUM(CASE WHEN ReputationLevel = 'Senior' THEN 1 ELSE 0 END) as SeniorUsers,
    SUM(CASE WHEN PostingIntensity = 'HeavyPoster' THEN 1 ELSE 0 END) as HeavyPosters,
    AVG(TotalPosts) as AvgPostsPerUser,
    AVG(Comments) as AvgCommentsPerUser,
    AVG(Badges) as AvgBadgesPerUser,
    AVG(MaxPostScore) as AvgMaxPostScore,
    AVG(AvgPostScore) as AvgAvgPostScore,
    SUM(CASE WHEN HasWebsite = 1 THEN 1 ELSE 0 END) as UsersWithWebsite,
    SUM(CASE WHEN HasLocation = 1 THEN 1 ELSE 0 END) as UsersWithLocation,
    SUM(CASE WHEN HasDetailedProfile = 1 THEN 1 ELSE 0 END) as UsersWithDetailedProfile
FROM FinalUserAnalysis
UNION ALL
SELECT 
    'Question Analysis' as ReportName,
    COUNT(*) as TotalQuestions,
    AVG(ViewCount) as AvgViews,
    AVG(Score) as AvgScore,
    AVG(AnswerCount) as AvgAnswers,
    AVG(CommentCount) as AvgComments,
    AVG(TagCount) as AvgTagCount,
    AVG(DaysOpen) as AvgDaysOpen,
    SUM(CASE WHEN IsClosed = 1 THEN 1 ELSE 0 END) as ClosedQuestions,
    SUM(CASE WHEN IsClosed = 0 THEN 1 ELSE 0 END) as OpenQuestions,
    SUM(CASE WHEN HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) as QuestionsWithAcceptedAnswer,
    AVG(Score) as AvgScore,
    MAX(ViewCount) as MaxViews,
    MIN(ViewCount) as MinViews,
    COUNT(*) as TotalQuestions
FROM QuestionTagAnalysis
WHERE ViewCount > 100
UNION ALL
SELECT 
    'Badge Distribution' as ReportName,
    COUNT(*) as TotalBadges,
    COUNT(DISTINCT UserId) as UniqueBadgeHolders,
    AVG(DaysSinceFirstBadge) as AvgDaysBetweenBadges,
    SUM(GoldBadge) as TotalGoldBadges,
    SUM(SilverBadge) as TotalSilverBadges,
    SUM(BronzeBadge) as TotalBronzeBadges,
    AVG(BadgeSequence) as AvgBadgeSequence,
    MIN(BadgeDate) as FirstBadgeDate,
    MAX(BadgeDate) as LastBadgeDate,
    COUNT(*) as TotalBadges,
    COUNT(DISTINCT UserId) as UniqueBadgeHolders,
    AVG(DaysSinceFirstBadge) as AvgDaysBetweenBadges,
    SUM(GoldBadge) as TotalGoldBadges,
    SUM(SilverBadge) as TotalSilverBadges,
    SUM(BronzeBadge) as TotalBronzeBadges,
    AVG(BadgeSequence) as AvgBadgeSequence
FROM BadgesWithRanking
WHERE BadgeDate >= '2020-01-01'
UNION ALL
SELECT 
    'Post Activity Analysis' as ReportName,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    AVG(AnswerCount) as AvgAnswers,
    AVG(CommentCount) as AvgComments,
    AVG(DaysSinceLastActivity) as AvgDaysSinceLastActivity,
    MAX(Score) as MaxScore,
    MIN(Score) as MinScore,
    COUNT(DISTINCT OwnerUserId) as UniquePostOwners,
    COUNT(CASE WHEN PostTypeDescription = 'Question' THEN 1 END) as TotalQuestions,
    COUNT(CASE WHEN PostTypeDescription = 'Answer' THEN 1 END) as TotalAnswers,
    AVG(MovingAverageScore) as AvgMovingAverageScore,
    AVG(TagsLength) as AvgTagsLength,
    SUM(FavoriteCount) as TotalFavorites,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    AVG(AnswerCount) as AvgAnswers,
    AVG(CommentCount) as AvgComments,
    AVG(DaysSinceLastActivity) as AvgDaysSinceLastActivity,
    MAX(Score) as MaxScore,
    MIN(Score) as MinScore,
    COUNT(DISTINCT OwnerUserId) as UniquePostOwners,
    COUNT(CASE WHEN PostTypeDescription = 'Question' THEN 1 END) as TotalQuestions,
    COUNT(CASE WHEN PostTypeDescription = 'Answer' THEN 1 END) as TotalAnswers,
    AVG(MovingAverageScore) as AvgMovingAverageScore,
    AVG(TagsLength) as AvgTagsLength,
    SUM(FavoriteCount) as TotalFavorites
FROM PostsWithActivityStats
WHERE CreationDate >= '2020-01-01'
AND Score IS NOT NULL
AND ViewCount IS NOT NULL;