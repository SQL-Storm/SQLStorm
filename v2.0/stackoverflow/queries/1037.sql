-- {"query": "1037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3159}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Id END) AS TotalAnswersProvided,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostsScoreSum,
        COALESCE(SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedOnPosts,
        CAST(u.Reputation AS numeric) / (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / 86400.0 + 1) AS ReputationPerDayActive,
        CASE
            WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 500 THEN 'ExtensiveBio'
            WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 150 THEN 'ModerateBio'
            WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 0 THEN 'BriefBio'
            ELSE 'NoBio'
        END AS BioLengthCategory,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%.com%' THEN TRUE
            ELSE FALSE
        END AS HasWebsiteUrl
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.AboutMe, u.WebsiteUrl
),
QuestionEditsIntervals AS (
    SELECT
        ph.PostId AS QuestionId,
        ph.CreationDate AS ThisEditDate,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevEditDate,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Edit %' OR Name LIKE 'Rollback %'
    )
),
QuestionPerformance AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(q.FavoriteCount, 0) AS FavoriteCount,
        q.Title,
        q.Tags,
        (SELECT SUM(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')) AS TotalAnswerScore,
        (SELECT COUNT(DISTINCT a.Id) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')) AS EffectiveAnswerCount,
        COUNT(DISTINCT comm.Id) AS QuestionCommentCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (
            SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Edit %' OR Name LIKE 'Rollback %'
        ) THEN ph.Id END) AS EditRevisionCount,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        AVG(EXTRACT(EPOCH FROM (qe.ThisEditDate - qe.PrevEditDate)) / 86400.0) AS AvgDaysBetweenEdits,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM q.CreationDate) ORDER BY q.ViewCount DESC, q.Score DESC) AS RankInYearByViewsAndScore,
        (q.ClosedDate IS NOT NULL) AS IsClosedQuestion,
        CASE
            WHEN q.ClosedDate IS NOT NULL AND q.ClosedDate > (q.CreationDate + INTERVAL '30 days') THEN 'LateClosure'
            WHEN q.ClosedDate IS NOT NULL AND q.ClosedDate <= (q.CreationDate + INTERVAL '30 days') THEN 'EarlyClosure'
            ELSE 'Open'
        END AS ClosureTimingCategory,
        STRING_AGG(DISTINCT ph_close.Comment, '; ') FILTER (WHERE ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')) AS CloseReasonComments
    FROM Posts q
    LEFT JOIN Comments comm ON q.Id = comm.PostId
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId
    LEFT JOIN PostHistory ph_close ON q.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    LEFT JOIN QuestionEditsIntervals qe ON q.Id = qe.QuestionId
    WHERE q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
    GROUP BY q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Title, q.Tags, q.ClosedDate
),
AnswerQuality AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        COUNT(DISTINCT ca.Id) AS AnswerCommentCount,
        MAX(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END), 0) AS UpvotesOnAnswer,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END), 0) AS DownvotesOnAnswer,
        CASE
            WHEN LENGTH(a.Body) > 2000 THEN 'VeryDetailedAnswer'
            WHEN LENGTH(a.Body) > 500 THEN 'DetailedAnswer'
            WHEN LENGTH(a.Body) > 100 THEN 'ConciseAnswer'
            ELSE 'BriefAnswer'
        END AS AnswerLengthCategory,
        LEAD(a.CreationDate) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS NextAnswerCreationDate,
        (
            SELECT AVG(1) -- average count of upvote votes per vote row for this post; Votes table likely records one row per vote without Score column
            FROM Votes v_ans
            WHERE v_ans.PostId = a.Id AND v_ans.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')
        ) AS AverageUpvoteScore
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
    LEFT JOIN Comments ca ON a.Id = ca.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId
    WHERE a.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score, a.Body, q.AcceptedAnswerId
),
UserBadgeTagMatch AS (
    SELECT
        qp.QuestionId,
        qp.OwnerUserId,
        STRING_AGG(DISTINCT b.Name, '; ') AS MatchingBadges,
        COUNT(DISTINCT b.Id) AS MatchingBadgeCount
    FROM QuestionPerformance qp
    JOIN Badges b ON qp.OwnerUserId = b.UserId
    WHERE
        qp.Tags IS NOT NULL
        AND b.TagBased = FALSE
        AND EXISTS (
            SELECT 1
            FROM (
                SELECT UNNEST(string_to_array(SUBSTRING(qp.Tags FROM 2 FOR LENGTH(qp.Tags) - 2), '><')) AS post_tag
            ) t
            WHERE LOWER(t.post_tag) = LOWER(b.Name)
        )
    GROUP BY qp.QuestionId, qp.OwnerUserId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationPerDayActive,
    ue.BioLengthCategory,
    ue.HasWebsiteUrl,
    qp.QuestionId,
    qp.Title AS QuestionTitle,
    qp.QuestionCreationDate,
    qp.QuestionScore,
    qp.ViewCount,
    qp.FavoriteCount,
    qp.EditRevisionCount,
    qp.AvgDaysBetweenEdits,
    qp.IsClosedQuestion,
    qp.ClosureTimingCategory,
    qp.CloseReasonComments,
    ap.AnswerId,
    ap.AnswerCreationDate,
    ap.AnswerScore,
    ap.IsAcceptedAnswer,
    ap.AnswerLengthCategory,
    COALESCE(ubtm.MatchingBadges, 'N/A') AS CorrelatedTagBadges,
    COALESCE(ubtm.MatchingBadgeCount, 0) AS CorrelatedBadgeMatchCount,
    (
        COALESCE(qp.QuestionScore * 2.5, 0) +
        COALESCE(qp.ViewCount / 50.0, 0) +
        COALESCE(qp.FavoriteCount * 10.0, 0) +
        COALESCE(qp.EffectiveAnswerCount * 5.0, 0) +
        COALESCE(qp.QuestionCommentCount * 1.0, 0) +
        (CASE WHEN qp.EditRevisionCount > 5 THEN qp.EditRevisionCount * 0.5 ELSE 0 END) +
        (CASE WHEN qp.IsClosedQuestion THEN -50 ELSE 0 END)
    ) AS CalculatedQuestionInfluenceScore,
    (
        COALESCE(ap.AnswerScore * 3.0, 0) +
        COALESCE(ap.UpvotesOnAnswer * 2.0, 0) -
        COALESCE(ap.DownvotesOnAnswer * 1.5, 0) +
        COALESCE(ap.AnswerCommentCount * 0.8, 0) +
        (CASE WHEN ap.IsAcceptedAnswer = 1 THEN 30 ELSE 0 END)
    ) AS CalculatedAnswerInfluenceScore,
    (ue.ReputationPerDayActive * 100) + ue.TotalPostsCreated + ue.TotalCommentsMade + ue.TotalUpvotesReceivedOnPosts AS UserOverallEngagementScore,
    RANK() OVER (PARTITION BY ue.BioLengthCategory ORDER BY ue.Reputation DESC, ue.ReputationPerDayActive DESC) AS RankWithinBioType,
    DENSE_RANK() OVER (ORDER BY (ue.ReputationPerDayActive * 100 + COALESCE(qp.QuestionScore,0) + COALESCE(ap.AnswerScore,0)) DESC) AS GlobalImpactRank
FROM UserEngagement ue
LEFT JOIN QuestionPerformance qp ON ue.UserId = qp.OwnerUserId
LEFT JOIN AnswerQuality ap ON ue.UserId = ap.OwnerUserId AND qp.QuestionId = ap.QuestionId
LEFT JOIN UserBadgeTagMatch ubtm ON qp.QuestionId = ubtm.QuestionId AND ue.UserId = ubtm.OwnerUserId
WHERE
    ue.Reputation > 10000
    AND (
        qp.QuestionId IS NOT NULL
        OR ap.AnswerId IS NOT NULL
    )
    AND (
        (qp.QuestionScore > 50 AND qp.ViewCount > 5000)
        OR (ap.AnswerScore > 30 AND ap.IsAcceptedAnswer = 1)
        OR (ue.ReputationPerDayActive > 1.5 AND ue.TotalPostsCreated > 100)
    )
    AND (
        qp.Title ILIKE '%sql%' OR qp.Title ILIKE '%database%' OR qp.Title ILIKE '%query%' OR qp.Title IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.UserId = ue.UserId
          AND ph_del.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Deleted')
          AND ph_del.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '6 months')
    )
ORDER BY
    GlobalImpactRank ASC,
    CalculatedQuestionInfluenceScore DESC NULLS LAST,
    CalculatedAnswerInfluenceScore DESC NULLS LAST
LIMIT 200;