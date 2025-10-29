-- {"query": "7637.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2555} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgPostScore,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) as PositiveScoreTotal,
        SUM(CASE WHEN p.Score < 0 THEN p.Score ELSE 0 END) as NegativeScoreTotal,
        COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN p.Tags END) as TaggedPosts,
        STRING_AGG(DISTINCT COALESCE(u.Location, 'Unknown'), ', ') as Locations,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        QuestionCount,
        AnswerCount,
        AvgPostScore,
        PositiveScoreTotal,
        NegativeScoreTotal,
        TaggedPosts,
        Locations,
        HighViewQuestions,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as rn
    FROM UserActivityStats
    WHERE PostCount > 0 OR CommentCount > 0 OR BadgeCount > 0
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COUNT(DISTINCT p.Id) as PostsWithTag,
        AVG(p.Score) as AvgScoreForTag,
        MAX(p.Score) as MaxScoreForTag,
        MIN(p.Score) as MinScoreForTag,
        COUNT(DISTINCT p.OwnerUserId) as UniquePosters,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TagPosters,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, ' | ') as QuestionTitles
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
QuestionTagAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName as OwnerName,
        STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ') as TagArray,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as ActualAnswers,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) as CommentCountActual,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) as Downvotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 1) as AcceptedVotes,
        CASE 
            WHEN p.AnswerCount IS NULL THEN 0
            ELSE p.AnswerCount
        END as ReportedAnswers
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2015-01-01 00:00:00'
),
ComplexTagAnalysis AS (
    SELECT 
        qta.QuestionId,
        qta.Title,
        qta.Tags,
        qta.Score,
        qta.ViewCount,
        qta.CreationDate,
        qta.OwnerUserId,
        qta.OwnerName,
        qta.TagArray,
        qta.ActualAnswers,
        qta.CommentCountActual,
        qta.Upvotes,
        qta.Downvotes,
        qta.AcceptedVotes,
        qta.ReportedAnswers,
        CASE 
            WHEN qta.Score > 0 THEN 
                CASE 
                    WHEN qta.ViewCount = 0 THEN 'No Views'
                    WHEN qta.Views > 1000 THEN 'High Engagement'
                    WHEN qta.Views > 100 THEN 'Medium Engagement'
                    ELSE 'Low Engagement'
                END
            ELSE 'Negative Score'
        END as EngagementLevel,
        CASE 
            WHEN qta.Score < 0 THEN 'Downvoted'
            WHEN qta.Score = 0 THEN 'Neutral'
            WHEN qta.Score > 10 THEN 'Highly Rated'
            WHEN qta.Score > 5 THEN 'Rated'
            ELSE 'Low Rated'
        END as RatingLevel,
        DENSE_RANK() OVER (ORDER BY qta.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY qta.Score DESC) as ScoreRank,
        RANK() OVER (PARTITION BY qta.OwnerUserId ORDER BY qta.CreationDate) as UserQuestionRank,
        ROW_NUMBER() OVER (PARTITION BY qta.OwnerUserId ORDER BY qta.Score DESC) as BestQuestionRank
    FROM QuestionTagAnalysis qta
),
CombinedStats AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.LastPostDate,
        tu.LastCommentDate,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.AvgPostScore,
        tu.PositiveScoreTotal,
        tu.NegativeScoreTotal,
        tu.TaggedPosts,
        tu.Locations,
        tu.HighViewQuestions,
        CASE 
            WHEN tu.Reputation > 10000 THEN 'Elite'
            WHEN tu.Reputation > 5000 THEN 'Advanced'
            WHEN tu.Reputation > 1000 THEN 'Intermediate'
            WHEN tu.Reputation > 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as RepTier,
        CASE 
            WHEN tu.PostCount > 1000 THEN 'Veteran'
            WHEN tu.PostCount > 100 THEN 'Experienced'
            WHEN tu.PostCount > 10 THEN 'Intermediate'
            WHEN tu.PostCount > 0 THEN 'Active'
            ELSE 'Inactive'
        END as ActivityTier,
        (tu.PostCount * 0.5 + tu.CommentCount * 0.3 + tu.BadgeCount * 0.2) as UserActivityScore,
        ROW_NUMBER() OVER (ORDER BY (tu.PostCount * 0.5 + tu.CommentCount * 0.3 + tu.BadgeCount * 0.2) DESC) as ActivityRank,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 1 AND Score > 100) as HighScoreQuestions,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 2 AND Score > 100) as HighScoreAnswers,
        (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 1) as MaxQuestionScore,
        (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 1) as AvgQuestionScore,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = tu.UserId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = tu.UserId AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as ModerationCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tu.UserId AND v.VoteTypeId IN (1, 2, 3)) as VotingCount,
        STRING_AGG(ta.TagName, ', ') as PrimaryTags
    FROM TopUsers tu
    LEFT JOIN (
        SELECT t.TagName, u.Id as UserId
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE t.TagName IS NOT NULL
        GROUP BY t.TagName, u.Id
        HAVING COUNT(*) > 5
    ) ta ON tu.UserId = ta.UserId
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, tu.CommentCount, tu.BadgeCount, 
             tu.LastPostDate, tu.LastCommentDate, tu.QuestionCount, tu.AnswerCount, tu.AvgPostScore,
             tu.PositiveScoreTotal, tu.NegativeScoreTotal, tu.TaggedPosts, tu.Locations, tu.HighViewQuestions
)
SELECT 
    'Top Users' as ReportType,
    CAST(ActivityRank as VARCHAR) as Rank,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    CONCAT(RepTier, ' | ', ActivityTier) as UserStatus,
    CAST(UserActivityScore as INTEGER) as ActivityScore,
    CAST(HighScoreQuestions as INTEGER) as HighScoreQuestions,
    CAST(HighScoreAnswers as INTEGER) as HighScoreAnswers,
    MaxQuestionScore,
    AvgQuestionScore,
    EditCount,
    ModerationCount,
    VotingCount,
    Locations,
    CAST(HighViewQuestions as INTEGER) as HighViewQuestions,
    STRING_AGG(PrimaryTags, ', ') as PrimaryTags
