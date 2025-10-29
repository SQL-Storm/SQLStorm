-- {"query": "7971.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1848} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT c.Id) as Comments,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
                CAST(COUNT(DISTINCT p.Id) AS FLOAT)
            ELSE 0 
        END as AnswerRatio,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
AnswerQuality AS (
    SELECT 
        p.ParentId,
        AVG(p.Score) as AvgAnswerScore,
        COUNT(*) as AnswerCount,
        STRING_AGG(p.OwnerDisplayName, ', ' ORDER BY p.Score DESC) as TopAnswerers,
        MAX(p.Score) as BestAnswerScore,
        MIN(p.Score) as WorstAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        COALESCE(STRING_AGG(p.Title, '; ' ORDER BY p.CreationDate DESC), '') as RecentQuestions,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgQuestionScore,
        MAX(p.Score) as MaxQuestionScore,
        MIN(p.Score) as MinQuestionScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
),
ComplexUserAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.AnswerRatio,
        us.ScoreRank,
        us.RepRank,
        us.TotalScore,
        CASE 
            WHEN us.Questions > 0 AND us.Answers > 0 THEN 
                (us.Answers * 100.0) / us.Questions
            ELSE 0 
        END as AnswerPercentage,
        CASE 
            WHEN us.Answers > us.Questions THEN 'More Answers Than Questions'
            WHEN us.Answers = us.Questions THEN 'Equal Answers and Questions'
            ELSE 'More Questions Than Answers'
        END as PostRatioStatus,
        CASE 
            WHEN us.Reputation >= 10000 THEN 'Elite'
            WHEN us.Reputation >= 1000 THEN 'Expert'
            WHEN us.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as RepTier,
        COALESCE(STRING_AGG(p.Title, '; '), '') as RecentTitles,
        COALESCE(MAX(p.CreationDate), '1900-01-01') as LatestPostTime,
        CASE 
            WHEN us.ScoreRank <= 10 THEN 'Top 10 Scorer'
            WHEN us.ScoreRank <= 50 THEN 'Top 50 Scorer'
            WHEN us.ScoreRank <= 100 THEN 'Top 100 Scorer'
            ELSE 'Regular User'
        END as ScoringTier
    FROM UserStats us
    LEFT JOIN Posts p ON us.UserId = p.OwnerUserId
    GROUP BY 
        us.UserId, us.DisplayName, us.Reputation, us.TotalPosts,
        us.Questions, us.Answers, us.AnswerRatio, us.ScoreRank,
        us.RepRank, us.TotalScore
)
SELECT 
    cua.UserId,
    cua.DisplayName,
    cua.Reputation,
    cua.TotalPosts,
    cua.Questions,
    cua.Answers,
    ROUND(cua.AnswerRatio, 3) as AnswerRatio,
    cua.ScoreRank,
    cua.RepRank,
    cua.TotalScore,
    ROUND(cua.AnswerPercentage, 2) as AnswerPercentage,
    cua.PostRatioStatus,
    cua.RepTier,
    SUBSTRING(cua.RecentTitles, 1, 200) as RecentTitlesPreview,
    cua.LatestPostTime,
    cua.ScoringTier,
    CASE 
        WHEN cua.Reputation >= 10000 AND cua.Answers > 100 THEN 'Veteran Answerer'
        WHEN cua.Reputation >= 1000 AND cua.Questions > 50 THEN 'Veteran Questioner'
        WHEN cua.Reputation >= 100 AND cua.Answers >= 10 THEN 'Regular Contributor'
        ELSE 'New Participant'
    END as ContributionStatus,
    CASE 
        WHEN cua.TotalScore > 1000 THEN 'Highly Active'
        WHEN cua.TotalScore > 100 THEN 'Moderately Active'
        WHEN cua.TotalScore > 0 THEN 'Active'
        ELSE 'Inactive'
    END as ActivityLevel,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) as BadgeCount,
    COUNT(DISTINCT CASE WHEN v.Id IS NOT NULL THEN v.Id END) as VoteCount,
    COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL AND p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL AND p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) as CommentCount,
    MAX(CASE WHEN p.Id IS NOT NULL THEN p.CreationDate ELSE NULL END) as MostRecentPostDate,
    MIN(CASE WHEN p.Id IS NOT NULL THEN p.CreationDate ELSE NULL END) as FirstPostDate,
    DATEDIFF(DAY, MIN(CASE WHEN p.Id IS NOT NULL THEN p.CreationDate ELSE NULL END), MAX(CASE WHEN p.Id IS NOT NULL THEN p.CreationDate ELSE NULL END)) as DaysActive,
    COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'No Tags') as UserTagsInPosts
FROM ComplexUserAnalysis cua
LEFT JOIN Badges b ON cua.UserId = b.UserId
LEFT JOIN Votes v ON cua.UserId = v.UserId
LEFT JOIN Posts p ON cua.UserId = p.OwnerUserId
LEFT JOIN Comments c ON cua.UserId = c.UserId
LEFT JOIN (
    SELECT DISTINCT p.OwnerUserId, SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) as TagList
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
) user_tags ON cua.UserId = user_tags.OwnerUserId
LEFT JOIN (
    SELECT tag_name FROM (
        SELECT unnest(string_to_array(tag_list, '><')) as tag_name
        FROM (
            SELECT DISTINCT p.Tags as tag_list
            FROM Posts p
            WHERE p.Tags IS NOT NULL AND p.Tags != ''
        ) tags_list
    ) tag_table
) t ON tag_name = t.TagName
GROUP BY 
    cua.UserId, cua.DisplayName, cua.Reputation, cua.TotalPosts,
    cua.Questions, cua.Answers, cua.AnswerRatio, cua.ScoreRank,
    cua.RepRank, cua.TotalScore, cua.AnswerPercentage,
    cua.PostRatioStatus, cua.RepTier, cua.RecentTitles,
    cua.LatestPostTime, cua.ScoringTier
HAVING 
    COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL THEN p.Id END) > 0
    AND SUM(COALESCE(p.Score, 0)) > -1000
ORDER BY 
    cua.TotalScore DESC,
    cua.Reputation DESC,
    cua.ScoreRank ASC
LIMIT 1000;