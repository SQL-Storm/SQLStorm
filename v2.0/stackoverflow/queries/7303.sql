-- {"query": "7303.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3027}
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationPercentile,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY u.Id) as RowNumInReputationBucket
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.AcceptedAnswerId IS NULL THEN 'Answered Question (No Accept)'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered Question (With Accept)'
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'High Scoring Answer'
            WHEN p.PostTypeId = 2 THEN 'Low Scoring Answer'
            ELSE 'Other'
        END as PostClassification,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate))/86400 AS INTEGER) as DaysSincePost,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly Rated'
            WHEN p.Score >= 10 THEN 'Moderately Rated'
            WHEN p.Score >= 1 THEN 'Low Rated'
            ELSE 'No Votes'
        END as RatingLevel,
        CASE WHEN p.Tags IS NOT NULL AND CHAR_LENGTH(p.Tags) > 10 THEN 'Tagged' ELSE 'Untagged' END as TagStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRankInUser,
        RANK() OVER (ORDER BY p.Score DESC) as PostScoreRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate) as PostCreationRank,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsPerUser,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvgQuestion'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAvgQuestion'
            ELSE 'AvgQuestion'
        END as QuestionPerformance
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT v.Id) as TotalVotes,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) as UpDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownVotes,
        COALESCE(MAX(v.CreationDate), TIMESTAMP '1900-01-01') as LastVoteDate,
        AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) as AvgVotesPerPost,
        RANK() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) as CommentRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) as VoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT v.Id) DESC) as VoteDenseRank,
        PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT v.Id)) as VotePercentile
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName
),
PostTagAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Tags,
        -- emulate splitting tags like '<tag1><tag2>' into rows: many dialects lack STRING_SPLIT/TRIM(BOTH)
        -- produce original tags string as TagArray for portability (caller can split further)
        p.Tags as TagArray,
        CASE 
            WHEN POSITION('sql' IN LOWER(p.Title)) > 0 OR POSITION('sql' IN LOWER(p.Tags)) > 0 THEN 'SQL Related'
            WHEN POSITION('javascript' IN LOWER(p.Title)) > 0 OR POSITION('javascript' IN LOWER(p.Tags)) > 0 THEN 'JavaScript Related'
            WHEN POSITION('python' IN LOWER(p.Title)) > 0 OR POSITION('python' IN LOWER(p.Tags)) > 0 THEN 'Python Related'
            ELSE 'Other'
        END as TechCategory,
        CASE 
            WHEN CHAR_LENGTH(p.Tags) > 50 THEN 'Many Tags'
            WHEN CHAR_LENGTH(p.Tags) > 20 THEN 'Moderate Tags'
            WHEN CHAR_LENGTH(p.Tags) > 5 THEN 'Few Tags'
            ELSE 'No Tags'
        END as TagDensity,
        ROW_NUMBER() OVER (ORDER BY CHAR_LENGTH(p.Tags) DESC) as TagLengthRank,
        DENSE_RANK() OVER (ORDER BY CHAR_LENGTH(p.Tags) DESC) as TagLengthDenseRank
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
),
ComplexQueryResults AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.Badges,
        us.ReputationLevel,
        us.TotalQuestionScore,
        us.TotalAnswerScore,
        us.AvgAnswerScore,
        us.ReputationPercentile,
        us.RowNumInReputationBucket,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.PostTypeId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.PostClassification,
        pa.DaysSincePost,
        pa.RatingLevel,
        pa.TagStatus,
        pa.PostRankInUser,
        pa.PostScoreRank,
        pa.PostCreationRank,
        pa.PrevScore,
        pa.NextScore,
        pa.AvgScorePerUser,
        pa.TotalPostsPerUser,
        pa.ScoreQuartile,
        pa.QuestionPerformance,
        ue.TotalComments,
        ue.TotalVotes,
        ue.UpDownVotes,
        ue.UpVotes,
        ue.DownVotes,
        ue.LastVoteDate,
        ue.AvgVotesPerPost,
        ue.CommentRank,
        ue.VoteRank,
        ue.VoteDenseRank,
        ue.VotePercentile,
        pta.TagArray,
        pta.TechCategory,
        pta.TagDensity,
        pta.TagLengthRank,
        pta.TagLengthDenseRank,
        CASE 
            WHEN us.TotalPosts > 10 OR us.TotalQuestionScore > 100 OR us.TotalAnswerScore > 100 THEN 'Highly Active'
            WHEN us.TotalPosts > 5 OR us.TotalQuestionScore > 50 OR us.TotalAnswerScore > 50 THEN 'Moderately Active'
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN us.Badges > 10 AND us.Reputation > 5000 THEN 'Active Community Member'
            WHEN us.Badges > 5 AND us.Reputation > 1000 THEN 'Regular Contributor'
            ELSE 'New Contributor'
        END as ContributionLevel,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - us.LastPostDate))/86400 AS INTEGER) as DaysSinceLastPost,
        CASE 
            WHEN us.Reputation > 5000 AND us.TotalPosts > 100 THEN 'Veteran Contributor'
            WHEN us.Questions > 50 AND us.Answers > 100 THEN 'Expert User'
            ELSE 'Regular User'
        END as UserStatus,
        (
            (us.TotalQuestionScore + us.TotalAnswerScore) * 
            CASE WHEN pa.Score > 0 THEN 1.0 ELSE 0.5 END *
            (1.0 + (us.Badges * 0.01)) *
            (1.0 + (us.Reputation / 10000.0))
        ) as CombinedMetric,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = us.UserId AND p2.Score > pa.Score) as HigherScorePosts,
        CASE WHEN EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = us.UserId AND p3.PostTypeId = 1 AND p3.Score > 100) THEN 'Has High Score Question' ELSE 'No High Score Question' END as HighScoreQuestionIndicator
    FROM UserStats us
    INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    LEFT JOIN UserEngagement ue ON us.UserId = ue.UserId
    LEFT JOIN PostTagAnalysis pta ON pa.PostId = pta.PostId
    WHERE 
        (us.Reputation > 1000 OR us.Badges > 1) AND
        pa.Score > -50 AND
        pa.Score < 1000 AND
        pa.DaysSincePost < 365 AND
        pa.PostClassification IN ('Answered Question (With Accept)', 'Answered Question (No Accept)', 'High Scoring Answer', 'Unanswered Question')
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    Badges,
    ReputationLevel,
    TotalQuestionScore,
    TotalAnswerScore,
    AvgAnswerScore,
    ReputationPercentile,
    RowNumInReputationBucket,
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    PostTypeId,
    AnswerCount,
    CommentCount,
    PostClassification,
    DaysSincePost,
    RatingLevel,
    TagStatus,
    PostRankInUser,
    PostScoreRank,
    PostCreationRank,
    PrevScore,
    NextScore,
    AvgScorePerUser,
    TotalPostsPerUser,
    ScoreQuartile,
    QuestionPerformance,
    TotalComments,
    TotalVotes,
    UpDownVotes,
    UpVotes,
    DownVotes,
    LastVoteDate,
    AvgVotesPerPost,
    CommentRank,
    VoteRank,
    VoteDenseRank,
    VotePercentile,
    TagArray,
    TechCategory,
    TagDensity,
    TagLengthRank,
    TagLengthDenseRank,
    ActivityLevel,
    ContributionLevel,
    DaysSinceLastPost,
    UserStatus,
    CombinedMetric,
    HigherScorePosts,
    HighScoreQuestionIndicator,
    CASE 
        WHEN CombinedMetric > 1000 THEN 'Elite Performer'
        WHEN CombinedMetric > 500 THEN 'Strong Performer'
        WHEN CombinedMetric > 250 THEN 'Moderate Performer'
        ELSE 'Basic Performer'
    END as PerformanceTier,
    CONCAT(DisplayName, ' (', ReputationLevel, ') - ', 
           CASE WHEN Questions > 0 THEN CONCAT('Q:', Questions, ',A:', Answers) ELSE 'No Posts' END) as UserStatusSummary,
    ROUND((Reputation * 1.0 / NULLIF(TotalPosts, 0)), 2) as ReputationPerPost,
    ROUND((TotalQuestionScore * 1.0 / NULLIF(Questions, 0)), 2) as AvgQuestionScore,
    ROUND((TotalAnswerScore * 1.0 / NULLIF(Answers, 0)), 2) as AvgAnswerScore,
    ROW_NUMBER() OVER (PARTITION BY ReputationLevel ORDER BY CombinedMetric DESC) as LevelRankingWithinTier,
    COALESCE(LastVoteDate, CreationDate) as EffectiveLastActivityDate
FROM ComplexQueryResults
WHERE 
    CombinedMetric > 50 OR 
    (Reputation > 1000 AND TotalPosts > 10) OR
    (Badges > 5 AND TotalComments > 10) OR
    (QuestionPerformance = 'AboveAvgQuestion' AND TotalQuestionScore > 100)
ORDER BY 
    CombinedMetric DESC,
    Reputation DESC,
    TotalPosts DESC
OFFSET 1000 ROWS
FETCH NEXT 500 ROWS ONLY;