FROM CombinedStats
WHERE ActivityRank <= 25
GROUP BY ActivityRank, DisplayName, Reputation, PostCount, CommentCount, BadgeCount, 
         RepTier, ActivityTier, UserActivityScore, HighScoreQuestions, HighScoreAnswers, 
         MaxQuestionScore, AvgQuestionScore, EditCount, ModerationCount, VotingCount, 
         Locations, HighViewQuestions, PrimaryTags
UNION ALL
SELECT 
    'Tag Statistics' as ReportType,
    CAST(TagCount as VARCHAR) as Rank,
    TagName,
    CAST(Count as VARCHAR) as Reputation,
    CAST(PostsWithTag as VARCHAR) as PostCount,
    CAST(TagCount as VARCHAR) as CommentCount,
    CAST(UniquePosters as VARCHAR) as BadgeCount,
    CONCAT('Tag Level: ', CASE WHEN TagCount > 1000 THEN 'Popular' WHEN TagCount > 100 THEN 'Moderate' ELSE 'Niche' END) as UserStatus,
    CAST(AvgScoreForTag as INTEGER) as ActivityScore,
    CAST(MaxScoreForTag as INTEGER) as HighScoreQuestions,
    CAST(MinScoreForTag as INTEGER) as HighScoreAnswers,
    NULL as MaxQuestionScore,
    NULL as AvgQuestionScore,
    NULL as EditCount,
    NULL as ModerationCount,
    NULL as VotingCount,
    TagPosters as Locations,
    CAST(0 as INTEGER) as HighViewQuestions,
    QuestionTitles as PrimaryTags
FROM TagStats
WHERE TagCount > 100
ORDER BY CASE ReportType WHEN 'Top Users' THEN 1 ELSE 2 END, 
         CASE ReportType WHEN 'Top Users' THEN ActivityRank ELSE TagCount END DESC;