-- {"query": "7969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2391} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) AS AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Basic'
            ELSE 'Newbie'
        END AS ReputationTier,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        RANK() OVER (PARTITION BY CASE WHEN u.Reputation >= 1000 THEN 1 ELSE 0 END ORDER BY u.Reputation DESC) AS ReputationRankByTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostsWithComplexity AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagsCount,
        CASE 
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 0 THEN LENGTH(p.Body)
            ELSE 0
        END AS BodyLength,
        CASE 
            WHEN p.Title IS NOT NULL AND LENGTH(p.Title) > 0 THEN LENGTH(p.Title)
            ELSE 0
        END AS TitleLength,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(YEAR, -1, GETDATE())
),
UserPostAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.BadgeCount,
        uas.CommentCount,
        uas.AccountAgeDays,
        uas.ReputationTier,
        uas.ReputationRank,
        uas.ReputationRankByTier,
        COALESCE(UPPER(SUBSTRING(uas.DisplayName, 1, 1)), 'X') AS DisplayInitial,
        CASE 
            WHEN uas.Reputation >= 10000 THEN 1
            WHEN uas.Reputation >= 1000 THEN 2
            WHEN uas.Reputation >= 100 THEN 3
            ELSE 4
        END AS RepTierNumeric,
        COALESCE(uas.Views, 0) + COALESCE(uas.UpVotes, 0) - COALESCE(uas.DownVotes, 0) AS NetActivityScore,
        LAG(uas.Reputation, 1) OVER (ORDER BY uas.Reputation DESC) AS PreviousReputation,
        LAG(uas.TotalPosts, 1) OVER (ORDER BY uas.Reputation DESC) AS PreviousTotalPosts,
        PERCENT_RANK() OVER (ORDER BY uas.Reputation) AS ReputationPercentile,
        NTILE(4) OVER (ORDER BY uas.Reputation) AS ReputationQuartile
    FROM UserActivityStats uas
    WHERE uas.TotalPosts > 0
),
TopQuestionTags AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagDenseRank
    FROM Tags t
    WHERE t.Count > 100
),
PostTagAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
            ELSE ARRAY[]::TEXT[]
        END AS PostTags,
        COALESCE(SUBSTRING(p.Title, 1, 50), '') AS TitleSnippet,
        COALESCE(SUBSTRING(p.Body, 1, 200), '') AS BodySnippet,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
ComplexJoinResult AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.ReputationTier,
        upa.ReputationRank,
        upa.NetActivityScore,
        upa.ReputationPercentile,
        upa.ReputationQuartile,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.PostTypeDesc,
        pa.HasAcceptedAnswer,
        pa.PostStatus,
        pa.TagsCount,
        pa.BodyLength,
        pa.TitleLength,
        CASE 
            WHEN pa.Score >= 100 THEN 'High'
            WHEN pa.Score >= 10 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        DATEDIFF(DAY, pa.CreationDate, GETDATE()) AS DaysSincePost,
        CASE 
            WHEN pa.AnswerCount > 0 THEN (pa.Score * 1.0 / pa.AnswerCount)
            ELSE 0
        END AS ScorePerAnswer,
        CASE 
            WHEN pa.ViewCount > 0 THEN (pa.Score * 1.0 / pa.ViewCount)
            ELSE 0
        END AS ScorePerView,
        CASE 
            WHEN pa.CommentCount > 0 THEN (pa.Score * 1.0 / pa.CommentCount)
            ELSE 0
        END AS ScorePerComment,
        CASE 
            WHEN upa.AnswerCount > 0 THEN (upa.AnswerCount * 1.0 / upa.QuestionCount)
            ELSE 0
        END AS AnswerToQuestionRatio
    FROM UserPostAnalysis upa
    INNER JOIN PostTagAnalysis pa ON upa.UserId = pa.OwnerUserId
    WHERE pa.Score >= 0
      AND pa.ViewCount >= 0
)
SELECT 
    TOP 1000 
    cro.UserId,
    cro.DisplayName,
    cro.Reputation,
    cro.ReputationTier,
    cro.ReputationRank,
    cro.NetActivityScore,
    cro.ReputationPercentile,
    cro.ReputationQuartile,
    cro.PostId,
    cro.Title,
    cro.Score,
    cro.ViewCount,
    cro.AnswerCount,
    cro.CommentCount,
    cro.FavoriteCount,
    cro.CreationDate,
    cro.PostTypeDesc,
    cro.HasAcceptedAnswer,
    cro.PostStatus,
    cro.TagsCount,
    cro.BodyLength,
    cro.TitleLength,
    cro.ScoreCategory,
    cro.DaysSincePost,
    cro.ScorePerAnswer,
    cro.ScorePerView,
    cro.ScorePerComment,
    cro.AnswerToQuestionRatio,
    DENSE_RANK() OVER (ORDER BY cro.Score DESC) AS GlobalScoreRank,
    RANK() OVER (PARTITION BY cro.ReputationTier ORDER BY cro.Score DESC) AS TierScoreRank,
    COUNT(*) OVER () AS TotalRecordCount,
    AVG(cro.Score) OVER (PARTITION BY cro.ReputationTier) AS AvgScoreByTier,
    STDDEV(cro.Score) OVER (PARTITION BY cro.ReputationTier) AS StdDevScoreByTier,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cro.Score) OVER (PARTITION BY cro.ReputationTier) AS MedianScoreByTier,
    MAX(cro.Score) OVER (ORDER BY cro.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS MovingMaxScore,
    LAG(cro.Score, 1) OVER (ORDER BY cro.Score DESC) AS PrevScore,
    LAG(cro.Reputation, 1) OVER (ORDER BY cro.Score DESC) AS PrevReputation,
    IIF(cro.Reputation > LAG(cro.Reputation, 1) OVER (ORDER BY cro.Score DESC), 'Up', 'Down') AS RepTrend,
    CASE 
        WHEN cro.Reputation > 10000 THEN 'Elite User'
        WHEN cro.Reputation > 5000 THEN 'Senior User'
        WHEN cro.Reputation > 1000 THEN 'Intermediate User'
        ELSE 'New User'
    END AS UserClassification,
    STUFF((
        SELECT DISTINCT ', ' + CAST(t.TagName AS VARCHAR(35))
        FROM Tags t
        WHERE t.Count > 100 
          AND EXISTS (
              SELECT 1 
              FROM PostTagAnalysis pta 
              WHERE pta.OwnerUserId = cro.UserId 
                AND t.TagName IN (SELECT UNNEST(pta.PostTags))
          )
        FOR XML PATH(''), TYPE
    ).value('.', 'VARCHAR(1000)'), 1, 2, '') AS UserTagList
FROM ComplexJoinResult cro
WHERE cro.NetActivityScore > 0
  AND cro.Score >= 0
  AND cro.ViewCount BETWEEN 0 AND 100000
ORDER BY cro.Score DESC, cro.CreationDate DESC;