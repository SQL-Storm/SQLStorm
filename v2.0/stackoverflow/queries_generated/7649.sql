-- {"query": "7649.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2931} 
WITH PostMetrics AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.ParentId,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        MAX(p.CreationDate) as LatestActivity,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END as TagAccessibility,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagRequirement,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) - t.Count as PopularityDelta
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryEventCount,
        COUNT(DISTINCT ph.PostHistoryTypeId) as DistinctEventTypes,
        MAX(ph.CreationDate) as LastEditDate,
        MIN(ph.CreationDate) as FirstEditDate,
        DATEDIFF(day, MIN(ph.CreationDate), MAX(ph.CreationDate)) as EditDurationDays,
        STRING_AGG(ph.PostHistoryTypeId, ', ') within group (order by ph.CreationDate) as EventTypesList,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) as ModerationEvents
    FROM PostHistory ph
    WHERE ph.PostId IS NOT NULL
    GROUP BY ph.PostId
),
DetailedVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        vt.Name as VoteTypeName,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as VoteSequence,
        COUNT(*) OVER (PARTITION BY v.PostId) as TotalVotesOnPost,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) as UpDownVoteCount,
        AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) as UpDownVoteRatio
    FROM Votes v
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
),
TaggedQuestions AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LEN(q.Tags) - 2), '><') as TagArray,
        COUNT(*) OVER () as TotalQuestions,
        AVG(q.Score) OVER () as AvgScoreAcrossAllQuestions,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC) as ScoreRanking
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND q.Tags != ''
),
AnswerQuality AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        DATEDIFF(day, q.CreationDate, a.CreationDate) as DaysToAnswer,
        CASE 
            WHEN a.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'Above Average'
            WHEN a.Score <= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) / 2 THEN 'Below Average'
            ELSE 'Average'
        END as QualityLevel,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as RankInQuestion,
        COUNT(*) OVER (PARTITION BY a.ParentId) as TotalAnswersToQuestion
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
),
QuestionTagAnalysis AS (
    SELECT 
        tq.QuestionId,
        tq.Title,
        tq.Tags,
        tq.TagArray,
        ta.PopularityRank,
        ta.TagCount,
        ta.TagAccessibility,
        ta.TagRequirement,
        CASE 
            WHEN tq.TagArray IS NOT NULL AND ARRAY_LENGTH(tq.TagArray, 1) > 0 THEN 
                (SELECT COUNT(*) FROM UNNEST(tq.TagArray) AS tag WHERE EXISTS (SELECT 1 FROM Tags t WHERE t.TagName = tag))
            ELSE 0 
        END as MatchingTags,
        (SELECT COUNT(*) FROM UNNEST(tq.TagArray) AS tag WHERE EXISTS (SELECT 1 FROM Tags t WHERE t.TagName = tag AND t.IsRequired = 1)) as RequiredTags,
        CASE 
            WHEN EXISTS (SELECT 1 FROM UNNEST(tq.TagArray) AS tag WHERE EXISTS (SELECT 1 FROM Tags t WHERE t.TagName = tag AND t.IsRequired = 1))
            THEN 'Has Required Tags'
            ELSE 'Missing Required Tags'
        END as RequiredTagStatus
    FROM TaggedQuestions tq
    LEFT JOIN TagAnalysis ta ON ta.TagName = ANY(tq.TagArray)
)

