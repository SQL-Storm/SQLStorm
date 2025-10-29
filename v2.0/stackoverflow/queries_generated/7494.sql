-- {"query": "7494.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2069} 
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0) as QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as ViewRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        NTILE(10) OVER (ORDER BY u.Reputation) as ReputationDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        STRING_AGG(DISTINCT t.TagName, ', ') as TagList,
        CASE 
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'No Answers'
        END as Status,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.ViewCount > 500 THEN 'Medium Traffic'
            WHEN p.ViewCount > 100 THEN 'Low Traffic'
            ELSE 'Very Low Traffic'
        END as TrafficLevel,
        DATEDIFF('DAY', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostTags pt ON p.Id = pt.PostId
    LEFT JOIN Tags t ON pt.TagId = t.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate > DATEADD('YEAR', -2, CURRENT_TIMESTAMP)
        AND p.ViewCount > 100
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.Tags
),
PostAnalysis AS (
    SELECT 
        pq.Id,
        pq.Title,
        pq.Score,
        pq.ViewCount,
        pq.OwnerName,
        pq.TagList,
        pq.Status,
        pq.TrafficLevel,
        pq.AgeInDays,
        LAG(pq.Score, 1) OVER (ORDER BY pq.Score DESC) as PrevScore,
        LEAD(pq.Score, 1) OVER (ORDER BY pq.Score DESC) as NextScore,
        AVG(pq.Score) OVER (PARTITION BY pq.Status) as AvgScoreByStatus,
        COUNT(*) OVER (PARTITION BY pq.Status) as CountByStatus,
        RANK() OVER (PARTITION BY pq.Status ORDER BY pq.Score DESC) as RankInStatus,
        PERCENT_RANK() OVER (ORDER BY pq.Score) as ScorePercentile,
        NTH_VALUE(pq.Title, 1) OVER (
            PARTITION BY pq.Status 
            ORDER BY pq.Score DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) as TopTitleByStatus
    FROM TopQuestions pq
),
QualityCheck AS (
    SELECT 
        pa.*,
        CASE 
            WHEN pa.Score > 50 AND pa.ViewCount > 500 THEN 'High Quality'
            WHEN pa.Score > 20 AND pa.ViewCount > 200 THEN 'Medium Quality'
            WHEN pa.Score > 5 AND pa.ViewCount > 50 THEN 'Low Quality'
            ELSE 'Very Low Quality'
        END as QualityLevel,
        CASE 
            WHEN pa.Score > pa.AvgScoreByStatus * 1.5 THEN 'Above Average'
            WHEN pa.Score < pa.AvgScoreByStatus * 0.5 THEN 'Below Average'
            ELSE 'Average'
        END as RelativeScore,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 2),
            0) as UpVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 3),
            0) as DownVotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.Id) as CommentCount,
        (
            SELECT COUNT(*) FROM PostHistory ph 
            WHERE ph.PostId = pa.Id 
            AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        ) as EditCount
    FROM PostAnalysis pa
),
FinalResult AS (
    SELECT 
        qc.*,
        us.ReputationRank,
        us.ViewRank,
        us.PostRank,
        us.ReputationDecile,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        us.QuestionPercentage,
        CASE 
            WHEN qc.QualityLevel = 'High Quality' AND qc.RelativeScore = 'Above Average' THEN 
                CASE WHEN qc.EditCount > 0 THEN 'Excellent - Well Maintained' ELSE 'Excellent - New & Clean' END
            WHEN qc.QualityLevel = 'Medium Quality' AND qc.RelativeScore = 'Above Average' THEN 'Good - Above Average'
            WHEN qc.QualityLevel = 'Low Quality' THEN 'Needs Improvement'
            ELSE 'Poor Quality'
        END as OverallQuality,
        CONCAT(
            'User Rank: ', us.ReputationRank, 
            ' | Post Rank: ', us.PostRank, 
            ' | Quality: ', qc.OverallQuality
        ) as SummaryTag,
        CASE 
            WHEN qc.AgeInDays < 30 THEN 'Fresh'
            WHEN qc.AgeInDays < 90 THEN 'Recent'
            WHEN qc.AgeInDays < 365 THEN 'Older'
            ELSE 'Legacy'
        END as PostAgeGroup
    FROM QualityCheck qc
    JOIN UserStats us ON qc.OwnerName = us.DisplayName
    WHERE qc.Score > 10
)
SELECT 
    fr.Id,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.OwnerName,
    fr.TagList,
    fr.Status,
    fr.TrafficLevel,
    fr.AgeInDays,
    fr.ScorePercentile,
    fr.QualityLevel,
    fr.RelativeScore,
    fr.UpVotes,
    fr.DownVotes,
    fr.CommentCount,
    fr.EditCount,
    fr.ReputationRank,
    fr.ViewRank,
    fr.PostRank,
    fr.ReputationDecile,
    fr.PostCount,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.BadgeCount,
    fr.QuestionPercentage,
    fr.OverallQuality,
    fr.SummaryTag,
    fr.PostAgeGroup,
    CASE 
        WHEN fr.ScorePercentile > 0.9 THEN 'Top 10%'
        WHEN fr.ScorePercentile > 0.75 THEN 'Top 25%'
        WHEN fr.ScorePercentile > 0.5 THEN 'Top 50%'
        ELSE 'Below Median'
    END as PercentileRanking
FROM FinalResult fr
WHERE fr.PostAgeGroup IN ('Fresh', 'Recent') 
    AND fr.OverallQuality IN ('Excellent - Well Maintained', 'Excellent - New & Clean', 'Good - Above Average')
ORDER BY fr.Score DESC, fr.ViewCount DESC
LIMIT 100
EXCEPT
SELECT 
    fr.Id,
    fr.Title,
    fr.Score,
    fr.ViewCount,
    fr.OwnerName,
    fr.TagList,
    fr.Status,
    fr.TrafficLevel,
    fr.AgeInDays,
    fr.ScorePercentile,
    fr.QualityLevel,
    fr.RelativeScore,
    fr.UpVotes,
    fr.DownVotes,
    fr.CommentCount,
    fr.EditCount,
    fr.ReputationRank,
    fr.ViewRank,
    fr.PostRank,
    fr.ReputationDecile,
    fr.PostCount,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.BadgeCount,
    fr.QuestionPercentage,
    fr.OverallQuality,
    fr.SummaryTag,
    fr.PostAgeGroup,
    CASE 
        WHEN fr.ScorePercentile > 0.9 THEN 'Top 10%'
        WHEN fr.ScorePercentile > 0.75 THEN 'Top 25%'
        WHEN fr.ScorePercentile > 0.5 THEN 'Top 50%'
        ELSE 'Below Median'
    END as PercentileRanking
FROM FinalResult fr
WHERE fr.ReputationDecile = 1
    OR EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = (
            SELECT Id FROM Users u WHERE u.DisplayName = fr.OwnerName
        ) 
        AND p.PostTypeId = 1 
        AND p.CreationDate > DATEADD('MONTH', -1, CURRENT_TIMESTAMP)
    )
ORDER BY fr.Score DESC, fr.ViewCount DESC
LIMIT 50