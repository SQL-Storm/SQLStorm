-- {"query": "7857.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2421} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Gold'
            WHEN u.Reputation >= 1000 THEN 'Silver'
            ELSE 'Bronze'
        END as Tier,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgesEarned,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
        Tier,
        ReputationRank,
        BadgesEarned,
        TotalScore,
        AvgPostScore,
        QuestionCount,
        AnswerCount,
        TotalQuestionViews,
        ROW_NUMBER() OVER (PARTITION BY Tier ORDER BY TotalScore DESC) as RankByScore
    FROM UserStats
    WHERE Reputation > 1000
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.LastEditDate,
        p.LastActivityDate,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'HasAcceptedAnswer'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'NoAcceptedAnswer'
            ELSE 'NonQuestion'
        END as QuestionStatus,
        UPPER(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)) as CleanTags,
        STRING_TO_ARRAY(UPPER(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2)), '><') as TagArray,
        STRING_LENGTH(p.Body) as BodyLength,
        COALESCE(SUM(v.Score), 0) as VoteScore,
        COUNT(v.Id) as VoteCount,
        AVG(v.Score) as AvgVoteScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= '2022-01-01' 
    GROUP BY p.Id, p.Title, p.Body, p.Score, p.ViewCount, p.CreationDate, p.PostTypeId, p.OwnerUserId, p.ParentId, p.AnswerCount, p.CommentCount, p.Tags, p.LastEditDate, p.LastActivityDate, u.DisplayName
),
ComplexAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Body,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.ParentId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.Tags,
        pa.LastEditDate,
        pa.LastActivityDate,
        pa.OwnerName,
        pa.PostTypeDesc,
        pa.EngagementCount,
        pa.DaysSinceLastActivity,
        pa.QuestionStatus,
        pa.CleanTags,
        pa.TagArray,
        pa.BodyLength,
        pa.VoteScore,
        pa.VoteCount,
        pa.AvgVoteScore,
        CASE 
            WHEN pa.BodyLength > 1000 THEN 'Long'
            WHEN pa.BodyLength > 500 THEN 'Medium'
            WHEN pa.BodyLength > 100 THEN 'Short'
            ELSE 'VeryShort'
        END as BodyLengthCategory,
        CASE 
            WHEN pa.TagArray IS NOT NULL THEN ARRAY_LENGTH(pa.TagArray)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN pa.VoteCount > 50 THEN 'HighlyVoted'
            WHEN pa.VoteCount > 20 THEN 'ModeratelyVoted'
            WHEN pa.VoteCount > 5 THEN 'LowVoted'
            ELSE 'Unvoted'
        END as VoteLevel,
        CASE 
            WHEN pa.DaysSinceLastActivity < 30 THEN 'RecentlyActive'
            WHEN pa.DaysSinceLastActivity < 90 THEN 'ModeratelyActive'
            WHEN pa.DaysSinceLastActivity < 365 THEN 'OccasionallyActive'
            ELSE 'Inactive'
        END as ActivityLevel,
        (pa.ViewCount * 1.0 / NULLIF(pa.Score, 0)) as ViewToScoreRatio,
        CASE 
            WHEN pa.VoteScore > 100 THEN 'Trending'
            WHEN pa.VoteScore > 50 THEN 'Popular'
            WHEN pa.VoteScore > 0 THEN 'Moderate'
            WHEN pa.VoteScore < -50 THEN 'Controversial'
            ELSE 'Neutral'
        END as PopularityStatus,
        ROW_NUMBER() OVER (ORDER BY pa.VoteScore DESC) as VoteRank,
        RANK() OVER (ORDER BY pa.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as PostSequence
    FROM PostAnalysis pa
),
CombinedResults AS (
    SELECT 
        cu.UserId,
        cu.DisplayName,
        cu.Reputation,
        cu.PostCount,
        cu.CommentCount,
        cu.BadgeCount,
        cu.LastPostDate,
        cu.Tier,
        cu.ReputationRank,
        cu.BadgesEarned,
        cu.TotalScore,
        cu.AvgPostScore,
        cu.QuestionCount,
        cu.AnswerCount,
        cu.TotalQuestionViews,
        cu.RankByScore,
        ca.PostId,
        ca.Title,
        ca.Body,
        ca.Score,
        ca.ViewCount,
        ca.CreationDate,
        ca.PostTypeId,
        ca.OwnerUserId,
        ca.ParentId,
        ca.AnswerCount as PostAnswerCount,
        ca.CommentCount as PostCommentCount,
        ca.Tags,
        ca.LastEditDate,
        ca.LastActivityDate,
        ca.OwnerName,
        ca.PostTypeDesc,
        ca.EngagementCount,
        ca.DaysSinceLastActivity,
        ca.QuestionStatus,
        ca.CleanTags,
        ca.TagArray,
        ca.BodyLength,
        ca.VoteScore,
        ca.VoteCount,
        ca.AvgVoteScore,
        ca.BodyLengthCategory,
        ca.TagCount,
        ca.VoteLevel,
        ca.ActivityLevel,
        ca.ViewToScoreRatio,
        ca.PopularityStatus,
        ca.VoteRank,
        ca.ScoreRank,
        ca.PostSequence
    FROM TopUsers cu
    LEFT JOIN ComplexAnalysis ca ON cu.UserId = ca.OwnerUserId
    WHERE cu.Reputation >= 10000 OR cu.PostCount > 100
)
SELECT 
    cr.UserId,
    cr.DisplayName,
    cr.Reputation,
    cr.PostCount,
    cr.CommentCount,
    cr.BadgeCount,
    cr.LastPostDate,
    cr.Tier,
    cr.ReputationRank,
    cr.BadgesEarned,
    cr.TotalScore,
    cr.AvgPostScore,
    cr.QuestionCount,
    cr.AnswerCount,
    cr.TotalQuestionViews,
    cr.RankByScore,
    cr.PostId,
    cr.Title,
    cr.Body,
    cr.Score,
    cr.ViewCount,
    cr.CreationDate,
    cr.PostTypeId,
    cr.OwnerUserId,
    cr.ParentId,
    cr.PostAnswerCount,
    cr.PostCommentCount,
    cr.Tags,
    cr.LastEditDate,
    cr.LastActivityDate,
    cr.OwnerName,
    cr.PostTypeDesc,
    cr.EngagementCount,
    cr.DaysSinceLastActivity,
    cr.QuestionStatus,
    cr.CleanTags,
    cr.TagArray,
    cr.BodyLength,
    cr.VoteScore,
    cr.VoteCount,
    cr.AvgVoteScore,
    cr.BodyLengthCategory,
    cr.TagCount,
    cr.VoteLevel,
    cr.ActivityLevel,
    cr.ViewToScoreRatio,
    cr.PopularityStatus,
    cr.VoteRank,
    cr.ScoreRank,
    cr.PostSequence,
    CASE 
        WHEN cr.ActivityLevel = 'RecentlyActive' AND cr.VoteRank <= 10 THEN 'TopActive'
        WHEN cr.ActivityLevel = 'RecentlyActive' AND cr.PopularityStatus IN ('Trending', 'Popular') THEN 'TopPopular'
        WHEN cr.ActivityLevel = 'RecentlyActive' AND cr.QuestionStatus = 'HasAcceptedAnswer' THEN 'TopAnswered'
        WHEN cr.ActivityLevel IN ('RecentlyActive', 'ModeratelyActive') AND cr.TagCount >= 3 THEN 'MultiTagged'
        ELSE 'Standard'
    END as PostClassification,
    ROW_NUMBER() OVER (ORDER BY cr.VoteScore DESC, cr.Score DESC) as OverallRank,
    LAG(cr.VoteScore) OVER (ORDER BY cr.VoteScore DESC) - cr.VoteScore as VoteScoreDifference,
    AVG(cr.VoteScore) OVER (PARTITION BY cr.UserId) as UserAvgVoteScore,
    MAX(cr.VoteScore) OVER (PARTITION BY cr.UserId) as UserMaxVoteScore,
    STDEV(cr.VoteScore) OVER (PARTITION BY cr.UserId) as UserVoteScoreStdDev,
    NTILE(10) OVER (ORDER BY cr.VoteScore DESC) as VoteScoreDecile,
    CASE 
        WHEN cr.VoteScore > (SELECT AVG(VoteScore) FROM ComplexAnalysis) THEN 1
        ELSE 0
    END as AboveAverageVote,
    CASE 
        WHEN cr.Score > (SELECT AVG(Score) FROM ComplexAnalysis) THEN 1
        ELSE 0
    END as AboveAverageScore
FROM CombinedResults cr
WHERE cr.PostId IS NOT NULL
ORDER BY cr.VoteScore DESC, cr.Reputation DESC
LIMIT 1000;