SELECT 
    pm.PostId,
    pm.PostTypeDesc,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.DaysSinceCreation,
    pm.UserPostRank,
    pm.ScoreRank,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount as UserAnswerCount,
    ua.TotalQuestionScore,
    ua.TotalAnswerScore,
    ua.AvgQuestionScore,
    ua.AvgAnswerScore,
    ta.TagName,
    ta.TagCount,
    ta.PopularityRank as TagPopularity,
    pht.HistoryEventCount,
    pht.DistinctEventTypes,
    pht.LastEditDate,
    pht.FirstEditDate,
    pht.EditDurationDays,
    dvt.TotalVotesOnPost,
    dvt.UpDownVoteCount,
    dvt.UpDownVoteRatio,
    aq.DaysToAnswer,
    aq.QualityLevel,
    aq.RankInQuestion,
    aq.TotalAnswersToQuestion,
    qta.RequiredTagStatus,
    CASE 
        WHEN pm.Score > 100 THEN 'Highly Upvoted'
        WHEN pm.Score > 20 THEN 'Moderately Upvoted'
        WHEN pm.Score > 0 THEN 'Slightly Upvoted'
        ELSE 'Not Upvoted'
    END as ScoreCategory,
    CASE 
        WHEN pm.DaysSinceCreation > 30 THEN 'Long-term Post'
        WHEN pm.DaysSinceCreation > 7 THEN 'Medium-term Post'
        ELSE 'New Post'
    END as PostAgeCategory,
    CASE 
        WHEN ua.AccountAgeDays > 365 THEN 'Veteran User'
        WHEN ua.AccountAgeDays > 30 THEN 'Regular User'
        ELSE 'New User'
    END as UserTenureCategory,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pm.OwnerUserId AND p.CreationDate > DATEADD(month, -1, GETDATE())) as PostsLastMonth,
    COALESCE(NULLIF(pm.Score, 0) / NULLIF(pm.ViewCount, 0) * 100, 0) as ScorePerViewPercentage,
    COALESCE(NULLIF(pm.AnswerCount, 0) / NULLIF(pm.CommentCount + 1, 0), 0) as AnswerPerCommentRatio,
    DATEDIFF(day, pm.CreationDate, GETDATE()) as DaysSincePost,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Votes v WHERE v.PostId = pm.PostId AND v.VoteTypeId = 1) THEN 'Accepted'
        ELSE 'Not Accepted'
    END as HasAcceptedAnswer,
    CASE 
        WHEN pm.PostTypeId = 2 AND EXISTS(SELECT 1 FROM Posts WHERE Id = pm.ParentId AND PostTypeId = 1) 
        THEN 'Answer to Question'
        WHEN pm.PostTypeId = 1 THEN 'Question'
        ELSE 'Other'
    END as PostRelation,
    CASE 
        WHEN EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = pm.PostId AND ph.PostHistoryTypeId IN (10, 12, 13, 14, 15, 19, 20)) 
        THEN 'Moderated'
        ELSE 'Unmoderated'
    END as ModerationStatus,
    COALESCE(pm.Tags, '') as PostTags,
    COALESCE(ta.TagAccessibility, 'Unknown') as TagAccessibility,
    COALESCE(ta.TagRequirement, 'Unknown') as TagRequirement,
    COALESCE(pm.Title, '') as PostTitle,
    COALESCE(pm.Title, '') LIKE '%[Ss]QL%' OR COALESCE(pm.Title, '') LIKE '%[Dd]atabase%' OR COALESCE(pm.Title, '') LIKE '%[Qq]uery%' OR COALESCE(pm.Title, '') LIKE '%[Ss]tore%' OR COALESCE(pm.Title, '') LIKE '%[Tt]able%' AS ContainsDatabaseKeywords
FROM PostMetrics pm
LEFT JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
LEFT JOIN PostHistorySummary pht ON pm.PostId = pht.PostId
LEFT JOIN DetailedVotes dvt ON pm.PostId = dvt.PostId AND dvt.VoteSequence = 1
LEFT JOIN AnswerQuality aq ON pm.PostId = aq.AnswerId
LEFT JOIN QuestionTagAnalysis qta ON pm.PostId = qta.QuestionId
LEFT JOIN TagAnalysis ta ON ta.TagName = (
    SELECT tag FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(pm.Tags, 2, LEN(pm.Tags) - 2), '><')) AS tag 
    WHERE tag IN (SELECT TagName FROM Tags)
    LIMIT 1
)
WHERE 
    pm.Score >= 0 
    AND pm.ViewCount >= 0 
    AND pm.PostTypeId IN (1, 2)
    AND (
        (pm.PostTypeId = 1 AND pm.Score >= 10) 
        OR (pm.PostTypeId = 2 AND pm.Score >= 5)
    )
    AND (ua.Reputation >= 100 OR ua.Reputation IS NULL)
    AND (
        EXISTS(SELECT 1 FROM Posts p WHERE p.Id = pm.PostId) 
        OR EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = pm.PostId)
    )
    AND NOT (pm.Tags IS NULL OR pm.Tags = '')
    AND (
        EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = pm.PostId AND ph.PostHistoryTypeId IN (10, 12, 13, 14, 15, 19, 20)) 
        OR pht.ModerationEvents > 0 
        OR pm.LastActivityDate > DATEADD(day, -30, GETDATE())
    )
    AND (
        EXISTS(SELECT 1 FROM Comments c WHERE c.PostId = pm.PostId) 
        OR (COALESCE(pm.CommentCount, 0) > 0)
    )
    AND (
        EXISTS(SELECT 1 FROM Votes v WHERE v.PostId = pm.PostId) 
        OR (COALESCE(dvt.TotalVotesOnPost, 0) > 0)
    )
LIMIT 5000;