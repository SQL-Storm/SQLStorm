-- {"query": "7067.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2017} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as RankByScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 100 THEN 'Medium'
            ELSE 'Low'
        END as ViewCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Popular'
            WHEN p.Score > 10 THEN 'Moderate'
            ELSE 'Low'
        END as Popularity,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
        COALESCE(p.AnswerCount, 0) * 100.0 / NULLIF(p.ViewCount, 0) as AnswerToViewRatio,
        COALESCE(p.CommentCount, 0) * 100.0 / NULLIF(p.ViewCount, 0) as CommentToViewRatio
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
TopQuestions AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.ViewCount,
        pp.AnswerCount,
        pp.CommentCount,
        pp.AgeInDays,
        pp.ViewCategory,
        pp.Popularity,
        pp.AnswerToViewRatio,
        pp.CommentToViewRatio,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY pp.Score DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY pp.ViewCount DESC) as RankByViews,
        RANK() OVER (ORDER BY pp.AnswerCount DESC) as RankByAnswers
    FROM PostPerformance pp
    JOIN Users u ON pp.OwnerUserId = u.Id
    WHERE pp.PostTypeId = 1 AND pp.ViewCount > 100
),
UserPostAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.TotalScore,
        uas.LastPostDate,
        uas.RankByScore,
        uas.RankByPostCount,
        COALESCE(avgq.Score, 0) as AvgQuestionScore,
        COALESCE(avgq.AnswerCount, 0) as AvgAnswersPerQuestion,
        COALESCE(avgq.ViewCount, 0) as AvgQuestionViews,
        CASE 
            WHEN uas.Questions > 0 THEN CAST(uas.Answers AS FLOAT) / CAST(uas.Questions AS FLOAT)
            ELSE 0
        END as AnswerRatio
    FROM UserActivityStats uas
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            AVG(Score) as Score,
            AVG(AnswerCount) as AnswerCount,
            AVG(ViewCount) as ViewCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
        HAVING COUNT(*) >= 10
    ) avgq ON uas.UserId = avgq.OwnerUserId
),
ActivityPatterns AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*) as PostCount,
        MAX(p.CreationDate) as LastPost,
        MIN(p.CreationDate) as FirstPost,
        DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) as ActivitySpan,
        DATEDIFF(DAY, MIN(p.CreationDate), GETDATE()) as DaysSinceFirstPost,
        CASE 
            WHEN DATEDIFF(DAY, MAX(p.CreationDate), GETDATE()) <= 30 THEN 'Active'
            WHEN DATEDIFF(DAY, MAX(p.CreationDate), GETDATE()) <= 90 THEN 'Moderately Active'
            ELSE 'Inactive'
        END as ActivityStatus,
        CASE 
            WHEN COUNT(*) > 50 THEN 'High Contributor'
            WHEN COUNT(*) > 10 THEN 'Regular Contributor'
            ELSE 'Occasional Contributor'
        END as ContributionLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT TOP 100
    ap.UserId,
    ap.DisplayName,
    ap.Reputation,
    ap.PostCount,
    ap.LastPost,
    ap.ContributionLevel,
    ap.ActivityStatus,
    ap.ActivitySpan,
    ap.DaysSinceFirstPost,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.Comments,
    upa.Badges,
    upa.TotalScore,
    upa.AvgQuestionScore,
    upa.AvgAnswersPerQuestion,
    upa.AvgQuestionViews,
    upa.AnswerRatio,
    upa.RankByScore as UserRank,
    upa.RankByPostCount as PostRank,
    CASE 
        WHEN upa.TotalScore > 1000 THEN 'High Scorer'
        WHEN upa.TotalScore > 100 THEN 'Moderate Scorer'
        ELSE 'Low Scorer'
    END as ScoreCategory,
    CASE 
        WHEN upa.Answers > upa.Questions THEN 'More Answers Than Questions'
        WHEN upa.Answers < upa.Questions THEN 'More Questions Than Answers'
        ELSE 'Equal Questions and Answers'
    END as QuestionAnswerBalance,
    ISNULL(
        (SELECT TOP 1 tq.Title 
         FROM TopQuestions tq 
         WHERE tq.OwnerName = ap.DisplayName 
         ORDER BY tq.Score DESC), 
        'No Top Questions'
    ) as TopQuestionTitle,
    ISNULL(
        (SELECT TOP 1 tq.Score 
         FROM TopQuestions tq 
         WHERE tq.OwnerName = ap.DisplayName 
         ORDER BY tq.Score DESC), 
        0
    ) as TopQuestionScore,
    COALESCE(
        (SELECT AVG(Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = ap.UserId 
         AND p.PostTypeId = 1), 
        0
    ) as AvgQuestionScoreForUser,
    COALESCE(
        (SELECT AVG(Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = ap.UserId 
         AND p.PostTypeId = 2), 
        0
    ) as AvgAnswerScoreForUser,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     JOIN Posts p ON ph.PostId = p.Id 
     WHERE p.OwnerUserId = ap.UserId 
     AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)) as EditCount,
    (SELECT COUNT(*) 
     FROM Votes v 
     JOIN Posts p ON v.PostId = p.Id 
     WHERE p.OwnerUserId = ap.UserId 
     AND v.VoteTypeId IN (2,3)) as VoteCount,
    CASE 
        WHEN ap.Reputation > 100000 THEN 'Legendary'
        WHEN ap.Reputation > 10000 THEN 'Master'
        WHEN ap.Reputation > 1000 THEN 'Expert'
        WHEN ap.Reputation > 100 THEN 'Beginner'
        ELSE 'Newbie'
    END as ReputationTier,
    ROW_NUMBER() OVER (ORDER BY ap.PostCount DESC, ap.Reputation DESC) as CombinedRank
FROM ActivityPatterns ap
JOIN UserPostAnalysis upa ON ap.UserId = upa.UserId
WHERE ap.ContributionLevel IN ('High Contributor', 'Regular Contributor')
    AND ap.ActivityStatus IN ('Active', 'Moderately Active')
    AND (upa.TotalPosts > 10 OR upa.TotalScore > 100)
    AND upa.AnswerRatio > 0.2
ORDER BY ap.PostCount DESC, ap.Reputation DESC, upa.TotalScore DESC;