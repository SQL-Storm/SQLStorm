-- {"query": "7894.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2538} 
WITH TopUsers AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) as RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
UserActivity AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.BadgeCount,
        tu.LatestPostDate,
        tu.RepRank,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        CASE 
            WHEN tu.RepRank <= 10 THEN 'Top 10'
            WHEN tu.RepRank <= 50 THEN 'Top 50'
            WHEN tu.RepRank <= 100 THEN 'Top 100'
            ELSE 'Others'
        END as RepTier,
        DENSE_RANK() OVER (ORDER BY tu.PostCount DESC) as PostRank,
        PERCENT_RANK() OVER (ORDER BY tu.Reputation) as RepPercentile,
        NTILE(4) OVER (ORDER BY tu.Reputation) as RepQuartile
    FROM TopUsers tu
    LEFT JOIN Posts p ON tu.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON tu.UserId = c.UserId
    LEFT JOIN PostHistory ph ON tu.UserId = ph.UserId
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.PostCount, tu.BadgeCount, tu.LatestPostDate, tu.RepRank
),
PostStats AS (
    SELECT 
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate, CURRENT_TIMESTAMP)) as DaysSinceCreation,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Common'
            ELSE 'Rare'
        END as ViewLevel
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
DetailedUserStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.BadgeCount,
        ua.TotalScore,
        ua.AvgScore,
        ua.CommentCount,
        ua.HistoryCount,
        ua.RepTier,
        ua.PostRank,
        ua.RepPercentile,
        ua.RepQuartile,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
           AND p.PostTypeId = 1 
           AND p.AcceptedAnswerId IS NOT NULL) as QuestionsWithAcceptedAnswer,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
           AND p.PostTypeId = 2) as AnswerCount,
        (SELECT AVG(p.Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
           AND p.PostTypeId = 1) as AvgQuestionScore,
        (SELECT AVG(p.Score) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
           AND p.PostTypeId = 2) as AvgAnswerScore,
        (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
         FROM Posts p 
         JOIN UNNEST(STRING_TO_ARRAY(p.Tags, '>')) AS t(TagName) 
         WHERE p.OwnerUserId = ua.UserId AND p.Tags IS NOT NULL AND p.Tags != '') as UserTags
    FROM UserActivity ua
    WHERE ua.RepRank <= 100
),
CombinedStats AS (
    SELECT 
        dus.UserId,
        dus.DisplayName,
        dus.Reputation,
        dus.PostCount,
        dus.BadgeCount,
        dus.TotalScore,
        dus.AvgScore,
        dus.CommentCount,
        dus.HistoryCount,
        dus.RepTier,
        dus.PostRank,
        dus.RepPercentile,
        dus.RepQuartile,
        dus.QuestionsWithAcceptedAnswer,
        dus.AnswerCount,
        dus.AvgQuestionScore,
        dus.AvgAnswerScore,
        COALESCE(dus.UserTags, '') as UserTags,
        RANK() OVER (ORDER BY dus.TotalScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY dus.Reputation DESC) as ReputationRank,
        CASE 
            WHEN dus.PostCount > 0 THEN (dus.PostCount + dus.BadgeCount) / NULLIF(dus.PostCount, 0)
            ELSE 0
        END as EngagementRatio,
        ROW_NUMBER() OVER (ORDER BY dus.Reputation DESC, dus.PostCount DESC) as CombinedRank
    FROM DetailedUserStats dus
),
FinalAnalysis AS (
    SELECT 
        cs.UserId,
        cs.DisplayName,
        cs.Reputation,
        cs.PostCount,
        cs.BadgeCount,
        cs.TotalScore,
        cs.AvgScore,
        cs.CommentCount,
        cs.HistoryCount,
        cs.RepTier,
        cs.PostRank,
        cs.RepPercentile,
        cs.RepQuartile,
        cs.QuestionsWithAcceptedAnswer,
        cs.AnswerCount,
        cs.AvgQuestionScore,
        cs.AvgAnswerScore,
        cs.UserTags,
        cs.ScoreRank,
        cs.ReputationRank,
        cs.EngagementRatio,
        cs.CombinedRank,
        (CASE 
            WHEN cs.RepTier = 'Top 10' THEN 'Elite'
            WHEN cs.RepTier = 'Top 50' THEN 'High Performer'
            WHEN cs.RepTier = 'Top 100' THEN 'Active Contributor'
            ELSE 'Regular User'
        END) as UserLevel,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = cs.UserId 
           AND p.PostTypeId = 1 
           AND p.FavoriteCount > 50) as HighlyFavoritedQuestions,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = cs.UserId 
           AND p.PostTypeId = 2 
           AND p.Score > 100) as HighScoreAnswers,
        (SELECT COUNT(DISTINCT p.Id) 
         FROM Posts p 
         JOIN PostHistory ph ON p.Id = ph.PostId 
         WHERE p.OwnerUserId = cs.UserId 
           AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditActivity
    FROM CombinedStats cs
    WHERE cs.Reputation > 10000
),
RankedData AS (
    SELECT 
        fa.UserId,
        fa.DisplayName,
        fa.Reputation,
        fa.PostCount,
        fa.BadgeCount,
        fa.TotalScore,
        fa.AvgScore,
        fa.CommentCount,
        fa.HistoryCount,
        fa.RepTier,
        fa.PostRank,
        fa.RepPercentile,
        fa.RepQuartile,
        fa.QuestionsWithAcceptedAnswer,
        fa.AnswerCount,
        fa.AvgQuestionScore,
        fa.AvgAnswerScore,
        fa.UserTags,
        fa.ScoreRank,
        fa.ReputationRank,
        fa.EngagementRatio,
        fa.CombinedRank,
        fa.UserLevel,
        fa.HighlyFavoritedQuestions,
        fa.HighScoreAnswers,
        fa.EditActivity,
        LAG(fa.Reputation) OVER (ORDER BY fa.Reputation DESC) - fa.Reputation as RepDeltaFromPrevious
    FROM FinalAnalysis fa
)
SELECT 
    rd.UserId,
    rd.DisplayName,
    rd.Reputation,
    rd.PostCount,
    rd.BadgeCount,
    rd.TotalScore,
    rd.AvgScore,
    rd.CommentCount,
    rd.HistoryCount,
    rd.RepTier,
    rd.PostRank,
    rd.RepPercentile,
    rd.RepQuartile,
    rd.QuestionsWithAcceptedAnswer,
    rd.AnswerCount,
    rd.AvgQuestionScore,
    rd.AvgAnswerScore,
    rd.UserTags,
    rd.ScoreRank,
    rd.ReputationRank,
    rd.EngagementRatio,
    rd.CombinedRank,
    rd.UserLevel,
    rd.HighlyFavoritedQuestions,
    rd.HighScoreAnswers,
    rd.EditActivity,
    rd.RepDeltaFromPrevious,
    CASE 
        WHEN rd.Reputation > 50000 THEN 100
        WHEN rd.Reputation > 25000 THEN 75
        WHEN rd.Reputation > 10000 THEN 50
        ELSE 25
    END as ReputationScore,
    ABS(rd.TotalScore - AVG(rd.TotalScore) OVER ()) as ScoreDeviation,
    NTILE(100) OVER (ORDER BY rd.Reputation) as ReputationPercentile,
    DENSE_RANK() OVER (ORDER BY rd.Reputation DESC, rd.TotalScore DESC) as OverallRank,
    (SELECT COUNT(*) 
     FROM Votes v 
     JOIN Posts p ON v.PostId = p.Id 
     WHERE p.OwnerUserId = rd.UserId 
       AND v.VoteTypeId IN (2, 3)) as TotalVoteCount,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = rd.UserId 
       AND b.Class = 1) as GoldBadgeCount,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = rd.UserId 
       AND b.Class = 2) as SilverBadgeCount,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = rd.UserId 
       AND b.Class = 3) as BronzeBadgeCount,
    CASE 
        WHEN rd.EditActivity > 10 THEN 'Very Active Editor'
        WHEN rd.EditActivity > 5 THEN 'Active Editor'
        WHEN rd.EditActivity > 0 THEN 'Occasional Editor'
        ELSE 'No Editing'
    END as EditingActivity,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
     FROM Posts p 
     JOIN UNNEST(STRING_TO_ARRAY(p.Tags, '>')) AS t(TagName) 
     WHERE p.OwnerUserId = rd.UserId 
       AND p.Tags IS NOT NULL 
       AND p.Tags != '') as AllUserTags,
    ROUND(CAST(rd.Reputation AS FLOAT) / NULLIF(rd.TotalScore, 0), 2) as RepPerScore,
    CASE 
        WHEN rd.EngagementRatio > 2 THEN 'Highly Engaged'
        WHEN rd.EngagementRatio > 1 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END as EngagementStatus
FROM RankedData rd
WHERE rd.Reputation BETWEEN 10000 AND 1000000
  AND rd.PostCount > 10
  AND rd.ScoreRank > 1
ORDER BY rd.Reputation DESC, rd.TotalScore DESC, rd.CombinedRank ASC
LIMIT 10000;